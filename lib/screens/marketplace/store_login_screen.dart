import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/store_service.dart';
import 'store_dashboard_screen.dart';
import 'store_signup_screen.dart';

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

  void _goToDashboard() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StoreDashboardScreen(config: widget.config),
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

  Future<void> _loginWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await StoreService.signInWithGoogle(rememberMe: _rememberMe);
      _goToDashboard();
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.config.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Espace Pro — Magasin'),
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
              const SizedBox(height: 4),
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
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('ou', style: TextStyle(color: Colors.black45)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _loginWithGoogle,
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Continuer avec Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 8),
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
            ],
          ),
        ),
      ),
    );
  }
}
