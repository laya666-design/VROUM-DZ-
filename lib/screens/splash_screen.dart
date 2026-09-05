import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../config/app_config.dart';
import '../models/user_role.dart';
import '../services/vehicule_service.dart';
import 'home_screen.dart';
import 'marketplace/magasin_shell_screen.dart';
import 'sos/depanneuse_shell_screen.dart';

/// Splash plein écran avec la roue qui tourne (VROUM).
///
/// Architecture VROUM Native :
/// - Par défaut → Accueil Conducteur (mode invité, aucune connexion forcée)
/// - Si l'utilisateur a déjà choisi un rôle Pro (magasin / dépanneuse) → shell pro
/// - Le choix de rôle n'est plus imposé au premier lancement
class SplashScreen extends StatefulWidget {
  final AppConfig config;
  final ValueNotifier<bool> isAr;

  const SplashScreen({
    super.key,
    required this.config,
    required this.isAr,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/video/splash_wheel.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        _controller.setLooping(false);
        _controller.setVolume(0);
        _controller.play();
        _controller.addListener(_onVideoUpdate);
      }).catchError((e) {
        _goToApp();
      });

    Future.delayed(const Duration(seconds: 8), _goToApp);
  }

  void _onVideoUpdate() {
    if (_controller.value.position >= _controller.value.duration &&
        !_navigated) {
      _goToApp();
    }
  }

  void _goToApp() {
    if (_navigated || !mounted) return;
    _navigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _resolveNextScreen(),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// VROUM Native : on ne force plus le RoleSelectionScreen.
  /// - Magasin / Dépanneuse déjà choisis → shell pro
  /// - Sinon → HomeScreen en mode Conducteur (invité)
  Widget _resolveNextScreen() {
    final role = SettingsService.userRole;

    if (role == UserRole.magasin) {
      return MagasinShellScreen(
        config: widget.config,
        isAr: widget.isAr.value,
      );
    }

    if (role == UserRole.depanneuse) {
      return DepanneuseShellScreen(
        config: widget.config,
        isAr: widget.isAr.value,
      );
    }

    // Par défaut : Conducteur (mode invité).
    return HomeScreen(config: widget.config, isAr: widget.isAr);
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _initialized
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            )
          : const Center(
              child: CircularProgressIndicator(color: Color(0xFF00C853)),
            ),
    );
  }
}
