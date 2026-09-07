import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'magasin_shell_screen.dart';
import '../../widgets/google_signin_button.dart';
import '../../config/app_config.dart';
import '../../services/store_service.dart';

class StoreSignupScreen extends StatefulWidget {
  final AppConfig config;
  const StoreSignupScreen({super.key, required this.config});
  @override
  State<StoreSignupScreen> createState() => _StoreSignupScreenState();
}
class _StoreSignupScreenState extends State<StoreSignupScreen> {
  final _nomController = TextEditingController();
  final _telController = TextEditingController();
  final _adresseController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _googleLoading = false;
  Future<void> _signup() async {
    setState(() { _loading = true; _error = null; });
    try {
      await StoreService.signUp(email: _emailController.text.trim(), password: _passwordController.text, nom: _nomController.text.trim(), tel: _telController.text.trim(), adresse: _adresseController.text.trim());
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Compte cree'), content: const Text('Ton compte est en attente de validation.'), actions: [FilledButton(onPressed: () { Navigator.pop(ctx); Navigator.pop(context); Navigator.pop(context); }, child: const Text('Compris'))]));
    } on FirebaseAuthException catch (e) { setState(() => _error = e.message ?? 'Inscription impossible.'); } catch (e) { setState(() => _error = 'Erreur : $e'); } finally { if (mounted) setState(() => _loading = false); }
  }
  Future<void> _signInWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    try {
      await StoreService.signInWithGoogle();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MagasinShellScreen(config: widget.config)));
    } catch (e) { setState(() => _error = e.toString().replaceFirst('Exception: ', '')); } finally { if (mounted) setState(() => _googleLoading = false); }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: widget.config.primaryColor, foregroundColor: Colors.white, title: const Text('Creer un compte magasin')),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _nomController, decoration: const InputDecoration(labelText: 'Nom du magasin')), const SizedBox(height: 12),
        TextField(controller: _telController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telephone')), const SizedBox(height: 12),
        TextField(controller: _adresseController, decoration: const InputDecoration(labelText: 'Adresse')), const SizedBox(height: 12),
        TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')), const SizedBox(height: 12),
        TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe (6+ car.)')),
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
        const SizedBox(height: 12),
        const OrDivider(),
        GoogleSignInButton(onPressed: _googleLoading || _loading ? null : _signInWithGoogle, isLoading: _googleLoading, accentColor: widget.config.primaryColor),
        const SizedBox(height: 20),
        FilledButton(onPressed: _loading ? null : _signup, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: widget.config.primaryColor), child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Creer le compte')),
      ]))),
    );
  }
}
