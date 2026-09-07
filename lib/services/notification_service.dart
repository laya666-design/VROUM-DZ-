import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Rappels locaux (device) avant expiration : J-30, J-15, J-7.
/// 100% local (flutter_local_notifications) — fonctionne même hors-ligne et
/// même app fermée, PAS besoin de serveur. C'est l'équivalent fonctionnel
/// d'une "push" pour ce cas d'usage précis (rappel programmé à l'avance).
///
/// Une vraie notification push envoyée depuis un serveur (ex: pour alerter
/// à distance, changer le contenu après coup, etc.) nécessiterait Firebase
/// Cloud Messaging + un backend — hors scope tant qu'on reste 100% local.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Décalages avant expiration pour lesquels on programme un rappel.
  static const List<int> _joursAvant = [30, 15, 7];

  static Future<void> init() async {
    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _plugin.initialize(settings);

    // Android 13+ : demande explicite de la permission de notifier.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  /// ID déterministe et stable pour un couple (véhicule, type de rappel,
  /// décalage) — permet de reprogrammer/annuler sans collision ni doublon.
  static int _notificationId(String vehiculeId, String typeRappel, int jours) {
    final key = '$vehiculeId-$typeRappel-$jours';
    return key.hashCode & 0x7fffffff;
  }

  /// Programme (ou reprogramme) les rappels J-30/J-15/J-7 pour un document
  /// donné (assurance ou contrôle technique) d'un véhicule.
  ///
  /// [typeRappel] : identifiant court stable, ex: 'assurance' ou 'ct'.
  /// [titre] : nom affiché dans la notification, ex: nom du véhicule.
  /// [libelleDocument] : ex: 'Assurance' ou 'Contrôle technique'.
  static Future<void> scheduleExpiryReminders({
    required String vehiculeId,
    required String typeRappel,
    required String titre,
    required String libelleDocument,
    required DateTime expiration,
  }) async {
    // On repart de zéro pour ce document : évite les doublons si la date
    // a changé (nouvelle photo, correction, etc.)
    await cancelReminders(vehiculeId, typeRappel);

    const androidDetails = AndroidNotificationDetails(
      'expiry_reminders',
      'Rappels d\'expiration',
      channelDescription:
          'Rappels avant expiration assurance / contrôle technique',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    final now = DateTime.now();

    for (final jours in _joursAvant) {
      final dateRappel = expiration.subtract(Duration(days: jours));
      // On ne programme que les rappels dans le futur.
      if (dateRappel.isBefore(now)) continue;

      // 9h du matin, plus utile qu'un rappel en pleine nuit.
      final dateTirSouhaitee = DateTime(
        dateRappel.year,
        dateRappel.month,
        dateRappel.day,
        9,
      );
      final tzDate = tz.TZDateTime.from(dateTirSouhaitee, tz.local);

      await _plugin.zonedSchedule(
        _notificationId(vehiculeId, typeRappel, jours),
        '$libelleDocument — $titre',
        'Expire dans $jours jour${jours > 1 ? 's' : ''}. Pense à renouveler.',
        tzDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static Future<void> cancelReminders(String vehiculeId, String typeRappel) async {
    for (final jours in _joursAvant) {
      await _plugin.cancel(_notificationId(vehiculeId, typeRappel, jours));
    }
  }

  /// Notification immédiate (son + visuel), réutilisable partout
  /// (nouvelles demandes magasin, nouvelles réponses acheteur, etc.).
  static Future<void> showNow({
    required String title,
    required String body,
    int id = 0,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'instant_alerts',
      'Alertes immédiates',
      channelDescription:
          'Nouvelles demandes, nouvelles réponses marketplace',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details);
  }
}
