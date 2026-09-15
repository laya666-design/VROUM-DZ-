import 'package:flutter/material.dart';

/// Dialogue "mot de passe oublié" pour un compte téléphone : demande une
/// adresse email réelle (première fois : associée définitivement au
/// compte ; fois suivantes : doit correspondre à celle déjà enregistrée)
/// à laquelle le lien de réinitialisation est envoyé.
///
/// [onEnvoyer] doit appeler StoreService.demanderResetParEmail ou
/// MarketplaceService.demanderResetParEmail selon le contexte (magasin
/// ou acheteur) et laisser remonter l'exception en cas d'erreur — le
/// dialogue affiche alors le message directement.
Future<void> showResetPasswordEmailDialog({
  required BuildContext context,
  required Color primaryColor,
  required Future<void> Function(String email) onEnvoyer,
}) {
  final emailController = TextEditingController();
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _ResetPasswordEmailDialogContent(
      emailController: emailController,
      primaryColor: primaryColor,
      onEnvoyer: onEnvoyer,
    ),
  );
}

class _ResetPasswordEmailDialogContent extends StatefulWidget {
  final TextEditingController emailController;
  final Color primaryColor;
  final Future<void> Function(String email) onEnvoyer;

  const _ResetPasswordEmailDialogContent({
    required this.emailController,
    required this.primaryColor,
    required this.onEnvoyer,
  });

  @override
  State<_ResetPasswordEmailDialogContent> createState() =>
      _ResetPasswordEmailDialogContentState();
}

class _ResetPasswordEmailDialogContentState
    extends State<_ResetPasswordEmailDialogContent> {
  bool _loading = false;
  bool _envoye = false;
  String? _error;

  Future<void> _envoyer() async {
    final email = widget.emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Entre une adresse email valide.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onEnvoyer(email);
      if (mounted) setState(() => _envoye = true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_envoye) {
      return AlertDialog(
        icon: const Icon(Icons.check_circle, color: Color(0xFF166534), size: 40),
        title: const Text('Email envoyé'),
        content: Text(
          'Vérifie la boîte de réception de ${widget.emailController.text.trim()} '
          '(et les spams) pour choisir un nouveau mot de passe.',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
            child: const Text('Compris'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Mot de passe oublié'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Indique ton adresse email : on t\'y envoie un lien pour '
            'choisir un nouveau mot de passe.\n\n'
            'La première fois, cet email reste associé à ton compte '
            'pour les prochaines réinitialisations.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.emailController,
            keyboardType: TextInputType.emailAddress,
            enabled: !_loading,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _loading ? null : _envoyer,
          style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Envoyer le lien'),
        ),
      ],
    );
  }
}
