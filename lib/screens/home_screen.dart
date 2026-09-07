import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/vehicule.dart';
import 'parts_portal_screen.dart';
import 'profile_screen.dart';
import 'vehicles_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppConfig config;
  final ValueNotifier<bool> isAr;

  const HomeScreen({super.key, required this.config, required this.isAr});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isAr,
      builder: (context, isAr, _) {
        final screens = [
          VehiclesScreen(config: widget.config, isAr: isAr),
          VehiclesScreen(
            config: widget.config,
            isAr: isAr,
            types: const [TypeVehicule.moto, TypeVehicule.scooter],
            titre: 'Motos & scooters',
            titreAr: 'الدراجات النارية',
            sousTitre:
                'Assurance, vignette et contrôle technique, par deux-roues.',
            sousTitreAr: 'التأمين والرخصة والفحص التقني، لكل دراجة.',
            iconePrincipale: Icons.two_wheeler,
            labelAjout: 'Ajouter une moto / un scooter',
            labelAjoutAr: 'إضافة دراجة نارية / سكوتر',
            labelVide: 'Aucune moto ni scooter pour le moment',
            labelVideAr: 'لا توجد دراجة حتى الآن',
          ),
          PartsPortalScreen(config: widget.config, isAr: isAr),
          ProfileScreen(config: widget.config, isAr: widget.isAr),
        ];

        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: widget.config.primaryColor,
              foregroundColor: Colors.white,
              title: Text(widget.config.appName),
              actions: [
                TextButton(
                  onPressed: () => widget.isAr.value = !isAr,
                  child: Text(
                    isAr ? 'FR' : 'AR',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            body: IndexedStack(index: _index, children: screens),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.directions_car),
                  label: isAr ? 'سياراتي' : 'Véhicules',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.two_wheeler),
                  label: isAr ? 'دراجاتي' : 'Motos',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.build),
                  label: isAr ? 'القطع' : 'Pièces',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person),
                  label: isAr ? 'حسابي' : 'Profil',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
