import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termini/checkmytime/services/push_notification_service.dart';

class _FakeAuthClient implements PushAuthClient {
  _FakeAuthClient({this.current});

  PushAuthUser? current;
  final StreamController<PushAuthUser?> controller =
      StreamController<PushAuthUser?>.broadcast();

  @override
  PushAuthUser? get currentUser => current;

  @override
  Stream<PushAuthUser?> authStateChanges() => controller.stream;

  Future<void> close() => controller.close();
}

class _FakeMessagingClient implements PushMessagingClient {
  final StreamController<RemoteMessage> onMessageController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> onMessageOpenedController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<String> onTokenRefreshController =
      StreamController<String>.broadcast();

  RemoteMessage? initialMessage;
  String? token;

  @override
  Stream<RemoteMessage> get onMessage => onMessageController.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => onMessageOpenedController.stream;

  @override
  Stream<String> get onTokenRefresh => onTokenRefreshController.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initialMessage;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> requestPermission({
    required bool alert,
    required bool badge,
    required bool sound,
  }) async {}

  @override
  Future<void> setForegroundNotificationPresentationOptions({
    required bool alert,
    required bool badge,
    required bool sound,
  }) async {}

  Future<void> close() async {
    await onMessageController.close();
    await onMessageOpenedController.close();
    await onTokenRefreshController.close();
  }
}

class _FakeNotificationClient implements PushNotificationClient {
  final List<RemoteMessage> shownMessages = <RemoteMessage>[];
  final List<int> badgeCounts = <int>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setAppBadgeCount(int count) async {
    badgeCounts.add(count);
  }

  @override
  Future<void> showRemoteMessage(RemoteMessage message) async {
    shownMessages.add(message);
  }
}

class _FakeTokenRepository implements PushTokenRepository {
  @override
  Future<void> upsertToken({
    required String userId,
    required String token,
    required String platform,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parseBadgeCount parses int and numeric strings', () {
    final service = PushNotificationService.forTesting(
      auth: _FakeAuthClient(),
      messaging: _FakeMessagingClient(),
      notifications: _FakeNotificationClient(),
      tokenRepository: _FakeTokenRepository(),
    );

    expect(service.parseBadgeCount(3), 3);
    expect(service.parseBadgeCount('7'), 7);
    expect(service.parseBadgeCount('not-a-number'), isNull);
    expect(service.parseBadgeCount(null), isNull);
  });

  test('resolveOpenTarget maps route payloads', () {
    final service = PushNotificationService.forTesting(
      auth: _FakeAuthClient(),
      messaging: _FakeMessagingClient(),
      notifications: _FakeNotificationClient(),
      tokenRepository: _FakeTokenRepository(),
    );

    final eventDetail = service.resolveOpenTarget(
      <Object?, Object?>{'route': 'event_detail', 'eventId': 'evt-123'},
    );
    expect(eventDetail.type, PushOpenTargetType.eventDetail);
    expect(eventDetail.eventId, 'evt-123');

    final fallback = service.resolveOpenTarget(
      <Object?, Object?>{'route': 'unknown'},
    );
    expect(fallback.type, PushOpenTargetType.events);
  });

  testWidgets('foreground message updates notification display and badge', (
    WidgetTester tester,
  ) async {
    final auth = _FakeAuthClient(current: PushAuthUser(uid: 'u1'));
    final messaging = _FakeMessagingClient();
    final notifications = _FakeNotificationClient();
    final navigatorKey = GlobalKey<NavigatorState>();

    final service = PushNotificationService.forTesting(
      auth: auth,
      messaging: messaging,
      notifications: notifications,
      tokenRepository: _FakeTokenRepository(),
      onOpenTarget: (_) {},
    );

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );
    await service.initialize(navigatorKey: navigatorKey);

    messaging.onMessageController.add(
      RemoteMessage(data: <String, dynamic>{'badgeCount': '5'}),
    );
    messaging.onMessageController.add(
      RemoteMessage(data: <String, dynamic>{'badgeCount': 0}),
    );
    await tester.pump();

    expect(notifications.shownMessages.length, 2);
    expect(notifications.badgeCounts, <int>[5, 0]);

    await messaging.close();
    await auth.close();
  });

  testWidgets('handles onMessageOpenedApp route when user is authenticated', (
    WidgetTester tester,
  ) async {
    final auth = _FakeAuthClient(current: PushAuthUser(uid: 'u1'));
    final messaging = _FakeMessagingClient();
    final notifications = _FakeNotificationClient();
    final navigatorKey = GlobalKey<NavigatorState>();
    final openedTargets = <PushOpenTarget>[];

    final service = PushNotificationService.forTesting(
      auth: auth,
      messaging: messaging,
      notifications: notifications,
      tokenRepository: _FakeTokenRepository(),
      onOpenTarget: openedTargets.add,
    );

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );
    await service.initialize(navigatorKey: navigatorKey);

    messaging.onMessageOpenedController.add(
      RemoteMessage(data: <String, dynamic>{'route': 'appointments'}),
    );
    await tester.pump();

    expect(openedTargets.length, 1);
    expect(openedTargets.single.type, PushOpenTargetType.appointments);

    await messaging.close();
    await auth.close();
  });

  testWidgets('handles cold-start initial message after auth becomes available', (
    WidgetTester tester,
  ) async {
    final auth = _FakeAuthClient();
    final messaging = _FakeMessagingClient()
      ..initialMessage =
          RemoteMessage(data: <String, dynamic>{'route': 'profile'});
    final notifications = _FakeNotificationClient();
    final navigatorKey = GlobalKey<NavigatorState>();
    final openedTargets = <PushOpenTarget>[];

    final service = PushNotificationService.forTesting(
      auth: auth,
      messaging: messaging,
      notifications: notifications,
      tokenRepository: _FakeTokenRepository(),
      onOpenTarget: openedTargets.add,
    );

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );
    await service.initialize(navigatorKey: navigatorKey);
    expect(openedTargets, isEmpty);

    auth.current = PushAuthUser(uid: 'u1');
    auth.controller.add(auth.current);
    await tester.pump();

    expect(openedTargets.length, 1);
    expect(openedTargets.single.type, PushOpenTargetType.profile);

    await messaging.close();
    await auth.close();
  });
}
