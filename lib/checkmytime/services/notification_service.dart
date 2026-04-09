import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_new_badger/flutter_new_badger.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  static const String defaultChannelId = 'checkmytime_general';
  static const String defaultChannelName = 'CheckMyTime';

  bool _isInitialized = false;
  int _notificationId = 0;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);

    const defaultAndroidChannel = AndroidNotificationChannel(
      defaultChannelId,
      defaultChannelName,
      description: 'Allgemeine Benachrichtigungen',
      importance: Importance.max,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
    >()
        ?.createNotificationChannel(defaultAndroidChannel);

    _isInitialized = true;
  }

  Future<void> requestPermissions() async {
    await initialize();

    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
    >()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
    >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin
    >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<bool> ensureNotificationPermission(BuildContext context) async {
    await initialize();

    var status = await Permission.notification.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isDenied) {
      final result = await Permission.notification.request();
      if (result.isGranted) {
        return true;
      }
      status = result;
    }

    if (status.isPermanentlyDenied ||
        status.isRestricted ||
        status.isLimited ||
        status.isDenied) {
      if (!context.mounted) return false;
      await _showNotificationSettingsDialog(context);
    }

    return false;
  }

  Future<void> _showNotificationSettingsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Benachrichtigungen deaktiviert'),
          content: const Text(
            'Damit du neue Nachrichten, Termine und Event-Einladungen erhältst, '
                'musst du Benachrichtigungen in den App-Einstellungen aktivieren.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await openAppSettings();
              },
              child: const Text('Einstellungen öffnen'),
            ),
          ],
        );
      },
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

    await _plugin.show(_notificationId, title, body, details);
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    final data = message.data;

    final title =
    (message.notification?.title ??
        data['title'] ??
        'Neue Benachrichtigung')
        .toString()
        .trim();

    final body =
    (message.notification?.body ?? data['body'] ?? '').toString().trim();

    final type = (data['type'] ?? '').toString().trim();

    final channel = switch (type) {
      'appointment' => (
      id: 'incoming_appointments',
      name: 'Eingehende Termine',
      description: 'Benachrichtigungen fuer neue Terminvorschlaege',
      ),
      'message' => (
      id: 'incoming_messages',
      name: 'Eingehende Nachrichten',
      description: 'Benachrichtigungen fuer neue Chat-Nachrichten',
      ),
      'event_invite' => (
      id: 'incoming_event_invites',
      name: 'Event-Einladungen',
      description: 'Benachrichtigungen fuer neue Event-Einladungen',
      ),
      _ => (
      id: defaultChannelId,
      name: defaultChannelName,
      description: 'Allgemeine Benachrichtigungen',
      ),
    };

    await _showNotification(
      channelId: channel.id,
      channelName: channel.name,
      channelDescription: channel.description,
      title: title,
      body: body,
    );
  }

  Future<void> setAppBadgeCount(int count) async {
    try {
      if (count <= 0) {
        await clearAppBadge();
        return;
      }

      await FlutterNewBadger.setBadge(count);
    } catch (error, stackTrace) {
      debugPrint('setAppBadgeCount failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<int?> getAppBadgeCount() async {
    try {
      return await FlutterNewBadger.getBadge();
    } catch (error, stackTrace) {
      debugPrint('getAppBadgeCount failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> incrementAppBadgeCount() async {
    try {
      await FlutterNewBadger.incrementBadgeCount();
    } catch (error, stackTrace) {
      debugPrint('incrementAppBadgeCount failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> decrementAppBadgeCount() async {
    try {
      await FlutterNewBadger.decrementBadgeCount();
    } catch (error, stackTrace) {
      debugPrint('decrementAppBadgeCount failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> clearAppBadge() async {
    try {
      await FlutterNewBadger.removeBadge();
    } catch (error, stackTrace) {
      debugPrint('clearAppBadge failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
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

  Future<void> showIncomingEventInviteNotification({
    required String title,
    required String body,
  }) async {
    await _showNotification(
      channelId: 'incoming_event_invites',
      channelName: 'Event-Einladungen',
      channelDescription: 'Benachrichtigungen fuer neue Event-Einladungen',
      title: title,
      body: body,
    );
  }
}