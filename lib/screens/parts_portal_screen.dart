import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/marketplace_service.dart';
import '../widgets/screen_background.dart';
import 'buyer_portal_screen.dart';
import 'marketplace/buyer_phone_login_screen.dart';

/// Onglet "Pièces" — Architecture VROUM Native.
///
/// Uniquement le parcours acheteur (scan pièce + demande aux magasins).
/// L'espace magasin (vendeur) est accessible uniquement via
/// Profil → Espace Pro, pour ne pas polluer l'expérience conducteur.
class PartsPortalScreen extends StatelessWidget {
  final AppConfig config;
  final bool isAr;
  const PartsPortalScreen({super.key, required this.config, this.isAr = false});

  bool get _ar => isAr;
  String _t(String fr, String ar) => _ar ? ar : fr;

  Future<void> _openBuyer(BuildContext context) async {
    await MarketplaceService.loadPhoneAsId();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarketplaceService.hasSession
            ? BuyerPortalScreen(config: config, isAr: isAr)
            : BuyerPhoneLoginScreen(config: config, isAr: isAr),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      category: BackgroundCategory.pieces,
      accentColor: config.primaryColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_t('Pièces détachées', 'قطع الغيار'),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                _t(
                  'Photographie ta pièce, obtiens la référence et contacte les magasins.',
                  'صوّر القطعة، احصل على المرجع واتصل بالمتاجر.',
                ),
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 28),
              _PortalCard(
                icon: Icons.camera_alt_outlined,
                title: _t('Identifier une pièce', 'تعرّف على قطعة'),
                subtitle: _t(
                  'Prends une photo → référence, compatibilité, magasins à proximité.',
                  'التقط صورة → المرجع، التوافق، المتاجر القريبة.',
                ),
                color: config.primaryColor,
                onTap: () => _openBuyer(context),
              ),
              const SizedBox(height: 16),
              _PortalCard(
                icon: Icons.list_alt_outlined,
                title: _t('Mes demandes', 'طلباتي'),
                subtitle: _t(
                  'Suivi des demandes déjà envoyées aux magasins.',
                  'متابعة الطلبات المرسلة للمتاجر.',
                ),
                color: Colors.black87,
                onTap: () => _openBuyer(context),
              ),
            ],
          ),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
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
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
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
