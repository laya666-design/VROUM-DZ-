import 'package:flutter/material.dart';

/// Bouton Google réutilisable pour tous les écrans de connexion
/// VROUM DZ — même style partout
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? accentColor;
  final String label;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.accentColor,
    this.label = 'Continuer avec Google',
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accentColor ?? const Color(0xFF22C55E),
              ),
            )
          : Image.network(
              'https://www.gstatic.com/images/branding/product/1x/gsa_512dp.png',
              height: 20,
              width: 20,
              errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 24),
            ),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

/// Séparateur "ou"
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Color(0xFFE5E7EB))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('ou', style: TextStyle(color: Colors.black45, fontSize: 13)),
          ),
          Expanded(child: Divider(color: Color(0xFFE5E7EB))),
        ],
      ),
    );
  }
}
