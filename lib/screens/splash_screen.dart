import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:video_player/video_player.dart';
import '../config/app_config.dart';
import 'role_router.dart';

/// Splash plein écran en 2 temps :
/// 1) vidéo d'intro (assets/video/splash_intro.mp4)
/// 2) demande de permission notifications
/// 3) vidéo de la roue qui tourne (assets/video/splash_wheel.mp4)
/// Puis route selon le rôle (ou RoleSelectionScreen au premier lancement).
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

enum _SplashStage { intro, wheel }

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  _SplashStage _stage = _SplashStage.intro;
  bool _initialized = false;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    _playVideo('assets/video/splash_intro.mp4', onDone: _afterIntro);
  }

  void _playVideo(String asset, {required VoidCallback onDone}) {
    _initialized = false;
    _advancing = false;
    _controller = VideoPlayerController.asset(asset)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        _controller.setLooping(false);
        _controller.setVolume(0);
        _controller.play();
        _controller.addListener(() => _onVideoUpdate(onDone));
      }).catchError((e) {
        onDone();
      });

    // Filet de sécurité si la vidéo ne se termine jamais correctement.
    Future.delayed(const Duration(seconds: 8), () {
      if (!_advancing) {
        _advancing = true;
        onDone();
      }
    });
  }

  void _onVideoUpdate(VoidCallback onDone) {
    if (_advancing) return;
    if (_controller.value.position >= _controller.value.duration) {
      _advancing = true;
      onDone();
    }
  }

  Future<void> _afterIntro() async {
    if (!mounted || _stage != _SplashStage.intro) return;
    _advancing = true;

    // Écran neutre (fond noir, sans vidéo) pendant la demande de
    // permission : ça garantit une vraie coupure visuelle entre les deux
    // vidéos, qui sinon peuvent sembler "collées" si Android a déjà
    // mémorisé la décision d'un test précédent et ne réaffiche pas la
    // popup (comportement système normal, hors de notre contrôle après
    // la 1ère décision).
    if (mounted) setState(() => _initialized = false);

    // Demandée ici (et pas dans main()) pour que la popup système
    // n'apparaisse qu'après la vidéo d'intro, et avant la vidéo de la roue.
    final permission = FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true)
        .catchError((_) {
      // Si ça échoue (permission déjà tranchée, etc.), on continue quand
      // même vers la suite du splash.
      return null;
    });

    // Délai minimum pour garantir la coupure visuelle même quand la popup
    // ne s'affiche pas (permission déjà accordée/refusée auparavant).
    await Future.wait([
      permission,
      Future.delayed(const Duration(milliseconds: 700)),
    ]);

    if (!mounted) return;
    await _controller.dispose();
    setState(() => _stage = _SplashStage.wheel);
    _playVideo('assets/video/splash_wheel.mp4', onDone: _goToApp);
  }

  void _goToApp() {
    if (!mounted || _stage != _SplashStage.wheel) return;

    // Le choix de l'écran suivant vit dans RoleRouter, partagé avec
    // RoleSelectionScreen — jamais dupliqué ici.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            RoleRouter.resolve(config: widget.config, isAr: widget.isAr),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
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
