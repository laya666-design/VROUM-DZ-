import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/marketplace_service.dart';
import '../../services/store_service.dart';
import '../buyer_portal_screen.dart';
import '../parts_portal_screen.dart';
import 'buyer_login_screen.dart';
import 'widgets/reset_password_email_dialog.dart';
import '../../widgets/google_signin_button.dart';

/// Connexion acheteur — panel identique à l'Espace Pro Magasin
/// (téléphone + mot de passe). Le numéro est converti en email
/// technique pour Firebase Auth (voir MarketplaceService).
class BuyerPhoneLoginScreen extends StatefulWidget {
  final AppConfig config;
  final bool isAr;
  const BuyerPhoneLoginScreen({
    super.key,
    required this.config,
    this.isAr = false,
  });

  @override
  State<BuyerPhoneLoginScreen> createState() => _BuyerPhoneLoginScreenState();
}

class _BuyerPhoneLoginScreenState extends State<BuyerPhoneLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _modeInscription = false;
  bool _motDePasseVisible = false;
  String? _error;
  bool _googleLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final phoneRaw = _phoneController.text;
    final password = _passwordController.text;

    // Validation basique du numéro (même règle que côté magasin, via
    // le message d'erreur ; la normalisation réelle est faite dans
    // MarketplaceService, qui accepte les mêmes formats).
    final digits = phoneRaw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9) {
      setState(() => _error =
          'Numéro invalide ($digits, ${digits.length} chiffres). '
          'Utilise le format 0556 65 32 20.');
      return;
    }
    if (password.length < 6) {
      setState(
          () => _error = 'Le mot de passe doit faire au moins 6 caractères.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_modeInscription) {
        await MarketplaceService.signUpWithPhonePassword(
          telephone: phoneRaw,
          password: password,
        );
      } else {
        await MarketplaceService.signInWithPhonePassword(
          telephone: phoneRaw,
          password: password,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              BuyerPortalScreen(config: widget.config, isAr: widget.isAr),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
      await MarketplaceService.signInWithGoogle();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BuyerPortalScreen(config: widget.config, isAr: widget.isAr),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: '',
      hintText: hint,
      prefixIcon: Icon(prefix, size: 20, color: Colors.black45),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF5F5F7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: widget.config.primaryColor, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.config.primaryColor;
    final busy = _loading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Croix = retour à l'écran précédent (le portail acheteur,
            // lui-même un onglet du menu principal). Bug corrigé : cet
            // écran est normalement empilé au-dessus du menu principal
            // (HomeScreen) ; un pushAndRemoveUntil ici videait TOUTE la
            // pile de navigation (y compris le menu principal avec ses
            // onglets Véhicules/Motos/Pièces/Rappels/Profil), laissant
            // l'utilisateur bloqué sans aucun moyen d'y retourner. Un
            // simple retour (pop), avec repli sur le menu principal si
            // jamais il n'y a rien à dépiler, résout le problème.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Retour',
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => PartsPortalScreen(
                              config: widget.config,
                              isAr: widget.isAr,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    // Logo / marque
                    Icon(Icons.person_rounded, size: 48, color: primary),
                    const SizedBox(height: 12),
                    Text(
                      'Portail acheteur',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withOpacity(0.87),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _modeInscription
                          ? 'Crée ton compte pour suivre tes demandes'
                          : 'Bon retour ! Connecte-toi pour continuer',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Téléphone
                    const Text(
                      'Téléphone',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      enabled: !busy,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        hint: '0556 65 32 20',
                        prefix: Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Mot de passe
                    const Text(
                      'Mot de passe',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_motDePasseVisible,
                      enabled: !busy,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _valider(),
                      decoration: _fieldDecoration(
                        hint: 'Entrez votre mot de passe',
                        prefix: Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _motDePasseVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: Colors.black45,
                          ),
                          onPressed: () => setState(
                              () => _motDePasseVisible = !_motDePasseVisible),
                        ),
                      ),
                    ),

                    // Mot de passe oublié
                    if (!_modeInscription)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  final numero = StoreService
                                      .normaliserNumeroLocal(
                                          _phoneController.text);
                                  if (numero == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Entre d\'abord ton numéro de téléphone ci-dessus.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  showResetPasswordEmailDialog(
                                    context: context,
                                    primaryColor: primary,
                                    onEnvoyer: (email) =>
                                        MarketplaceService.demanderResetParEmail(
                                      telephone: numero,
                                      email: email,
                                    ),
                                  );
                                },
                          style: TextButton.styleFrom(
                            foregroundColor: primary,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Mot de passe oublié ?',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Bouton principal
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: busy ? null : _valider,
                        style: FilledButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _modeInscription
                                    ? 'Créer mon compte'
                                    : 'Connexion',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),

                    const OrDivider(),
                    GoogleSignInButton(
                      onPressed: _googleLoading || busy ? null : _signInWithGoogle,
                      isLoading: _googleLoading,
                      accentColor: primary,
                    ),
                    const SizedBox(height: 24),

                    // Lien email
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BuyerLoginScreen(
                                    config: widget.config,
                                    isAr: widget.isAr,
                                  ),
                                ),
                              );
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black54,
                      ),
                      child: const Text(
                        'Se connecter avec un e-mail',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Inscription / connexion
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _modeInscription
                              ? 'Déjà un compte ? '
                              : 'Pas encore de compte ? ',
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black54),
                        ),
                        GestureDetector(
                          onTap: busy
                              ? null
                              : () => setState(() {
                                    _modeInscription = !_modeInscription;
                                    _error = null;
                                  }),
                          child: Text(
                            _modeInscription ? 'Se connecter' : "S'inscrire",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
