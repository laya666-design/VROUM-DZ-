import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/store_service.dart';
import '../role_router.dart';
import 'store_dashboard_screen.dart';
import 'magasin_shell_screen.dart';
import 'store_forgot_password_screen.dart';
import 'store_phone_login_screen.dart';
import 'store_signup_screen.dart';
import '../../widgets/google_signin_button.dart';

class StoreLoginScreen extends StatefulWidget {
  final AppConfig config;
  const StoreLoginScreen({super.key, required this.config});

  @override
  State<StoreLoginScreen> createState() => _StoreLoginScreenState();
}

class _StoreLoginScreenState extends State<StoreLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = true;
  bool _loading = false;
  String? _error;
  bool _googleLoading = false;

  void _goToDashboard() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MagasinShellScreen(config: widget.config),
      ),
    );
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await StoreService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        rememberMe: _rememberMe,
      );
      _goToDashboard();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Connexion impossible.');
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await StoreService.signInWithGoogle(rememberMe: _rememberMe);
      _goToDashboard();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _goToForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreForgotPasswordScreen(
          config: widget.config,
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  void _retourProfil() {
    RoleRouter.changerDeProfil(
      context,
      config: widget.config,
      isAr: ValueNotifier<bool>(false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _retourProfil();
      },
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: widget.config.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Espace Pro — Magasin'),
        // Cet écran est toujours atteint par un pushReplacement (choix
        // du rôle, ou déconnexion) : jamais de route précédente à
        // dépiler, donc la flèche retour par défaut ne s'affichait
        // jamais. Une flèche explicite + le bouton retour système
        // ramènent au choix de profil.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: _retourProfil,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.storefront, size: 56),
              const SizedBox(height: 8),
              const Text(
                'Reçois les demandes de pièces des clients autour de toi '
                'et réponds avec ton prix.',
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
              CheckboxListTile(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? true),
                title: const Text('Se souvenir de moi'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
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
                    builder: (_) =>
                        StoreSignupScreen(config: widget.config),
                  ),
                ),
                child: const Text('Créer un compte magasin'),
              ),
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        StorePhoneLoginScreen(config: widget.config),
                  ),
                ),
                child: const Text('Utiliser le téléphone à la place'),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
