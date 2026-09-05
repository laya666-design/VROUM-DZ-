import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/marketplace_service.dart';
import 'buyer_portal_screen.dart';

/// Entrée de l'onglet "Pièces" du conducteur.
/// Va directement au portail acheteur (scan photo), session ou pas : la
/// connexion (numéro + mot de passe) n'est demandée qu'au moment où elle
/// devient utile (ex: retrouver ses anciennes demandes), jamais avant.
/// L'envoi d'une demande fonctionne déjà sans connexion préalable
/// (MarketplaceService.ensureSignedIn crée une session anonyme au besoin).
class PartsPortalScreen extends StatefulWidget {
  final AppConfig config;
  final bool isAr;
  const PartsPortalScreen({super.key, required this.config, this.isAr = false});

  @override
  State<PartsPortalScreen> createState() => _PartsPortalScreenState();
}

class _PartsPortalScreenState extends State<PartsPortalScreen> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await MarketplaceService.loadPhoneAsId();
    if (!mounted) return;
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return BuyerPortalScreen(config: widget.config, isAr: widget.isAr);
  }
}
