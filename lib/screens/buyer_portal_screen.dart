import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'marketplace/mes_demandes_screen.dart';
import 'parts_screen.dart';

/// Portail acheteur : le scan photo (PartsScreen) avec un accès direct à
/// "Mes demandes" pour suivre les réponses des magasins.
class BuyerPortalScreen extends StatelessWidget {
  final AppConfig config;
  final bool isAr;
  const BuyerPortalScreen({super.key, required this.config, this.isAr = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: config.primaryColor,
        foregroundColor: Colors.white,
        title: Text(isAr ? 'بوابة المشتري' : 'Portail acheteur'),
        actions: [
          IconButton(
            tooltip: isAr ? 'طلباتي' : 'Mes demandes',
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MesDemandesScreen(config: config)),
            ),
          ),
        ],
      ),
      body: PartsScreen(config: config, isAr: isAr),
    );
  }
}
