import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';
import 'package:termini/checkmytime/pages/event_detail_page.dart';
import 'package:termini/checkmytime/pages/events_page.dart';
import 'package:termini/checkmytime/pages/profile_page.dart';
import 'package:termini/checkmytime/services/notification_service.dart';

class PushAuthUser {
  PushAuthUser({required this.uid});

  final String uid;
}

abstract class PushAuthClient {
  PushAuthUser? get currentUser;

  Stream<PushAuthUser?> authStateChanges();
}

class FirebasePushAuthClient implements PushAuthClient {
  @override
  PushAuthUser? get currentUser {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return PushAuthUser(uid: user.uid);
  }

  @override
  Stream<PushAuthUser?> authStateChanges() {
    return FirebaseAuth.instance.authStateChanges().map((user) {
      if (user == null) return null;
      return PushAuthUser(uid: user.uid);
    });
  }
}

abstract class PushMessagingClient {
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Stream<String> get onTokenRefresh;

  Future<void> requestPermission({
    required bool alert,
    required bool badge,
    required bool sound,
  });

  Future<void> setForegroundNotificationPresentationOptions({
    required bool alert,
    required bool badge,
    required bool sound,
  });

  Future<RemoteMessage?> getInitialMessage();
  Future<String?> getToken();
}

class FirebasePushMessagingClient implements PushMessagingClient {
  FirebasePushMessagingClient(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> requestPermission({
    required bool alert,
    required bool badge,
    required bool sound,
  }) {
    return _messaging.requestPermission(
      alert: alert,
      badge: badge,
      sound: sound,
    );
  }

  @override
  Future<void> setForegroundNotificationPresentationOptions({
    required bool alert,
    required bool badge,
    required bool sound,
  }) {
    return _messaging.setForegroundNotificationPresentationOptions(
      alert: alert,
      badge: badge,
      sound: sound,
    );
  }

  @override
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();

  @override
  Future<String?> getToken() => _messaging.getToken();
}

abstract class PushNotificationClient {
  Future<void> initialize();
  Future<void> showRemoteMessage(RemoteMessage message);
  Future<void> setAppBadgeCount(int count);
}

class DefaultPushNotificationClient implements PushNotificationClient {
  @override
  Future<void> initialize() => NotificationService.instance.initialize();

  @override
  Future<void> setAppBadgeCount(int count) {
    return NotificationService.instance.setAppBadgeCount(count);
  }

  @override
  Future<void> showRemoteMessage(RemoteMessage message) {
    return NotificationService.instance.showRemoteMessage(message);
  }
}

abstract class PushTokenRepository {
  Future<void> upsertToken({
    required String userId,
    required String token,
    required String platform,
  });
}

class FirestorePushTokenRepository implements PushTokenRepository {
  @override
  Future<void> upsertToken({
    required String userId,
    required String token,
    required String platform,
  }) async {
    final now = FieldValue.serverTimestamp();
    final deviceRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(token);

    await deviceRef.set({
      'token': token,
      'platform': platform,
      'updatedAt': now,
      'createdAt': now,
      'enabled': true,
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'fcmToken': token,
      'updatedAt': now,
    }, SetOptions(merge: true));
  }
}

enum PushOpenTargetType { appointments, events, eventDetail, profile, chat }

class PushOpenTarget {
  PushOpenTarget({
    required this.type,
    this.eventId,
    this.contactId,
    this.contactName,
    this.phoneNumber,
  });

  final PushOpenTargetType type;
  final String? eventId;
  final String? contactId;
  final String? contactName;
  final String? phoneNumber;
}

class PushNotificationService {
  PushNotificationService._()
      : _auth = FirebasePushAuthClient(),
        _messaging = FirebasePushMessagingClient(FirebaseMessaging.instance),
        _notifications = DefaultPushNotificationClient(),
        _tokenRepository = FirestorePushTokenRepository(),
        _onOpenTarget = null;

  PushNotificationService.forTesting({
    required PushAuthClient auth,
    required PushMessagingClient messaging,
    required PushNotificationClient notifications,
    required PushTokenRepository tokenRepository,
    void Function(PushOpenTarget target)? onOpenTarget,
  }) : _auth = auth,
        _messaging = messaging,
        _notifications = notifications,
        _tokenRepository = tokenRepository,
        _onOpenTarget = onOpenTarget;

  static final PushNotificationService instance = PushNotificationService._();

  final PushAuthClient _auth;
  final PushMessagingClient _messaging;
  final PushNotificationClient _notifications;
  final PushTokenRepository _tokenRepository;
  final void Function(PushOpenTarget target)? _onOpenTarget;
  bool _isInitialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;
  RemoteMessage? _pendingOpenMessage;

  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (_isInitialized) return;
    _isInitialized = true;
    _navigatorKey = navigatorKey;

    await _notifications.initialize();

    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _messaging.onMessage.listen((message) async {
      await _notifications.showRemoteMessage(message);
    });

    _messaging.onMessageOpenedApp.listen(_handleMessageOpen);

    _messaging.onTokenRefresh.listen((token) async {
      await _upsertTokenForCurrentUser(token);
    });

    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        try {
          final token = await _messaging
              .getToken()
              .timeout(const Duration(seconds: 10));
          if (token != null) {
            await _upsertTokenForCurrentUser(token);
          }
        } catch (_) {}

        if (_pendingOpenMessage != null) {
          final pending = _pendingOpenMessage!;
          _pendingOpenMessage = null;
          _openFromMessage(pending);
        }
      }
    });

    RemoteMessage? initialMessage;
    try {
      initialMessage = await _messaging
          .getInitialMessage()
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (initialMessage != null) {
      _handleMessageOpen(initialMessage);
    }

    try {
      final token = await _messaging
          .getToken()
          .timeout(const Duration(seconds: 10));
      if (token != null) {
        await _upsertTokenForCurrentUser(token);
      }
    } catch (_) {}
  }

  Future<void> _upsertTokenForCurrentUser(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _tokenRepository.upsertToken(
      userId: user.uid,
      token: token,
      platform: _platformLabel(),
    );
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  void _handleMessageOpen(RemoteMessage message) {
    if (_auth.currentUser == null) {
      _pendingOpenMessage = message;
      return;
    }

    _openFromMessage(message);
  }

  void _openFromMessage(RemoteMessage message) {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      _pendingOpenMessage = message;
      return;
    }

    final data = message.data;
    final target = resolveOpenTarget(data);
    _onOpenTarget?.call(target);
    if (_onOpenTarget != null) return;

    switch (target.type) {
      case PushOpenTargetType.appointments:
        navigator.push(
          MaterialPageRoute(builder: (_) => const EventsPage()),
        );
        return;
      case PushOpenTargetType.events:
        navigator.push(MaterialPageRoute(builder: (_) => const EventsPage()));
        return;
      case PushOpenTargetType.eventDetail:
        final eventId = target.eventId ?? '';
        if (eventId.isNotEmpty) {
          navigator.push(
            MaterialPageRoute(
              builder:
                  (_) => EventDetailPage(
                eventId: eventId,
                view: EventDetailView.invitation,
              ),
            ),
          );
          return;
        }
        navigator.push(MaterialPageRoute(builder: (_) => const EventsPage()));
        return;
      case PushOpenTargetType.profile:
        navigator.push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        return;
      case PushOpenTargetType.chat:
        final contactId = target.contactId ?? '';
        final contactName = target.contactName ?? 'Unbekannt';
        final phone = target.phoneNumber ?? '';
        if (contactId.isNotEmpty) {
          navigator.push(
            MaterialPageRoute(
              builder:
                  (_) => ContactThreadPage(
                contactId: contactId,
                contactName: contactName,
                phoneNumber: phone,
              ),
            ),
          );
          return;
        }
        navigator.push(
          MaterialPageRoute(builder: (_) => const EventsPage()),
        );
        return;
    }
  }

  @visibleForTesting
  PushOpenTarget resolveOpenTarget(Map<Object?, Object?> data) {
    final route = (data['route'] ?? data['target'] ?? '').toString().trim();
    switch (route) {
      case 'appointments':
        return PushOpenTarget(type: PushOpenTargetType.events);
      case 'events':
        return PushOpenTarget(type: PushOpenTargetType.events);
      case 'event_detail':
        final eventId = (data['eventId'] ?? '').toString().trim();
        return PushOpenTarget(
          type: PushOpenTargetType.eventDetail,
          eventId: eventId,
        );
      case 'profile':
        return PushOpenTarget(type: PushOpenTargetType.profile);
      case 'chat':
        return PushOpenTarget(
          type: PushOpenTargetType.chat,
          contactId: (data['contactId'] ?? '').toString().trim(),
          contactName: (data['contactName'] ?? 'Unbekannt').toString().trim(),
          phoneNumber: (data['phoneNumber'] ?? '').toString().trim(),
        );
      default:
        return PushOpenTarget(type: PushOpenTargetType.events);
    }
  }

  @visibleForTesting
  int? parseBadgeCount(Object? value) => _parseBadgeCount(value);

  int? _parseBadgeCount(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}