const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');
admin.initializeApp();

// Forfaits d'abonnement magasin — doivent rester identiques à
// `kSubscriptionPlans` côté Flutter (lib/services/marketplace_models.dart).
// Définis ici côté serveur pour que le prix ne dépende jamais de ce que
// le client envoie (sécurité : un client ne choisit qu'un planId, jamais
// un montant).
const PLANS = {
  mensuel: { nom: 'Mensuel', dureeJours: 30, prixDA: 2000 },
  trimestriel: { nom: 'Trimestriel', dureeJours: 90, prixDA: 5000 },
  annuel: { nom: 'Annuel', dureeJours: 365, prixDA: 18000 },
};

// Config Chargily Pay (à définir une fois avant déploiement) :
//   firebase functions:config:set chargily.secret_key="test_sk_xxx" \
//     chargily.webhook_secret="xxx" chargily.mode="test"
// Passer chargily.mode à "live" + une clé "live_sk_xxx" une fois prêt à
// encaisser réellement.
function chargilyConfig() {
  const cfg = functions.config().chargily || {};
  const live = cfg.mode === 'live';
  return {
    secretKey: cfg.secret_key,
    webhookSecret: cfg.webhook_secret,
    baseUrl: live
      ? 'https://pay.chargily.net/api/v2'
      : 'https://pay.chargily.net/test/api/v2',
  };
}

/**
 * Notifie tous les magasins actifs (avec token FCM enregistré) dès
 * qu'une nouvelle demande de pièce est diffusée.
 *
 * C'est LE morceau qui nécessite un vrai backend : la diffusion "push"
 * ne peut pas se faire depuis l'app cliente elle-même (elle n'a pas les
 * droits d'envoyer des notifications à d'autres utilisateurs). D'où
 * Cloud Functions ici.
 */
exports.notifyStoresOnNewRequest = functions.firestore
  .document('part_requests/{requestId}')
  .onCreate(async (snap) => {
    const requestData = snap.data();

    const storesSnap = await admin
      .firestore()
      .collection('stores')
      .where('actif', '==', true)
      .get();

    const tokens = storesSnap.docs
      .map((doc) => doc.data().fcmToken)
      .filter((t) => !!t);

    if (tokens.length === 0) {
      console.log('Aucun magasin actif avec token FCM — rien à notifier.');
      return null;
    }

    const message = {
      notification: {
        title: 'Nouvelle demande de pièce',
        body: requestData.pieceNom
          ? `Pièce recherchée : ${requestData.pieceNom}`
          : 'Un client recherche une pièce.',
      },
      data: {
        requestId: snap.id,
      },
      tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(
      `Notifications envoyées : ${response.successCount} succès, ${response.failureCount} échecs.`
    );
    return response;
  });

/**
 * Fait passer automatiquement à "expire" tout magasin dont l'essai
 * gratuit ou l'abonnement payé est terminé. Tourne une fois par jour.
 *
 * C'est nécessaire côté serveur (Admin SDK, donc au-delà des Firestore
 * Rules) : un client ne peut jamais modifier son propre
 * `subscriptionStatus` (voir firestore.rules), donc rien côté app ne
 * peut faire cette bascule — sinon un essai resterait "essai" pour
 * toujours une fois sa date dépassée.
 */
exports.checkExpiredSubscriptions = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const db = admin.firestore();

    const essaisExpires = await db
      .collection('stores')
      .where('subscriptionStatus', '==', 'essai')
      .where('trialEndDate', '<=', now)
      .get();

    const abonnementsExpires = await db
      .collection('stores')
      .where('subscriptionStatus', '==', 'actif')
      .where('subscriptionEndDate', '<=', now)
      .get();

    const batch = db.batch();
    [...essaisExpires.docs, ...abonnementsExpires.docs].forEach((doc) => {
      batch.update(doc.ref, { subscriptionStatus: 'expire' });
    });

    const total = essaisExpires.size + abonnementsExpires.size;
    if (total === 0) {
      console.log('Aucun essai/abonnement à expirer aujourd\'hui.');
      return null;
    }
    await batch.commit();
    console.log(`${total} magasin(s) passé(s) en "expire".`);
    return null;
  });

/**
 * Valide une preuve de paiement reçue et active/renouvelle l'abonnement
 * du magasin pour 30 jours. À appeler manuellement (ex: HTTPS callable
 * réservé à un compte admin, ou directement depuis la console Firebase
 * en modifiant le document — cette fonction est le point d'entrée propre
 * une fois que tu veux automatiser la validation).
 */
exports.validatePayment = functions.https.onCall(async (data, context) => {
  // TODO : restreindre cet appel à un compte admin identifié
  // (context.auth.token.admin === true) avant mise en prod.
  const { storeId, paymentId } = data;
  if (!storeId || !paymentId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'storeId et paymentId sont requis.'
    );
  }

  const db = admin.firestore();
  const storeRef = db.collection('stores').doc(storeId);
  const paymentRef = storeRef.collection('payment_requests').doc(paymentId);

  const subscriptionEndDate = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
  );

  await db.runTransaction(async (tx) => {
    tx.update(paymentRef, { statut: 'valide' });
    tx.update(storeRef, {
      subscriptionStatus: 'actif',
      subscriptionEndDate,
    });
  });

  return { success: true, subscriptionEndDate: subscriptionEndDate.toDate() };
});

/**
 * Crée une session de paiement Chargily Pay pour le forfait choisi et
 * renvoie l'URL de checkout à ouvrir dans le navigateur. Appelée depuis
 * l'app (PaymentService.createCheckout) — jamais de clé secrète côté
 * client, tout part d'ici.
 */
exports.createChargilyCheckout = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Connecte-toi d\'abord.');
  }
  const planId = data.planId;
  const plan = PLANS[planId];
  if (!plan) {
    throw new functions.https.HttpsError('invalid-argument', 'Forfait inconnu.');
  }

  const { secretKey, baseUrl } = chargilyConfig();
  if (!secretKey) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Paiement automatique non configuré (clé Chargily manquante).'
    );
  }

  const storeId = context.auth.uid;

  const res = await fetch(`${baseUrl}/checkouts`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${secretKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      amount: plan.prixDA,
      currency: 'dzd',
      description: `Abonnement El Bouni Pièces Auto — forfait ${plan.nom}`,
      success_url: 'https://elbouni-pieces-auto.web.app/abonnement-succes',
      failure_url: 'https://elbouni-pieces-auto.web.app/abonnement-echec',
      webhook_endpoint:
        'https://us-central1-fakerni-b96c2.cloudfunctions.net/chargilyWebhook',
      locale: 'fr',
      metadata: { storeId, planId },
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error('Erreur création checkout Chargily :', res.status, errText);
    throw new functions.https.HttpsError(
      'internal',
      'Impossible de créer la session de paiement.'
    );
  }

  const checkout = await res.json();
  return { checkoutUrl: checkout.checkout_url };
});

/**
 * Webhook Chargily Pay : reçoit la confirmation "checkout.paid" et active
 * automatiquement l'abonnement du magasin concerné pour la durée du
 * forfait payé. C'est ce qui rend le paiement "automatique" — le magasin
 * n'a rien d'autre à faire une fois la carte validée sur la page Chargily.
 */
exports.chargilyWebhook = functions.https.onRequest(async (req, res) => {
  const { webhookSecret } = chargilyConfig();
  const signature = req.headers['signature'];

  if (webhookSecret) {
    const expected = crypto
      .createHmac('sha256', webhookSecret)
      .update(req.rawBody)
      .digest('hex');
    if (!signature || signature !== expected) {
      console.warn('Signature webhook Chargily invalide — requête ignorée.');
      res.status(401).send('Signature invalide.');
      return;
    }
  }

  const event = req.body;
  if (event.type !== 'checkout.paid') {
    // On ignore les autres événements (checkout.failed, etc.) — le
    // magasin reste simplement en 'paiement_en_attente'.
    res.status(200).send('OK');
    return;
  }

  const checkout = event.data;
  const storeId = checkout.metadata?.storeId;
  const planId = checkout.metadata?.planId;
  const plan = PLANS[planId];

  if (!storeId || !plan) {
    console.error('Webhook Chargily sans storeId/planId exploitable.', checkout.metadata);
    res.status(200).send('OK'); // on accuse réception quand même
    return;
  }

  const subscriptionEndDate = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + plan.dureeJours * 24 * 60 * 60 * 1000)
  );

  const db = admin.firestore();
  const storeRef = db.collection('stores').doc(storeId);
  const paymentRef = storeRef.collection('payment_requests').doc();

  await db.runTransaction(async (tx) => {
    tx.set(paymentRef, {
      storeId,
      planId,
      montant: plan.prixDA,
      methode: 'Chargily (carte)',
      statut: 'valide',
      dateEnvoi: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(storeRef, {
      subscriptionStatus: 'actif',
      subscriptionEndDate,
      currentPlanId: planId,
    });
  });

  console.log(`Abonnement activé automatiquement pour ${storeId} (${planId}).`);
  res.status(200).send('OK');
});
