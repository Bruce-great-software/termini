import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';
import 'package:termini/checkmytime/pages/event_detail_page.dart';
import 'package:termini/checkmytime/pages/profile_page.dart';
import 'package:termini/checkmytime/pages/chat_page.dart';
import 'package:termini/checkmytime/pages/user_page.dart';
import 'package:termini/checkmytime/services/notification_service.dart';
import 'package:termini/checkmytime/pages/events_page.dart';
import 'package:termini/checkmytime/pages/notifications_page.dart';

class CheckMyTimeHomePage extends StatefulWidget {
  const CheckMyTimeHomePage({super.key});

  @override
  State<CheckMyTimeHomePage> createState() => _CheckMyTimeHomePageState();
}

class _CheckMyTimeHomePageState extends State<CheckMyTimeHomePage>
    with WidgetsBindingObserver {
  static const Duration _onlineGracePeriod = Duration(minutes: 3);
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isSearching = false;
  String _searchQuery = '';
  String? _searchError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _searchResults = [];
  final Map<String, _ContactPreviewData> _contactPreviewCache = {};
  final Set<String> _dismissedActivityIds = <String>{};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _threadsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _eventsSubscription;
  bool _hasInitializedUnreadState = false;
  bool _hasInitializedInviteState = false;
  Map<String, int> _knownUnreadCountsByThread = {};
  Set<String> _knownPendingInviteIds = <String>{};
  Set<String> _knownPendingOwnerRequestKeys = <String>{};
  Set<String> _knownJoinDecisionKeys = <String>{};
  Set<String> _pendingJoinDecisionKeys = <String>{};
  Map<String, String> _knownOwnerResponseStatuses = <String, String>{};
  Set<String> _pendingOwnerResponseKeys = <String>{};
  int _lastPublishedBadgeCount = -1;
  int _eventsInitialTabIndex = 0;
  int _eventsPageOpenToken = 0;
  String? _latestInvitedEventId;
  Timer? _presenceHeartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeNotifications();
    _startPresenceTracking();
    _listenForIncomingAppointments();
    _listenForIncomingEventInvites();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await NotificationService.instance.ensureNotificationPermission(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceHeartbeat?.cancel();
    unawaited(_setCurrentUserPresence(isOnline: false));
    _threadsSubscription?.cancel();
    _eventsSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    await NotificationService.instance.initialize();
    await NotificationService.instance.requestPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPresenceTracking();
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _presenceHeartbeat?.cancel();
      unawaited(_setCurrentUserPresence(isOnline: false));
    }
  }

  Future<void> _startPresenceTracking() async {
    _presenceHeartbeat?.cancel();
    await _setCurrentUserPresence(isOnline: true);
    _presenceHeartbeat = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(_setCurrentUserPresence(isOnline: true));
    });
  }

  Future<void> _setCurrentUserPresence({required bool isOnline}) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(currentUserId).set(
        {
          'isOnline': isOnline,
          'lastSeenAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  bool _isUserOnline(Map<String, dynamic>? data) {
    if (data == null || data['isOnline'] != true) {
      return false;
    }

    final lastSeen = data['lastSeenAt'];
    if (lastSeen is! Timestamp) return true;

    return DateTime.now().difference(lastSeen.toDate()) <= _onlineGracePeriod;
  }

  String _buildThreadId(String uidA, String uidB) {
    final ids = [uidA, uidB]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  String _otherParticipantId(List<String> participants, String currentUserId) {
    for (final id in participants) {
      if (id != currentUserId) return id;
    }
    return '';
  }

  void _listenForIncomingAppointments() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    _threadsSubscription?.cancel();
    _threadsSubscription = FirebaseFirestore.instance
        .collection('contact_threads')
        .where('participantMap.$currentUserId', isEqualTo: true)
        .snapshots()
        .listen((snapshot) async {
      final currentCounts = <String, int>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['hiddenFor_$currentUserId'] == true) continue;
        final unreadCount =
        (data['unreadCountFor_$currentUserId'] ?? 0) as int;
        currentCounts[doc.id] = unreadCount;
      }

      if (!_hasInitializedUnreadState) {
        _hasInitializedUnreadState = true;
        _knownUnreadCountsByThread = currentCounts;
        await _publishBadgeCount();
        return;
      }

      // WICHTIG:
      // Chat-Nachrichten und Sprachnachrichten erhöhen ebenfalls den
      // unreadCount eines Threads. Eine lokale "Neue Planung"-Notification
      // an dieser Stelle würde deshalb bei normalen Nachrichten fälschlich
      // eine zweite Push auslösen.
      //
      // Die eigentlichen Push-Benachrichtigungen kommen bereits über FCM /
      // PushNotificationService. Hier synchronisieren wir deshalb nur noch
      // den lokalen Badge-Zustand.
      _knownUnreadCountsByThread = currentCounts;
      await _publishBadgeCount();
    });
  }

  bool _isPendingEventInvite(Map<String, dynamic> data, String currentUserId) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final invitedUserIds = List<String>.from(
      data['invitedUserIds'] ?? const [],
    );
    final acceptedUserIds = List<String>.from(
      data['acceptedUserIds'] ?? const [],
    );
    final maybeUserIds = List<String>.from(data['maybeUserIds'] ?? const []);
    final declinedUserIds = List<String>.from(
      data['declinedUserIds'] ?? const [],
    );

    if (createdBy == currentUserId) return false;
    if (!invitedUserIds.contains(currentUserId)) return false;
    if (acceptedUserIds.contains(currentUserId)) return false;
    if (maybeUserIds.contains(currentUserId)) return false;
    if (declinedUserIds.contains(currentUserId)) return false;
    return true;
  }

  Map<String, dynamic> _inviteSeenAtMap(Map<String, dynamic> data) {
    return Map<String, dynamic>.from(
      data['inviteSeenAtMap'] ?? const <String, dynamic>{},
    );
  }

  String _responseForUser(Map<String, dynamic> data, String currentUserId) {
    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    final directResponse =
    (responseMap[currentUserId] ?? '').toString().trim().toLowerCase();

    final acceptedUserIds = List<String>.from(
      data['acceptedUserIds'] ?? const [],
    );
    final maybeUserIds = List<String>.from(data['maybeUserIds'] ?? const []);
    final declinedUserIds = List<String>.from(
      data['declinedUserIds'] ?? const [],
    );

    if (acceptedUserIds.contains(currentUserId)) return 'accepted';
    if (maybeUserIds.contains(currentUserId)) return 'maybe';
    if (declinedUserIds.contains(currentUserId)) return 'declined';
    if (directResponse.isNotEmpty) return directResponse;
    return 'pending';
  }

  bool _hasSeenInvite(Map<String, dynamic> data, String currentUserId) {
    if (currentUserId.trim().isEmpty) return false;
    final seenMap = _inviteSeenAtMap(data);
    if (seenMap[currentUserId] != null) return true;

    final response = _responseForUser(data, currentUserId);
    return response == 'accepted' || response == 'maybe' || response == 'declined';
  }

  bool _isUnseenPendingEventInvite(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    return _isPendingEventInvite(data, currentUserId) &&
        !_hasSeenInvite(data, currentUserId);
  }

  bool _isBellCountHandledByEventState(String type) {
    switch (type.trim().toLowerCase()) {
      case 'event_invite':
      case 'event_join_request':
      case 'event_direct_join':
      case 'event_response_accepted':
      case 'event_response_maybe':
      case 'event_response_declined':
      case 'event_join_request_accepted':
      case 'event_join_request_declined':
        return true;
      default:
        return false;
    }
  }


  Set<String> _pendingRequestKeysForOwner(
      String eventId,
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy != currentUserId) return const <String>{};

    final joinMode = (data['joinMode'] ?? 'invite_only')
        .toString()
        .trim()
        .toLowerCase();

    // Nur echte Teilnahme-Anfragen des Typs "Anfrage senden" sollen
    // beim Ersteller als neue Anfrage zählen.
    // Reine Einladungen bei "Nur Einladung" dürfen hier nicht
    // als Anfrage/Badge/Notification auftauchen.
    if (joinMode != 'request') return const <String>{};

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );

    final pendingKeys = <String>{};
    for (final entry in responseMap.entries) {
      final requesterId = entry.key.toString().trim();
      final status = entry.value.toString().trim();
      if (requesterId.isEmpty || requesterId == currentUserId) continue;
      if (status == 'pending') {
        pendingKeys.add('$eventId:$requesterId');
      }
    }
    return pendingKeys;
  }

  String? _joinDecisionKeyForRequester(
      String eventId,
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy == currentUserId) return null;

    final joinMode = (data['joinMode'] ?? '').toString().trim().toLowerCase();
    if (joinMode != 'request') return null;

    final acceptedUserIds = List<String>.from(
      data['acceptedUserIds'] ?? const [],
    );
    final declinedUserIds = List<String>.from(
      data['declinedUserIds'] ?? const [],
    );
    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    final directResponse =
    (responseMap[currentUserId] ?? '').toString().trim().toLowerCase();

    if (acceptedUserIds.contains(currentUserId) || directResponse == 'accepted') {
      return '$eventId:accepted';
    }
    if (declinedUserIds.contains(currentUserId) || directResponse == 'declined') {
      return '$eventId:declined';
    }
    return null;
  }

  String _joinDecisionLabelFromKey(String decisionKey) {
    if (decisionKey.endsWith(':accepted')) return 'angenommen';
    if (decisionKey.endsWith(':declined')) return 'abgelehnt';
    return 'neu';
  }

  Map<String, String> _ownerResponseStatusesForEvent(
      String eventId,
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy != currentUserId) return const <String, String>{};

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    final invitedUserIds = List<String>.from(
      data['invitedUserIds'] ?? const [],
    );
    final memberIds = List<String>.from(data['memberIds'] ?? const []);
    final acceptedUserIds = List<String>.from(
      data['acceptedUserIds'] ?? const [],
    );
    final maybeUserIds = List<String>.from(data['maybeUserIds'] ?? const []);
    final declinedUserIds = List<String>.from(
      data['declinedUserIds'] ?? const [],
    );

    final userIds = <String>{
      ...invitedUserIds,
      ...memberIds,
      ...acceptedUserIds,
      ...maybeUserIds,
      ...declinedUserIds,
      ...responseMap.keys.map((key) => key.toString().trim()),
    }..removeWhere((id) => id.trim().isEmpty || id == currentUserId);

    final result = <String, String>{};
    for (final userId in userIds) {
      String status = '';
      if (acceptedUserIds.contains(userId)) {
        status = 'accepted';
      } else if (maybeUserIds.contains(userId)) {
        status = 'maybe';
      } else if (declinedUserIds.contains(userId)) {
        status = 'declined';
      } else {
        status = (responseMap[userId] ?? '').toString().trim().toLowerCase();
      }

      if (status.isEmpty) {
        status = 'pending';
      }

      result['$eventId:$userId'] = status;
    }

    return result;
  }

  String _ownerResponseKey(String baseKey, String status) {
    return '$baseKey:$status';
  }

  String _ownerResponseBaseKey(String fullKey) {
    final parts = fullKey.split(':');
    if (parts.length < 3) return fullKey;
    return '${parts[0]}:${parts[1]}';
  }

  String _ownerResponseStatusFromKey(String fullKey) {
    final parts = fullKey.split(':');
    return parts.isEmpty ? '' : parts.last;
  }

  String _ownerResponseUserIdFromKey(String fullKey) {
    final parts = fullKey.split(':');
    if (parts.length < 2) return '';
    return parts[1];
  }

  String _ownerResponseSubtitle({
    required Map<String, dynamic> data,
    required String status,
    required String actorName,
  }) {
    final joinMode = (data['joinMode'] ?? '').toString().trim().toLowerCase();

    if (status == 'accepted' && joinMode == 'direct') {
      return '$actorName ist direkt beigetreten.';
    }

    switch (status) {
      case 'accepted':
        return '$actorName hat zugesagt.';
      case 'maybe':
        return '$actorName hat vielleicht geantwortet.';
      case 'declined':
        return '$actorName hat abgesagt.';
      default:
        return '$actorName hat reagiert.';
    }
  }

  Future<String> _loadUserDisplayName(String userId) async {
    if (userId.trim().isEmpty) return 'Jemand';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = doc.data() ?? <String, dynamic>{};
      final name =
      (data['displayName'] ?? data['name'] ?? '').toString().trim();
      return name.isEmpty ? 'Jemand' : name;
    } catch (_) {
      return 'Jemand';
    }
  }


  int _timestampKey(Timestamp? value) => value?.millisecondsSinceEpoch ?? 0;

  bool _hasDismissedNotificationPrefix(
      Set<String> dismissedKeys,
      String prefix,
      ) {
    return dismissedKeys.any((key) => key.startsWith(prefix));
  }

  Future<void> _dismissActivityForCurrentUser(
      String currentUserId,
      String activityId,
      ) async {
    if (currentUserId.trim().isEmpty || activityId.trim().isEmpty) return;

    setState(() {
      _dismissedActivityIds.add(activityId);
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(currentUserId).set(
        {
          'dismissedActivityIds': FieldValue.arrayUnion([activityId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aktivität entfernt.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dismissedActivityIds.remove(activityId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aktivität konnte nicht entfernt werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Stream<int> _unreadNotificationsStream(String uid) {
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  String _relativeTime(DateTime value) {
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'Gerade eben';
    if (diff.inHours < 1) return 'vor ${diff.inMinutes} Min';
    if (diff.inDays < 1) return 'vor ${diff.inHours} Std';
    if (diff.inDays < 7) return 'vor ${diff.inDays} Tag${diff.inDays == 1 ? '' : 'en'}';
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }

  int _eventActionBadgeCount({
    Set<String> dismissedKeys = const <String>{},
  }) {
    final inviteCount = _knownPendingInviteIds.where((eventId) {
      return !_hasDismissedNotificationPrefix(
        dismissedKeys,
        'event_invite:$eventId:',
      );
    }).length;

    final ownerRequestCount = _knownPendingOwnerRequestKeys.where((requestKey) {
      final eventId = requestKey.split(':').first;
      return !_hasDismissedNotificationPrefix(
        dismissedKeys,
        'event_owner_request:$eventId:',
      );
    }).length;

    final joinDecisionCount = _pendingJoinDecisionKeys.where((decisionKey) {
      final parts = decisionKey.split(':');
      if (parts.length < 2) return true;
      return !_hasDismissedNotificationPrefix(
        dismissedKeys,
        'event_join_decision:${parts[0]}:${parts[1]}:',
      );
    }).length;

    final ownerResponseCount = _pendingOwnerResponseKeys.where((fullKey) {
      final eventId = _ownerResponseBaseKey(fullKey).split(':').first;
      return !_hasDismissedNotificationPrefix(
        dismissedKeys,
        'event_owner_response:$eventId:',
      );
    }).length;

    return inviteCount +
        ownerRequestCount +
        joinDecisionCount +
        ownerResponseCount;
  }

  int _preferredEventsTabIndex() {
    if (_knownPendingOwnerRequestKeys.isNotEmpty ||
        _pendingOwnerResponseKeys.isNotEmpty) {
      return 2;
    }
    if (_pendingJoinDecisionKeys.isNotEmpty || _knownPendingInviteIds.isNotEmpty) {
      return 1;
    }
    return 0;
  }

  void _openEventsArea({required bool pushRoute}) {
    final initialTabIndex = _preferredEventsTabIndex();

    setState(() {
      _eventsInitialTabIndex = initialTabIndex;
      _eventsPageOpenToken++;
      _pendingJoinDecisionKeys = <String>{};
      _pendingOwnerResponseKeys = <String>{};
    });

    unawaited(_publishBadgeCount());

    if (pushRoute) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventsPage(initialTabIndex: initialTabIndex),
        ),
      );
      return;
    }

    setState(() {
      _selectedIndex = 2;
    });
  }

  Widget _buildNavigationIcon(IconData icon, int badgeCount) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (badgeCount > 0)
          Positioned(
            right: -8,
            top: -6,
            child: _NewItemsBadge(count: badgeCount),
          ),
      ],
    );
  }

  void _listenForIncomingEventInvites() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    _eventsSubscription?.cancel();
    _eventsSubscription = FirebaseFirestore.instance
        .collection('events')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) async {
      final pendingInviteIds = <String>{};
      final pendingOwnerRequestKeys = <String>{};
      final currentJoinDecisionKeys = <String>{};
      final currentOwnerResponseStatuses = <String, String>{};
      final eventTitlesByRequestKey = <String, String>{};
      final eventTitlesByDecisionKey = <String, String>{};
      final eventTitlesByOwnerBaseKey = <String, String>{};
      final joinModesByOwnerBaseKey = <String, String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final eventStatus = (data['status'] ?? '').toString().trim().toLowerCase();
        final isCancelledEvent = eventStatus == 'cancelled' || eventStatus == 'canceled';

        if (_isUnseenPendingEventInvite(data, currentUserId)) {
          pendingInviteIds.add(doc.id);
        }

        final pendingKeys =
        _pendingRequestKeysForOwner(doc.id, data, currentUserId);
        if (pendingKeys.isNotEmpty) {
          final eventTitle = (data['title'] ?? 'deinem Event').toString().trim();
          for (final key in pendingKeys) {
            pendingOwnerRequestKeys.add(key);
            eventTitlesByRequestKey[key] =
            eventTitle.isEmpty ? 'deinem Event' : eventTitle;
          }
        }

        final decisionKey =
        _joinDecisionKeyForRequester(doc.id, data, currentUserId);
        if (decisionKey != null) {
          currentJoinDecisionKeys.add(decisionKey);
          final eventTitle = (data['title'] ?? 'dem Event').toString().trim();
          eventTitlesByDecisionKey[decisionKey] =
          eventTitle.isEmpty ? 'dem Event' : eventTitle;
        }

        final ownerResponses =
        _ownerResponseStatusesForEvent(doc.id, data, currentUserId);
        if (ownerResponses.isNotEmpty) {
          final eventTitle = (data['title'] ?? 'dem Event').toString().trim();
          final joinMode =
          (data['joinMode'] ?? '').toString().trim().toLowerCase();

          ownerResponses.forEach((baseKey, status) {
            currentOwnerResponseStatuses[baseKey] = status;
            eventTitlesByOwnerBaseKey[baseKey] =
            eventTitle.isEmpty ? 'dem Event' : eventTitle;
            joinModesByOwnerBaseKey[baseKey] = joinMode;
          });
        }

        if (isCancelledEvent) {
          // Event-Absagen werden bereits serverseitig per Push verschickt.
          // Hier deshalb keine zusätzlichen lokalen Event-Notifications auslösen,
          // damit die Absage nicht doppelt erscheint.
          continue;
        }
      }

      if (!_hasInitializedInviteState) {
        _hasInitializedInviteState = true;
        _knownPendingInviteIds = pendingInviteIds;
        _knownPendingOwnerRequestKeys = pendingOwnerRequestKeys;
        _knownJoinDecisionKeys = currentJoinDecisionKeys;
        _knownOwnerResponseStatuses = currentOwnerResponseStatuses;
        if (mounted) {
          setState(() {});
        }
        await _publishBadgeCount();
        return;
      }

      final newInviteIds = pendingInviteIds.difference(_knownPendingInviteIds);
      for (final eventId in newInviteIds) {
        // Die eigentliche Event-Einladung wird bereits serverseitig per FCM
        // verschickt. Hier keine zweite lokale Notification auslösen,
        // sonst erscheint dieselbe Einladung doppelt.
        if (mounted) {
          setState(() => _latestInvitedEventId = eventId);
        }
      }

      final newOwnerRequestKeys = pendingOwnerRequestKeys.difference(
        _knownPendingOwnerRequestKeys,
      );

      for (final requestKey in newOwnerRequestKeys) {
        final eventTitle = eventTitlesByRequestKey[requestKey] ?? 'deinem Event';
        await NotificationService.instance.showIncomingEventRequestNotification(
          title: 'Neue Teilnahme-Anfrage',
          body: 'Für "$eventTitle" gibt es eine neue Anfrage.',
        );
      }

      final newJoinDecisionKeys = currentJoinDecisionKeys.difference(
        _knownJoinDecisionKeys,
      );

      for (final decisionKey in newJoinDecisionKeys) {
        final eventTitle = eventTitlesByDecisionKey[decisionKey] ?? 'deinem Event';
        final decisionLabel = _joinDecisionLabelFromKey(decisionKey);
        await NotificationService.instance.showIncomingEventRequestNotification(
          title: 'Anfrage beantwortet',
          body: 'Deine Anfrage für "$eventTitle" wurde $decisionLabel.',
        );
      }

      final newOwnerResponseKeys = <String>{};
      for (final entry in currentOwnerResponseStatuses.entries) {
        final baseKey = entry.key;
        final currentStatus = entry.value;
        final previousStatus = _knownOwnerResponseStatuses[baseKey];
        final joinMode = joinModesByOwnerBaseKey[baseKey] ?? '';

        if (currentStatus == 'pending') {
          continue;
        }

        bool shouldNotify = false;
        if (previousStatus == null) {
          shouldNotify = true;
        } else if (previousStatus != currentStatus) {
          final isOwnerDecisionForRequest =
              joinMode == 'request' &&
                  previousStatus == 'pending' &&
                  (currentStatus == 'accepted' || currentStatus == 'declined');

          if (!isOwnerDecisionForRequest) {
            shouldNotify = true;
          }
        }

        if (shouldNotify) {
          newOwnerResponseKeys.add(_ownerResponseKey(baseKey, currentStatus));
        }
      }

      for (final fullKey in newOwnerResponseKeys) {
        final baseKey = _ownerResponseBaseKey(fullKey);
        final status = _ownerResponseStatusFromKey(fullKey);
        final actorUserId = _ownerResponseUserIdFromKey(fullKey);
        final actorName = await _loadUserDisplayName(actorUserId);
        final eventTitle = eventTitlesByOwnerBaseKey[baseKey] ?? 'dem Event';
        final joinMode = joinModesByOwnerBaseKey[baseKey] ?? '';

        final title = status == 'accepted' && joinMode == 'direct'
            ? 'Neuer Teilnehmer'
            : 'Teilnahme aktualisiert';
        final body = _ownerResponseSubtitle(
          data: {'joinMode': joinMode},
          status: status,
          actorName: actorName,
        );

        await NotificationService.instance.showIncomingEventUpdateNotification(
          title: title,
          body: '$body Bei "$eventTitle".',
        );
      }

      _knownPendingInviteIds = pendingInviteIds;
      _knownPendingOwnerRequestKeys = pendingOwnerRequestKeys;
      _knownJoinDecisionKeys = currentJoinDecisionKeys;
      _knownOwnerResponseStatuses = currentOwnerResponseStatuses;
      _pendingJoinDecisionKeys = {
        ..._pendingJoinDecisionKeys.where(currentJoinDecisionKeys.contains),
        ...newJoinDecisionKeys,
      };
      _pendingOwnerResponseKeys = {
        ..._pendingOwnerResponseKeys.where((fullKey) {
          final baseKey = _ownerResponseBaseKey(fullKey);
          final status = _ownerResponseStatusFromKey(fullKey);
          return currentOwnerResponseStatuses[baseKey] == status;
        }),
        ...newOwnerResponseKeys,
      };
      if (mounted) {
        setState(() {});
      }
      await _publishBadgeCount();
    });
  }

  Future<void> _publishBadgeCount() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    final unreadAppointments = _knownUnreadCountsByThread.values.fold<int>(
      0,
          (total, value) => total + value,
    );
    final totalBadgeCount = unreadAppointments + _eventActionBadgeCount();

    if (totalBadgeCount == _lastPublishedBadgeCount) return;
    _lastPublishedBadgeCount = totalBadgeCount;

    await NotificationService.instance.setAppBadgeCount(totalBadgeCount);
    await FirebaseFirestore.instance.collection('users').doc(currentUserId).set(
      {
        'badgeCount': totalBadgeCount,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<_ContactPreviewData> _loadContactPreview({
    required String contactId,
    required String fallbackName,
    required String fallbackPhone,
  }) async {
    if (_contactPreviewCache.containsKey(contactId)) {
      return _contactPreviewCache[contactId]!;
    }

    var resolvedName = fallbackName.trim();
    var resolvedPhone = fallbackPhone.trim();
    var resolvedImageUrl = '';

    try {
      final doc =
      await FirebaseFirestore.instance
          .collection('users')
          .doc(contactId)
          .get();
      final data = doc.data();

      if (data != null) {
        final firestoreName =
        (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final firestorePhone = (data['phoneNumber'] ?? '').toString().trim();
        final firestoreImageUrl =
        (data['profileImageUrl'] ?? '').toString().trim();

        if (firestoreName.isNotEmpty) {
          resolvedName = firestoreName;
        }
        if (firestorePhone.isNotEmpty) {
          resolvedPhone = firestorePhone;
        }
        if (firestoreImageUrl.isNotEmpty) {
          resolvedImageUrl = firestoreImageUrl;
        }
      }
    } catch (_) {}

    if (resolvedName.isEmpty) {
      resolvedName = 'Unbekannt';
    }

    final preview = _ContactPreviewData(
      name: resolvedName,
      phone: resolvedPhone,
      imageUrl: resolvedImageUrl,
    );
    _contactPreviewCache[contactId] = preview;
    return preview;
  }


  bool _isOtherUserTyping(
      Map<String, dynamic> data,
      String currentUserId,
      String otherParticipantId,
      ) {
    final typingTimestamp =
        data['typingAt'] as Timestamp? ??
            data['typingUpdatedAt'] as Timestamp? ??
            data['currentlyTypingAt'] as Timestamp?;

    final isTypingFresh = typingTimestamp != null &&
        DateTime.now().difference(typingTimestamp.toDate()) <=
            const Duration(seconds: 8);

    final typingBy = (data['typingBy'] ??
        data['typingUserId'] ??
        data['typingUid'] ??
        data['currentlyTypingUserId'] ??
        '')
        .toString()
        .trim();
    if (typingBy.isNotEmpty) {
      return typingBy == otherParticipantId &&
          typingBy != currentUserId &&
          isTypingFresh;
    }

    final typingIds = List<String>.from(
      data['typingUserIds'] ?? data['currentlyTypingUserIds'] ?? const [],
    );
    return typingIds.contains(otherParticipantId) &&
        !typingIds.contains(currentUserId) &&
        isTypingFresh;
  }

  String _formatVoiceDuration(dynamic value) {
    if (value == null) return '';
    if (value is int) {
      final minutes = value ~/ 60;
      final seconds = value % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }

    final raw = value.toString().trim();
    return raw;
  }

  String _threadPreviewText(
      Map<String, dynamic> data, {
        required String currentUserId,
        required String otherParticipantId,
        required bool isOnline,
      }) {
    if (_isOtherUserTyping(data, currentUserId, otherParticipantId)) {
      return 'Schreibt gerade…';
    }

    final lastMessageType = (data['lastMessageType'] ??
        data['messageType'] ??
        data['lastInteractionType'] ??
        '')
        .toString()
        .trim()
        .toLowerCase();

    final voiceDuration = _formatVoiceDuration(
      data['lastVoiceDuration'] ??
          data['lastVoiceDurationSeconds'] ??
          data['lastAudioDuration'] ??
          data['lastMessageDuration'],
    );

    if (lastMessageType == 'voice' ||
        lastMessageType == 'audio' ||
        lastMessageType == 'sprachnachricht') {
      return voiceDuration.isNotEmpty
          ? 'Sprachnachricht · $voiceDuration'
          : 'Sprachnachricht';
    }

    final previewCandidates = [
      data['lastMessageText'],
      data['lastMessage'],
      data['lastMessagePreview'],
      data['lastText'],
      data['lastInteractionText'],
      data['lastAppointmentTitle'],
    ];

    for (final candidate in previewCandidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    return isOnline ? 'Online jetzt' : 'Noch keine Nachricht';
  }

  String _formatThreadTime(Map<String, dynamic> data) {
    final timestamp =
        data['updatedAt'] as Timestamp? ?? data['lastInteractionAt'] as Timestamp?;
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) return 'Jetzt';
    if (difference.inMinutes < 60) return '${difference.inMinutes} Min.';
    if (difference.inHours < 24) return '${difference.inHours} Std.';

    final today = DateTime(now.year, now.month, now.day);
    final otherDay = DateTime(date.year, date.month, date.day);
    final dayDifference = today.difference(otherDay).inDays;

    if (dayDifference == 1) return 'Gestern';
    if (dayDifference < 7) {
      const weekdays = [
        'Mo.',
        'Di.',
        'Mi.',
        'Do.',
        'Fr.',
        'Sa.',
        'So.',
      ];
      return weekdays[date.weekday - 1];
    }

    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }

  Widget _buildContactAvatar({
    required _ContactPreviewData preview,
    required ThemeData theme,
    bool isOnline = false,
  }) {
    final colorScheme = theme.colorScheme;

    if (preview.imageUrl.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isOnline ? Border.all(color: const Color(0xFF19B35E), width: 2.5) : null,
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: CircleAvatar(
          radius: 24,
          backgroundImage: NetworkImage(preview.imageUrl),
        ),
      );
    }

    final letter =
    preview.name.isNotEmpty
        ? preview.name.characters.first.toUpperCase()
        : '?';

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isOnline ? Border.all(color: const Color(0xFF19B35E), width: 2.5) : null,
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: theme.textTheme.titleMedium?.copyWith(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPresenceAvatar({
    required _ContactPreviewData preview,
    required ThemeData theme,
    required bool isOnline,
  }) {
    final avatar = _buildContactAvatar(
      preview: preview,
      theme: theme,
      isOnline: isOnline,
    );
    if (!isOnline) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF19B35E),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThreadRow({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required _ContactPreviewData preview,
    required bool hasUnread,
    required int unreadCount,
    required bool isOnline,
    required String previewText,
    required String trailingTimeText,
    required bool isTyping,
    required bool showDivider,
    required bool isFirst,
    required bool isLast,
    required VoidCallback onTap,
  }) {
    final topRadius = isFirst ? const Radius.circular(22) : Radius.zero;
    final bottomRadius = isLast ? const Radius.circular(22) : Radius.zero;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
      height: 1.1,
    );
    final previewColor = isTyping
        ? colorScheme.primary
        : hasUnread
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.only(
          topLeft: topRadius,
          topRight: topRadius,
          bottomLeft: bottomRadius,
          bottomRight: bottomRadius,
        ),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPresenceAvatar(
                    preview: preview,
                    theme: theme,
                    isOnline: isOnline,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                preview.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle,
                              ),
                            ),
                            if (trailingTimeText.trim().isNotEmpty)
                              Text(
                                trailingTimeText,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: hasUnread
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                previewText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: previewColor,
                                  fontWeight: isTyping || hasUnread
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  fontStyle: isTyping
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ),
                            if (hasUnread) ...[
                              const SizedBox(width: 10),
                              _ThreadUnreadBadge(count: unreadCount),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (showDivider) ...[
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.65),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  void _resetSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _searchError = null;
      _searchResults = [];
      _isSearching = false;
    });
  }

  Future<void> _openChatThread({
    required String contactId,
    required String contactName,
    required String phoneNumber,
  }) async {
    final safeName =
    contactName.trim().isEmpty ? 'Unbekannt' : contactName.trim();
    final safePhone = phoneNumber.trim();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId != null && contactId.isNotEmpty) {
      final threadId = _buildThreadId(currentUserId, contactId);
      try {
        await FirebaseFirestore.instance
            .collection('contact_threads')
            .doc(threadId)
            .set({
          'participants': [currentUserId, contactId]..sort(),
          'participantMap': {currentUserId: true, contactId: true},
          'contactNames': {contactId: safeName},
          'contactPhones': {contactId: safePhone},
          'hiddenFor_$currentUserId': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'unreadCountFor_$currentUserId': 0,
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactThreadPage(
          contactId: contactId,
          contactName: safeName,
          phoneNumber: safePhone,
        ),
      ),
    );
  }

  Future<void> _openContact({
    required String contactId,
    required String contactName,
    required String phoneNumber,
  }) async {
    final safeName =
    contactName.trim().isEmpty ? 'Unbekannt' : contactName.trim();
    final safePhone = phoneNumber.trim();

    _resetSearch();

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserPage(
          userId: contactId,
          initialName: safeName,
          onMessageTap: () {
            _openChatThread(
              contactId: contactId,
              contactName: safeName,
              phoneNumber: safePhone,
            );
          },
        ),
      ),
    );

    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  Future<void> _searchUsers(String value) async {
    final query = value.trim();

    setState(() {
      _searchQuery = query;
      _searchError = null;
    });

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final snapshot =
      await FirebaseFirestore.instance.collection('users').limit(50).get();

      final lowerQuery = query.toLowerCase();

      final filtered =
      snapshot.docs.where((doc) {
        if (doc.id == currentUid) return false;

        final data = doc.data();
        final displayName =
        (data['displayName'] ?? '').toString().trim().toLowerCase();
        final legacyName =
        (data['name'] ?? '').toString().trim().toLowerCase();
        final phoneNumber =
        (data['phoneNumber'] ?? '').toString().trim().toLowerCase();

        return displayName.contains(lowerQuery) ||
            legacyName.contains(lowerQuery) ||
            phoneNumber.contains(lowerQuery);
      }).toList();

      if (!mounted) return;

      setState(() {
        _searchResults = filtered;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _searchError = 'Fehler bei der Suche.';
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Center(
          child: Text(_searchError!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(child: Text('Keine Person gefunden.')),
      );
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gefundene Personen', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ..._searchResults.map((doc) {
            final data = doc.data();
            final fallbackName =
            (data['displayName'] ?? data['name'] ?? 'Unbekannt')
                .toString()
                .trim();
            final fallbackPhone = (data['phoneNumber'] ?? '').toString().trim();
            final isProfilePublic = data['isProfilePublic'] as bool? ?? true;

            return FutureBuilder<_ContactPreviewData>(
              future: _loadContactPreview(
                contactId: doc.id,
                fallbackName: fallbackName,
                fallbackPhone: fallbackPhone,
              ),
              builder: (context, snapshot) {
                final preview =
                    snapshot.data ??
                        _ContactPreviewData(
                          name: fallbackName.isEmpty ? 'Unbekannt' : fallbackName,
                          phone: fallbackPhone,
                          imageUrl: '',
                        );

                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      _openContact(
                        contactId: doc.id,
                        contactName: preview.name,
                        phoneNumber: preview.phone,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _buildContactAvatar(preview: preview, theme: theme),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preview.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  preview.phone.isNotEmpty
                                      ? preview.phone
                                      : 'Keine Nummer vorhanden',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isProfilePublic
                                        ? const Color(0xFFEAF8EF)
                                        : const Color(0xFFFFF4E6),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    isProfilePublic ? 'Öffentliches Profil' : 'Privates Profil',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: isProfilePublic
                                          ? const Color(0xFF19B35E)
                                          : const Color(0xFFE39B2E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  String _buildGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Guten Morgen';
    if (hour < 18) return 'Guten Tag';
    return 'Guten Abend';
  }

  String _buildGreetingWithName(String? displayName) {
    final baseGreeting = _buildGreeting();
    final resolvedName = (displayName ?? '').trim();
    if (resolvedName.isEmpty) return baseGreeting;

    final firstName = resolvedName.split(RegExp(r'\s+')).first.trim();
    if (firstName.isEmpty) return baseGreeting;

    return '$baseGreeting, $firstName';
  }

  int _totalUnreadMessages() {
    return _knownUnreadCountsByThread.values.fold<int>(
      0,
          (runningTotal, unreadCount) => runningTotal + unreadCount,
    );
  }

  Widget _buildHeroSection(
      ThemeData theme,
      ColorScheme colorScheme,
      String? currentUserId,
      ) {
    final unreadTotal = _totalUnreadMessages();
    final activeThreads = _knownUnreadCountsByThread.length;
    final authDisplayName = FirebaseAuth.instance.currentUser?.displayName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            const Color(0xFF7C8AF4),
            colorScheme.primaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream:
            currentUserId == null
                ? null
                : FirebaseFirestore.instance
                .collection('users')
                .doc(currentUserId)
                .snapshots(),
            builder: (context, snapshot) {
              final userData = snapshot.data?.data();
              final firestoreName =
              (userData?['displayName'] ?? userData?['name'] ?? '')
                  .toString()
                  .trim();
              final greetingText = _buildGreetingWithName(
                firestoreName.isNotEmpty ? firestoreName : authDisplayName,
              );

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  greetingText,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroStatCard(
                  label: 'Ungelesen',
                  value: '$unreadTotal',
                  icon: Icons.mark_chat_unread_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeroStatCard(
                  label: 'Gespräche',
                  value: '$activeThreads',
                  icon: Icons.people_alt_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineUsersSection(
      ThemeData theme,
      ColorScheme colorScheme,
      String? currentUserId,
      ) {
    if (currentUserId == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
      FirebaseFirestore.instance
          .collection('users')
          .where('isOnline', isEqualTo: true)
          .limit(12)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final onlineUsers = snapshot.data!.docs.where((doc) {
          if (doc.id == currentUserId) return false;
          return _isUserOnline(doc.data());
        }).toList()
          ..sort((a, b) {
            final aName =
            (a.data()['displayName'] ?? a.data()['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final bName =
            (b.data()['displayName'] ?? b.data()['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            return aName.compareTo(bName);
          });

        if (onlineUsers.isEmpty) {
          return const SizedBox.shrink();
        }

        final visibleUsers = onlineUsers.take(10).toList();

        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: visibleUsers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final doc = visibleUsers[index];
                final data = doc.data();
                final displayName =
                (data['displayName'] ?? data['name'] ?? 'Unbekannt')
                    .toString()
                    .trim();
                final preview = _ContactPreviewData(
                  name: displayName.isEmpty ? 'Unbekannt' : displayName,
                  phone: (data['phoneNumber'] ?? '').toString().trim(),
                  imageUrl: (data['profileImageUrl'] ?? '').toString().trim(),
                );

                return Tooltip(
                  message: preview.name,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      _openContact(
                        contactId: doc.id,
                        contactName: preview.name,
                        phoneNumber: preview.phone,
                      );
                    },
                    child: SizedBox(
                      width: 72,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildPresenceAvatar(
                            preview: preview,
                            theme: theme,
                            isOnline: true,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            preview.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }


  Widget _buildFollowingActivitiesSection(
      ThemeData theme,
      ColorScheme colorScheme,
      String? currentUserId,
      ) {
    if (currentUserId == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() ?? <String, dynamic>{};
        final followingIds =
        List<String>.from(userData['followingIds'] ?? const <String>[]);
        final dismissedActivityIds = <String>{
          ...List<String>.from(userData['dismissedActivityIds'] ?? const <String>[]),
          ..._dismissedActivityIds,
        };

        Widget emptyCard({
          required String title,
          required String subtitle,
          required IconData icon,
        }) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          );
        }

        if (followingIds.isEmpty) {
          return emptyCard(
            title: 'Aktivitäten deiner Kontakte',
            subtitle:
            'Folge Leuten, um hier ihre Aktivitäten zu sehen. Private Profile bleiben in der Suche sichtbar, Inhalte öffnen sich dann nach Zusage.',
            icon: Icons.dynamic_feed_outlined,
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('activities')
              .orderBy('createdAt', descending: true)
              .limit(40)
              .snapshots(),
          builder: (context, activitySnapshot) {
            if (!activitySnapshot.hasData) {
              return const SizedBox.shrink();
            }

            final docs = activitySnapshot.data!.docs.where((doc) {
              final data = doc.data();
              final actorUserId = (data['actorUserId'] ?? '').toString().trim();
              return actorUserId.isNotEmpty &&
                  actorUserId != currentUserId &&
                  followingIds.contains(actorUserId) &&
                  !dismissedActivityIds.contains(doc.id);
            }).take(10).toList();

            if (docs.isEmpty) {
              return emptyCard(
                title: 'Aktivitäten deiner Kontakte',
                subtitle:
                'Noch ruhig – sobald deine Kontakte etwas planen oder ihr Profil aktualisieren, erscheint es hier.',
                icon: Icons.schedule_outlined,
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aktivitäten deiner Kontakte',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Hier siehst du, was Menschen planen, denen du bereits folgst.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ...docs.map((doc) {
                  final data = doc.data();
                  final actorUserId =
                  (data['actorUserId'] ?? '').toString().trim();
                  final actorName =
                  (data['actorName'] ?? 'Jemand').toString().trim();
                  final actorImageUrl =
                  (data['actorImageUrl'] ?? '').toString().trim();
                  final type = (data['type'] ?? '').toString().trim();
                  final eventTitle =
                  (data['eventTitle'] ?? 'Event').toString().trim();
                  final eventId = (data['eventId'] ?? '').toString().trim();
                  final createdAt =
                      (data['createdAt'] as Timestamp?)?.toDate() ??
                          DateTime.now();

                  String title;
                  String subtitle;

                  switch (type) {
                    case 'profile_updated':
                      title = '$actorName hat sein Profil aktualisiert';
                      subtitle = _relativeTime(createdAt);
                      break;
                    case 'event_created':
                    default:
                      title = '$actorName hat „$eventTitle“ erstellt';
                      subtitle = _relativeTime(createdAt);
                      break;
                  }

                  final preview = _ContactPreviewData(
                    name: actorName.isEmpty ? 'Jemand' : actorName,
                    phone: '',
                    imageUrl: actorImageUrl,
                  );

                  return Dismissible(
                    key: ValueKey('activity_${doc.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: colorScheme.error,
                      ),
                    ),
                    onDismissed: (_) => _dismissActivityForCurrentUser(currentUserId, doc.id),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          if (eventId.isNotEmpty) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EventDetailPage(
                                  eventId: eventId,
                                  view: EventDetailView.openEvent,
                                ),
                              ),
                            );
                            return;
                          }

                          if (actorUserId.isNotEmpty) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UserPage(
                                  userId: actorUserId,
                                  initialName: actorName,
                                  initialImageUrl: actorImageUrl,
                                ),
                              ),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildContactAvatar(preview: preview, theme: theme),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      subtitle,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }


  Widget _buildSearchPanel(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personen finden',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Suche nach Namen oder Telefonnummern und öffne direkt einen Kontakt.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _searchUsers,
            decoration: InputDecoration(
              hintText: 'Nach Name oder Nummer suchen',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
              _searchController.text.isNotEmpty
                  ? IconButton(
                onPressed: _resetSearch,
                icon: const Icon(Icons.close),
              )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _hideThreadForCurrentUser(
      String threadId,
      String currentUserId,
      ) async {
    try {
      await FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(threadId)
          .set({
        'hiddenFor_$currentUserId': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kontakt wurde von der Startseite entfernt.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kontakt konnte nicht entfernt werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildThreadsSection(String currentUserId) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
      FirebaseFirestore.instance
          .collection('contact_threads')
          .where('participantMap.$currentUserId', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs =
        [...snapshot.data?.docs ?? []]
            .where((doc) => doc.data()['hiddenFor_$currentUserId'] != true)
            .toList()
          ..sort((a, b) {
            final aData = a.data();
            final bData = b.data();
            final aUnread =
            (aData['unreadCountFor_$currentUserId'] ?? 0) as int;
            final bUnread =
            (bData['unreadCountFor_$currentUserId'] ?? 0) as int;

            if (aUnread != bUnread) {
              return bUnread.compareTo(aUnread);
            }

            final aTs =
                aData['updatedAt'] as Timestamp? ??
                    aData['lastInteractionAt'] as Timestamp?;
            final bTs =
                bData['updatedAt'] as Timestamp? ??
                    bData['lastInteractionAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kontakte',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Deine letzten Unterhaltungen auf einen Blick.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: List.generate(docs.length, (index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final participants = List<String>.from(
                    data['participants'] ?? const [],
                  );
                  final otherId = _otherParticipantId(participants, currentUserId);
                  final contactNames = Map<String, dynamic>.from(
                    data['contactNames'] ?? const {},
                  );
                  final contactPhones = Map<String, dynamic>.from(
                    data['contactPhones'] ?? const {},
                  );

                  final fallbackName =
                  (contactNames[otherId] ?? 'Unbekannt').toString().trim();
                  final fallbackPhone =
                  (contactPhones[otherId] ?? '').toString().trim();
                  final unreadCount =
                  (data['unreadCountFor_$currentUserId'] ?? 0) as int;
                  final hasUnread = unreadCount > 0;
                  final isFirst = index == 0;
                  final isLast = index == docs.length - 1;

                  return FutureBuilder<_ContactPreviewData>(
                    future: _loadContactPreview(
                      contactId: otherId,
                      fallbackName: fallbackName,
                      fallbackPhone: fallbackPhone,
                    ),
                    builder: (context, previewSnapshot) {
                      final preview =
                          previewSnapshot.data ??
                              _ContactPreviewData(
                                name: fallbackName.isEmpty ? 'Unbekannt' : fallbackName,
                                phone: fallbackPhone,
                                imageUrl: '',
                              );

                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream:
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(otherId)
                            .snapshots(),
                        builder: (context, presenceSnapshot) {
                          final isOnline = _isUserOnline(
                            presenceSnapshot.data?.data(),
                          );
                          final isTyping = _isOtherUserTyping(
                            data,
                            currentUserId,
                            otherId,
                          );
                          final previewText = _threadPreviewText(
                            data,
                            currentUserId: currentUserId,
                            otherParticipantId: otherId,
                            isOnline: isOnline,
                          );
                          final trailingTimeText = _formatThreadTime(data);

                          return Dismissible(
                            key: ValueKey(doc.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: colorScheme.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.only(
                                  topLeft: isFirst
                                      ? const Radius.circular(24)
                                      : Radius.zero,
                                  topRight: isFirst
                                      ? const Radius.circular(24)
                                      : Radius.zero,
                                  bottomLeft: isLast
                                      ? const Radius.circular(24)
                                      : Radius.zero,
                                  bottomRight: isLast
                                      ? const Radius.circular(24)
                                      : Radius.zero,
                                ),
                              ),
                              child: Icon(
                                Icons.delete_outline,
                                color: colorScheme.error,
                              ),
                            ),
                            confirmDismiss: (_) async {
                              await _hideThreadForCurrentUser(doc.id, currentUserId);
                              return true;
                            },
                            child: _buildThreadRow(
                              theme: theme,
                              colorScheme: colorScheme,
                              preview: preview,
                              hasUnread: hasUnread,
                              unreadCount: unreadCount,
                              isOnline: isOnline,
                              previewText: previewText,
                              trailingTimeText: trailingTimeText,
                              isTyping: isTyping,
                              showDivider: !isLast,
                              isFirst: isFirst,
                              isLast: isLast,
                              onTap: () {
                                _openContact(
                                  contactId: otherId,
                                  contactName: preview.name,
                                  phoneNumber: preview.phone,
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }


  String _formatInviteDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    final date = timestamp.toDate();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }

  Widget _buildEventInvitesSection(String currentUserId) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
      FirebaseFirestore.instance
          .collection('events')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final allDocs = [...snapshot.data?.docs ?? []];

        final pendingInvites = allDocs
            .where((doc) => _isPendingEventInvite(doc.data(), currentUserId))
            .toList()
          ..sort((a, b) {
            final aDate = a.data()['eventDate'] as Timestamp?;
            final bDate = b.data()['eventDate'] as Timestamp?;
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return aDate.compareTo(bDate);
          });

        final decisionUpdates = allDocs
            .where((doc) {
          final key = _joinDecisionKeyForRequester(
            doc.id,
            doc.data(),
            currentUserId,
          );
          return key != null && _pendingJoinDecisionKeys.contains(key);
        })
            .toList();

        final ownerResponseUpdates = <_OwnerEventUpdateItem>[];
        for (final doc in allDocs) {
          final ownerResponseStatuses = _ownerResponseStatusesForEvent(
            doc.id,
            doc.data(),
            currentUserId,
          );

          ownerResponseStatuses.forEach((baseKey, status) {
            final fullKey = _ownerResponseKey(baseKey, status);
            if (status != 'pending' &&
                _pendingOwnerResponseKeys.contains(fullKey)) {
              ownerResponseUpdates.add(
                _OwnerEventUpdateItem(
                  doc: doc,
                  notificationKey: fullKey,
                ),
              );
            }
          });
        }

        if (pendingInvites.isEmpty &&
            decisionUpdates.isEmpty &&
            ownerResponseUpdates.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Events',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Neue Einladungen, Antworten auf deine Anfragen und Reaktionen auf deine Events.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ...ownerResponseUpdates.take(3).map((item) {
              final data = item.doc.data();
              final title = (data['title'] ?? 'Event').toString().trim();
              final eventDate = data['eventDate'] as Timestamp?;
              final actorId = _ownerResponseUserIdFromKey(item.notificationKey);
              final status = _ownerResponseStatusFromKey(item.notificationKey);

              return FutureBuilder<String>(
                future: _loadUserDisplayName(actorId),
                builder: (context, snapshot) {
                  final actorName = snapshot.data ?? 'Jemand';
                  return _ActionCard(
                    icon: status == 'declined'
                        ? Icons.cancel_outlined
                        : status == 'maybe'
                        ? Icons.help_outline
                        : Icons.check_circle_outline,
                    title: title.isEmpty ? 'Event' : title,
                    subtitle:
                    '${_ownerResponseSubtitle(data: data, status: status, actorName: actorName)} - ${_formatInviteDate(eventDate)}.',
                    badgeCount: 1,
                    onTap: () {
                      setState(() {
                        _pendingOwnerResponseKeys.remove(item.notificationKey);
                      });
                      unawaited(_publishBadgeCount());
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EventDetailPage(
                            eventId: item.doc.id,
                            view: EventDetailView.myEvent,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            }),
            if (ownerResponseUpdates.isNotEmpty &&
                (decisionUpdates.isNotEmpty || pendingInvites.isNotEmpty))
              const SizedBox(height: 8),
            ...decisionUpdates.take(3).map((doc) {
              final data = doc.data();
              final title = (data['title'] ?? 'Event').toString().trim();
              final eventDate = data['eventDate'] as Timestamp?;
              final decisionKey = _joinDecisionKeyForRequester(
                doc.id,
                data,
                currentUserId,
              );
              final decisionLabel = _joinDecisionLabelFromKey(decisionKey ?? '');

              return _ActionCard(
                icon: decisionLabel == 'abgelehnt'
                    ? Icons.cancel_outlined
                    : Icons.check_circle_outline,
                title: title.isEmpty ? 'Event' : title,
                subtitle:
                'Deine Anfrage wurde $decisionLabel - ${_formatInviteDate(eventDate)}.',
                badgeCount: 1,
                onTap: () {
                  if (decisionKey != null) {
                    setState(() {
                      _pendingJoinDecisionKeys.remove(decisionKey);
                    });
                    unawaited(_publishBadgeCount());
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EventDetailPage(
                        eventId: doc.id,
                        view: EventDetailView.invitation,
                      ),
                    ),
                  );
                },
              );
            }),
            if (decisionUpdates.isNotEmpty && pendingInvites.isNotEmpty)
              const SizedBox(height: 8),
            ...pendingInvites.take(3).map((doc) {
              final data = doc.data();
              final title = (data['title'] ?? 'Event').toString().trim();
              final creator =
              (data['createdByName'] ?? 'Unbekannt').toString().trim();
              final eventDate = data['eventDate'] as Timestamp?;

              return _ActionCard(
                icon: Icons.mail_outline_rounded,
                title: title.isEmpty ? 'Event' : title,
                subtitle:
                'Von $creator - ${_formatInviteDate(eventDate)}. Tippe zum Antworten.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => EventDetailPage(
                        eventId: doc.id,
                        view: EventDetailView.invitation,
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildHomeTab(
      ColorScheme colorScheme,
      ThemeData theme,
      String? currentUserId,
      ) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _buildHeroSection(theme, colorScheme, currentUserId),
        _buildOnlineUsersSection(theme, colorScheme, currentUserId),
        const SizedBox(height: 16),
        _buildSearchPanel(theme, colorScheme),
        if (_searchQuery.isNotEmpty)
          _buildSearchResults()
        else
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentUserId != null) _buildThreadsSection(currentUserId),
                if (currentUserId != null)
                  _buildEventInvitesSection(currentUserId),
                if (currentUserId != null) ...[
                  const SizedBox(height: 20),
                  _buildFollowingActivitiesSection(
                    theme,
                    colorScheme,
                    currentUserId,
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  'Schnellaktionen',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Die wichtigsten Bereiche für deinen nächsten Schritt.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.celebration_outlined,
                  title: 'Events',
                  subtitle:
                  'Hier planst und verwaltest du später gemeinsame Aktivitäten, Einladungen und Anfragen.',
                  badgeCount: _eventActionBadgeCount(),
                  onTap: () {
                    _openEventsArea(pushRoute: true);
                  },
                ),
                _ActionCard(
                  icon: Icons.person_outline,
                  title: 'Mein Profil',
                  subtitle:
                  'Hier kannst du Name, Bild und weitere Angaben ergänzen.',
                  onTap: () {
                    setState(() {
                      _selectedIndex = 3;
                    });
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBody(
      ColorScheme colorScheme,
      ThemeData theme,
      String? currentUserId,
      ) {
    if (_selectedIndex == 1) {
      return const ChatPage();
    }

    if (_selectedIndex == 2) {
      return EventsPage(
        key: ValueKey('events-$_eventsPageOpenToken'),
        initialTabIndex: _eventsInitialTabIndex,
        highlightedEventId: _latestInvitedEventId,
      );
    }

    if (_selectedIndex == 3) {
      return const ProfilePage();
    }

    return _buildHomeTab(colorScheme, theme, currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: _selectedIndex == 1 ? null : const Text('CheckMyTime'),
        actions: [
          if (currentUserId != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUserId)
                  .snapshots(),
              builder: (context, userSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('notifications')
                      .where('toUserId', isEqualTo: currentUserId)
                      .limit(100)
                      .snapshots(),
                  builder: (context, notifSnapshot) {
                    final currentUserData =
                        userSnapshot.data?.data() ?? const <String, dynamic>{};
                    final dismissedNotificationKeys = Set<String>.from(
                      currentUserData['dismissedNotificationKeys'] ?? const <String>[],
                    );
                    final pendingFollowerIds = List<String>.from(
                      currentUserData['pendingFollowerIds'] ?? const [],
                    );

                    final unreadOtherNotifications = (notifSnapshot.data?.docs ?? const [])
                        .where((doc) {
                      final data = doc.data();
                      final isRead = data['read'] == true;
                      final type = (data['type'] ?? '').toString().trim();
                      final status =
                      (data['status'] ?? 'pending').toString().trim().toLowerCase();
                      final isPendingFollowRequest =
                          type == 'follow_request' && status == 'pending';
                      final isHandledByEventState =
                      _isBellCountHandledByEventState(type);
                      final isDismissed =
                      dismissedNotificationKeys.contains('notif:${doc.id}');
                      return !isRead &&
                          !isPendingFollowRequest &&
                          !isHandledByEventState &&
                          !isDismissed;
                    })
                        .length;

                    final visiblePendingFollowerCount = pendingFollowerIds.where((requesterId) {
                      return !dismissedNotificationKeys.contains('pending_follow:$requesterId');
                    }).length;

                    final count = unreadOtherNotifications +
                        visiblePendingFollowerCount +
                        _eventActionBadgeCount(
                          dismissedKeys: dismissedNotificationKeys,
                        );

                    return IconButton(
                      tooltip: 'Mitteilungen',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsPage(),
                          ),
                        );
                      },
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.notifications_none_rounded),
                          if (count > 0)
                            Positioned(
                              right: -6,
                              top: -6,
                              child: _ThreadUnreadBadge(count: count),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            )
          else
            IconButton(
              tooltip: 'Mitteilungen',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsPage(),
                  ),
                );
              },
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          IconButton(
            tooltip: 'Kontakte',
            onPressed:
                () => setState(() {
              _selectedIndex = 3;
            }),
            icon: const Icon(Icons.people_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocusNode.unfocus(),
          child: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, authSnapshot) {
              final currentUserId = authSnapshot.data?.uid;
              return _buildBody(colorScheme, theme, currentUserId);
            },
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index == 2) {
            _openEventsArea(pushRoute: false);
            return;
          }

          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: _buildNavigationIcon(
              Icons.calendar_month_outlined,
              _eventActionBadgeCount(),
            ),
            selectedIcon: _buildNavigationIcon(
              Icons.calendar_month,
              _eventActionBadgeCount(),
            ),
            label: 'Events',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

class _OwnerEventUpdateItem {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String notificationKey;

  const _OwnerEventUpdateItem({
    required this.doc,
    required this.notificationKey,
  });
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badgeCount;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedAccent = colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: resolvedAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: resolvedAccent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (badgeCount > 0) _NewItemsBadge(count: badgeCount),
                    if (badgeCount > 0) const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewItemsBadge extends StatelessWidget {
  final int count;

  const _NewItemsBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFB7E61E),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count == 1 ? '1 neu' : '$count neu',
        style: theme.textTheme.labelMedium?.copyWith(
          color: Colors.black,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}


class _ThreadUnreadBadge extends StatelessWidget {
  final int count;

  const _ThreadUnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const BoxDecoration(
        color: Color(0xFFB7E61E),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.black,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _HeroStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _HeroStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactPreviewData {
  final String name;
  final String phone;
  final String imageUrl;

  const _ContactPreviewData({
    required this.name,
    required this.phone,
    required this.imageUrl,
  });
}
