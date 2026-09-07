import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// FIX exact_alarms_not_permitted - ne bloque plus l'UI
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const List<int> _joursAvant = [30, 15, 7];

  static Future<void> init() async {
    tz_data.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(settings);
    try {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  static int _notificationId(String vehiculeId, String typeRappel, int jours) {
    final key = '$vehiculeId-$typeRappel-$jours';
    return key.hashCode & 0x7fffffff;
  }

  static Future<void> scheduleExpiryReminders({
    required String vehiculeId,
    required String typeRappel,
    required String titre,
    required String libelleDocument,
    required DateTime expiration,
  }) async {
    await cancelReminders(vehiculeId, typeRappel);
    const androidDetails = AndroidNotificationDetails('expiry_reminders','Rappels d\'expiration',channelDescription:'Rappels',importance:Importance.high,priority:Priority.high);
    const details = NotificationDetails(android: androidDetails);
    final now = DateTime.now();
    for (final jours in _joursAvant) {
      final dateRappel = expiration.subtract(Duration(days: jours));
      if (dateRappel.isBefore(now)) continue;
      final tzDate = tz.TZDateTime.from(DateTime(dateRappel.year,dateRappel.month,dateRappel.day,9), tz.local);
      try {
        await _plugin.zonedSchedule(_notificationId(vehiculeId,typeRappel,jours),'$libelleDocument — $titre','Expire dans $jours jours',tzDate,details,androidScheduleMode:AndroidScheduleMode.exactAllowWhileIdle,uiLocalNotificationDateInterpretation:UILocalNotificationDateInterpretation.absoluteTime);
      } catch (_) {
        try {
          await _plugin.zonedSchedule(_notificationId(vehiculeId,typeRappel,jours),'$libelleDocument — $titre','Expire dans $jours jours',tzDate,details,androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,uiLocalNotificationDateInterpretation:UILocalNotificationDateInterpretation.absoluteTime);
        } catch (_) {}
      }
    }
  }

  static Future<void> cancelReminders(String vehiculeId, String typeRappel) async {
    for (final jours in _joursAvant) await _plugin.cancel(_notificationId(vehiculeId,typeRappel,jours));
  }

  static Future<void> showNow({required String title, required String body, int id=0}) async {
    const androidDetails = AndroidNotificationDetails('instant_alerts','Alertes immédiates',importance:Importance.high,priority:Priority.high,playSound:true,enableVibration:true);
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id,title,body,details);
  }
}
