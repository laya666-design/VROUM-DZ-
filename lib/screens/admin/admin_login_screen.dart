import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/admin_service.dart';
import 'admin_dashboard_screen.dart';
import 'admin_forgot_password_screen.dart';
import '../../widgets/google_signin_button.dart';

/// Écran de connexion admin — accessible uniquement via l'appui long
/// caché sur "À propos" dans l'onglet Profil (pas de bouton visible pour
/// les utilisateurs normaux ni pour les magasins).
class AdminLoginScreen extends StatefulWidget {
  final AppConfig config;
  const AdminLoginScreen({super.key, required this.config});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _googleLoading = false;

  /// true = connexion par téléphone (secours si l'email est bloqué),
  /// false = connexion par email (méthode principale).
  bool _viaTelephone = false;

  /// Tant que ceci vaut true, on affiche un loader plutôt que le
  /// formulaire : le temps de vérifier si une session admin valide
  /// existe déjà (Firebase Auth garde la session active tout seul
  /// entre deux ouvertures de l'écran — inutile de redemander l'email
  /// et le mot de passe si le token porte déjà le claim admin).
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final isAdmin = await AdminService.isCurrentUserAdmin();
      if (isAdmin) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminDashboardScreen(config: widget.config),
          ),
        );
        return;
      }
    }
    if (mounted) setState(() => _checkingSession = false);
  }


  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _googleLoading = true;
      _error = null;
    });
    try {
      await AdminService.signInWithGoogle();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboardScreen(config: widget.config),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() {
        _loading = false;
        _googleLoading = false;
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_viaTelephone) {
        await AdminService.signInWithPhone(
          telephone: _phoneController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await AdminService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      // force: true car le token qui vient d'être émis à la connexion
      // ne contient pas encore le claim admin s'il a été posé après.
      final isAdmin = await AdminService.isCurrentUserAdmin(force: true);
      if (!isAdmin) {
        await AdminService.signOut();
        setState(() => _error = 'Ce compte n\'a pas les droits admin.');
        return;
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboardScreen(config: widget.config),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Connexion impossible.');
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return Scaffold(
        appBar: AppBar(title: const Text('Espace Admin')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Espace Admin')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.admin_panel_settings, size: 56),
                      const SizedBox(height: 24),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Email'),
                            icon: Icon(Icons.email_outlined),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Téléphone'),
                            icon: Icon(Icons.phone_outlined),
                          ),
                        ],
                        selected: {_viaTelephone},
                        onSelectionChanged: _loading
                            ? null
                            : (s) => setState(() {
                                  _viaTelephone = s.first;
                                  _error = null;
                                }),
                      ),
                      const SizedBox(height: 16),
                      if (_viaTelephone) ...[
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Téléphone admin',
                            hintText: '0556 65 32 20',
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'À utiliser si l\'email est bloqué ou inaccessible. Le '
                          'numéro doit avoir été associé au compte au préalable.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ] else
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email admin'),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Mot de passe'),
                        onSubmitted: (_) => _login(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                      ],
                      if (!_viaTelephone)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _loading
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AdminForgotPasswordScreen(
                                          config: widget.config,
                                          initialEmail: _emailController.text.trim(),
                                        ),
                                      ),
                                    ),
                            child: const Text('Mot de passe oublié ?'),
                          ),
                        ),
                      const SizedBox(height: 4),
                      GoogleSignInButton(
                onPressed: _googleLoading || _loading ? null : _signInWithGoogle,
                isLoading: _googleLoading,
              ),
              const SizedBox(height: 12),
              FilledButton(
                        onPressed: _loading ? null : _login,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Se connecter'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
