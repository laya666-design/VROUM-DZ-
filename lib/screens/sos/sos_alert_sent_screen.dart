import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../services/notification_service.dart';
import '../../services/sos_models.dart';
import '../../services/sos_service.dart';

/// Écran affiché juste après l'envoi d'une alerte SOS : suit le statut
/// en direct ("En attente..." puis coordonnées de la dépanneuse, puis
/// confirmation d'arrivée), avec une notification locale (son +
/// vibration) à chaque étape franchie.
class SosAlertSentScreen extends StatefulWidget {
  final AppConfig config;
  final String alertId;
  final String wilaya;

  const SosAlertSentScreen({
    super.key,
    required this.config,
    required this.alertId,
    required this.wilaya,
  });

  @override
  State<SosAlertSentScreen> createState() => _SosAlertSentScreenState();
}

class _SosAlertSentScreenState extends State<SosAlertSentScreen> {
  SosAlert? _alerte;
  String? _dernierStatut;
  StreamSubscription<SosAlert?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = SosService.watchAlert(widget.alertId).listen(_onAlerte);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onAlerte(SosAlert? alerte) {
    if (!mounted) return;
    final ancien = _dernierStatut;
    final nouveau = alerte?.statut;

    // Ne notifie que sur un vrai changement (pas le premier snapshot
    // reçu à l'ouverture de l'écran).
    if (ancien != null && nouveau != null && ancien != nouveau) {
      final nom = alerte?.acceptedByDepanneuseNom ?? '';
      if (nouveau == SosStatus.acceptee) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.alert);
        NotificationService.showNow(
          title: 'Alerte acceptée',
          body: nom.isEmpty
              ? 'Une dépanneuse arrive pour te dépanner.'
              : '$nom arrive pour te dépanner.',
          id: 3000 + (widget.alertId.hashCode & 0xffff),
        );
      } else if (nouveau == SosStatus.arrivee) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.alert);
        NotificationService.showNow(
          title: 'Dépanneuse arrivée',
          body: nom.isEmpty
              ? 'La dépanneuse est arrivée sur place.'
              : '$nom est arrivée sur place.',
          id: 3000 + (widget.alertId.hashCode & 0xffff),
        );
      }
    }

    setState(() {
      _alerte = alerte;
      _dernierStatut = nouveau;
    });
  }

  Future<void> _appeler(String tel) async {
    final uri = Uri(scheme: 'tel', path: tel);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _annuler(BuildContext context) async {
    await SosService.cancelAlert(widget.alertId);
    if (context.mounted) _retourMenuPrincipal(context);
  }

  /// Revient au menu principal (écran racine : HomeScreen côté conducteur,
  /// ou le shell du rôle côté magasin) quel que soit l'état de l'alerte.
  /// Avant, une fois l'alerte acceptée/arrivée, il n'y avait plus aucun
  /// bouton pour quitter cet écran (seul "Annuler" existait, et
  /// uniquement pendant l'attente) — l'utilisateur restait bloqué ici.
  /// popUntil((route) => route.isFirst) garantit un retour au menu
  /// principal même si d'autres écrans ont été empilés entre-temps.
  void _retourMenuPrincipal(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final sos = config.sosColor;
    final alerte = _alerte;
    final accepte = alerte?.estAcceptee ?? false;
    final arrivee = alerte?.estArrivee ?? false;
    final annulee = alerte?.statut == SosStatus.annulee;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: sos,
        foregroundColor: Colors.white,
        title: const Text('Alerte SOS'),
        // Bouton retour explicite (au lieu du pop par défaut) : garantit
        // un retour fiable au menu principal quel que soit l'état de la
        // pile de navigation.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Menu principal',
          onPressed: () => _retourMenuPrincipal(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (annulee) ...[
                const Icon(Icons.cancel_outlined, size: 64, color: Colors.black38),
                const SizedBox(height: 16),
                const Text('Alerte annulée.', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 20),
              ] else if (!accepte && !arrivee) ...[
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(color: sos, strokeWidth: 4),
                ),
                const SizedBox(height: 20),
                Text(
                  'Alerte envoyée aux dépanneuses de la wilaya de ${widget.wilaya}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'En attente qu\'une dépanneuse accepte...',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 28),
                OutlinedButton(
                  onPressed: () => _annuler(context),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.black54),
                  child: const Text('Annuler l\'alerte'),
                ),
              ] else ...[
                Icon(Icons.check_circle, size: 64, color: config.primaryColor),
                const SizedBox(height: 16),
                Text(
                  arrivee ? 'La dépanneuse est arrivée !' : 'Une dépanneuse arrive !',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  alerte?.acceptedByDepanneuseNom ?? '',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                if ((alerte?.acceptedByDepanneuseTel ?? '').isNotEmpty)
                  Builder(builder: (context) {
                    final tel = alerte!.acceptedByDepanneuseTel!;
                    return SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () => _appeler(tel),
                        style: FilledButton.styleFrom(backgroundColor: config.primaryColor),
                        icon: const Icon(Icons.call),
                        label: Text('Appeler $tel'),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
              ],
              // Toujours visible, quel que soit l'état de l'alerte — avant,
              // une fois l'alerte acceptée/arrivée, rien ne permettait de
              // quitter cet écran.
              TextButton.icon(
                onPressed: () => _retourMenuPrincipal(context),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Retour au menu principal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
