import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../config/wilayas.dart';
import '../../services/sos_service.dart';
import '../role_router.dart';
import 'depanneuse_dashboard_screen.dart';
import 'depanneuse_shell_screen.dart';

/// Connexion / inscription dépanneuse — accès caché (appui long sur le
/// bouton SOS), même mécanisme téléphone + mot de passe que l'Espace Pro
/// magasin, mais compte séparé (collection Firestore `depanneuses`).
class DepanneuseAuthScreen extends StatefulWidget {
  final AppConfig config;
  const DepanneuseAuthScreen({super.key, required this.config});

  @override
  State<DepanneuseAuthScreen> createState() => _DepanneuseAuthScreenState();
}

class _DepanneuseAuthScreenState extends State<DepanneuseAuthScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nomController = TextEditingController();

  bool _loading = false;
  bool _modeInscription = false;
  bool _motDePasseVisible = false;
  String? _error;
  String? _wilaya;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _nomController.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final password = _passwordController.text;
    if (password.length < 6) {
      setState(() => _error = 'Le mot de passe doit faire au moins 6 caractères.');
      return;
    }
    if (_modeInscription) {
      if (_nomController.text.trim().isEmpty) {
        setState(() => _error = 'Indique le nom de la dépanneuse.');
        return;
      }
      if (_wilaya == null) {
        setState(() => _error = 'Choisis ta wilaya.');
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_modeInscription) {
        await SosService.signUp(
          telephone: _phoneController.text,
          password: password,
          nom: _nomController.text.trim(),
          wilaya: _wilaya!,
        );
      } else {
        await SosService.signIn(
          telephone: _phoneController.text,
          password: password,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DepanneuseShellScreen(config: widget.config),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
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
        borderSide: BorderSide(color: widget.config.sosColor, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sos = widget.config.sosColor;
    final busy = _loading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    // Cet écran est toujours atteint par un pushReplacement
                    // (accès caché SOS, ou déconnexion) : il n'y a jamais de
                    // route précédente à dépiler, donc Navigator.maybePop ne
                    // faisait rien. La croix ramène explicitement au choix
                    // de profil (les 3 cartes).
                    onPressed: () => RoleRouter.changerDeProfil(context),
                    icon: const Icon(Icons.close, size: 22),
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
                    Image.asset(
                      'assets/images/icon_depanneuse.png',
                      height: 56,
                      errorBuilder: (context, error, stack) =>
                          Icon(Icons.local_shipping_rounded, size: 48, color: sos),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Espace Dépanneuse',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _modeInscription
                          ? 'Crée ton compte pour recevoir les alertes de panne de ta wilaya'
                          : 'Connecte-toi pour voir les alertes de ta wilaya',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 28),

                    if (_modeInscription) ...[
                      TextField(
                        controller: _nomController,
                        enabled: !busy,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          hint: 'Nom de la dépanneuse',
                          prefix: Icons.badge_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _wilaya,
                        decoration: _fieldDecoration(
                          hint: 'Wilaya',
                          prefix: Icons.map_outlined,
                        ),
                        items: kWilayasAlgerie
                            .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                            .toList(),
                        onChanged: busy ? null : (v) => setState(() => _wilaya = v),
                      ),
                      const SizedBox(height: 12),
                    ],

                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      enabled: !busy,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        hint: 'Téléphone : 0556 65 32 20',
                        prefix: Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_motDePasseVisible,
                      enabled: !busy,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _valider(),
                      decoration: _fieldDecoration(
                        hint: 'Mot de passe',
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

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 20),

                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: busy ? null : _valider,
                        style: FilledButton.styleFrom(
                          backgroundColor: sos,
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

                    const SizedBox(height: 20),

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
                              color: sos,
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
