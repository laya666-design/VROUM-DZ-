import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../config/app_config.dart';
import 'role_router.dart';

/// Splash plein écran avec la roue qui tourne (VROUM).
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
