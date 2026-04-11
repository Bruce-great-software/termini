import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
  static const List<_FilterChoice> _visibilityChoices = [
    _FilterChoice('all', 'Alle'),
    _FilterChoice('public', 'Öffentlich'),
    _FilterChoice('friends', 'Freunde'),
    _FilterChoice('private', 'Privat'),
  ];

  static const List<_FilterChoice> _categoryChoices = [
    _FilterChoice('all', 'Alle'),
    _FilterChoice('sport', 'Sport'),
    _FilterChoice('freizeit', 'Freizeit'),
    _FilterChoice('essen_trinken', 'Essen & Trinken'),
    _FilterChoice('nachtleben', 'Nachtleben'),
    _FilterChoice('dienstleistung', 'Dienstleistung'),
    _FilterChoice('lernen_arbeit', 'Lernen & Arbeit'),
  ];

  late final TabController _tabController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream;

  String _searchQuery = '';
  String _visibilityFilter = 'all';
  String _categoryFilter = 'all';
  bool _onlyFreeSpots = false;

  String get _normalizedSearchQuery => _searchQuery.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _eventsStream = FirebaseFirestore.instance
        .collection('events')
        .orderBy('createdAt', descending: true)
        .snapshots();

    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text;
    if (!mounted || next == _searchQuery) return;

    final selection = _searchController.selection;
    setState(() => _searchQuery = next);
    _restoreSelectionAfterFrame(selection);
  }

  void _restoreSelectionAfterFrame(TextSelection selection) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (!_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      }

      final textLength = _searchController.text.length;
      final baseOffset = selection.baseOffset.clamp(0, textLength);
      final extentOffset = selection.extentOffset.clamp(0, textLength);

      _searchController.selection = TextSelection(
        baseOffset: baseOffset,
        extentOffset: extentOffset,
      );
    });
  }

  void _applySuggestion(String value) {
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );

    if (!_searchFocusNode.hasFocus) {
      _searchFocusNode.requestFocus();
    }

    if (_searchQuery != value) {
      setState(() => _searchQuery = value);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    if (!_searchFocusNode.hasFocus) {
      _searchFocusNode.requestFocus();
    }
  }

  Timestamp? _scheduledTimestamp(Map<String, dynamic> data) {
    return data['scheduledAt'] as Timestamp? ?? data['eventDate'] as Timestamp?;
  }

  String _formatHeaderDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    return DateFormat('EEEE, d. MMMM', 'de_DE').format(timestamp.toDate());
  }

  String _formatShortDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    return DateFormat('dd.MM.yyyy', 'de_DE').format(timestamp.toDate());
  }

  String _formatTime(Map<String, dynamic> data) {
    const keys = [
      'timeText',
      'eventTimeText',
      'time',
      'eventTime',
      'startTimeText',
      'startTime',
    ];

    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    final scheduledAt = _scheduledTimestamp(data)?.toDate();
    if (scheduledAt != null &&
        (scheduledAt.hour != 0 || scheduledAt.minute != 0)) {
      return DateFormat('HH:mm', 'de_DE').format(scheduledAt);
    }

    return 'Ganztägig';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortEvents(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final sorted = docs.toList();
    sorted.sort((a, b) {
      final aDate = _scheduledTimestamp(a.data());
      final bDate = _scheduledTimestamp(b.data());

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return sorted;
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

  String _normalizeVisibility(Map<String, dynamic> data) {
    final raw = (data['visibility'] ?? '').toString().trim().toLowerCase();
    if (raw == 'open') return 'public';
    if (raw == 'public' || raw == 'friends' || raw == 'private') return raw;
    if (_normalizeKind(data) == 'open') return 'public';
    return 'private';
  }

  String _kindLabel(Map<String, dynamic> data) {
    switch (_normalizeKind(data)) {
      case 'appointment':
        return 'Termin';
      case 'activity':
        return 'Aktivität';
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
    if (directResponse.isNotEmpty) return directResponse;

    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);

    if (accepted.contains(currentUserId)) return 'accepted';
    if (maybe.contains(currentUserId)) return 'maybe';
    if (declined.contains(currentUserId)) return 'declined';
    return 'pending';
  }

  String _overallStatus(Map<String, dynamic> data) {
    final raw = (data['status'] ?? '').toString().trim();
    return raw.isEmpty ? 'pending' : raw;
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
      return 'Von dir erstellt';
    }

    return 'Von ${createdByName.isEmpty ? 'Unbekannt' : createdByName} erstellt';
  }

  bool _isJoinedByCurrentUser(Map<String, dynamic> data, String currentUserId) {
    final invited = List<String>.from(data['invitedUserIds'] ?? const []);
    final memberIds = List<String>.from(data['memberIds'] ?? const []);
    return invited.contains(currentUserId) || memberIds.contains(currentUserId);
  }

  bool _isVisibleToCurrentUser(Map<String, dynamic> data, String currentUserId) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy == currentUserId) return true;
    if (_isJoinedByCurrentUser(data, currentUserId)) return true;
    return _normalizeVisibility(data) == 'public';
  }

  bool _hasFreeSpots(Map<String, dynamic> data) {
    final hasLimit = data['hasParticipantLimit'] == true;
    if (!hasLimit) return true;

    final rawMax = data['maxParticipants'];
    final maxParticipants = rawMax is int
        ? rawMax
        : int.tryParse((rawMax ?? '').toString().trim());

    if (maxParticipants == null || maxParticipants <= 0) return true;

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );

    final acceptedCount = responseMap.isNotEmpty
        ? responseMap.values
        .where((value) => value.toString().trim() == 'accepted')
        .length
        : List<String>.from(data['acceptedUserIds'] ?? const []).length;

    return acceptedCount < maxParticipants;
  }

  bool _matchesSearch(
      Map<String, dynamic> data,
      String normalizedQuery,
      ) {
    if (normalizedQuery.isEmpty) return true;

    final title = (data['title'] ?? '').toString().toLowerCase();
    final topic = (data['topic'] ?? '').toString().toLowerCase();
    final category = (data['category'] ?? '').toString().toLowerCase();
    final location = (data['locationText'] ?? '').toString().toLowerCase();
    final approxLocation =
    (data['approxLocationText'] ?? '').toString().toLowerCase();
    final exactLocation =
    (data['exactLocationText'] ?? '').toString().toLowerCase();
    final tags = List<String>.from(data['tags'] ?? const [])
        .map((tag) => tag.toLowerCase());

    return title.contains(normalizedQuery) ||
        topic.contains(normalizedQuery) ||
        category.contains(normalizedQuery) ||
        location.contains(normalizedQuery) ||
        approxLocation.contains(normalizedQuery) ||
        exactLocation.contains(normalizedQuery) ||
        tags.any((tag) => tag.contains(normalizedQuery));
  }

  bool _matchesFilters(
      Map<String, dynamic> data, {
        required String normalizedQuery,
      }) {
    if (_visibilityFilter != 'all' &&
        _normalizeVisibility(data) != _visibilityFilter) {
      return false;
    }

    if (_categoryFilter != 'all') {
      final category = (data['category'] ?? '').toString().trim().toLowerCase();
      if (category != _categoryFilter) return false;
    }

    if (_onlyFreeSpots && !_hasFreeSpots(data)) {
      return false;
    }

    return _matchesSearch(data, normalizedQuery);
  }

  List<_EventSuggestion> _buildSuggestions(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final query = _normalizedSearchQuery;
    if (query.isEmpty) return const [];

    final suggestionsByKey = <String, _EventSuggestion>{};

    void addSuggestion({
      required String text,
      required String category,
      required String kind,
    }) {
      final value = text.trim();
      if (value.isEmpty) return;

      final lowerValue = value.toLowerCase();
      if (!lowerValue.contains(query)) return;

      suggestionsByKey.putIfAbsent(
        lowerValue,
            () => _EventSuggestion(
          text: value,
          category: category.trim(),
          kind: kind.trim(),
        ),
      );
    }

    for (final doc in docs) {
      final data = doc.data();
      final category = (data['category'] ?? '').toString();
      final kind = (data['kind'] ?? data['type'] ?? '').toString();

      addSuggestion(
        text: (data['topic'] ?? '').toString(),
        category: category,
        kind: kind,
      );
      addSuggestion(
        text: (data['title'] ?? '').toString(),
        category: category,
        kind: kind,
      );

      for (final tag in List<String>.from(data['tags'] ?? const [])) {
        addSuggestion(text: tag, category: category, kind: kind);
      }
    }

    final suggestions = suggestionsByKey.values.toList()
      ..sort((a, b) {
        final aText = a.text.toLowerCase();
        final bText = b.text.toLowerCase();
        final aStarts = aText.startsWith(query);
        final bStarts = bText.startsWith(query);

        if (aStarts != bStarts) return aStarts ? -1 : 1;
        return aText.compareTo(bText);
      });

    return suggestions.take(6).toList();
  }

  String _kindLabelFromRaw(String rawKind) {
    switch (rawKind) {
      case 'appointment':
        return 'Termin';
      case 'activity':
        return 'Aktivität';
      case 'service':
        return 'Dienstleistung';
      case 'open':
      default:
        return 'Event';
    }
  }

  String _categoryLabel(String rawCategory) {
    switch (rawCategory) {
      case 'sport':
        return 'Sport';
      case 'freizeit':
        return 'Freizeit';
      case 'essen_trinken':
        return 'Essen & Trinken';
      case 'nachtleben':
        return 'Nachtleben';
      case 'dienstleistung':
        return 'Dienstleistung';
      case 'lernen_arbeit':
        return 'Lernen & Arbeit';
      default:
        return rawCategory;
    }
  }

  String? _suggestionSubtitle(_EventSuggestion suggestion) {
    final parts = <String>[];
    if (suggestion.category.isNotEmpty) {
      parts.add(_categoryLabel(suggestion.category));
    }
    if (suggestion.kind.isNotEmpty) {
      parts.add(_kindLabelFromRaw(suggestion.kind));
    }
    return parts.isEmpty ? null : parts.join(' • ');
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_EventsFilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String visibility = _visibilityFilter;
        String category = _categoryFilter;
        bool freeSpots = _onlyFreeSpots;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget buildModalChips({
              required String selectedValue,
              required ValueChanged<String> onSelected,
              required List<_FilterChoice> options,
            }) {
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: options.map((option) {
                  return ChoiceChip(
                    selected: selectedValue == option.value,
                    onSelected: (_) => setModalState(() => onSelected(option.value)),
                    label: Text(option.label),
                    showCheckmark: false,
                  );
                }).toList(),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
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
                    const SizedBox(height: 18),
                    Text(
                      'Sichtbarkeit',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    buildModalChips(
                      selectedValue: visibility,
                      onSelected: (value) => visibility = value,
                      options: _visibilityChoices,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Kategorie',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    buildModalChips(
                      selectedValue: category,
                      onSelected: (value) => category = value,
                      options: _categoryChoices,
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: freeSpots,
                      onChanged: (value) => setModalState(() => freeSpots = value),
                      title: const Text('Nur Events mit freien Plätzen'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pop(
                                const _EventsFilterResult(
                                  visibility: 'all',
                                  category: 'all',
                                  onlyFreeSpots: false,
                                ),
                              );
                            },
                            child: const Text('Zurücksetzen'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop(
                                _EventsFilterResult(
                                  visibility: visibility,
                                  category: category,
                                  onlyFreeSpots: freeSpots,
                                ),
                              );
                            },
                            child: const Text('Übernehmen'),
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

    if (result == null || !mounted) return;

    setState(() {
      _visibilityFilter = result.visibility;
      _categoryFilter = result.category;
      _onlyFreeSpots = result.onlyFreeSpots;
    });
  }

  Widget _buildHighlightedSuggestionText(
      BuildContext context,
      String value,
      String query,
      ) {
    final lowerValue = value.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final start = lowerValue.indexOf(lowerQuery);

    if (start < 0 || lowerQuery.isEmpty) {
      return Text(value);
    }

    final end = start + lowerQuery.length;
    final defaultStyle = Theme.of(context).textTheme.bodyLarge;
    final highlightStyle = defaultStyle?.copyWith(fontWeight: FontWeight.w800);

    return RichText(
      text: TextSpan(
        style: defaultStyle,
        children: [
          TextSpan(text: value.substring(0, start)),
          TextSpan(
            text: value.substring(start, end),
            style: highlightStyle,
          ),
          TextSpan(text: value.substring(end)),
        ],
      ),
    );
  }

  Widget _buildSearchArea(
      BuildContext context,
      ColorScheme colorScheme,
      List<_EventSuggestion> suggestions,
      ) {
    final hasActiveFilter =
        _visibilityFilter != 'all' || _categoryFilter != 'all' || _onlyFreeSpots;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('events_search_field'),
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          autofocus: false,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Suche nach Billard, Cage Soccer, Kaffee ...',
                            prefixIcon: const Icon(Icons.search),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                            suffixIcon: _searchQuery.trim().isEmpty
                                ? null
                                : IconButton(
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                          onTap: () {
                            if (!_searchFocusNode.hasFocus) {
                              _searchFocusNode.requestFocus();
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              onPressed: _openFilterSheet,
                              icon: const Icon(Icons.tune_rounded),
                              tooltip: 'Filter',
                            ),
                            if (hasActiveFilter)
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateEventPage(),
                      ),
                    );
                  },
                  child: const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_searchQuery.trim().isNotEmpty && suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: suggestions.map((suggestion) {
                  final subtitle = _suggestionSubtitle(suggestion);
                  return ListTile(
                    leading: const Icon(Icons.north_west_rounded),
                    title: _buildHighlightedSuggestionText(
                      context,
                      suggestion.text,
                      _searchQuery,
                    ),
                    subtitle: subtitle == null ? null : Text(subtitle),
                    onTap: () => _applySuggestion(suggestion.text),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
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
  }) {
    if (docs.isEmpty) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [emptyState],
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data();
        final rawStatus = statusResolver(data);

        return _EventCard(
          key: ValueKey(doc.id),
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
      },
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

            final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final visibleDocs = docs
                .where((doc) => _isVisibleToCurrentUser(doc.data(), currentUserId))
                .toList();

            final normalizedQuery = _normalizedSearchQuery;
            final suggestions = _buildSuggestions(visibleDocs);

            final filteredVisibleDocs = visibleDocs
                .where(
                  (doc) => _matchesFilters(
                doc.data(),
                normalizedQuery: normalizedQuery,
              ),
            )
                .toList();

            final myEvents = _sortEvents(
              filteredVisibleDocs.where(
                    (doc) => (doc.data()['createdBy'] ?? '').toString() == currentUserId,
              ),
            );

            final invitedEvents = _sortEvents(
              filteredVisibleDocs.where((doc) {
                final data = doc.data();
                final createdBy = (data['createdBy'] ?? '').toString();
                return createdBy != currentUserId &&
                    _isJoinedByCurrentUser(data, currentUserId);
              }),
            );

            final openEvents = _sortEvents(
              filteredVisibleDocs.where((doc) {
                final data = doc.data();
                final createdBy = (data['createdBy'] ?? '').toString();
                return createdBy != currentUserId &&
                    !_isJoinedByCurrentUser(data, currentUserId) &&
                    _normalizeVisibility(data) == 'public';
              }),
            );

            return Column(
              children: [
                _buildSearchArea(context, colorScheme, suggestions),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      labelColor: colorScheme.primary,
                      unselectedLabelColor: colorScheme.onSurfaceVariant,
                      labelStyle: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      tabs: const [
                        Tab(text: 'Entdecken'),
                        Tab(text: 'Einladungen'),
                        Tab(text: 'Meine Events'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
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
                          emptyState: const _EventEmptyState(
                            icon: Icons.public_off_outlined,
                            title: 'Keine offenen Events gefunden',
                            subtitle:
                            'Aktuell gibt es keine öffentlichen Events, die zu deiner Suche oder deinen Filtern passen.',
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
                            title: 'Keine passenden Einladungen',
                            subtitle:
                            'Sobald Einladungen zu deiner Suche oder deinen Filtern passen, erscheinen sie hier.',
                          ),
                        ),
                        _buildTabContent(
                          context: context,
                          theme: theme,
                          colorScheme: colorScheme,
                          docs: myEvents,
                          view: EventDetailView.myEvent,
                          currentUserId: currentUserId,
                          statusResolver: _overallStatus,
                          emptyState: const _EventEmptyState(
                            icon: Icons.event_busy_outlined,
                            title: 'Noch keine eigenen Events',
                            subtitle:
                            'Du hast aktuell keine Events, die zu deiner Suche oder deinen Filtern passen.',
                          ),
                        ),
                      ],
                    ),
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
  final Timestamp? scheduledAt;
  final VoidCallback onTap;

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
    required this.metaText,
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
                    color: colorScheme.primary.withOpacity(0.95),
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
                                    color: kindColor.withOpacity(0.10),
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
                                  color: statusColor.withOpacity(0.10),
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
                      Text(
                        'Datum: ${formatShortDate(scheduledAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
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
            color: colorScheme.primary.withOpacity(0.75),
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

class _EventSuggestion {
  final String text;
  final String category;
  final String kind;

  const _EventSuggestion({
    required this.text,
    required this.category,
    required this.kind,
  });
}

class _FilterChoice {
  final String value;
  final String label;

  const _FilterChoice(this.value, this.label);
}

class _EventsFilterResult {
  final String visibility;
  final String category;
  final bool onlyFreeSpots;

  const _EventsFilterResult({
    required this.visibility,
    required this.category,
    required this.onlyFreeSpots,
  });
}
