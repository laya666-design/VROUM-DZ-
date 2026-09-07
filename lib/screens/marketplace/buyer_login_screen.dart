import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/marketplace_service.dart';
import '../buyer_portal_screen.dart';
import 'buyer_forgot_password_screen.dart';
import 'buyer_phone_login_screen.dart';
import 'buyer_signup_screen.dart';
import '../../widgets/google_signin_button.dart';

/// Connexion acheteur par email + mot de passe — alternative au flux
/// téléphone (voir BuyerPhoneLoginScreen), même structure que
/// StoreLoginScreen côté magasin.
class BuyerLoginScreen extends StatefulWidget {
  final AppConfig config;
  final bool isAr;
  const BuyerLoginScreen({
    super.key,
    required this.config,
    this.isAr = false,
  });

  @override
  State<BuyerLoginScreen> createState() => _BuyerLoginScreenState();
}

class _BuyerLoginScreenState extends State<BuyerLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _googleLoading = false;


  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await MarketplaceService.signInWithGoogle();
      _goToPortail();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _goToPortail() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BuyerPortalScreen(config: widget.config, isAr: widget.isAr),
      ),
    );
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await MarketplaceService.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      _goToPortail();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Connexion impossible.');
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BuyerForgotPasswordScreen(
          config: widget.config,
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.config.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Portail acheteur'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.person_rounded, size: 56),
              const SizedBox(height: 8),
              const Text(
                'Retrouve tes demandes et suis les réponses des magasins.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _goToForgotPassword,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Mot de passe oublié ?'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const OrDivider(),
              GoogleSignInButton(
                onPressed: _googleLoading || _loading ? null : _signInWithGoogle,
                isLoading: _googleLoading,
                accentColor: widget.config.primaryColor,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading ? null : _login,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: widget.config.primaryColor,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Se connecter'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BuyerSignupScreen(
                      config: widget.config,
                      isAr: widget.isAr,
                    ),
                  ),
                ),
                child: const Text('Créer un compte acheteur'),
              ),
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BuyerPhoneLoginScreen(
                      config: widget.config,
                      isAr: widget.isAr,
                    ),
                  ),
                ),
                child: const Text('Utiliser le téléphone à la place'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
