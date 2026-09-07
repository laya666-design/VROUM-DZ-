import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'firebase_options.dart';
import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_profile_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'services/store_service.dart';
import 'services/vehicule_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // "Se souvenir de moi" côté magasin : déconnecte si l'utilisateur avait
  // décoché la case lors de sa dernière connexion.
  await StoreService.applyRememberMePreference();

  // Stockage local (Hive) pour la gestion multi-véhicules — Phase 1.
  await VehiculeService.init();
  await SettingsService.init();

  // Rappels locaux J-30/J-15/J-7 avant expiration.
  await NotificationService.init();

  // Bannière publicitaire (AdMob).
  await MobileAds.instance.initialize();

  runApp(const AjalakApp());
}

/// Vide les SnackBars affichés à chaque changement d'écran.
/// Sans ça, un SnackBar (ex: "Demande envoyée aux magasins.") reste visible
/// et suit l'utilisateur sur les écrans suivants tant que son délai n'est
/// pas écoulé, car un seul ScaffoldMessenger est partagé par toute l'app.
class _ClearSnackBarsOnNavigate extends NavigatorObserver {
  void _clear() {
    final context = navigator?.context;
    if (context != null) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _clear();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _clear();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _clear();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _clear();
  }
}

class AjalakApp extends StatefulWidget {
  const AjalakApp({super.key});
  @override
  State<AjalakApp> createState() => _AjalakAppState();
}

class _AjalakAppState extends State<AjalakApp> {
  final ValueNotifier<bool> isAr = ValueNotifier(false);
  late bool _profileChosen = SettingsService.hasChosenVehicleProfile;
  final _navigatorObserver = _ClearSnackBarsOnNavigate();

  Future<void> _chooseProfile(String value) async {
    await SettingsService.setVehicleProfile(value);
    setState(() => _profileChosen = true);
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current();
    return ValueListenableBuilder<bool>(
      valueListenable: isAr,
      builder: (context, arActive, _) {
        return MaterialApp(
          title: config.appName,
          debugShowCheckedModeBanner: false,
          navigatorObservers: [_navigatorObserver],
          // Bug corrigé : la locale n'était jamais transmise au MaterialApp,
          // donc seuls les libellés traduits à la main changeaient, pas les
          // widgets système (dates, etc.) ni la direction par défaut.
          locale: arActive ? const Locale('ar') : const Locale('fr'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('fr'), Locale('ar')],
          theme: AppTheme.light(config),
          // Splash vidéo de la roue qui tourne (plein écran) au lancement,
          // puis on enchaîne vers l'onboarding ou l'accueil selon le profil.
          home: SplashScreen(config: config, isAr: isAr),
        );
      },
    );
  }
}
