import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  int _notificationId = 0;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _isInitialized = true;
  }

  Future<void> requestPermissions() async {
    await initialize();

    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _showNotification({
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    _notificationId++;

    await _plugin.show(
      _notificationId,
      title,
      body,
      details,
    );
  }

  Future<void> showIncomingAppointmentNotification({
    required String title,
    required String body,
  }) async {
    await _showNotification(
      channelId: 'incoming_appointments',
      channelName: 'Eingehende Termine',
      channelDescription: 'Benachrichtigungen für neue Terminvorschläge',
      title: title,
      body: body,
    );
  }

  Future<void> showIncomingChatNotification({
    required String title,
    required String body,
  }) async {
    await _showNotification(
      channelId: 'incoming_messages',
      channelName: 'Eingehende Nachrichten',
      channelDescription: 'Benachrichtigungen für neue Chat-Nachrichten',
      title: title,
      body: body,
    );
  }
}
