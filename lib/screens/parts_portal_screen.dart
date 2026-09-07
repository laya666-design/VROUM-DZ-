import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/store_service.dart';
import 'buyer_portal_screen.dart';
import 'marketplace/store_dashboard_screen.dart';
import 'marketplace/store_login_screen.dart';

/// Entrée de l'onglet "Pièces" : deux branches distinctes.
/// - Portail acheteur : accessible à tous les clients (scan photo + suivi
///   de "Mes demandes").
/// - Portail vendeur (Espace magasin) : réservé aux magasins, protégé par
///   un compte (email/mot de passe, chaque magasin a son propre ID dans
///   l'app). Un client sans compte magasin ne peut jamais y entrer.
class PartsPortalScreen extends StatelessWidget {
  final AppConfig config;
  final bool isAr;
  const PartsPortalScreen({super.key, required this.config, this.isAr = false});

  bool get _ar => isAr;
  String _t(String fr, String ar) => _ar ? ar : fr;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_t('Pièces détachées', 'قطع الغيار'),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              _t('Choisis ton profil pour continuer.', 'اختر ملفك للمتابعة.'),
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 28),
            _PortalCard(
              icon: Icons.camera_alt_outlined,
              title: _t('Portail acheteur', 'بوابة المشتري'),
              subtitle: _t(
                'Photographie ta pièce cassée, obtiens la référence et '
                'diffuse ta demande aux magasins.',
                'صوّر القطعة المكسورة، احصل على المرجع وأرسل طلبك للمتاجر.',
              ),
              color: config.primaryColor,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BuyerPortalScreen(config: config, isAr: isAr),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _PortalCard(
              icon: Icons.storefront_outlined,
              title: _t('Portail vendeur — Espace magasin', 'بوابة البائع'),
              subtitle: _t(
                'Réservé aux magasins : reçois les commandes des clients, '
                'réponds avec ton prix, gère ton abonnement.',
                'مخصص للمتاجر: استقبل الطلبات، أجب بالسعر، أدر اشتراكك.',
              ),
              color: Colors.black87,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoreService.isLoggedIn
                      ? StoreDashboardScreen(config: config)
                      : StoreLoginScreen(config: config),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PortalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
