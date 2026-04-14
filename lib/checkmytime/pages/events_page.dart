import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/pages/create_event_page.dart';
import 'package:termini/checkmytime/pages/event_detail_page.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

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
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream;
  Position? _userPosition;
  bool _isLoadingUserLocation = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    if (normalizedDay == today) return 'Heute';
    if (normalizedDay == tomorrow) return 'Morgen';

    return DateFormat('EEEE, d. MMMM', 'de_DE').format(normalizedDay);
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
      final aDistance = _distanceInMeters(a.data());
      final bDistance = _distanceInMeters(b.data());
      final aDate = _scheduledTimestamp(a.data());
      final bDate = _scheduledTimestamp(b.data());

      int compareDate() {
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      }

      int compareDistance() {
        if (aDistance != null && bDistance != null) {
          return aDistance.compareTo(bDistance);
        }
        if (aDistance != null) return -1;
        if (bDistance != null) return 1;
        return 0;
      }

      if (_selectedOpenEventsSort == 'date_distance') {
        final byDate = compareDate();
        if (byDate != 0) return byDate;

        final byDistance = compareDistance();
        if (byDistance != 0) return byDistance;
        return 0;
      }

      final byDistance = compareDistance();
      if (byDistance != 0) return byDistance;

      final byDate = compareDate();
      if (byDate != 0) return byDate;
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
        _selectedOpenEventsSort != 'distance_date';
  }

  int get _activeFilterCount {
    var count = 0;
    if (_selectedKindFilter != 'all') count++;
    if (_selectedDateFilter != 'all') count++;
    if (_selectedRadiusFilter != 'all') count++;
    if (_selectedOpenEventsSort != 'distance_date') count++;
    return count;
  }

  String? get _selectedRadiusLabel {
    switch (_selectedRadiusFilter) {
      case '5':
        return '5 km';
      case '10':
        return '10 km';
      case '25':
        return '25 km';
      case '50':
        return '50 km';
      case '100':
        return '100 km';
      default:
        return null;
    }
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

  Future<void> _openFilterSheet() async {
    String tempKind = _selectedKindFilter;
    String tempDate = _selectedDateFilter;
    String tempRadius = _selectedRadiusFilter;
    String tempSort = _selectedOpenEventsSort;

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
                          label: 'Alle Daten',
                          selectedValue: tempDate,
                          onSelected: (value) => tempDate = value,
                        ),
                        buildChoice(
                          value: 'today',
                          label: 'Heute',
                          selectedValue: tempDate,
                          onSelected: (value) => tempDate = value,
                        ),
                        buildChoice(
                          value: 'next7days',
                          label: 'Nächste 7 Tage',
                          selectedValue: tempDate,
                          onSelected: (value) => tempDate = value,
                        ),
                        buildChoice(
                          value: 'thisMonth',
                          label: 'Diesen Monat',
                          selectedValue: tempDate,
                          onSelected: (value) => tempDate = value,
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
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        buildChoice(
                          value: 'all',
                          label: 'Überall',
                          selectedValue: tempRadius,
                          onSelected: (value) => tempRadius = value,
                        ),
                        buildChoice(
                          value: '5',
                          label: '5 km',
                          selectedValue: tempRadius,
                          onSelected: (value) => tempRadius = value,
                        ),
                        buildChoice(
                          value: '10',
                          label: '10 km',
                          selectedValue: tempRadius,
                          onSelected: (value) => tempRadius = value,
                        ),
                        buildChoice(
                          value: '25',
                          label: '25 km',
                          selectedValue: tempRadius,
                          onSelected: (value) => tempRadius = value,
                        ),
                        buildChoice(
                          value: '50',
                          label: '50 km',
                          selectedValue: tempRadius,
                          onSelected: (value) => tempRadius = value,
                        ),
                        buildChoice(
                          value: '100',
                          label: '100 km',
                          selectedValue: tempRadius,
                          onSelected: (value) => tempRadius = value,
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
                              });
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
    List<_ActiveFilterChipData> activeChips = const [],
    bool groupByDay = false,
  }) {
    if (docs.isEmpty) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (_hasActiveEventFilters)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ActiveSearchInfo(
                searchText: _searchController.text.trim(),
                activeFilterCount: _activeFilterCount,
                activeChips: activeChips,
              ),
            ),
          _hasActiveEventFilters
              ? const _EventEmptyState(
            icon: Icons.search_off_rounded,
            title: 'Keine passenden Events',
            subtitle:
            'Für deine aktuelle Suche oder den gewählten Filter wurden keine Events gefunden.',
          )
              : emptyState,
        ],
      );
    }

    Widget buildEventCard(
        QueryDocumentSnapshot<Map<String, dynamic>> doc,
        ) {
      final data = doc.data();
      final rawStatus = statusResolver(data);

      return _EventCard(
        eventId: doc.id,
        data: data,
        theme: theme,
        colorScheme: colorScheme,
        formatHeaderDate: _formatHeaderDate,
        formatShortDate: _formatShortDate,
        formatTime: _formatTime,
        kindLabel: _kindLabel(data),
        kindColor: _kindColor(colorScheme, data),
        statusLabel: _statusLabel(rawStatus),
        statusColor: _statusColor(colorScheme, rawStatus),
        metaText: _metaText(data, currentUserId),
        participantsText: _participantsText(data),
        locationInfo: _locationInfo(data),
        distanceText: _distanceText(data),
        scheduledAt: _scheduledTimestamp(data),
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
        itemCount: docs.length + (_hasActiveEventFilters ? 1 : 0),
        itemBuilder: (context, index) {
          if (_hasActiveEventFilters && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ActiveSearchInfo(
                searchText: _searchController.text.trim(),
                activeFilterCount: _activeFilterCount,
                resultCount: docs.length,
                activeChips: activeChips,
              ),
            );
          }

          final docIndex = _hasActiveEventFilters ? index - 1 : index;
          return buildEventCard(docs[docIndex]);
        },
      );
    }

    final children = <Widget>[];
    if (_hasActiveEventFilters) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ActiveSearchInfo(
            searchText: _searchController.text.trim(),
            activeFilterCount: _activeFilterCount,
            resultCount: docs.length,
            activeChips: activeChips,
          ),
        ),
      );
    }

    DateTime? previousDay;
    for (final doc in docs) {
      final scheduledAt = _scheduledTimestamp(doc.data());
      final currentDay = _normalizedDayFromTimestamp(scheduledAt);

      if (previousDay != currentDay) {
        children.add(
          _DayGroupHeader(
            label: _groupHeaderLabel(scheduledAt),
          ),
        );
        previousDay = currentDay;
      }

      children.add(buildEventCard(doc));
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Events')),
        body: const Center(
          child: Text('Du bist aktuell nicht eingeloggt.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
      ),
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
                      matchesDate = !scheduledAt.isBefore(todayStart) &&
                          scheduledAt.isBefore(
                            todayStart.add(const Duration(days: 1)),
                          );
                      break;
                    case 'next7days':
                      matchesDate = !scheduledAt.isBefore(todayStart) &&
                          scheduledAt.isBefore(nextWeekEnd);
                      break;
                    case 'thisMonth':
                      matchesDate = !scheduledAt.isBefore(todayStart) &&
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

              final invited = List<String>.from(
                data['invitedUserIds'] ?? const [],
              );
              final memberIds = List<String>.from(
                data['memberIds'] ?? const [],
              );

              if (invited.contains(currentUserId) ||
                  memberIds.contains(currentUserId)) {
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

                if (_selectedRadiusFilter != 'all') {
                  final maxDistanceKm = double.tryParse(_selectedRadiusFilter);
                  final distanceInMeters = _distanceInMeters(data);
                  if (maxDistanceKm != null) {
                    if (distanceInMeters == null ||
                        distanceInMeters > maxDistanceKm * 1000) {
                      continue;
                    }
                  }
                }

                openEvents.add(doc);
              }
            }

            _sortEventsInPlace(myEvents);
            _sortEventsInPlace(invitedEvents);
            _sortOpenEventsInPlace(openEvents);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                      tabs: const [
                        Tab(text: 'Offene Events'),
                        Tab(text: 'Einladungen'),
                        Tab(text: 'Meine Events'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
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
                        activeChips: [
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

  const _DayGroupHeader({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
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
  final List<_ActiveFilterChipData> activeChips;

  const _ActiveSearchInfo({
    required this.searchText,
    required this.activeFilterCount,
    this.resultCount,
    this.activeChips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final parts = <String>[];
    if (searchText.isNotEmpty) {
      parts.add('Suche: "$searchText"');
    }
    if (activeFilterCount > 0) {
      parts.add('$activeFilterCount Filter aktiv');
    }
    if (resultCount != null) {
      parts.add('$resultCount Treffer');
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
  final String metaText;
  final String participantsText;
  final _LocationInfo locationInfo;
  final String? distanceText;
  final Timestamp? scheduledAt;
  final VoidCallback onTap;

  const _EventCard({
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
    required this.metaText,
    required this.participantsText,
    required this.locationInfo,
    required this.distanceText,
    required this.scheduledAt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Event').toString().trim();
    final description = (data['description'] ?? '').toString().trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant),
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
                    color: colorScheme.primary.withValues(alpha: 0.95),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
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
                                    style: theme.textTheme.labelMedium?.copyWith(
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
                          if (distanceText != null && distanceText!.trim().isNotEmpty)
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
  final String label;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final bool useSubtleColor;

  const _EventInfoChip({
    required this.icon,
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

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.58,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
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
