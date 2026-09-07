import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'firebase_options.dart';
import 'config/app_config.dart';
import 'screens/home_screen.dart';
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

class AjalakApp extends StatefulWidget {
  const AjalakApp({super.key});
  @override
  State<AjalakApp> createState() => _AjalakAppState();
}

class _AjalakAppState extends State<AjalakApp> {
  final ValueNotifier<bool> isAr = ValueNotifier(false);

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current();
    return ValueListenableBuilder<bool>(
      valueListenable: isAr,
      builder: (context, arActive, _) {
        return MaterialApp(
          title: config.appName,
          debugShowCheckedModeBanner: false,
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
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: config.primaryColor,
              primary: config.primaryColor,
            ),
          ),
          home: HomeScreen(config: config, isAr: isAr),
        );
      },
    );
  }
}
