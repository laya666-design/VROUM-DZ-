import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../config/app_config.dart';

/// Connexion Téléphone + Mot de passe — Architecture VROUM Native.
///
/// Note technique :
/// Firebase Auth n'accepte pas nativement "téléphone + mot de passe".
/// Approche simple et robuste :
/// - On utilise un email synthétique : `{phoneDigits}@vroum.dz`
/// - Le mot de passe est le mot de passe choisi par l'utilisateur
/// - L'email réel (optionnel) est stocké dans Firestore / SharedPreferences pour le reset
class PhonePasswordLoginScreen extends StatefulWidget {
  final AppConfig config;
  final ValueNotifier<bool> isAr;
  final VoidCallback? onSuccess;

  const PhonePasswordLoginScreen({
    super.key,
    required this.config,
    required this.isAr,
    this.onSuccess,
  });

  @override
  State<PhonePasswordLoginScreen> createState() =>
      _PhonePasswordLoginScreenState();
}

class _PhonePasswordLoginScreenState extends State<PhonePasswordLoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('0') && digits.length == 10) {
      return '213${digits.substring(1)}';
    }
    if (digits.startsWith('213')) return digits;
    return digits;
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final phone = _normalizePhone(_phoneCtrl.text.trim());
      if (phone.length < 10) {
        setState(() => _error = 'Numéro de téléphone invalide');
        return;
      }
      final password = _passwordCtrl.text;
      if (password.length < 6) {
        setState(() => _error = 'Mot de passe trop court (min. 6 caractères)');
        return;
      }

      // Email synthétique pour Firebase Auth
      final syntheticEmail = '$phone@vroum.dz';

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: syntheticEmail,
        password: password,
      );

      if (!mounted) return;
      widget.onSuccess?.call();
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
          _error = 'Numéro ou mot de passe incorrect';
        } else {
          _error = e.message ?? 'Erreur de connexion';
        }
      });
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isAr,
      builder: (context, isAr, _) {
        final t = (String fr, String ar) => isAr ? ar : fr;

        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              title: Text(t('Connexion', 'تسجيل الدخول')),
              backgroundColor: widget.config.primaryColor,
              foregroundColor: Colors.black,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t(
                        'Connecte-toi avec ton numéro et ton mot de passe',
                        'سجّل الدخول برقمك وكلمة المرور',
                      ),
                      style: const TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: t('Numéro de téléphone', 'رقم الهاتف'),
                        hintText: '0555 12 34 56',
                        prefixIcon: const Icon(Icons.phone),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: t('Mot de passe', 'كلمة المرور'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          // TODO: naviguer vers forgot password
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(t(
                                'Réinitialisation : email si disponible, sinon SMS',
                                'إعادة التعيين: البريد إن وُجد، وإلا رسالة SMS',
                              )),
                            ),
                          );
                        },
                        child: Text(t('Mot de passe oublié ?', 'نسيت كلمة المرور؟')),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.config.primaryColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              t('Se connecter', 'دخول'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PhonePasswordSignupScreen(
                              config: widget.config,
                              isAr: widget.isAr,
                              onSuccess: widget.onSuccess,
                            ),
                          ),
                        );
                      },
                      child: Text(t(
                        'Pas encore de compte ? S’inscrire',
                        'ليس لديك حساب؟ سجّل الآن',
                      )),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Forward declaration — défini dans le même dossier
class PhonePasswordSignupScreen extends StatefulWidget {
  final AppConfig config;
  final ValueNotifier<bool> isAr;
  final VoidCallback? onSuccess;

  const PhonePasswordSignupScreen({
    super.key,
    required this.config,
    required this.isAr,
    this.onSuccess,
  });

  @override
  State<PhonePasswordSignupScreen> createState() =>
      _PhonePasswordSignupScreenState();
}

class _PhonePasswordSignupScreenState extends State<PhonePasswordSignupScreen> {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('0') && digits.length == 10) {
      return '213${digits.substring(1)}';
    }
    if (digits.startsWith('213')) return digits;
    return digits;
  }

  Future<void> _signup() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final phone = _normalizePhone(_phoneCtrl.text.trim());
      if (phone.length < 10) {
        setState(() => _error = 'Numéro de téléphone invalide');
        return;
      }
      final password = _passwordCtrl.text;
      if (password.length < 6) {
        setState(() => _error = 'Mot de passe trop court (min. 6 caractères)');
        return;
      }

      final syntheticEmail = '$phone@vroum.dz';

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: syntheticEmail,
        password: password,
      );

      // Stocker le téléphone et l'email optionnel dans les custom claims / Firestore
      // pour l'instant on met à jour le displayName
      await cred.user?.updateDisplayName(phone);

      // TODO: sauvegarder email réel dans Firestore si renseigné
      // pour permettre le reset par email

      if (!mounted) return;
      widget.onSuccess?.call();
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'email-already-in-use') {
          _error = 'Ce numéro est déjà inscrit';
        } else if (e.code == 'weak-password') {
          _error = 'Mot de passe trop faible';
        } else {
          _error = e.message ?? 'Erreur d’inscription';
        }
      });
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isAr,
      builder: (context, isAr, _) {
        final t = (String fr, String ar) => isAr ? ar : fr;

        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              title: Text(t('Inscription', 'إنشاء حساب')),
              backgroundColor: widget.config.primaryColor,
              foregroundColor: Colors.black,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t(
                        'Crée ton compte avec ton numéro de téléphone',
                        'أنشئ حسابك برقم هاتفك',
                      ),
                      style: const TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: t('Numéro de téléphone *', 'رقم الهاتف *'),
                        hintText: '0555 12 34 56',
                        prefixIcon: const Icon(Icons.phone),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: t('Mot de passe *', 'كلمة المرور *'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: t(
                          'Email (optionnel, pour récupérer le mot de passe)',
                          'البريد (اختياري، لاستعادة كلمة المرور)',
                        ),
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _signup,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.config.primaryColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              t('Créer mon compte', 'إنشاء حسابي'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
