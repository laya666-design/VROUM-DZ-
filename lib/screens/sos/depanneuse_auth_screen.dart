import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../config/wilayas.dart';
import '../../widgets/google_signin_button.dart';
import '../../services/sos_service.dart';
import '../../services/store_service.dart';
import '../role_router.dart';
import 'depanneuse_dashboard_screen.dart';
import 'depanneuse_shell_screen.dart';

/// Résultat du dialog de complétion de profil après une première
/// connexion Google (voir _showCompleterProfilGoogleDialog).
class _ProfilGoogleInfos {
  final String nom;
  final String tel;
  final String wilaya;
  _ProfilGoogleInfos({required this.nom, required this.tel, required this.wilaya});
}

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
  bool _googleLoading = false;
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


  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await SosService.signInWithGoogle();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DepanneuseShellScreen(config: widget.config),
        ),
      );
    } on NeedsDepanneuseProfileException catch (e) {
      // Première connexion Google : nom + téléphone + wilaya sont
      // obligatoires avant de créer le compte, sinon la wilaya resterait
      // vide et le compte ne recevrait jamais aucune alerte SOS.
      final infos = await _showCompleterProfilGoogleDialog(
        nomSuggere: e.nomSuggere,
      );
      if (infos == null) {
        // Annulé : on déconnecte pour ne pas laisser une session Google
        // à moitié configurée (sans profil Firestore) trainer.
        await FirebaseAuth.instance.signOut();
        if (mounted) setState(() => _googleLoading = false);
        return;
      }
      try {
        await SosService.completeGoogleProfile(
          uid: e.uid,
          nom: infos.nom,
          telephone: infos.tel,
          wilaya: infos.wilaya,
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DepanneuseShellScreen(config: widget.config),
          ),
        );
      } catch (e2) {
        setState(() => _error = e2.toString().replaceFirst('Exception: ', ''));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  /// Dialog non annulable par erreur (bouton Valider désactivé tant que
  /// les 3 champs ne sont pas remplis) qui collecte nom + téléphone +
  /// wilaya après une première connexion Google.
  Future<_ProfilGoogleInfos?> _showCompleterProfilGoogleDialog({
    required String nomSuggere,
  }) {
    final nomCtrl = TextEditingController(text: nomSuggere);
    final telCtrl = TextEditingController();
    String? wilayaChoisie;
    String? erreurTel;
    return showDialog<_ProfilGoogleInfos>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Complète ton profil'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nécessaire pour recevoir les alertes de panne de ta wilaya.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nomCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Nom de la dépanneuse',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: telCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Téléphone',
                      hintText: '0556 65 32 20',
                      errorText: erreurTel,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: wilayaChoisie,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Wilaya',
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: kWilayasAlgerie
                        .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                        .toList(),
                    onChanged: (v) =>
                        setStateDialog(() => wilayaChoisie = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () {
                  final numero =
                      StoreService.normaliserNumeroLocal(telCtrl.text);
                  if (numero == null) {
                    setStateDialog(() =>
                        erreurTel = 'Numéro invalide. Ex : 0556 65 32 20.');
                    return;
                  }
                  if (wilayaChoisie == null) return;
                  Navigator.pop(
                    ctx,
                    _ProfilGoogleInfos(
                      nom: nomCtrl.text.trim(),
                      tel: numero,
                      wilaya: wilayaChoisie!,
                    ),
                  );
                },
                child: const Text('Valider'),
              ),
            ],
          ),
        );
      },
    );
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

    void retourProfil() {
      RoleRouter.changerDeProfil(
        context,
        config: widget.config,
        isAr: ValueNotifier<bool>(false),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) retourProfil();
      },
      child: Scaffold(
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
                    // faisait rien. La croix + le bouton retour système
                    // ramènent explicitement au choix de profil (les 3 cartes).
                    onPressed: retourProfil,
                    icon: const Icon(Icons.arrow_back, size: 22),
                    tooltip: 'Retour',
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

                    const OrDivider(),
                    GoogleSignInButton(
                      onPressed: _googleLoading || busy ? null : _signInWithGoogle,
                      isLoading: _googleLoading,
                      accentColor: sos,
                      label: 'Continuer avec Google',
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
    ),
    );
  }
}
