# Architecture VROUM Native

Architecture adaptée au marché algérien et au conducteur algérien.

## Principes

1. **Mode invité par défaut** — Aucune connexion forcée au démarrage
2. **Téléphone = identité principale**
3. **WhatsApp comme canal de communication n°1**
4. **Wilaya au centre** (SOS, magasins, pièces)
5. **Friction minimale** — On demande le compte seulement quand c’est utile

## Parcours

```
Splash (roue)
    ↓
Accueil libre (Conducteur / Invité)
    ├── Mes Véhicules      → 100% local (Hive + OCR ML Kit)
    ├── Chercher une pièce → 3 essais gratuits sans compte
    ├── SOS Panne          → Téléphone + Wilaya uniquement
    ├── Magasins           → Consultation libre
    └── Profil
          └── Espace Pro   → Magasin / Dépanneuse (opt-in)
```

## Authentification

- **Méthode** : Téléphone + Mot de passe
- **Email** : optionnel (recommandé pour reset)
- **Mot de passe oublié** :
  - Si email présent → reset par email (gratuit)
  - Sinon → SMS OTP Firebase (tu es déjà sur Blaze)

## Quand on demande le compte

| Action                        | Compte requis ? | Ce qu’on demande              |
|------------------------------|-----------------|-------------------------------|
| Scanner assurance / CT       | Non             | —                             |
| Voir les magasins            | Non             | —                             |
| Identifier une pièce (×3)    | Non             | —                             |
| Identifier une pièce (après) | Oui             | Téléphone + Mot de passe      |
| Publier une demande de pièce | Oui             | Téléphone + Mot de passe      |
| Envoyer un SOS               | Léger           | Téléphone + Wilaya uniquement |
| Espace Pro                   | Oui             | Compte complet                |

## Changements réalisés dans ce code

- `SplashScreen` : plus de RoleSelection forcé → Accueil Conducteur par défaut
- `RoleSelectionScreen` : accessible uniquement via Profil → « Espace Pro »
- `ProfileScreen` : bouton « Espace Pro » ajouté
- Onboarding profil véhicule : plus imposé au premier lancement

## Prochaines étapes recommandées

1. Créer les écrans `PhonePasswordLoginScreen` / `PhonePasswordSignupScreen`
2. Brancher Firebase Auth (email synthétique ou custom token) pour Téléphone + Mot de passe
3. Limiter les scans Gemini à 3 sans compte
4. Afficher clairement « Espace Pro » et le rendre plus visible si besoin

## Pourquoi ça cartonne en Algérie

- Respecte les habitudes (téléphone, WhatsApp, wilaya)
- Donne de la valeur avant de demander l’engagement
- Évite la friction des apps « compte d’abord »
- Reste simple pour un conducteur de 40 ans à El Bouni ou Sétif
