import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';
import 'package:termini/checkmytime/pages/event_detail_page.dart';
import 'package:termini/checkmytime/pages/profile_page.dart';
import 'package:termini/checkmytime/pages/chat_page.dart';
import 'package:termini/checkmytime/pages/user_page.dart';
import 'package:termini/checkmytime/services/notification_service.dart';
import 'package:termini/checkmytime/pages/events_page.dart';
import 'package:termini/checkmytime/pages/notifications_page.dart';

// =====================================================================
//  DESIGN TOKENS — Dark Neon
// =====================================================================
class _Neon {
  static const bg = Color(0xFF0A0A0F);
  static const bgElevated = Color(0xFF15151C);
  static const surface = Color(0xFF1E1E28);
  static const surfaceHigh = Color(0xFF262633);
  static const stroke = Color(0xFF2E2E3D);
  static const strokeStrong = Color(0xFF3A3A4D);

  static const textPrimary = Color(0xFFF5F5FA);
  static const textSecondary = Color(0xFFA0A0B8);
  static const textMuted = Color(0xFF6B6B80);

  static const cyan = Color(0xFF00E5FF);
  static const pink = Color(0xFFFF2E93);
  static const lime = Color(0xFFC6FF4A);
  static const purple = Color(0xFF8B5CF6);

  static const online = Color(0xFF00FFA3);
  static const danger = Color(0xFFFF3B6B);

  static List<BoxShadow> glow(Color c, {double blur = 18, double alpha = 0.45}) => [
    BoxShadow(
      color: c.withValues(alpha: alpha),
      blurRadius: blur,
      spreadRadius: 0,
    ),
  ];
}

class CheckMyTimeHomePage extends StatefulWidget {
  const CheckMyTimeHomePage({super.key});

  @override
  State<CheckMyTimeHomePage> createState() => _CheckMyTimeHomePageState();
}

class _CheckMyTimeHomePageState extends State<CheckMyTimeHomePage>
    with WidgetsBindingObserver {
  static const Duration _onlineGracePeriod = Duration(minutes: 3);
  int _selectedIndex = 0;
  late ThemeData _darkTheme;
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
  Timer? _searchDebounce;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _darkTheme = _buildDarkTheme();
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
    _searchDebounce?.cancel();
    unawaited(_setCurrentUserPresence(isOnline: false));
    _threadsSubscription?.cancel();
    _eventsSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _setSelectedIndex(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
    });
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

  String _ownerResponseKey(String baseKey, String status) => '$baseKey:$status';

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
      _showSnack('Aktivität entfernt.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dismissedActivityIds.remove(activityId);
      });
      _showSnack('Aktivität konnte nicht entfernt werden.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _Neon.textPrimary)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _Neon.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _Neon.strokeStrong),
        ),
      ),
    );
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

    _setSelectedIndex(2);
  }

  void _listenForIncomingEventInvites() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    _eventsSubscription?.cancel();
    _eventsSubscription = FirebaseFirestore.instance
        .collection('events')
        .where('memberIds', arrayContains: currentUserId)
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
    final normalizedContactId = contactId.trim();

    if (normalizedContactId.isEmpty) {
      return _ContactPreviewData(
        name: fallbackName.trim().isEmpty ? 'Unbekannt' : fallbackName.trim(),
        phone: fallbackPhone.trim(),
        imageUrl: '',
      );
    }

    if (_contactPreviewCache.containsKey(normalizedContactId)) {
      return _contactPreviewCache[normalizedContactId]!;
    }

    var resolvedName = fallbackName.trim();
    var resolvedPhone = fallbackPhone.trim();
    var resolvedImageUrl = '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(normalizedContactId)
          .get();
      final data = doc.data();

      if (data != null) {
        final firestoreName =
        (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final firestorePhone = (data['phoneNumber'] ?? '').toString().trim();
        final firestoreImageUrl =
        (data['profileImageUrl'] ?? '').toString().trim();

        if (firestoreName.isNotEmpty) resolvedName = firestoreName;
        if (firestorePhone.isNotEmpty) resolvedPhone = firestorePhone;
        if (firestoreImageUrl.isNotEmpty) resolvedImageUrl = firestoreImageUrl;
      }
    } catch (_) {}

    if (resolvedName.isEmpty) resolvedName = 'Unbekannt';

    final preview = _ContactPreviewData(
      name: resolvedName,
      phone: resolvedPhone,
      imageUrl: resolvedImageUrl,
    );
    _contactPreviewCache[normalizedContactId] = preview;
    return preview;
  }

  bool _isOtherUserTyping(
      Map<String, dynamic> data,
      String currentUserId,
      String otherParticipantId,
      ) {
    final typingTimestamp = data['typingAt'] as Timestamp? ??
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
    return value.toString().trim();
  }

  String _threadPreviewText(
      Map<String, dynamic> data, {
        required bool isTyping,
        required bool isOnline,
      }) {
    if (isTyping) return 'Schreibt gerade…';

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
    final timestamp = data['updatedAt'] as Timestamp? ??
        data['lastInteractionAt'] as Timestamp?;
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) return 'Jetzt';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24) return '${difference.inHours}h';

    final today = DateTime(now.year, now.month, now.day);
    final otherDay = DateTime(date.year, date.month, date.day);
    final dayDifference = today.difference(otherDay).inDays;

    if (dayDifference == 1) return 'Gestern';
    if (dayDifference < 7) {
      const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
      return weekdays[date.weekday - 1];
    }

    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }

  // =====================================================================
  //  AVATARS
  // =====================================================================

  Widget _buildContactAvatar({
    required _ContactPreviewData preview,
    required ThemeData theme,
    bool isOnline = false,
    double size = 48,
  }) {
    final letter = preview.name.isNotEmpty
        ? preview.name.characters.first.toUpperCase()
        : '?';

    final ring = isOnline
        ? Border.all(color: _Neon.online, width: 2)
        : Border.all(color: _Neon.stroke, width: 1);

    if (preview.imageUrl.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: ring,
          boxShadow: isOnline ? _Neon.glow(_Neon.online, blur: 12, alpha: 0.5) : null,
        ),
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: Image.network(
            preview.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _avatarFallback(letter, size),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring,
        gradient: const LinearGradient(
          colors: [_Neon.cyan, _Neon.purple, _Neon.pink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: isOnline
            ? _Neon.glow(_Neon.online, blur: 12, alpha: 0.5)
            : _Neon.glow(_Neon.purple, blur: 10, alpha: 0.25),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _avatarFallback(String letter, double size) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [_Neon.cyan, _Neon.pink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
        ),
      ),
    );
  }

  Widget _buildPresenceAvatar({
    required _ContactPreviewData preview,
    required ThemeData theme,
    required bool isOnline,
    double size = 48,
  }) {
    final avatar = _buildContactAvatar(
      preview: preview,
      theme: theme,
      isOnline: isOnline,
      size: size,
    );
    if (!isOnline) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _Neon.online,
              border: Border.all(color: _Neon.bg, width: 2),
              boxShadow: _Neon.glow(_Neon.online, blur: 8, alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }

  // =====================================================================
  //  SEARCH
  // =====================================================================

  void _resetSearch() {
    _searchDebounce?.cancel();
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

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

    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_searchUsers(query));
    });
  }

  Future<void> _searchUsers(String value) async {
    final query = value.trim();
    final requestId = ++_searchRequestId;

    if (query.isEmpty || query.length < 2) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .limit(30)
          .get();

      final lowerQuery = query.toLowerCase();

      final filtered = snapshot.docs.where((doc) {
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

      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _searchResults = filtered;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _searchError = 'Fehler bei der Suche.';
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) return const SizedBox.shrink();

    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(
          child: CircularProgressIndicator(
            color: _Neon.cyan,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Center(
          child: Text(
            _searchError!,
            style: const TextStyle(color: _Neon.danger),
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(
          child: Text(
            'Keine Person gefunden.',
            style: TextStyle(color: _Neon.textSecondary),
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('ERGEBNISSE', accent: _Neon.cyan),
          const SizedBox(height: 12),
          ..._searchResults.map((doc) {
            final data = doc.data();
            final fallbackName =
            (data['displayName'] ?? data['name'] ?? 'Unbekannt')
                .toString()
                .trim();
            final fallbackPhone = (data['phoneNumber'] ?? '').toString().trim();
            final isProfilePublic = data['isProfilePublic'] as bool? ?? true;
            final preview = _ContactPreviewData(
              name: fallbackName.isEmpty ? 'Unbekannt' : fallbackName,
              phone: fallbackPhone,
              imageUrl: (data['profileImageUrl'] ?? '').toString().trim(),
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RepaintBoundary(
                child: _GlassCard(
                  onTap: () => _openContact(
                    contactId: doc.id,
                    contactName: preview.name,
                    phoneNumber: preview.phone,
                  ),
                  padding: const EdgeInsets.all(14),
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
                              style: const TextStyle(
                                color: _Neon.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              preview.phone.isNotEmpty
                                  ? preview.phone
                                  : 'Keine Nummer',
                              style: const TextStyle(
                                color: _Neon.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _NeonPill(
                              text: isProfilePublic ? 'Öffentlich' : 'Privat',
                              color: isProfilePublic ? _Neon.lime : _Neon.pink,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: _Neon.cyan,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
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

  // =====================================================================
  //  HERO
  // =====================================================================

  Widget _buildHeroSection(String? currentUserId) {
    final unreadTotal = _totalUnreadMessages();
    final activeThreads = _knownUnreadCountsByThread.length;
    final authDisplayName = FirebaseAuth.instance.currentUser?.displayName;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _Neon.strokeStrong),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _Neon.bgElevated,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF11141D),
                      Color(0xFF161926),
                      Color(0xFF0F1118),
                    ],
                  ),
                ),
                child: IgnorePointer(
                  child: Stack(
                    children: const [
                      Positioned(
                        left: -40,
                        top: -20,
                        child: _StaticGlowOrb(
                          size: 180,
                          color: _Neon.cyan,
                          opacity: 0.14,
                        ),
                      ),
                      Positioned(
                        right: -50,
                        bottom: -30,
                        child: _StaticGlowOrb(
                          size: 200,
                          color: _Neon.pink,
                          opacity: 0.10,
                        ),
                      ),
                      Positioned(
                        right: 60,
                        top: 40,
                        child: _StaticGlowOrb(
                          size: 120,
                          color: _Neon.purple,
                          opacity: 0.08,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: currentUserId == null
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
                        firestoreName.isNotEmpty
                            ? firestoreName
                            : authDisplayName,
                      );

                      return Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _Neon.cyan,
                              boxShadow: _Neon.glow(_Neon.cyan,
                                  blur: 10, alpha: 0.9),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              greetingText.toUpperCase(),
                              style: const TextStyle(
                                color: _Neon.textSecondary,
                                fontSize: 11,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [_Neon.cyan, _Neon.pink],
                    ).createShader(bounds),
                    child: const Text(
                      'CheckMyTime',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        height: 1.05,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Deine Kontakte. Deine Events. In Echtzeit.',
                    style: TextStyle(
                      color: _Neon.textSecondary,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStatCard(
                          label: 'Ungelesen',
                          value: '$unreadTotal',
                          icon: Icons.bolt_rounded,
                          accent: _Neon.cyan,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _HeroStatCard(
                          label: 'Threads',
                          value: '$activeThreads',
                          icon: Icons.forum_rounded,
                          accent: _Neon.pink,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  //  SEARCH PANEL
  // =====================================================================

  Widget _buildSearchPanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([_searchController, _searchFocusNode]),
      builder: (context, _) {
        final hasFocus = _searchFocusNode.hasFocus;
        final hasText = _searchController.text.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: _Neon.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasFocus ? _Neon.cyan : _Neon.stroke,
              width: 1.2,
            ),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: _Neon.textPrimary, fontSize: 15),
            cursorColor: _Neon.cyan,
            decoration: InputDecoration(
              hintText: 'Personen suchen…',
              hintStyle: const TextStyle(color: _Neon.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, color: _Neon.textSecondary),
              suffixIcon: hasText
                  ? IconButton(
                onPressed: _resetSearch,
                icon: const Icon(
                  Icons.close_rounded,
                  color: _Neon.textSecondary,
                ),
              )
                  : null,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        );
      },
    );
  }

  // =====================================================================
  //  ONLINE USERS (horizontal stories-style)
  // =====================================================================

  Widget _buildOnlineUsersSection(String? currentUserId) {
    if (currentUserId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('isOnline', isEqualTo: true)
          .limit(12)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final onlineUsers = snapshot.data!.docs.where((doc) {
          if (doc.id == currentUserId) return false;
          return _isUserOnline(doc.data());
        }).toList()
          ..sort((a, b) {
            final aName = (a.data()['displayName'] ?? a.data()['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final bName = (b.data()['displayName'] ?? b.data()['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            return aName.compareTo(bName);
          });

        if (onlineUsers.isEmpty) return const SizedBox.shrink();

        final visibleUsers = onlineUsers.take(10).toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 12),
                child: Row(
                  children: [
                    _sectionLabel('JETZT ONLINE', accent: _Neon.online),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _Neon.online.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${visibleUsers.length}',
                        style: const TextStyle(
                          color: _Neon.online,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: visibleUsers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
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
                      imageUrl:
                      (data['profileImageUrl'] ?? '').toString().trim(),
                    );

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _openContact(
                          contactId: doc.id,
                          contactName: preview.name,
                          phoneNumber: preview.phone,
                        );
                      },
                      child: SizedBox(
                        width: 64,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            _buildPresenceAvatar(
                              preview: preview,
                              theme: Theme.of(context),
                              isOnline: true,
                              size: 56,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              preview.name.split(' ').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _Neon.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =====================================================================
  //  FOLLOWING ACTIVITIES
  // =====================================================================

  Widget _buildFollowingActivitiesSection(String? currentUserId) {
    if (currentUserId == null) return const SizedBox.shrink();

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
          ...List<String>.from(
              userData['dismissedActivityIds'] ?? const <String>[]),
          ..._dismissedActivityIds,
        };

        if (followingIds.isEmpty) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('activities')
              .orderBy('createdAt', descending: true)
              .limit(40)
              .snapshots(),
          builder: (context, activitySnapshot) {
            if (!activitySnapshot.hasData) return const SizedBox.shrink();

            final docs = activitySnapshot.data!.docs.where((doc) {
              final data = doc.data();
              final actorUserId = (data['actorUserId'] ?? '').toString().trim();
              return actorUserId.isNotEmpty &&
                  actorUserId != currentUserId &&
                  followingIds.contains(actorUserId) &&
                  !dismissedActivityIds.contains(doc.id);
            }).take(10).toList();

            if (docs.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('AKTIVITÄT', accent: _Neon.purple),
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
                    switch (type) {
                      case 'profile_updated':
                        title = '$actorName hat das Profil aktualisiert';
                        break;
                      case 'event_created':
                      default:
                        title = '$actorName hat „$eventTitle" erstellt';
                        break;
                    }

                    final preview = _ContactPreviewData(
                      name: actorName.isEmpty ? 'Jemand' : actorName,
                      phone: '',
                      imageUrl: actorImageUrl,
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Dismissible(
                        key: ValueKey('activity_${doc.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: _Neon.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: _Neon.danger.withValues(alpha: 0.4)),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: _Neon.danger,
                          ),
                        ),
                        onDismissed: (_) => _dismissActivityForCurrentUser(
                            currentUserId, doc.id),
                        child: _GlassCard(
                          padding: const EdgeInsets.all(14),
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
                          child: Row(
                            children: [
                              _buildContactAvatar(
                                preview: preview,
                                theme: Theme.of(context),
                                size: 42,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        color: _Neon.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        height: 1.3,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _relativeTime(createdAt),
                                      style: const TextStyle(
                                        color: _Neon.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // =====================================================================
  //  THREADS
  // =====================================================================

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
      _showSnack('Kontakt von Startseite entfernt.');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Konnte nicht entfernt werden.');
    }
  }

  Widget _buildThreadsSection(String currentUserId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('contact_threads')
          .where('participantMap.$currentUserId', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: CircularProgressIndicator(
                color: _Neon.cyan,
                strokeWidth: 2,
              ),
            ),
          );
        }

        final docs = [...snapshot.data?.docs ?? []]
            .where((doc) => doc.data()['hiddenFor_$currentUserId'] != true)
            .where((doc) {
          final participants = List<String>.from(
            doc.data()['participants'] ?? const [],
          );
          return _otherParticipantId(participants, currentUserId).isNotEmpty;
        }).toList()
          ..sort((a, b) {
            final aData = a.data();
            final bData = b.data();
            final aUnread =
            (aData['unreadCountFor_$currentUserId'] ?? 0) as int;
            final bUnread =
            (bData['unreadCountFor_$currentUserId'] ?? 0) as int;

            if (aUnread != bUnread) return bUnread.compareTo(aUnread);

            final aTs = aData['updatedAt'] as Timestamp? ??
                aData['lastInteractionAt'] as Timestamp?;
            final bTs = bData['updatedAt'] as Timestamp? ??
                bData['lastInteractionAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

        if (docs.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('KONTAKTE', accent: _Neon.cyan),
              const SizedBox(height: 12),
              ...List.generate(docs.length, (index) {
                final doc = docs[index];
                final data = doc.data();
                final participants = List<String>.from(
                  data['participants'] ?? const [],
                );
                final otherId =
                _otherParticipantId(participants, currentUserId);
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

                return FutureBuilder<_ContactPreviewData>(
                  future: _loadContactPreview(
                    contactId: otherId,
                    fallbackName: fallbackName,
                    fallbackPhone: fallbackPhone,
                  ),
                  builder: (context, previewSnapshot) {
                    final preview = previewSnapshot.data ??
                        _ContactPreviewData(
                          name: fallbackName.isEmpty
                              ? 'Unbekannt'
                              : fallbackName,
                          phone: fallbackPhone,
                          imageUrl: '',
                        );

                    return StreamBuilder<
                        DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
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
                          isTyping: isTyping,
                          isOnline: isOnline,
                        );
                        final trailingTimeText = _formatThreadTime(data);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Dismissible(
                            key: ValueKey(doc.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: _Neon.danger.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color:
                                    _Neon.danger.withValues(alpha: 0.4)),
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                color: _Neon.danger,
                              ),
                            ),
                            confirmDismiss: (_) async {
                              await _hideThreadForCurrentUser(
                                  doc.id, currentUserId);
                              return true;
                            },
                            child: _ThreadTile(
                              avatar: _buildPresenceAvatar(
                                preview: preview,
                                theme: Theme.of(context),
                                isOnline: isOnline,
                                size: 52,
                              ),
                              name: preview.name,
                              previewText: previewText,
                              trailingTime: trailingTimeText,
                              hasUnread: hasUnread,
                              unreadCount: unreadCount,
                              isTyping: isTyping,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                _openContact(
                                  contactId: otherId,
                                  contactName: preview.name,
                                  phoneNumber: preview.phone,
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // =====================================================================
  //  EVENT INVITES
  // =====================================================================

  String _formatInviteDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    final date = timestamp.toDate();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }

  Widget _buildEventInvitesSection(String currentUserId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('memberIds', arrayContains: currentUserId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
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

        final decisionUpdates = allDocs.where((doc) {
          final key = _joinDecisionKeyForRequester(
            doc.id,
            doc.data(),
            currentUserId,
          );
          return key != null && _pendingJoinDecisionKeys.contains(key);
        }).toList();

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

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('EVENTS', accent: _Neon.pink),
              const SizedBox(height: 12),
              ...ownerResponseUpdates.take(3).map((item) {
                final data = item.doc.data();
                final title = (data['title'] ?? 'Event').toString().trim();
                final eventDate = data['eventDate'] as Timestamp?;
                final actorId =
                _ownerResponseUserIdFromKey(item.notificationKey);
                final status =
                _ownerResponseStatusFromKey(item.notificationKey);

                return FutureBuilder<String>(
                  future: _loadUserDisplayName(actorId),
                  builder: (context, snap) {
                    final actorName = snap.data ?? 'Jemand';
                    final accent = status == 'declined'
                        ? _Neon.danger
                        : status == 'maybe'
                        ? _Neon.lime
                        : _Neon.online;
                    return _ActionCard(
                      icon: status == 'declined'
                          ? Icons.close_rounded
                          : status == 'maybe'
                          ? Icons.help_outline_rounded
                          : Icons.check_rounded,
                      accent: accent,
                      title: title.isEmpty ? 'Event' : title,
                      subtitle:
                      '${_ownerResponseSubtitle(data: data, status: status, actorName: actorName)} · ${_formatInviteDate(eventDate)}',
                      badgeCount: 1,
                      onTap: () {
                        setState(() {
                          _pendingOwnerResponseKeys
                              .remove(item.notificationKey);
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
              ...decisionUpdates.take(3).map((doc) {
                final data = doc.data();
                final title = (data['title'] ?? 'Event').toString().trim();
                final eventDate = data['eventDate'] as Timestamp?;
                final decisionKey = _joinDecisionKeyForRequester(
                  doc.id,
                  data,
                  currentUserId,
                );
                final decisionLabel =
                _joinDecisionLabelFromKey(decisionKey ?? '');
                final accent = decisionLabel == 'abgelehnt'
                    ? _Neon.danger
                    : _Neon.online;

                return _ActionCard(
                  icon: decisionLabel == 'abgelehnt'
                      ? Icons.close_rounded
                      : Icons.check_rounded,
                  accent: accent,
                  title: title.isEmpty ? 'Event' : title,
                  subtitle:
                  'Deine Anfrage wurde $decisionLabel · ${_formatInviteDate(eventDate)}',
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
              ...pendingInvites.take(3).map((doc) {
                final data = doc.data();
                final title = (data['title'] ?? 'Event').toString().trim();
                final creator =
                (data['createdByName'] ?? 'Unbekannt').toString().trim();
                final eventDate = data['eventDate'] as Timestamp?;

                return _ActionCard(
                  icon: Icons.mail_rounded,
                  accent: _Neon.pink,
                  title: title.isEmpty ? 'Event' : title,
                  subtitle:
                  'Von $creator · ${_formatInviteDate(eventDate)} · Zum Antworten tippen',
                  onTap: () {
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
            ],
          ),
        );
      },
    );
  }

  // =====================================================================
  //  SECTION LABEL
  // =====================================================================

  Widget _sectionLabel(String text, {required Color accent}) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
            boxShadow: _Neon.glow(accent, blur: 8, alpha: 0.7),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
      ],
    );
  }

  // =====================================================================
  //  HOME TAB
  // =====================================================================

  Widget _buildHomeTab(String? currentUserId, int eventBadge) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1200,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        _buildHeroSection(currentUserId),
        _buildSearchPanel(),
        if (_searchQuery.isNotEmpty)
          _buildSearchResults()
        else ...[
          const SizedBox(height: 24),
          _buildOnlineUsersSection(currentUserId),
          if (currentUserId != null) _buildThreadsSection(currentUserId),
          if (currentUserId != null) _buildEventInvitesSection(currentUserId),
          if (currentUserId != null) _buildFollowingActivitiesSection(currentUserId),
          _sectionLabel('SCHNELLZUGRIFF', accent: _Neon.lime),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.event_rounded,
            accent: _Neon.pink,
            title: 'Events',
            subtitle:
            'Gemeinsame Aktivitäten planen, Einladungen und Anfragen verwalten.',
            badgeCount: eventBadge,
            onTap: () => _openEventsArea(pushRoute: true),
          ),
          _ActionCard(
            icon: Icons.person_rounded,
            accent: _Neon.cyan,
            title: 'Mein Profil',
            subtitle: 'Name, Bild und weitere Angaben bearbeiten.',
            onTap: () => _setSelectedIndex(3),
          ),
        ],
      ],
    );
  }

  // =====================================================================
  //  BODY ROUTING
  // =====================================================================

  Widget _buildBody(String? currentUserId, int eventBadge) {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        _buildHomeTab(currentUserId, eventBadge),
        const ChatPage(),
        EventsPage(
          key: ValueKey('events-$_eventsPageOpenToken'),
          initialTabIndex: _eventsInitialTabIndex,
          highlightedEventId: _latestInvitedEventId,
        ),
        const ProfilePage(),
      ],
    );
  }

  // =====================================================================
  //  BUILD
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final eventBadge = _eventActionBadgeCount();

    return Theme(
      data: _darkTheme,
      child: Scaffold(
        backgroundColor: _Neon.bg,
        extendBody: true,
        appBar: _selectedIndex == 0
            ? _buildAppBar(currentUserId)
            : _buildSecondaryAppBar(currentUserId),
        body: SafeArea(
          bottom: false,
          child: GestureDetector(
            onTap: () => _searchFocusNode.unfocus(),
            child: _buildBody(currentUserId, eventBadge),
          ),
        ),
        bottomNavigationBar: _buildNeonNavBar(eventBadge),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String? currentUserId) {
    return AppBar(
      backgroundColor: _Neon.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      toolbarHeight: 56,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [_Neon.cyan, _Neon.pink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: _Neon.glow(_Neon.cyan, blur: 14, alpha: 0.45),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'CheckMyTime',
            style: TextStyle(
              color: _Neon.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      actions: [
        _buildNotificationButton(currentUserId),
        const SizedBox(width: 4),
        _IconTile(
          icon: Icons.people_outline_rounded,
          onTap: () => _setSelectedIndex(3),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  PreferredSizeWidget _buildSecondaryAppBar(String? currentUserId) {
    if (_selectedIndex == 1) {
      return PreferredSize(
        preferredSize: const Size.fromHeight(0),
        child: Container(color: _Neon.bg),
      );
    }

    return AppBar(
      backgroundColor: _Neon.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      toolbarHeight: 56,
      title: Text(
        _selectedIndex == 2 ? 'Events' : 'Profil',
        style: const TextStyle(
          color: _Neon.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      actions: [
        _buildNotificationButton(currentUserId),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildNotificationButton(String? currentUserId) {
    if (currentUserId == null) {
      return _IconTile(
        icon: Icons.notifications_none_rounded,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const NotificationsPage(),
            ),
          );
        },
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
              currentUserData['dismissedNotificationKeys'] ??
                  const <String>[],
            );
            final pendingFollowerIds = List<String>.from(
              currentUserData['pendingFollowerIds'] ?? const [],
            );

            final unreadOtherNotifications =
                (notifSnapshot.data?.docs ?? const []).where((doc) {
                  final data = doc.data();
                  final isRead = data['read'] == true;
                  final type = (data['type'] ?? '').toString().trim();
                  final status = (data['status'] ?? 'pending')
                      .toString()
                      .trim()
                      .toLowerCase();
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
                }).length;

            final visiblePendingFollowerCount =
                pendingFollowerIds.where((requesterId) {
                  return !dismissedNotificationKeys
                      .contains('pending_follow:$requesterId');
                }).length;

            final count = unreadOtherNotifications +
                visiblePendingFollowerCount +
                _eventActionBadgeCount(
                  dismissedKeys: dismissedNotificationKeys,
                );

            return _IconTile(
              icon: Icons.notifications_none_rounded,
              badgeCount: count,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsPage(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // =====================================================================
  //  FLOATING NEON NAV BAR
  // =====================================================================

  Widget _buildNeonNavBar(int eventBadges) {

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: _Neon.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _Neon.strokeStrong, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: _Neon.cyan.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: _selectedIndex == 0,
                accent: _Neon.cyan,
                onTap: () => _setSelectedIndex(0),
              ),
              _NavItem(
                icon: Icons.chat_bubble_rounded,
                label: 'Chat',
                selected: _selectedIndex == 1,
                accent: _Neon.cyan,
                onTap: () => _setSelectedIndex(1),
              ),
              _NavItem(
                icon: Icons.event_rounded,
                label: 'Events',
                selected: _selectedIndex == 2,
                accent: _Neon.pink,
                badgeCount: eventBadges,
                onTap: () => _openEventsArea(pushRoute: false),
              ),
              _NavItem(
                icon: Icons.person_rounded,
                label: 'Profil',
                selected: _selectedIndex == 3,
                accent: _Neon.cyan,
                onTap: () => _setSelectedIndex(3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================================
  //  THEME
  // =====================================================================

  ThemeData _buildDarkTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: _Neon.bg,
      colorScheme: const ColorScheme.dark(
        primary: _Neon.cyan,
        onPrimary: Colors.black,
        secondary: _Neon.pink,
        surface: _Neon.surface,
        onSurface: _Neon.textPrimary,
        error: _Neon.danger,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: _Neon.textPrimary,
        displayColor: _Neon.textPrimary,
      ),
      splashColor: _Neon.cyan.withValues(alpha: 0.08),
      highlightColor: _Neon.cyan.withValues(alpha: 0.04),
    );
  }
}

// =====================================================================
//  SHARED COMPONENTS
// =====================================================================

class _OwnerEventUpdateItem {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String notificationKey;

  const _OwnerEventUpdateItem({
    required this.doc,
    required this.notificationKey,
  });
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

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const _GlassCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: _Neon.cyan.withValues(alpha: 0.08),
        highlightColor: _Neon.cyan.withValues(alpha: 0.04),
        child: Ink(
          decoration: BoxDecoration(
            color: _Neon.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor ?? _Neon.stroke,
              width: 1,
            ),
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badgeCount;
  final Color accent;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeCount = 0,
    this.accent = _Neon.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        borderColor: badgeCount > 0
            ? accent.withValues(alpha: 0.45)
            : _Neon.stroke,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
                boxShadow: badgeCount > 0
                    ? _Neon.glow(accent, blur: 16, alpha: 0.35)
                    : null,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _Neon.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _Neon.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (badgeCount > 0)
                  _NeonBadge(count: badgeCount, color: accent)
                else
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: _Neon.textMuted,
                    size: 18,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final Widget avatar;
  final String name;
  final String previewText;
  final String trailingTime;
  final bool hasUnread;
  final int unreadCount;
  final bool isTyping;
  final VoidCallback onTap;

  const _ThreadTile({
    required this.avatar,
    required this.name,
    required this.previewText,
    required this.trailingTime,
    required this.hasUnread,
    required this.unreadCount,
    required this.isTyping,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderColor:
        hasUnread ? _Neon.cyan.withValues(alpha: 0.4) : _Neon.stroke,
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _Neon.textPrimary,
                            fontWeight:
                            hasUnread ? FontWeight.w800 : FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (trailingTime.isNotEmpty)
                        Text(
                          trailingTime,
                          style: TextStyle(
                            color: hasUnread ? _Neon.cyan : _Neon.textMuted,
                            fontWeight:
                            hasUnread ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          previewText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isTyping
                                ? _Neon.cyan
                                : hasUnread
                                ? _Neon.textPrimary
                                : _Neon.textSecondary,
                            fontStyle:
                            isTyping ? FontStyle.italic : FontStyle.normal,
                            fontWeight: isTyping || hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 10),
                        _NeonBadge(count: unreadCount, color: _Neon.cyan),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeonBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _NeonBadge({required this.count, this.color = _Neon.cyan});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: _Neon.glow(color, blur: 10, alpha: 0.6),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _NeonPill extends StatelessWidget {
  final String text;
  final Color color;

  const _NeonPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _HeroStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _HeroStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: _Neon.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: _Neon.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  const _IconTile({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _Neon.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _Neon.stroke),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(icon, color: _Neon.textPrimary, size: 20),
                if (badgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: _NeonBadge(count: badgeCount, color: _Neon.pink),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final int badgeCount;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: selected
                  ? Border.all(color: accent.withValues(alpha: 0.45))
                  : null,
              boxShadow: selected
                  ? _Neon.glow(accent, blur: 14, alpha: 0.35)
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: selected ? accent : _Neon.textMuted,
                      size: 22,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? accent : _Neon.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: 6,
                    right: 10,
                    child: _NeonBadge(count: badgeCount, color: accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
//  STATIC HERO BACKGROUND
// =====================================================================

class _StaticGlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _StaticGlowOrb({
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
