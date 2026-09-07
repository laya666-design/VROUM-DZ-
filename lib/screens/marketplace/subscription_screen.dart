import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../services/marketplace_models.dart';
import '../../services/payment_service.dart';
import '../../services/store_service.dart';

/// Espace abonnement du magasin : statut de l'essai/abonnement en cours,
/// choix d'un forfait, et paiement automatique par carte (Chargily Pay —
/// CIB / Edahabia). Une option "j'ai déjà payé par virement/CCP" reste
/// disponible en repli pour les magasins sans carte bancaire.
class SubscriptionScreen extends StatefulWidget {
  final AppConfig config;
  final StoreProfile profile;
  const SubscriptionScreen(
      {super.key, required this.config, required this.profile});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String _planId = kSubscriptionPlans.first.id;
  bool _payingAuto = false;
  bool _showManuel = false;

  // -- Paiement manuel (virement / CCP / Baridimob), en repli --
  File? _recu;
  String _methode = 'Baridimob';
  bool _sendingManuel = false;

  SubscriptionPlan get _planChoisi =>
      kSubscriptionPlans.firstWhere((p) => p.id == _planId);

  Future<void> _payerAutomatique() async {
    setState(() => _payingAuto = true);
    try {
      final url = await PaymentService.createCheckout(_planId);
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir la page de paiement.')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Termine le paiement dans le navigateur. Ton abonnement '
              's\'active automatiquement dès confirmation.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _payingAuto = false);
    }
  }

  Future<void> _choisirRecu() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img == null) return;
    setState(() => _recu = File(img.path));
  }

  Future<void> _envoyerManuel() async {
    if (_recu == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute une photo du reçu.')),
      );
      return;
    }
    setState(() => _sendingManuel = true);
    try {
      await StoreService.submitPaymentProof(
        recu: _recu!,
        montant: _planChoisi.prixDA,
        methode: _methode,
        planId: _planId,
      );
      if (!mounted) return;
      setState(() => _recu = null);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Preuve envoyée'),
          content: const Text(
            'Ton paiement est en cours de vérification. Ton abonnement '
            'sera activé dès validation (généralement sous 24h).',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Compris'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingManuel = false);
    }
  }

  Widget _statutCard() {
    final p = widget.profile;
    late final String titre;
    late final String sousTitre;
    late final Color couleur;
    late final IconData icone;

    switch (p.subscriptionStatus) {
      case SubscriptionStatus.essai:
        final j = p.joursRestants;
        titre = j > 0 ? 'Essai gratuit — $j jour(s) restant(s)' : 'Essai terminé';
        sousTitre = j > 0
            ? 'Profite de l\'essai gratuit, aucun paiement requis.'
            : 'Ton essai gratuit est terminé. Choisis un forfait pour '
                'continuer à recevoir des demandes.';
        couleur = j > 0 ? Colors.green : Colors.red;
        icone = j > 0 ? Icons.card_giftcard : Icons.lock_clock;
        break;
      case SubscriptionStatus.actif:
        final j = p.joursRestants;
        final nomPlan = kSubscriptionPlans
            .where((pl) => pl.id == p.currentPlanId)
            .map((pl) => pl.nom)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);
        titre = j > 0
            ? 'Abonnement ${nomPlan ?? ''} actif — $j jour(s) restant(s)'
            : 'Abonnement expiré';
        sousTitre = j > 0
            ? 'Merci ! Tu reçois toutes les demandes de pièces.'
            : 'Ton abonnement est terminé. Renouvelle pour continuer.';
        couleur = j > 0 ? Colors.green : Colors.red;
        icone = j > 0 ? Icons.verified : Icons.lock_clock;
        break;
      case SubscriptionStatus.enAttente:
        titre = 'Paiement en cours de vérification';
        sousTitre = 'On valide généralement sous 24h. Reviens un peu plus tard.';
        couleur = Colors.orange;
        icone = Icons.hourglass_top;
        break;
      default:
        titre = 'Abonnement expiré';
        sousTitre = 'Choisis un forfait pour recevoir les demandes de pièces.';
        couleur = Colors.red;
        icone = Icons.lock_clock;
    }

    return Card(
      color: couleur.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icone, color: couleur, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre, style: TextStyle(fontWeight: FontWeight.bold, color: couleur)),
                  const SizedBox(height: 4),
                  Text(sousTitre, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _forfaitCard(SubscriptionPlan p) {
    final selected = p.id == _planId;
    final mensualise = p.prixParMoisDA.round();
    return InkWell(
      onTap: () => setState(() => _planId = p.id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? widget.config.primaryColor : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected ? widget.config.primaryColor.withOpacity(0.06) : null,
        ),
        child: Row(
          children: [
            Radio<String>(
              value: p.id,
              groupValue: _planId,
              activeColor: widget.config.primaryColor,
              onChanged: (v) => setState(() => _planId = v ?? _planId),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('≈ $mensualise DA / mois',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            Text('${p.prixDA} DA',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final peutPayer = p.subscriptionStatus != SubscriptionStatus.enAttente;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.config.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Mon abonnement'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge_outlined, size: 16, color: Colors.black54),
                  const SizedBox(width: 6),
                  Text('ID magasin : ${p.idCourt}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _statutCard(),
            if (peutPayer) ...[
              const SizedBox(height: 20),
              Text('Choisis un forfait', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ...kSubscriptionPlans.map(_forfaitCard),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _payingAuto ? null : _payerAutomatique,
                icon: _payingAuto
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.credit_card),
                label: Text(_payingAuto
                    ? 'Ouverture du paiement…'
                    : 'Payer ${_planChoisi.prixDA} DA par carte (CIB / Edahabia)'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: widget.config.primaryColor,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Paiement 100% automatique via Chargily Pay : ton abonnement '
                's\'active dès la confirmation, sans rien envoyer.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _showManuel = !_showManuel),
                child: Text(_showManuel
                    ? 'Masquer le paiement par virement/CCP'
                    : 'Pas de carte ? Payer par virement / CCP / Baridimob'),
              ),
              if (_showManuel) ...[
                const Divider(height: 24),
                DropdownButtonFormField<String>(
                  value: _methode,
                  decoration: const InputDecoration(
                    labelText: 'Méthode de paiement',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Baridimob', child: Text('Baridimob')),
                    DropdownMenuItem(value: 'CCP', child: Text('CCP')),
                    DropdownMenuItem(value: 'Virement', child: Text('Virement bancaire')),
                  ],
                  onChanged: (v) => setState(() => _methode = v ?? 'Baridimob'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _choisirRecu,
                  icon: const Icon(Icons.photo_camera),
                  label: Text(_recu == null ? 'Ajouter la photo du reçu' : 'Reçu sélectionné ✓'),
                ),
                if (_recu != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_recu!, height: 160, fit: BoxFit.cover),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sendingManuel ? null : _envoyerManuel,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: _sendingManuel
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Envoyer la preuve de paiement'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
