import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/admin_service.dart';
import '../../services/biometric_service.dart';
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

  /// true si une session Firebase admin valide existe déjà mais que la
  /// confirmation biométrique (activée précédemment) reste à faire —
  /// on affiche alors un simple bouton "Déverrouiller" plutôt que le
  /// formulaire email/mot de passe complet.
  bool _biometricLocked = false;
  bool _biometricChecking = false;

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
        final biometricEnabled = await BiometricService.isEnabled();
        if (biometricEnabled && await BiometricService.isAvailable()) {
          final unlocked = await BiometricService.authenticate();
          if (!unlocked) {
            // Session Firebase toujours valide, mais l'utilisateur n'a
            // pas confirmé son empreinte/visage : on ne rentre pas tout
            // seul dans le tableau de bord, on propose de réessayer.
            if (mounted) {
              setState(() {
                _biometricLocked = true;
                _checkingSession = false;
              });
            }
            return;
          }
        }
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

  Future<void> _retryBiometric() async {
    setState(() => _biometricChecking = true);
    final unlocked = await BiometricService.authenticate();
    if (!mounted) return;
    if (unlocked) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboardScreen(config: widget.config),
        ),
      );
      return;
    }
    setState(() => _biometricChecking = false);
  }

  /// Après une connexion email/téléphone/Google réussie : si l'appareil
  /// supporte la biométrie et que l'option n'est pas encore activée, on
  /// propose de l'activer pour la prochaine fois. Ne bloque jamais la
  /// connexion en cours (l'admin accède au tableau de bord quoi qu'il
  /// réponde).
  Future<void> _maybeOfferBiometricEnrollment() async {
    if (await BiometricService.isEnabled()) return;
    if (!await BiometricService.isAvailable()) return;
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connexion biométrique'),
        content: const Text(
          'Utiliser ton empreinte ou ton visage pour retrouver l\'espace '
          'Admin plus vite la prochaine fois, sans retaper l\'email et le '
          'mot de passe ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non merci'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activer'),
          ),
        ],
      ),
    );
    if (accept == true) {
      await BiometricService.setEnabled(true);
    }
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
      await _maybeOfferBiometricEnrollment();
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
      await _maybeOfferBiometricEnrollment();
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
    if (_biometricLocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Espace Admin')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fingerprint, size: 72),
                  const SizedBox(height: 16),
                  const Text(
                    'Session admin retrouvée. Confirme ton identité pour '
                    'continuer.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _biometricChecking ? null : _retryBiometric,
                    icon: _biometricChecking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.fingerprint),
                    label: const Text('Déverrouiller'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _biometricChecking
                        ? null
                        : () async {
                            // Repli : se déconnecter pour revenir au
                            // formulaire email/mot de passe classique
                            // (utile si l'empreinte enregistrée a changé).
                            await AdminService.signOut();
                            if (!mounted) return;
                            setState(() => _biometricLocked = false);
                          },
                    child: const Text('Se connecter autrement'),
                  ),
                ],
              ),
            ),
          ),
        ),
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
