import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_new_badger/flutter_new_badger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:termini/checkmytime/services/unread_count_repository.dart';

@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();
  final UnreadCountRepository _unreadCountRepository =
      UnreadCountRepository.instance;

  static const String defaultChannelId = 'checkmytime_general_v2';
  static const String defaultChannelName = 'CheckMyTime';
  static const String _groupKeyPrefix = 'checkmytime_group';
  static const int _summaryNotificationBaseId = 900000000;
  static const String _recentRemoteMessageKey = 'recent_remote_messages_v1';
  static const String _dedupeSeparator = '\u001F';
  static const Duration _remoteDedupWindow = Duration(seconds: 45);

  bool _isInitialized = false;

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

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
      onBackgroundNotificationResponse,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
    >();

    if (androidPlugin != null) {
      for (final channel in _allChannels()) {
        await androidPlugin.createNotificationChannel(channel);
      }
    }

    _isInitialized = true;
  }

  List<AndroidNotificationChannel> _allChannels() {
    return const [
      AndroidNotificationChannel(
        defaultChannelId,
        defaultChannelName,
        description: 'Allgemeine Benachrichtigungen',
        importance: Importance.max,
        showBadge: true,
      ),
      AndroidNotificationChannel(
        'incoming_appointments_v2',
        'Neue Planungen',
        description: 'Benachrichtigungen fuer neue Planungen',
        importance: Importance.high,
        showBadge: true,
      ),
      AndroidNotificationChannel(
        'incoming_messages_v2',
        'Eingehende Nachrichten',
        description: 'Benachrichtigungen fuer neue Chat-Nachrichten',
        importance: Importance.high,
        showBadge: true,
      ),
      AndroidNotificationChannel(
        'incoming_follow_v2',
        'Follow-Aktivitäten',
        description: 'Benachrichtigungen fuer Follow-Anfragen und Zusagen',
        importance: Importance.high,
        showBadge: true,
      ),
      AndroidNotificationChannel(
        'incoming_event_invites_v2',
        'Event-Einladungen',
        description: 'Benachrichtigungen fuer neue Event-Einladungen',
        importance: Importance.high,
        showBadge: true,
      ),
      AndroidNotificationChannel(
        'incoming_event_updates_v2',
        'Event-Aktualisierungen',
        description: 'Benachrichtigungen fuer Event-Anfragen und Entscheidungen',
        importance: Importance.high,
        showBadge: true,
      ),
    ];
  }

  void _onNotificationResponse(NotificationResponse response) {
    // Badge/Unread wird über Firestore-State in der App synchronisiert.
  }

  Future<void> requestPermissions() async {
    await initialize();

    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
    >()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
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
            'Damit du neue Nachrichten, Planungen und Event-Einladungen erhältst, '
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
    required int notificationId,
    required int unreadCount,
    required String groupKey,
    String? payload,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      number: unreadCount,
      groupKey: groupKey,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      badgeNumber: unreadCount,
      threadIdentifier: groupKey,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(notificationId, title, body, details, payload: payload);

    await _showSummaryNotification(
      groupKey: groupKey,
      channelId: channelId,
      channelName: channelName,
      channelDescription: channelDescription,
      unreadCount: unreadCount,
    );
  }

  Future<void> _showSummaryNotification({
    required String groupKey,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required int unreadCount,
  }) async {
    final androidSummaryDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      setAsGroupSummary: true,
      groupKey: groupKey,
      importance: Importance.high,
      priority: Priority.high,
      number: unreadCount,
      styleInformation: InboxStyleInformation(
        const <String>[],
        summaryText: '$unreadCount ungelesen',
      ),
    );

    final iosSummaryDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: true,
      presentSound: false,
      badgeNumber: unreadCount,
      threadIdentifier: groupKey,
    );

    await _plugin.show(
      _summaryNotificationId(groupKey),
      'CheckMyTime',
      '$unreadCount ungelesene Benachrichtigungen',
      NotificationDetails(
        android: androidSummaryDetails,
        iOS: iosSummaryDetails,
      ),
    );
  }

  int _summaryNotificationId(String groupKey) {
    return _summaryNotificationBaseId + (groupKey.hashCode & 0x0FFFFFFF);
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    if (await _shouldSkipDuplicateRemoteMessage(message)) {
      return;
    }

    final data = message.data;

    final title =
    (message.notification?.title ?? data['title'] ?? 'Neue Benachrichtigung')
        .toString()
        .trim();

    final body = (message.notification?.body ?? data['body'] ?? '')
        .toString()
        .trim();

    final type = (data['type'] ?? '').toString().trim();

    final channel = switch (type) {
      'appointment' => (
      id: 'incoming_appointments_v2',
      name: 'Neue Planungen',
      description: 'Benachrichtigungen fuer neue Planungen',
      ),
      'message' => (
      id: 'incoming_messages_v2',
      name: 'Eingehende Nachrichten',
      description: 'Benachrichtigungen fuer neue Chat-Nachrichten',
      ),
      'follow_request' => (
      id: 'incoming_follow_v2',
      name: 'Follow-Aktivitäten',
      description: 'Benachrichtigungen fuer Follow-Anfragen und Zusagen',
      ),
      'follow_request_accepted' => (
      id: 'incoming_follow_v2',
      name: 'Follow-Aktivitäten',
      description: 'Benachrichtigungen fuer Follow-Anfragen und Zusagen',
      ),
      'event_invite' => (
      id: 'incoming_event_invites_v2',
      name: 'Event-Einladungen',
      description: 'Benachrichtigungen fuer neue Event-Einladungen',
      ),
      'event_join_request' => (
      id: 'incoming_event_updates_v2',
      name: 'Event-Aktualisierungen',
      description: 'Benachrichtigungen fuer Event-Anfragen und Entscheidungen',
      ),
      'event_join_request_accepted' => (
      id: 'incoming_event_updates_v2',
      name: 'Event-Aktualisierungen',
      description: 'Benachrichtigungen fuer Event-Anfragen und Entscheidungen',
      ),
      'event_join_request_declined' => (
      id: 'incoming_event_updates_v2',
      name: 'Event-Aktualisierungen',
      description: 'Benachrichtigungen fuer Event-Anfragen und Entscheidungen',
      ),
      'event_deleted' => (
      id: 'incoming_event_updates_v2',
      name: 'Event-Aktualisierungen',
      description: 'Benachrichtigungen fuer Event-Anfragen und Entscheidungen',
      ),
      'event_updated' => (
      id: 'incoming_event_updates_v2',
      name: 'Event-Aktualisierungen',
      description: 'Benachrichtigungen fuer Event-Anfragen und Entscheidungen',
      ),
      _ => (
      id: defaultChannelId,
      name: defaultChannelName,
      description: 'Allgemeine Benachrichtigungen',
      ),
    };

    final unreadCount = await _resolveUnreadCount(data);

    await _showNotification(
      channelId: channel.id,
      channelName: channel.name,
      channelDescription: channel.description,
      title: title,
      body: body,
      notificationId: await _resolveNotificationId(message),
      unreadCount: unreadCount,
      groupKey: '$_groupKeyPrefix:${channel.id}',
      payload: data.toString(),
    );

    await setAppBadgeCount(unreadCount);
  }

  Future<void> syncRemoteBadgeOnly(RemoteMessage message) async {
    if (await _shouldSkipDuplicateRemoteMessage(message)) {
      return;
    }

    final unreadCount = await _resolveUnreadCount(message.data);
    await setAppBadgeCount(unreadCount);
  }

  Future<int> _resolveUnreadCount(Map<String, dynamic> data) async {
    final serverBadgeCount = int.tryParse((data['badgeCount'] ?? '').toString());
    final hasValidServerBadge = serverBadgeCount != null && serverBadgeCount > 0;
    return hasValidServerBadge
        ? _unreadCountRepository.setUnreadCount(serverBadgeCount)
        : _unreadCountRepository.incrementUnreadCount();
  }

  Future<bool> _shouldSkipDuplicateRemoteMessage(RemoteMessage message) async {
    final dedupeKey = _remoteMessageDedupeKey(message);
    if (dedupeKey.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _remoteDedupWindow.inMilliseconds;
    final storedEntries = prefs.getStringList(_recentRemoteMessageKey) ?? const <String>[];

    final freshEntries = <String>[];
    var isDuplicate = false;

    for (final entry in storedEntries) {
      final separatorIndex = entry.lastIndexOf(_dedupeSeparator);
      if (separatorIndex <= 0 || separatorIndex >= entry.length - 1) {
        continue;
      }

      final key = entry.substring(0, separatorIndex);
      final timestamp = int.tryParse(entry.substring(separatorIndex + 1));
      if (timestamp == null || timestamp < cutoff) {
        continue;
      }

      if (key == dedupeKey) {
        isDuplicate = true;
      }

      freshEntries.add('$key$_dedupeSeparator$timestamp');
    }

    if (isDuplicate) {
      await prefs.setStringList(_recentRemoteMessageKey, freshEntries);
      return true;
    }

    freshEntries.add('$dedupeKey$_dedupeSeparator$now');
    await prefs.setStringList(_recentRemoteMessageKey, freshEntries);
    return false;
  }

  String _remoteMessageDedupeKey(RemoteMessage message) {
    final messageId = message.messageId?.trim();
    if (messageId != null && messageId.isNotEmpty) {
      return 'messageId:$messageId';
    }

    final data = message.data;
    final title =
    (message.notification?.title ?? data['title'] ?? '').toString().trim();
    final body =
    (message.notification?.body ?? data['body'] ?? '').toString().trim();

    final parts = <String>[
      (data['type'] ?? '').toString().trim(),
      (data['eventId'] ?? '').toString().trim(),
      (data['threadId'] ?? '').toString().trim(),
      (data['contactId'] ?? '').toString().trim(),
      (data['appointmentId'] ?? '').toString().trim(),
      (data['senderId'] ?? '').toString().trim(),
      (data['route'] ?? data['target'] ?? '').toString().trim(),
      title,
      body,
    ].where((part) => part.isNotEmpty).toList();

    if (parts.isEmpty) return '';
    return parts.join('|');
  }

  Future<int> _resolveNotificationId(RemoteMessage message) async {
    final messageId = message.messageId?.trim();
    if (messageId != null && messageId.isNotEmpty) {
      return messageId.hashCode & 0x7FFFFFFF;
    }

    final data = message.data;
    final stableKey = [
      data['type'],
      data['eventId'],
      data['threadId'],
      data['contactId'],
      data['appointmentId'],
      data['route'],
      data['target'],
    ].join('|');

    if (stableKey.trim().replaceAll('|', '').isNotEmpty) {
      return stableKey.hashCode & 0x7FFFFFFF;
    }

    return _unreadCountRepository.nextNotificationSequence();
  }

  Future<void> syncUnreadCount(int count) async {
    final unreadCount = await _unreadCountRepository.setUnreadCount(count);
    await setAppBadgeCount(unreadCount);
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
      final unreadCount = await _unreadCountRepository.incrementUnreadCount();
      await setAppBadgeCount(unreadCount);
    } catch (error, stackTrace) {
      debugPrint('incrementAppBadgeCount failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> decrementAppBadgeCount() async {
    try {
      final unreadCount = await _unreadCountRepository.decrementUnreadCount();
      await setAppBadgeCount(unreadCount);
    } catch (error, stackTrace) {
      debugPrint('decrementAppBadgeCount failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> clearAppBadge() async {
    try {
      await _unreadCountRepository.setUnreadCount(0);
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
    final unreadCount = await _unreadCountRepository.incrementUnreadCount();
    await _showNotification(
      channelId: 'incoming_appointments_v2',
      channelName: 'Neue Planungen',
      channelDescription: 'Benachrichtigungen für neue Planungen',
      title: title,
      body: body,
      notificationId: await _unreadCountRepository.nextNotificationSequence(),
      unreadCount: unreadCount,
      groupKey: '$_groupKeyPrefix:incoming_appointments_v2',
    );
    await setAppBadgeCount(unreadCount);
  }

  Future<void> showIncomingChatNotification({
    required String title,
    required String body,
  }) async {
    final unreadCount = await _unreadCountRepository.incrementUnreadCount();
    await _showNotification(
      channelId: 'incoming_messages_v2',
      channelName: 'Eingehende Nachrichten',
      channelDescription: 'Benachrichtigungen für neue Chat-Nachrichten',
      title: title,
      body: body,
      notificationId: await _unreadCountRepository.nextNotificationSequence(),
      unreadCount: unreadCount,
      groupKey: '$_groupKeyPrefix:incoming_messages_v2',
    );
    await setAppBadgeCount(unreadCount);
  }


  Future<void> showIncomingEventRequestNotification({
    required String title,
    required String body,
  }) async {
    await showIncomingEventUpdateNotification(title: title, body: body);
  }

  Future<void> showIncomingEventUpdateNotification({
    required String title,
    required String body,
  }) async {
    final unreadCount = await _unreadCountRepository.incrementUnreadCount();
    await _showNotification(
      channelId: 'incoming_event_updates_v2',
      channelName: 'Event-Aktualisierungen',
      channelDescription: 'Benachrichtigungen fuer Event-Anfragen und Entscheidungen',
      title: title,
      body: body,
      notificationId: await _unreadCountRepository.nextNotificationSequence(),
      unreadCount: unreadCount,
      groupKey: '$_groupKeyPrefix:incoming_event_updates_v2',
    );
    await setAppBadgeCount(unreadCount);
  }

  Future<void> showIncomingEventInviteNotification({
    required String title,
    required String body,
  }) async {
    final unreadCount = await _unreadCountRepository.incrementUnreadCount();
    await _showNotification(
      channelId: 'incoming_event_invites_v2',
      channelName: 'Event-Einladungen',
      channelDescription: 'Benachrichtigungen fuer neue Event-Einladungen',
      title: title,
      body: body,
      notificationId: await _unreadCountRepository.nextNotificationSequence(),
      unreadCount: unreadCount,
      groupKey: '$_groupKeyPrefix:incoming_event_invites_v2',
    );
    await setAppBadgeCount(unreadCount);
  }
}