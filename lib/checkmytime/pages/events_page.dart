import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/pages/create_event_page.dart';
import 'package:termini/checkmytime/pages/event_detail_page.dart';

class EventsPage extends StatefulWidget {
  final int initialTabIndex;
  final String? highlightedEventId;

  const EventsPage({
    super.key,
    this.initialTabIndex = 0,
    this.highlightedEventId,
  });

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  String _selectedKindFilter = 'all';
  String _selectedDateFilter = 'all';
  String _selectedRadiusFilter = 'all';
  String _selectedOpenEventsSort = 'distance_date';
  String _selectedOpenQuickFilter = 'all';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream;
  Position? _userPosition;
  bool _isLoadingUserLocation = false;
  bool _didAutoJumpToMyEvents = false;

  String? _highlightedEventId;
  final GlobalKey _highlightedCardKey = GlobalKey();
  bool _needsScrollToHighlight = false;


  @override
  void initState() {
    super.initState();
    _highlightedEventId = widget.highlightedEventId;
    _needsScrollToHighlight = widget.highlightedEventId != null;

    final initialTab = widget.highlightedEventId != null
        ? 1
        : widget.initialTabIndex.clamp(0, 2);
    _tabController = TabController(length: 3, vsync: this, initialIndex: initialTab);

    if (_highlightedEventId != null) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _highlightedEventId = null);
      });
    }
    _tabController.addListener(_onTabChanged);
    _eventsStream = FirebaseFirestore.instance
        .collection('events')
        .orderBy('createdAt', descending: true)
        .snapshots();
    _searchController.addListener(_onSearchChanged);
    _loadUserLocation();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && mounted) {
      setState(() {});
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Timestamp? _scheduledTimestamp(Map<String, dynamic> data) {
    return data['scheduledAt'] as Timestamp? ?? data['eventDate'] as Timestamp?;
  }

  double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double? _distanceInMeters(Map<String, dynamic> data) {
    final userPosition = _userPosition;
    if (userPosition == null) return null;

    final lat = _parseDouble(data['exactLocationLat']);
    final lng = _parseDouble(data['exactLocationLng']);
    if (lat == null || lng == null) return null;

    final distanceInMeters = Geolocator.distanceBetween(
      userPosition.latitude,
      userPosition.longitude,
      lat,
      lng,
    );

    if (distanceInMeters.isNaN || distanceInMeters.isInfinite) return null;
    return distanceInMeters;
  }

  Future<void> _loadUserLocation() async {
    if (_isLoadingUserLocation) return;
    _isLoadingUserLocation = true;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );

      if (!mounted) return;
      setState(() => _userPosition = position);
    } catch (_) {
      // Falls Standort nicht verfügbar ist, zeigen wir die Entfernung einfach nicht an.
    } finally {
      _isLoadingUserLocation = false;
    }
  }

  String _formatHeaderDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    return DateFormat('EEEE, d. MMMM', 'de_DE').format(timestamp.toDate());
  }

  String _formatShortDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    return DateFormat('dd.MM.yyyy', 'de_DE').format(timestamp.toDate());
  }

  DateTime? _normalizedDayFromTimestamp(Timestamp? timestamp) {
    final date = timestamp?.toDate();
    if (date == null) return null;
    return DateTime(date.year, date.month, date.day);
  }

  String _groupHeaderLabel(Timestamp? timestamp) {
    final normalizedDay = _normalizedDayFromTimestamp(timestamp);
    if (normalizedDay == null) return 'Kein Datum';
    return DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(normalizedDay);
  }

  String _formatTime(Map<String, dynamic> data) {
    final candidates = [
      data['timeText'],
      data['eventTimeText'],
      data['time'],
      data['eventTime'],
      data['startTimeText'],
      data['startTime'],
    ];

    for (final candidate in candidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    final scheduledAt = _scheduledTimestamp(data)?.toDate();
    if (scheduledAt != null &&
        (scheduledAt.hour != 0 || scheduledAt.minute != 0)) {
      return DateFormat('HH:mm', 'de_DE').format(scheduledAt);
    }

    return 'Ganztägig';
  }

  bool _hasExplicitTime(Map<String, dynamic> data) {
    final candidates = [
      data['timeText'],
      data['eventTimeText'],
      data['time'],
      data['eventTime'],
      data['startTimeText'],
      data['startTime'],
    ];

    for (final candidate in candidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty) return true;
    }

    final scheduledAt = _scheduledTimestamp(data)?.toDate();
    if (scheduledAt != null &&
        (scheduledAt.hour != 0 || scheduledAt.minute != 0)) {
      return true;
    }

    return false;
  }

  bool _isPastOpenEvent(Map<String, dynamic> data, DateTime now) {
    final scheduledAt = _scheduledTimestamp(data)?.toDate();
    if (scheduledAt == null) return false;

    if (_hasExplicitTime(data)) {
      return scheduledAt.isBefore(now);
    }

    final todayStart = DateTime(now.year, now.month, now.day);
    final scheduledDay = DateTime(
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
    );

    return scheduledDay.isBefore(todayStart);
  }

  void _sortEventsInPlace(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> list,
      ) {
    list.sort((a, b) {
      final aDate = _scheduledTimestamp(a.data());
      final bDate = _scheduledTimestamp(b.data());

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
  }

  void _sortOpenEventsInPlace(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> list,
      ) {
    list.sort((a, b) {
      final aData = a.data();
      final bData = b.data();
      final aDistance = _distanceInMeters(aData);
      final bDistance = _distanceInMeters(bData);
      final aDate = _scheduledTimestamp(aData);
      final bDate = _scheduledTimestamp(bData);
      final aDateTime = aDate?.toDate();
      final bDateTime = bDate?.toDate();
      final aHasExplicitTime = _hasExplicitTime(aData);
      final bHasExplicitTime = _hasExplicitTime(bData);

      int compareDistance() {
        if (aDistance != null && bDistance != null) {
          return aDistance.compareTo(bDistance);
        }
        if (aDistance != null) return -1;
        if (bDistance != null) return 1;
        return 0;
      }

      int compareChronologically() {
        if (aDateTime == null && bDateTime == null) return 0;
        if (aDateTime == null) return 1;
        if (bDateTime == null) return -1;

        final aDay = DateTime(aDateTime.year, aDateTime.month, aDateTime.day);
        final bDay = DateTime(bDateTime.year, bDateTime.month, bDateTime.day);

        final byDay = aDay.compareTo(bDay);
        if (byDay != 0) return byDay;

        if (aHasExplicitTime != bHasExplicitTime) {
          return aHasExplicitTime ? -1 : 1;
        }

        if (aHasExplicitTime && bHasExplicitTime) {
          final byTime = aDateTime.compareTo(bDateTime);
          if (byTime != 0) return byTime;
        }

        return 0;
      }

      final byDay = compareChronologically();
      if (byDay != 0) return byDay;

      if (_selectedOpenEventsSort == 'distance_date') {
        final byDistance = compareDistance();
        if (byDistance != 0) return byDistance;
      }

      return 0;
    });
  }

  String _normalizeKind(Map<String, dynamic> data) {
    final raw = (data['kind'] ?? data['type'] ?? 'open').toString().trim();
    switch (raw) {
      case 'appointment':
      case 'activity':
      case 'service':
      case 'open':
        return raw;
      default:
        return 'open';
    }
  }

  String _kindLabel(Map<String, dynamic> data) {
    switch (_normalizeKind(data)) {
      case 'appointment':
        return 'Termin';
      case 'activity':
        return 'Treffen';
      case 'service':
        return 'Dienstleistung';
      case 'open':
      default:
        return 'Event';
    }
  }

  Color _kindColor(ColorScheme colorScheme, Map<String, dynamic> data) {
    switch (_normalizeKind(data)) {
      case 'appointment':
        return Colors.indigo;
      case 'activity':
        return Colors.teal;
      case 'service':
        return Colors.deepOrange;
      case 'open':
      default:
        return colorScheme.primary;
    }
  }

  String _responseForUser(Map<String, dynamic> data, String currentUserId) {
    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    final directResponse = (responseMap[currentUserId] ?? '').toString().trim();

    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);

    if (accepted.contains(currentUserId)) return 'accepted';
    if (maybe.contains(currentUserId)) return 'maybe';
    if (declined.contains(currentUserId)) return 'declined';
    if (directResponse.isNotEmpty) return directResponse;
    return 'pending';
  }


  Map<String, dynamic> _inviteSeenAtMap(Map<String, dynamic> data) {
    return Map<String, dynamic>.from(
      data['inviteSeenAtMap'] ?? const <String, dynamic>{},
    );
  }

  bool _hasSeenInvite(Map<String, dynamic> data, String userId) {
    if (userId.trim().isEmpty) return false;
    final seenMap = _inviteSeenAtMap(data);
    if (seenMap[userId] != null) return true;

    final response = _responseForUser(data, userId);
    return response == 'accepted' || response == 'maybe' || response == 'declined';
  }

  bool _isUnseenPendingEventInvite(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    return _isPendingEventInvite(data, currentUserId) &&
        !_hasSeenInvite(data, currentUserId);
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

  bool _isJoinDecisionForRequester(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy == currentUserId) return false;

    final joinMode = (data['joinMode'] ?? '').toString().trim().toLowerCase();
    if (joinMode != 'request') return false;

    final response = _responseForUser(data, currentUserId);
    return response == 'accepted' || response == 'declined';
  }

  bool _belongsToInvitationsTab(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final invited = List<String>.from(
      data['invitedUserIds'] ?? const [],
    );
    final memberIds = List<String>.from(data['memberIds'] ?? const []);

    return invited.contains(currentUserId) ||
        memberIds.contains(currentUserId) ||
        _isJoinDecisionForRequester(data, currentUserId);
  }

  int _pendingOwnerRequestCount(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy != currentUserId) return 0;

    final explicitRequestUserIds = List<String>.from(
      data['requestUserIds'] ?? const [],
    );
    if (explicitRequestUserIds.isNotEmpty) {
      return explicitRequestUserIds.where((id) => id != currentUserId).length;
    }

    final joinMode = (data['joinMode'] ?? '').toString().trim().toLowerCase();
    if (joinMode != 'request') return 0;

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );

    return responseMap.entries.where((entry) {
      return entry.key != currentUserId &&
          entry.value.toString().trim().toLowerCase() == 'pending';
    }).length;
  }

  bool _hasPendingOwnerRequests(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    return _pendingOwnerRequestCount(data, currentUserId) > 0;
  }

  String _overallStatus(Map<String, dynamic> data) {
    final raw = (data['status'] ?? '').toString().trim();
    if (raw.isEmpty) return 'pending';
    return raw;
  }

  String _statusLabel(String rawStatus) {
    switch (rawStatus) {
      case 'accepted':
      case 'confirmed':
        return 'Bestätigt';
      case 'maybe':
        return 'Vielleicht';
      case 'declined':
      case 'cancelled':
        return 'Abgelehnt';
      case 'open':
        return 'Offen';
      case 'done':
        return 'Erledigt';
      case 'pending':
      default:
        return 'Ausstehend';
    }
  }

  Color _statusColor(ColorScheme colorScheme, String rawStatus) {
    switch (rawStatus) {
      case 'accepted':
      case 'confirmed':
        return Colors.green;
      case 'maybe':
        return Colors.orange;
      case 'declined':
      case 'cancelled':
        return colorScheme.error;
      case 'open':
        return colorScheme.primary;
      case 'done':
        return Colors.teal;
      case 'pending':
      default:
        return colorScheme.primary;
    }
  }

  String _metaText(Map<String, dynamic> data, String currentUserId) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final createdByName =
    (data['createdByName'] ?? 'Unbekannt').toString().trim();

    if (createdBy == currentUserId) {
      return 'Von dir vorgeschlagen';
    }

    return 'Von ${createdByName.isEmpty ? 'Unbekannt' : createdByName} vorgeschlagen';
  }

  int _acceptedCount(Map<String, dynamic> data) {
    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );

    if (responseMap.isNotEmpty) {
      return responseMap.values
          .where((value) => value.toString().trim() == 'accepted')
          .length;
    }

    final acceptedUserIds = List<String>.from(
      data['acceptedUserIds'] ?? data['participantIds'] ?? const [],
    );
    return acceptedUserIds.length;
  }

  String _participantsText(Map<String, dynamic> data) {
    final acceptedCount = _acceptedCount(data);
    final hasLimit = data['hasParticipantLimit'] == true;
    final rawMax = data['maxParticipants'];
    final maxParticipants = rawMax is int
        ? rawMax
        : int.tryParse((rawMax ?? '').toString().trim());

    if (hasLimit && maxParticipants != null && maxParticipants > 0) {
      return '$acceptedCount/$maxParticipants Teilnehmer';
    }

    if (acceptedCount == 1) {
      return '1 Teilnehmer';
    }

    return '$acceptedCount Teilnehmer';
  }

  Set<String> _eventViewerUserIds(Map<String, dynamic> data) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final viewerIds = <String>{
      ...List<String>.from(data['eventViewerUserIds'] ?? const []),
      ...Map<String, dynamic>.from(
        data['eventViewAtMap'] ?? const <String, dynamic>{},
      ).keys.map((id) => id.trim()),
    }..removeWhere((id) => id.trim().isEmpty || id == createdBy);

    return viewerIds;
  }

  String _viewCountText(Map<String, dynamic> data) {
    final count = _eventViewerUserIds(data).length;
    if (count == 1) return '1 Besucher';
    return '$count Besucher';
  }

  Set<String> _engagedUserIds(Map<String, dynamic> data) {
    final engaged = <String>{
      ...List<String>.from(data['invitedUserIds'] ?? const []),
      ...List<String>.from(data['memberIds'] ?? const []),
      ...List<String>.from(data['participantIds'] ?? const []),
      ...List<String>.from(data['acceptedUserIds'] ?? const []),
      ...List<String>.from(data['maybeUserIds'] ?? const []),
      ...List<String>.from(data['declinedUserIds'] ?? const []),
    };

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    for (final entry in responseMap.entries) {
      final userId = entry.key.trim();
      final status = entry.value.toString().trim().toLowerCase();
      if (userId.isEmpty) continue;
      if ({'pending', 'accepted', 'confirmed', 'maybe', 'declined', 'cancelled'}.contains(status)) {
        engaged.add(userId);
      }
    }

    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy.isNotEmpty) {
      engaged.add(createdBy);
    }

    return engaged;
  }

  Set<String> _eventInterestedUserIds(Map<String, dynamic> data) {
    final rawInterested = List<String>.from(data['interestedUserIds'] ?? const [])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    rawInterested.removeWhere(_engagedUserIds(data).contains);
    return rawInterested;
  }

  bool _isInterestActiveForUser(Map<String, dynamic> data, String currentUserId) {
    return _eventInterestedUserIds(data).contains(currentUserId.trim());
  }

  bool _canToggleInterest(Map<String, dynamic> data, String currentUserId) {
    final userId = currentUserId.trim();
    if (userId.isEmpty) return false;
    return !_engagedUserIds(data).contains(userId);
  }

  String _interestCountText(Map<String, dynamic> data) {
    final count = _eventInterestedUserIds(data).length;
    if (count == 1) return '1 interessiert';
    return '$count interessiert';
  }

  Future<void> _toggleInterest({
    required String eventId,
    required Map<String, dynamic> data,
    required String currentUserId,
  }) async {
    if (!_canToggleInterest(data, currentUserId)) return;

    final userId = currentUserId.trim();
    final isActive = _isInterestActiveForUser(data, userId);

    try {
      await FirebaseFirestore.instance.collection('events').doc(eventId).update({
        'interestedUserIds': isActive
            ? FieldValue.arrayRemove([userId])
            : FieldValue.arrayUnion([userId]),
        if (isActive)
          'interestedAtMap.$userId': FieldValue.delete()
        else
          'interestedAtMap.$userId': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Interesse konnte gerade nicht aktualisiert werden.'),
        ),
      );
    }
  }

  String? _distanceText(Map<String, dynamic> data) {
    final distanceInMeters = _distanceInMeters(data);
    if (distanceInMeters == null) return null;

    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m entfernt';
    }

    final distanceInKilometers = distanceInMeters / 1000;
    if (distanceInKilometers < 10) {
      return '${NumberFormat('0.0', 'de_DE').format(distanceInKilometers)} km entfernt';
    }

    return '${NumberFormat('0', 'de_DE').format(distanceInKilometers.round())} km entfernt';
  }

  _LocationInfo _locationInfo(Map<String, dynamic> data) {
    final exactVisibility =
    (data['exactLocationVisibility'] ?? 'all').toString().trim().toLowerCase();
    final exact = (data['exactLocationText'] ?? data['locationText'] ?? '')
        .toString()
        .trim();
    final approximate = (data['approxLocationText'] ?? '').toString().trim();

    if (exact.isNotEmpty && exactVisibility == 'all') {
      return _LocationInfo(
        label: exact,
        typeLabel: 'Genauer Ort',
        icon: Icons.location_on_outlined,
      );
    }
    if (approximate.isNotEmpty) {
      return _LocationInfo(
        label: approximate,
        typeLabel: 'Ungefährer Ort',
        icon: Icons.place_outlined,
      );
    }
    return const _LocationInfo.empty();
  }

  bool get _hasActiveEventFilters {
    return _searchController.text.trim().isNotEmpty ||
        _selectedKindFilter != 'all' ||
        _selectedDateFilter != 'all' ||
        _selectedRadiusFilter != 'all' ||
        _selectedOpenEventsSort != 'distance_date' ||
        _selectedOpenQuickFilter != 'all';
  }

  int get _activeFilterCount {
    var count = 0;
    if (_searchController.text.trim().isNotEmpty) count++;
    if (_selectedKindFilter != 'all') count++;
    if (_selectedDateFilter != 'all') count++;
    final selectedRadius = double.tryParse(_selectedRadiusFilter);
    if (selectedRadius != null && selectedRadius < 100) count++;
    if (_selectedOpenEventsSort != 'distance_date') count++;
    if (_selectedOpenQuickFilter != 'all') count++;
    return count;
  }

  String? get _selectedKindFilterLabel {
    switch (_selectedKindFilter) {
      case 'activity':
        return 'Aktivität';
      case 'appointment':
        return 'Termin';
      case 'service':
        return 'Dienstleistung';
      default:
        return null;
    }
  }

  String? get _selectedDateFilterLabel {
    switch (_selectedDateFilter) {
      case 'today':
        return 'Heute';
      case 'next7days':
        return 'Nächste 7 Tage';
      case 'thisMonth':
        return 'Diesen Monat';
      default:
        return null;
    }
  }

  double? get _effectiveRadiusKm {
    if (_selectedRadiusFilter == 'all') return null;

    final radius = double.tryParse(_selectedRadiusFilter);
    if (radius == null || radius >= 100) return null;
    return radius;
  }

  String? get _selectedRadiusLabel {
    final radius = int.tryParse(_selectedRadiusFilter);
    if (radius == null || radius >= 100) return null;
    return '$radius km';
  }

  String? get _selectedOpenEventsSortLabel {
    switch (_selectedOpenEventsSort) {
      case 'date_distance':
        return 'Chronologisch';
      case 'distance_date':
      default:
        return null;
    }
  }

  String? get _selectedOpenQuickFilterLabel {
    switch (_selectedOpenQuickFilter) {
      case 'today':
        return 'Heute';
      case 'tomorrow':
        return 'Morgen';
      case 'thisWeek':
        return 'Diese Woche';
      default:
        return null;
    }
  }

  List<_ActiveFilterChipData> _buildCommonActiveChips() {
    return [
      if (_searchController.text.trim().isNotEmpty)
        _ActiveFilterChipData(
          label: 'Suche: "${_searchController.text.trim()}"',
          onRemove: () {
            _searchController.clear();
            if (mounted) setState(() {});
          },
        ),
      if (_selectedKindFilterLabel != null)
        _ActiveFilterChipData(
          label: _selectedKindFilterLabel!,
          onRemove: () {
            setState(() {
              _selectedKindFilter = 'all';
            });
          },
        ),
      if (_selectedDateFilterLabel != null)
        _ActiveFilterChipData(
          label: _selectedDateFilterLabel!,
          onRemove: () {
            setState(() {
              _selectedDateFilter = 'all';
            });
          },
        ),
    ];
  }

  String _buildResultsSummary(int resultCount) {
    final resultLabel = resultCount == 1 ? '1 Treffer' : '$resultCount Treffer';
    final contexts = <String>[];

    if (_selectedOpenQuickFilter == 'today') {
      contexts.add('heute');
    } else if (_selectedOpenQuickFilter == 'tomorrow') {
      contexts.add('morgen');
    } else if (_selectedOpenQuickFilter == 'thisWeek') {
      contexts.add('diese Woche');
    } else if (_selectedDateFilter == 'today') {
      contexts.add('heute');
    } else if (_selectedDateFilter == 'next7days') {
      contexts.add('in den nächsten 7 Tagen');
    } else if (_selectedDateFilter == 'thisMonth') {
      contexts.add('diesen Monat');
    }

    if (_selectedKindFilterLabel != null) {
      contexts.add('für ${_selectedKindFilterLabel!.toLowerCase()}');
    }

    final radiusKm = _effectiveRadiusKm?.round();
    if (radiusKm != null) {
      contexts.add('im Umkreis von $radiusKm km');
    }

    if (_searchController.text.trim().isNotEmpty) {
      contexts.add('für deine Suche');
    }

    if (contexts.isEmpty) return resultLabel;
    return '$resultLabel ${contexts.join(' • ')}';
  }

  int _nextRadiusStep(int currentKm) {
    if (currentKm < 10) return 10;
    if (currentKm < 25) return 25;
    if (currentKm < 50) return 50;
    return 100;
  }

  void _resetAllEventFilters() {
    _searchController.clear();
    setState(() {
      _selectedKindFilter = 'all';
      _selectedDateFilter = 'all';
      _selectedRadiusFilter = 'all';
      _selectedOpenEventsSort = 'distance_date';
      _selectedOpenQuickFilter = 'all';
    });
  }

  Future<void> _openFilterSheet() async {
    String tempKind = _selectedKindFilter;
    String tempDate = _selectedDateFilter;
    String tempRadius = _selectedRadiusFilter;
    String tempSort = _selectedOpenEventsSort;
    String tempQuick = _selectedOpenQuickFilter;
    double tempRadiusKm = double.tryParse(tempRadius) ?? 100;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget buildChoice({
              required String value,
              required String label,
              required String selectedValue,
              required ValueChanged<String> onSelected,
            }) {
              return ChoiceChip(
                selected: selectedValue == value,
                onSelected: (_) {
                  setModalState(() => onSelected(value));
                },
                label: Text(label),
                showCheckmark: false,
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filter',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Typ',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        buildChoice(
                          value: 'all',
                          label: 'Alle',
                          selectedValue: tempKind,
                          onSelected: (value) => tempKind = value,
                        ),
                        buildChoice(
                          value: 'activity',
                          label: 'Aktivität',
                          selectedValue: tempKind,
                          onSelected: (value) => tempKind = value,
                        ),
                        buildChoice(
                          value: 'appointment',
                          label: 'Termin',
                          selectedValue: tempKind,
                          onSelected: (value) => tempKind = value,
                        ),
                        buildChoice(
                          value: 'service',
                          label: 'Dienstleistung',
                          selectedValue: tempKind,
                          onSelected: (value) => tempKind = value,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Datum',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        buildChoice(
                          value: 'all',
                          label: 'Alle',
                          selectedValue: tempQuick,
                          onSelected: (value) => tempQuick = value,
                        ),
                        buildChoice(
                          value: 'today',
                          label: 'Heute',
                          selectedValue: tempQuick,
                          onSelected: (value) => tempQuick = value,
                        ),
                        buildChoice(
                          value: 'tomorrow',
                          label: 'Morgen',
                          selectedValue: tempQuick,
                          onSelected: (value) => tempQuick = value,
                        ),
                        buildChoice(
                          value: 'thisWeek',
                          label: 'Diese Woche',
                          selectedValue: tempQuick,
                          onSelected: (value) => tempQuick = value,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Umkreis',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${tempRadiusKm.round()} km',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Slider(
                          value: tempRadiusKm.clamp(1, 100),
                          min: 1,
                          max: 100,
                          divisions: 99,
                          label: '${tempRadiusKm.round()} km',
                          onChanged: (value) {
                            setModalState(() {
                              tempRadiusKm = value;
                              tempRadius = value.round().toString();
                            });
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Text(
                                '1 km',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '100 km',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Sortierung offene Events',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        buildChoice(
                          value: 'distance_date',
                          label: 'Nähe zuerst',
                          selectedValue: tempSort,
                          onSelected: (value) => tempSort = value,
                        ),
                        buildChoice(
                          value: 'date_distance',
                          label: 'Chronologisch',
                          selectedValue: tempSort,
                          onSelected: (value) => tempSort = value,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _selectedKindFilter = 'all';
                                _selectedDateFilter = 'all';
                                _selectedRadiusFilter = 'all';
                                _selectedOpenEventsSort = 'distance_date';
                                _selectedOpenQuickFilter = 'all';
                              });
                              tempRadius = 'all';
                              tempRadiusKm = 100;
                              Navigator.of(context).pop();
                            },
                            child: const Text('Zurücksetzen'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              setState(() {
                                _selectedKindFilter = tempKind;
                                _selectedDateFilter = tempDate;
                                _selectedRadiusFilter = tempRadius;
                                _selectedOpenEventsSort = tempSort;
                                _selectedOpenQuickFilter = tempQuick;
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('Anwenden'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTabContent({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required EventDetailView view,
    required String currentUserId,
    required Widget emptyState,
    required String Function(Map<String, dynamic>) statusResolver,
    String? resultsSummary,
    Widget? filteredEmptyState,
    List<_ActiveFilterChipData> activeChips = const [],
    Widget? topContent,
    bool groupByDay = false,
  }) {
    if (docs.isEmpty) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _hasActiveEventFilters
              ? (filteredEmptyState ??
              const _EventEmptyState(
                icon: Icons.search_off_rounded,
                title: 'Keine passenden Events',
                subtitle:
                'Für deine aktuelle Suche oder den gewählten Filter wurden keine Events gefunden.',
              ))
              : emptyState,
        ],
      );
    }

    if (_needsScrollToHighlight && docs.any((d) => d.id == _highlightedEventId)) {
      _needsScrollToHighlight = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _highlightedCardKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.15,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
          );
        }
      });
    }

    Widget buildEventCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final data = doc.data();
      final rawStatus = statusResolver(data);
      final isHighlighted = doc.id == _highlightedEventId;
      final isUnseen = view == EventDetailView.invitation &&
          _isUnseenPendingEventInvite(data, currentUserId);
      final hasOpenInviteAction = view == EventDetailView.invitation &&
          _isPendingEventInvite(data, currentUserId);
      final resolvedStatusLabel = view == EventDetailView.invitation &&
          rawStatus == 'pending'
          ? 'Antwort offen'
          : _statusLabel(rawStatus);
      final resolvedStatusColor = view == EventDetailView.invitation &&
          rawStatus == 'pending'
          ? const Color(0xFFFF6B35)
          : _statusColor(colorScheme, rawStatus);

      return _EventCard(
        key: isHighlighted ? _highlightedCardKey : null,
        eventId: doc.id,
        data: data,
        theme: theme,
        colorScheme: colorScheme,
        formatHeaderDate: _formatHeaderDate,
        formatShortDate: _formatShortDate,
        formatTime: _formatTime,
        kindLabel: _kindLabel(data),
        kindColor: _kindColor(colorScheme, data),
        statusLabel: resolvedStatusLabel,
        statusColor: resolvedStatusColor,
        interactionBadgeLabel: view == EventDetailView.myEvent &&
            _hasPendingOwnerRequests(data, currentUserId)
            ? '${_pendingOwnerRequestCount(data, currentUserId)} neu'
            : view == EventDetailView.invitation &&
            _isJoinDecisionForRequester(data, currentUserId)
            ? 'neu'
            : isUnseen
            ? 'Neu'
            : null,
        isHighlighted: isHighlighted,
        showActionRequiredDot: hasOpenInviteAction,
        metaText: _metaText(data, currentUserId),
        interestText: _interestCountText(data),
        isInterestActive: _isInterestActiveForUser(data, currentUserId),
        onInterestTap: _canToggleInterest(data, currentUserId)
            ? () => _toggleInterest(
          eventId: doc.id,
          data: data,
          currentUserId: currentUserId,
        )
            : null,
        participantsText: _participantsText(data),
        visitorsText: _viewCountText(data),
        locationInfo: _locationInfo(data),
        distanceText: _distanceText(data),
        scheduledAt: _scheduledTimestamp(data),
        showDateInHeader: !groupByDay,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EventDetailPage(
                eventId: doc.id,
                view: view,
              ),
            ),
          );
        },
      );
    }

    if (!groupByDay) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: docs.length,
        itemBuilder: (context, index) {
          return buildEventCard(docs[index]);
        },
      );
    }

    final groupedDocs = <_EventDayGroup>[];
    DateTime? currentDay;
    Timestamp? currentTimestamp;
    var currentDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final doc in docs) {
      final scheduledAt = _scheduledTimestamp(doc.data());
      final normalizedDay = _normalizedDayFromTimestamp(scheduledAt);

      if (currentDocs.isEmpty || currentDay == normalizedDay) {
        currentDay = normalizedDay;
        currentTimestamp ??= scheduledAt;
        currentDocs.add(doc);
        continue;
      }

      groupedDocs.add(
        _EventDayGroup(
          timestamp: currentTimestamp,
          docs: currentDocs,
        ),
      );

      currentDay = normalizedDay;
      currentTimestamp = scheduledAt;
      currentDocs = [doc];
    }

    if (currentDocs.isNotEmpty) {
      groupedDocs.add(
        _EventDayGroup(
          timestamp: currentTimestamp,
          docs: currentDocs,
        ),
      );
    }

    return _GroupedEventsScrollView(
      groups: groupedDocs,
      theme: theme,
      backgroundColor: theme.scaffoldBackgroundColor,
      horizontalPadding: 16,
      headerLabelBuilder: _groupHeaderLabel,
      itemBuilder: buildEventCard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Eventss')),
        body: const Center(
          child: Text('Du bist aktuell nicht eingeloggt.'),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreateEventPage(),
            ),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Erstellen'),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _eventsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text('Fehler beim Laden der Events.'),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            final myEvents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final invitedEvents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final openEvents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            final query = _searchController.text.trim().toLowerCase();
            final hasQuery = query.isNotEmpty;
            final now = DateTime.now();
            final todayStart = DateTime(now.year, now.month, now.day);
            final nextWeekEnd = todayStart.add(const Duration(days: 7));
            final monthEnd = DateTime(now.year, now.month + 1, 1);

            for (final doc in docs) {
              final data = doc.data();

              final matchesKind = _selectedKindFilter == 'all' ||
                  _normalizeKind(data) == _selectedKindFilter;
              if (!matchesKind) continue;

              bool matchesDate = true;
              if (_selectedDateFilter != 'all') {
                final scheduledAt = _scheduledTimestamp(data)?.toDate();
                if (scheduledAt == null) {
                  matchesDate = false;
                } else {
                  switch (_selectedDateFilter) {
                    case 'today':
                      matchesDate =
                          !scheduledAt.isBefore(todayStart) &&
                              scheduledAt.isBefore(
                                todayStart.add(const Duration(days: 1)),
                              );
                      break;
                    case 'next7days':
                      matchesDate =
                          !scheduledAt.isBefore(todayStart) &&
                              scheduledAt.isBefore(nextWeekEnd);
                      break;
                    case 'thisMonth':
                      matchesDate =
                          !scheduledAt.isBefore(todayStart) &&
                              scheduledAt.isBefore(monthEnd);
                      break;
                  }
                }
              }
              if (!matchesDate) continue;

              if (hasQuery) {
                final locationInfo = _locationInfo(data);
                final haystack = [
                  (data['title'] ?? '').toString(),
                  (data['description'] ?? '').toString(),
                  (data['createdByName'] ?? '').toString(),
                  locationInfo.label,
                  locationInfo.typeLabel,
                  _kindLabel(data),
                ].join(' ').toLowerCase();

                if (!haystack.contains(query)) continue;
              }

              final createdBy = (data['createdBy'] ?? '').toString();
              if (createdBy == currentUserId) {
                myEvents.add(doc);
                continue;
              }

              if (_belongsToInvitationsTab(data, currentUserId)) {
                invitedEvents.add(doc);
                continue;
              }

              final kind = _normalizeKind(data);
              final visibility =
              (data['visibility'] ?? '').toString().trim().toLowerCase();

              final isOpenKind = kind == 'open';
              final isOpenVisibility =
                  visibility == 'open' || visibility == 'public';

              if (isOpenKind || isOpenVisibility) {
                if (_isPastOpenEvent(data, now)) {
                  continue;
                }

                final scheduledAt = _scheduledTimestamp(data)?.toDate();
                final currentDay = DateTime(now.year, now.month, now.day);
                final tomorrow = currentDay.add(const Duration(days: 1));
                final weekEnd = currentDay.add(const Duration(days: 7));

                if (_selectedOpenQuickFilter != 'all') {
                  if (scheduledAt == null) {
                    continue;
                  }

                  final scheduledDay = DateTime(
                    scheduledAt.year,
                    scheduledAt.month,
                    scheduledAt.day,
                  );

                  if (_selectedOpenQuickFilter == 'today' &&
                      scheduledDay != currentDay) {
                    continue;
                  }

                  if (_selectedOpenQuickFilter == 'tomorrow' &&
                      scheduledDay != tomorrow) {
                    continue;
                  }

                  if (_selectedOpenQuickFilter == 'thisWeek' &&
                      (scheduledDay.isBefore(currentDay) ||
                          scheduledDay.isAfter(weekEnd))) {
                    continue;
                  }
                }

                final maxDistanceKm = _effectiveRadiusKm;
                if (maxDistanceKm != null) {
                  final distanceInMeters = _distanceInMeters(data);
                  if (distanceInMeters == null ||
                      distanceInMeters > maxDistanceKm * 1000) {
                    continue;
                  }
                }

                openEvents.add(doc);
              }
            }

            _sortEventsInPlace(myEvents);
            _sortEventsInPlace(invitedEvents);
            _sortOpenEventsInPlace(openEvents);

            final myPendingRequestCount = myEvents.fold<int>(0, (sum, doc) {
              return sum + _pendingOwnerRequestCount(doc.data(), currentUserId);
            });

            final invitationAttentionCount = invitedEvents.where((doc) {
              final data = doc.data();
              return _isUnseenPendingEventInvite(data, currentUserId) ||
                  _isJoinDecisionForRequester(data, currentUserId);
            }).length;

            if (invitationAttentionCount > 0 &&
                !_didAutoJumpToMyEvents &&
                _tabController.index == 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _didAutoJumpToMyEvents) return;
                _didAutoJumpToMyEvents = true;
                _tabController.animateTo(1);
              });
            } else if (myPendingRequestCount > 0 &&
                !_didAutoJumpToMyEvents &&
                _tabController.index == 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _didAutoJumpToMyEvents) return;
                _didAutoJumpToMyEvents = true;
                _tabController.animateTo(2);
              });
            }

            final currentTabIndex = _tabController.index;
            final openActiveChips = <_ActiveFilterChipData>[
              ..._buildCommonActiveChips(),
              if (_selectedOpenQuickFilterLabel != null)
                _ActiveFilterChipData(
                  label: _selectedOpenQuickFilterLabel!,
                  onRemove: () {
                    setState(() {
                      _selectedOpenQuickFilter = 'all';
                    });
                  },
                ),
              if (_selectedOpenEventsSortLabel != null)
                _ActiveFilterChipData(
                  label: _selectedOpenEventsSortLabel!,
                  onRemove: () {
                    setState(() {
                      _selectedOpenEventsSort = 'distance_date';
                    });
                  },
                ),
              if (_selectedRadiusLabel != null)
                _ActiveFilterChipData(
                  label: _selectedRadiusLabel!,
                  onRemove: () {
                    setState(() {
                      _selectedRadiusFilter = 'all';
                    });
                  },
                ),
            ];

            final currentActiveChips =
            currentTabIndex == 0 ? openActiveChips : _buildCommonActiveChips();
            final currentResultCount = currentTabIndex == 0
                ? openEvents.length
                : currentTabIndex == 1
                ? invitedEvents.length
                : myEvents.length;
            final currentSummary = currentTabIndex == 0
                ? _buildResultsSummary(openEvents.length)
                : null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _SearchBarCard(
                    controller: _searchController,
                    onFilterTap: _openFilterSheet,
                    activeFilterCount: _activeFilterCount,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: const TextScaler.linear(1.0)),
                      child: TabBar(
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        labelColor: colorScheme.primary,
                        unselectedLabelColor: colorScheme.onSurfaceVariant,
                        labelStyle: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                        tabs: [
                          const Tab(
                            child: _ResponsiveTabLabel(label: 'Offene Events'),
                          ),
                          Tab(
                            child: _TabLabelWithBadge(
                              label: 'Einladungen',
                              badgeCount: invitationAttentionCount,
                            ),
                          ),
                          Tab(
                            child: _TabLabelWithBadge(
                              label: 'Meine Events',
                              badgeCount: myPendingRequestCount,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_hasActiveEventFilters)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _ActiveSearchInfo(
                      searchText: _searchController.text.trim(),
                      activeFilterCount: _activeFilterCount,
                      resultCount: currentResultCount,
                      summaryText: currentSummary,
                      activeChips: currentActiveChips,
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildTabContent(
                        context: context,
                        theme: theme,
                        colorScheme: colorScheme,
                        docs: openEvents,
                        view: EventDetailView.openEvent,
                        currentUserId: currentUserId,
                        statusResolver: (_) => 'open',
                        resultsSummary: _buildResultsSummary(openEvents.length),
                        filteredEmptyState: _effectiveRadiusKm != null
                            ? _RadiusEmptyState(
                          radiusKm: _effectiveRadiusKm!.round(),
                          onExpand: () {
                            setState(() {
                              final currentRadius =
                                  _effectiveRadiusKm?.round() ?? 100;
                              _selectedRadiusFilter =
                                  _nextRadiusStep(currentRadius)
                                      .toString();
                            });
                          },
                          onReset: _resetAllEventFilters,
                        )
                            : null,
                        activeChips: [
                          ..._buildCommonActiveChips(),
                          if (_selectedOpenQuickFilterLabel != null)
                            _ActiveFilterChipData(
                              label: _selectedOpenQuickFilterLabel!,
                              onRemove: () {
                                setState(() {
                                  _selectedOpenQuickFilter = 'all';
                                });
                              },
                            ),
                          if (_selectedOpenEventsSortLabel != null)
                            _ActiveFilterChipData(
                              label: _selectedOpenEventsSortLabel!,
                              onRemove: () {
                                setState(() {
                                  _selectedOpenEventsSort = 'distance_date';
                                });
                              },
                            ),
                          if (_selectedRadiusLabel != null)
                            _ActiveFilterChipData(
                              label: _selectedRadiusLabel!,
                              onRemove: () {
                                setState(() {
                                  _selectedRadiusFilter = 'all';
                                });
                              },
                            ),
                        ],
                        groupByDay: true,
                        emptyState: const _EventEmptyState(
                          icon: Icons.public_off_outlined,
                          title: 'Keine offenen Events',
                          subtitle:
                          'Aktuell gibt es keine offenen Events für dich. Neue öffentliche Aktivitäten erscheinen später hier.',
                        ),
                      ),
                      _buildTabContent(
                        context: context,
                        theme: theme,
                        colorScheme: colorScheme,
                        docs: invitedEvents,
                        view: EventDetailView.invitation,
                        currentUserId: currentUserId,
                        statusResolver: (data) =>
                            _responseForUser(data, currentUserId),
                        activeChips: _buildCommonActiveChips(),
                        groupByDay: true,
                        emptyState: const _EventEmptyState(
                          icon: Icons.mail_outline_rounded,
                          title: 'Keine Einladungen vorhanden',
                          subtitle:
                          'Sobald dich jemand zu einem Event einlädt, erscheint es hier in deiner Übersicht.',
                        ),
                      ),
                      _buildTabContent(
                        context: context,
                        theme: theme,
                        colorScheme: colorScheme,
                        docs: myEvents,
                        view: EventDetailView.myEvent,
                        currentUserId: currentUserId,
                        statusResolver: (data) => _overallStatus(data),
                        activeChips: _buildCommonActiveChips(),
                        groupByDay: true,
                        emptyState: const _EventEmptyState(
                          icon: Icons.event_busy_outlined,
                          title: 'Noch keine eigenen Events',
                          subtitle:
                          'Du hast noch keine Events erstellt. Über den Plus-Button kannst du direkt dein erstes Event planen.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeStyleBadge extends StatelessWidget {
  final String label;

  const _HomeStyleBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFB7E61D),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.black87,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ResponsiveTabLabel extends StatelessWidget {
  final String label;

  const _ResponsiveTabLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

class _TabLabelWithBadge extends StatelessWidget {
  final String label;
  final int badgeCount;

  const _TabLabelWithBadge({
    required this.label,
    required this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    if (badgeCount <= 0) {
      return _ResponsiveTabLabel(label: label);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 8),
            _HomeStyleBadge(
              label: badgeCount == 1 ? '1 neu' : '$badgeCount neu',
            ),
          ],
        ),
      ),
    );
  }
}


class _EventDayGroup {
  final Timestamp? timestamp;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  const _EventDayGroup({
    required this.timestamp,
    required this.docs,
  });
}

typedef _GroupedEventCardBuilder = Widget Function(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    );

class _GroupedEventsScrollView extends StatefulWidget {
  final List<_EventDayGroup> groups;
  final ThemeData theme;
  final Color backgroundColor;
  final double horizontalPadding;
  final String Function(Timestamp? timestamp) headerLabelBuilder;
  final _GroupedEventCardBuilder itemBuilder;

  const _GroupedEventsScrollView({
    required this.groups,
    required this.theme,
    required this.backgroundColor,
    required this.horizontalPadding,
    required this.headerLabelBuilder,
    required this.itemBuilder,
  });

  @override
  State<_GroupedEventsScrollView> createState() =>
      _GroupedEventsScrollViewState();
}

class _GroupedEventsScrollViewState extends State<_GroupedEventsScrollView> {
  static const double _stickyHeaderHeight = _DayGroupHeaderDelegate._headerExtent;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _stackKey = GlobalKey();
  late List<GlobalKey> _headerKeys;

  int _activeIndex = 0;
  double _stickyOpacity = 1;
  double _stickyTranslateY = 0;

  @override
  void initState() {
    super.initState();
    _headerKeys = _createHeaderKeys();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateStickyHeader());
  }

  @override
  void didUpdateWidget(covariant _GroupedEventsScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups.length != widget.groups.length) {
      _headerKeys = _createHeaderKeys();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateStickyHeader());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  List<GlobalKey> _createHeaderKeys() {
    return List<GlobalKey>.generate(widget.groups.length, (_) => GlobalKey());
  }

  void _handleScroll() {
    if (!mounted) return;
    _updateStickyHeader();
  }

  void _updateStickyHeader() {
    if (!mounted || widget.groups.isEmpty) return;

    final stackContext = _stackKey.currentContext;
    if (stackContext == null) return;

    final stackBox = stackContext.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;

    final topPositions = <double>[];
    for (final key in _headerKeys) {
      final headerContext = key.currentContext;
      if (headerContext == null) return;

      final box = headerContext.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;

      final offset = box.localToGlobal(Offset.zero, ancestor: stackBox);
      topPositions.add(offset.dy);
    }

    var activeIndex = 0;
    for (var i = 0; i < topPositions.length; i++) {
      if (topPositions[i] <= 0) {
        activeIndex = i;
      } else {
        break;
      }
    }

    final nextTop = activeIndex + 1 < topPositions.length
        ? topPositions[activeIndex + 1]
        : double.infinity;
    final pushOffset = (_stickyHeaderHeight - nextTop)
        .clamp(0.0, _stickyHeaderHeight)
        .toDouble();
    final shouldShowOverlay = topPositions.first < 0;
    final opacity = shouldShowOverlay
        ? (1 - (pushOffset / _stickyHeaderHeight)).clamp(0.0, 1.0)
        : 0.0;

    if (_activeIndex != activeIndex ||
        (_stickyOpacity - opacity).abs() > 0.001 ||
        (_stickyTranslateY + pushOffset).abs() > 0.001) {
      setState(() {
        _activeIndex = activeIndex;
        _stickyOpacity = opacity;
        _stickyTranslateY = -pushOffset;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return const SizedBox.shrink();
    }

    final activeGroup = widget.groups[_activeIndex.clamp(0, widget.groups.length - 1)];

    return Stack(
      key: _stackKey,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _updateStickyHeader());
            return false;
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              for (var groupIndex = 0; groupIndex < widget.groups.length; groupIndex++) ...[
                SliverToBoxAdapter(
                  child: KeyedSubtree(
                    key: _headerKeys[groupIndex],
                    child: Container(
                      color: widget.backgroundColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.horizontalPadding,
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: _DayGroupHeader(
                          label: widget.headerLabelBuilder(
                            widget.groups[groupIndex].timestamp,
                          ),
                          count: widget.groups[groupIndex].docs.length,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                          widget.itemBuilder(widget.groups[groupIndex].docs[index]),
                      childCount: widget.groups[groupIndex].docs.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: 24),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Transform.translate(
              offset: Offset(0, _stickyTranslateY),
              child: Opacity(
                opacity: _stickyOpacity,
                child: Container(
                  color: widget.backgroundColor,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.horizontalPadding,
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _DayGroupHeader(
                      label: widget.headerLabelBuilder(activeGroup.timestamp),
                      count: activeGroup.docs.length,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  static const double _headerExtent = 50;

  final String label;
  final int count;
  final Color backgroundColor;
  final double horizontalPadding;

  const _DayGroupHeaderDelegate({
    required this.label,
    required this.count,
    required this.backgroundColor,
    required this.horizontalPadding,
  });

  @override
  double get minExtent => _headerExtent;

  @override
  double get maxExtent => _headerExtent;

  @override
  Widget build(
      BuildContext context,
      double shrinkOffset,
      bool overlapsContent,
      ) {
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _DayGroupHeader(
            label: label,
            count: count,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DayGroupHeaderDelegate oldDelegate) {
    return label != oldDelegate.label ||
        count != oldDelegate.count ||
        backgroundColor != oldDelegate.backgroundColor ||
        horizontalPadding != oldDelegate.horizontalPadding;
  }
}

class _ActiveFilterChipData {

  final String label;
  final VoidCallback? onRemove;

  const _ActiveFilterChipData({
    required this.label,
    this.onRemove,
  });
}

class _DayGroupHeader extends StatelessWidget {
  final String label;
  final int count;

  const _DayGroupHeader({
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final countLabel = count == 1 ? '1 Event' : '$count Events';

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '· $countLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: colorScheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBarCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onFilterTap;
  final int activeFilterCount;

  const _SearchBarCard({
    required this.controller,
    required this.onFilterTap,
    required this.activeFilterCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasText = controller.text.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Suche nach Event, Ort oder Person',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasText)
                IconButton(
                  tooltip: 'Suche löschen',
                  onPressed: controller.clear,
                  icon: const Icon(Icons.close_rounded),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      tooltip: 'Filter',
                      onPressed: onFilterTap,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                    if (activeFilterCount > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$activeFilterCount',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}

class _ActiveSearchInfo extends StatelessWidget {
  final String searchText;
  final int activeFilterCount;
  final int? resultCount;
  final String? summaryText;
  final List<_ActiveFilterChipData> activeChips;

  const _ActiveSearchInfo({
    required this.searchText,
    required this.activeFilterCount,
    this.resultCount,
    this.summaryText,
    this.activeChips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final parts = <String>[];
    if (activeFilterCount > 0) {
      parts.add('$activeFilterCount Filter aktiv');
    }
    if (summaryText != null && summaryText!.trim().isNotEmpty) {
      parts.add(summaryText!);
    } else if (resultCount != null) {
      parts.add('$resultCount Treffer');
    }
    if (parts.isEmpty && searchText.isNotEmpty) {
      parts.add('Suche aktiv');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            parts.join(' • '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (activeChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in activeChips)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: chip.onRemove,
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              chip.label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (chip.onRemove != null) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationInfo {
  final String label;
  final String typeLabel;
  final IconData icon;

  const _LocationInfo({
    required this.label,
    required this.typeLabel,
    required this.icon,
  });

  const _LocationInfo.empty()
      : label = '',
        typeLabel = '',
        icon = Icons.place_outlined;

  bool get isEmpty => label.trim().isEmpty;
}

class _EventCard extends StatelessWidget {
  final String eventId;
  final Map<String, dynamic> data;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final String Function(Timestamp?) formatHeaderDate;
  final String Function(Timestamp?) formatShortDate;
  final String Function(Map<String, dynamic>) formatTime;
  final String kindLabel;
  final Color kindColor;
  final String statusLabel;
  final Color statusColor;
  final String? interactionBadgeLabel;
  final String metaText;
  final String interestText;
  final bool isInterestActive;
  final VoidCallback? onInterestTap;
  final String participantsText;
  final String? visitorsText;
  final _LocationInfo locationInfo;
  final String? distanceText;
  final Timestamp? scheduledAt;
  final bool showDateInHeader;
  final VoidCallback onTap;
  final bool isHighlighted;
  final bool showActionRequiredDot;

  const _EventCard({
    super.key,
    required this.eventId,
    required this.data,
    required this.theme,
    required this.colorScheme,
    required this.formatHeaderDate,
    required this.formatShortDate,
    required this.formatTime,
    required this.kindLabel,
    required this.kindColor,
    required this.statusLabel,
    required this.statusColor,
    required this.interactionBadgeLabel,
    this.isHighlighted = false,
    this.showActionRequiredDot = false,
    required this.metaText,
    required this.interestText,
    required this.isInterestActive,
    required this.onInterestTap,
    required this.participantsText,
    required this.visitorsText,
    required this.locationInfo,
    required this.distanceText,
    required this.scheduledAt,
    this.showDateInHeader = true,
    required this.onTap,
  });

  String? _relativeStartText() {
    final startDate = scheduledAt?.toDate();
    if (startDate == null) return null;

    final now = DateTime.now();
    if (!startDate.isAfter(now)) return null;

    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    final today = DateTime(now.year, now.month, now.day);
    final dayDiff = startDay.difference(today).inDays;
    final diff = startDate.difference(now);

    if (dayDiff == 0) {
      if (diff.inMinutes < 60) {
        final minutes = diff.inMinutes <= 1 ? 1 : diff.inMinutes;
        return 'Startet in $minutes Min.';
      }

      final hours = (diff.inMinutes / 60).ceil();
      return 'Startet in $hours Std.';
    }

    if (dayDiff == 1) return 'Startet morgen';
    if (dayDiff < 7) return 'Startet in $dayDiff Tagen';
    return 'Startet am ${DateFormat('dd.MM.', 'de_DE').format(startDate)}';
  }

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Event').toString().trim();
    final description = (data['description'] ?? '').toString().trim();
    final relativeStartText = _relativeStartText();

    const highlightColor = Color(0xFF19B35E);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: isHighlighted
                  ? highlightColor.withValues(alpha: 0.06)
                  : colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isHighlighted
                    ? highlightColor
                    : colorScheme.outlineVariant,
                width: isHighlighted ? 2 : 1,
              ),
              boxShadow: isHighlighted
                  ? [
                BoxShadow(
                  color: highlightColor.withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: Offset.zero,
                ),
              ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? highlightColor.withValues(alpha: 0.95)
                        : colorScheme.primary.withValues(alpha: 0.95),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (showDateInHeader) ...[
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            formatHeaderDate(scheduledAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ] else
                        const Spacer(),
                      const Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatTime(data),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isHighlighted) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Neu',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kindColor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    kindLabel,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      color: kindColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (interactionBadgeLabel != null) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: _HomeStyleBadge(
                                      label: interactionBadgeLabel!,
                                    ),
                                  ),
                                ],
                                if (relativeStartText != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      relativeStartText,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                                if (description.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (showActionRequiredDot) ...[
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF6B35),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _EventInfoChip(
                            icon: Icons.favorite_border_rounded,
                            activeIcon: Icons.favorite_rounded,
                            isActive: isInterestActive,
                            onTap: onInterestTap,
                            label: interestText,
                            theme: theme,
                            colorScheme: colorScheme,
                          ),
                          if (visitorsText != null &&
                              visitorsText!.trim().isNotEmpty)
                            _EventInfoChip(
                              icon: Icons.visibility_outlined,
                              label: visitorsText!,
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                          _EventInfoChip(
                            icon: Icons.group_outlined,
                            label: participantsText,
                            theme: theme,
                            colorScheme: colorScheme,
                          ),
                          if (!locationInfo.isEmpty)
                            _EventInfoChip(
                              icon: locationInfo.icon,
                              label: locationInfo.label,
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                          if (distanceText != null &&
                              distanceText!.trim().isNotEmpty)
                            _EventInfoChip(
                              icon: Icons.near_me_outlined,
                              label: distanceText!,
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                          if (!locationInfo.isEmpty &&
                              locationInfo.typeLabel.trim().isNotEmpty)
                            _EventInfoChip(
                              icon: Icons.info_outline_rounded,
                              label: locationInfo.typeLabel,
                              theme: theme,
                              colorScheme: colorScheme,
                              useSubtleColor: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        metaText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventInfoChip extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final bool isActive;
  final VoidCallback? onTap;
  final String label;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final bool useSubtleColor;

  const _EventInfoChip({
    required this.icon,
    this.activeIcon,
    this.isActive = false,
    this.onTap,
    required this.label,
    required this.theme,
    required this.colorScheme,
    this.useSubtleColor = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = useSubtleColor
        ? colorScheme.onSurfaceVariant
        : colorScheme.primary;
    final effectiveIcon = isActive ? (activeIcon ?? icon) : icon;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.58,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: isActive ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  effectiveIcon,
                  size: 14,
                  color: chipColor,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: chipColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadiusEmptyState extends StatelessWidget {
  final int radiusKm;
  final VoidCallback onExpand;
  final VoidCallback onReset;

  const _RadiusEmptyState({
    required this.radiusKm,
    required this.onExpand,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.radar_rounded,
            size: 56,
            color: colorScheme.primary.withValues(alpha: 0.75),
          ),
          const SizedBox(height: 14),
          Text(
            'Keine Events im Umkreis von $radiusKm km',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Erweitere den Umkreis oder setze die Filter zurück, um wieder Ergebnisse zu sehen.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onExpand,
                  child: const Text('Umkreis erweitern'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onReset,
                  child: const Text('Filter zurücksetzen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EventEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 56,
            color: colorScheme.primary.withValues(alpha: 0.75),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
