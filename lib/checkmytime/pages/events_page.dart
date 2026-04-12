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
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  String _normalizeJoinMode(Map<String, dynamic> data) {
    final raw = (data['joinMode'] ?? 'invite_only').toString().trim().toLowerCase();
    switch (raw) {
      case 'request':
      case 'direct':
      case 'invite_only':
        return raw;
      default:
        return 'invite_only';
    }
  }

  int _pendingCount(Map<String, dynamic> data) {
    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );

    if (responseMap.isNotEmpty) {
      return responseMap.values
          .where((value) => value.toString().trim() == 'pending')
          .length;
    }

    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final invitedUserIds = List<String>.from(data['invitedUserIds'] ?? const []);
    final acceptedUserIds = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybeUserIds = List<String>.from(data['maybeUserIds'] ?? const []);
    final declinedUserIds = List<String>.from(data['declinedUserIds'] ?? const []);

    final pending = invitedUserIds.toSet()
      ..remove(createdBy)
      ..removeAll(acceptedUserIds)
      ..removeAll(maybeUserIds)
      ..removeAll(declinedUserIds);

    return pending.length;
  }

  int _pendingRequestsAcrossEvents(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    var total = 0;
    for (final doc in docs) {
      final data = doc.data();
      if (_normalizeJoinMode(data) == 'request') {
        total += _pendingCount(data);
      }
    }
    return total;
  }

  List<_EventHighlightData> _cardHighlights({
    required ColorScheme colorScheme,
    required Map<String, dynamic> data,
    required EventDetailView view,
    required String currentUserId,
  }) {
    final joinMode = _normalizeJoinMode(data);
    final pendingCount = _pendingCount(data);
    final response = _responseForUser(data, currentUserId);
    final highlights = <_EventHighlightData>[];

    if (view == EventDetailView.myEvent) {
      if (joinMode == 'request') {
        highlights.add(
          _EventHighlightData(
            icon: Icons.mark_email_unread_outlined,
            label: pendingCount == 1
                ? '1 offene Anfrage'
                : '$pendingCount offene Anfragen',
            color: pendingCount > 0 ? Colors.orange : Colors.green,
          ),
        );
      } else if (joinMode == 'direct') {
        highlights.add(
          const _EventHighlightData(
            icon: Icons.flash_on_outlined,
            label: 'Direkter Beitritt',
            color: Colors.green,
          ),
        );
      } else {
        highlights.add(
          _EventHighlightData(
            icon: Icons.mail_outline_rounded,
            label: 'Nur Einladung',
            color: colorScheme.primary,
          ),
        );
      }
      return highlights;
    }

    if (view == EventDetailView.invitation) {
      switch (response) {
        case 'accepted':
          highlights.add(
            const _EventHighlightData(
              icon: Icons.check_circle_outline_rounded,
              label: 'Du bist dabei',
              color: Colors.green,
            ),
          );
          break;
        case 'maybe':
          highlights.add(
            const _EventHighlightData(
              icon: Icons.help_outline_rounded,
              label: 'Du bist auf Vielleicht',
              color: Colors.orange,
            ),
          );
          break;
        case 'declined':
          highlights.add(
            _EventHighlightData(
              icon: Icons.cancel_outlined,
              label: 'Du hast abgesagt',
              color: colorScheme.error,
            ),
          );
          break;
        case 'pending':
        default:
          highlights.add(
            _EventHighlightData(
              icon: joinMode == 'request'
                  ? Icons.send_outlined
                  : Icons.schedule_outlined,
              label: joinMode == 'request'
                  ? 'Anfrage gesendet'
                  : 'Antwort ausstehend',
              color: Colors.orange,
            ),
          );
      }

      if (joinMode == 'request') {
        highlights.add(
          const _EventHighlightData(
            icon: Icons.lock_clock_outlined,
            label: 'Freigabe durch Ersteller',
            color: Colors.orange,
          ),
        );
      }
      return highlights;
    }

    if (view == EventDetailView.openEvent) {
      if (joinMode == 'request') {
        highlights.add(
          const _EventHighlightData(
            icon: Icons.lock_clock_outlined,
            label: 'Anfrage nötig',
            color: Colors.orange,
          ),
        );
      } else if (joinMode == 'direct') {
        highlights.add(
          const _EventHighlightData(
            icon: Icons.flash_on_outlined,
            label: 'Direkter Beitritt',
            color: Colors.green,
          ),
        );
      } else {
        highlights.add(
          _EventHighlightData(
            icon: Icons.mail_outline_rounded,
            label: 'Zugang per Einladung',
            color: colorScheme.primary,
          ),
        );
      }
    }

    return highlights;
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

  String _locationText(Map<String, dynamic> data) {
    final exactVisibility =
    (data['exactLocationVisibility'] ?? 'all').toString().trim().toLowerCase();
    final exact = (data['exactLocationText'] ?? data['locationText'] ?? '')
        .toString()
        .trim();
    final approximate = (data['approxLocationText'] ?? '').toString().trim();

    if (exact.isNotEmpty && exactVisibility == 'all') {
      return exact;
    }
    if (approximate.isNotEmpty) {
      return approximate;
    }
    if (exact.isNotEmpty) {
      return exact;
    }
    return '';
  }


  Widget _buildTabContent({
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
          locationText: _locationText(data),
          scheduledAt: _scheduledTimestamp(data),
          highlights: _cardHighlights(
            colorScheme: colorScheme,
            data: data,
            view: view,
            currentUserId: currentUserId,
          ),
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
          stream: FirebaseFirestore.instance
              .collection('events')
              .orderBy('createdAt', descending: true)
              .snapshots(),
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

            final myEvents = _sortEvents(
              docs.where(
                    (doc) => (doc.data()['createdBy'] ?? '').toString() == currentUserId,
              ),
            );

            final invitedEvents = _sortEvents(
              docs.where((doc) {
                final data = doc.data();
                final createdBy = (data['createdBy'] ?? '').toString();
                final invited = List<String>.from(
                  data['invitedUserIds'] ?? const [],
                );
                final memberIds = List<String>.from(
                  data['memberIds'] ?? const [],
                );

                return createdBy != currentUserId &&
                    (invited.contains(currentUserId) ||
                        memberIds.contains(currentUserId));
              }),
            );

            final openEvents = _sortEvents(
              docs.where((doc) {
                final data = doc.data();
                final createdBy = (data['createdBy'] ?? '').toString();
                final invited = List<String>.from(
                  data['invitedUserIds'] ?? const [],
                );
                final memberIds = List<String>.from(
                  data['memberIds'] ?? const [],
                );
                final kind = _normalizeKind(data);
                final visibility =
                (data['visibility'] ?? '').toString().trim().toLowerCase();

                final isOpenKind = kind == 'open';
                final isOpenVisibility =
                    visibility == 'open' || visibility == 'public';

                return createdBy != currentUserId &&
                    !invited.contains(currentUserId) &&
                    !memberIds.contains(currentUserId) &&
                    (isOpenKind || isOpenVisibility);
              }),
            );

            final pendingOwnerRequests = _pendingRequestsAcrossEvents(myEvents);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Events planen',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Hier siehst du deine eigenen Planungen, Einladungen und offene Events in einem einheitlichen Stil.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SummaryChip(
                              icon: Icons.event_note_outlined,
                              label: '${myEvents.length} eigene',
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                            _SummaryChip(
                              icon: Icons.mail_outline_rounded,
                              label: '${invitedEvents.length} Einladungen',
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                            _SummaryChip(
                              icon: Icons.public_outlined,
                              label: '${openEvents.length} offene',
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                            if (pendingOwnerRequests > 0)
                              _SummaryChip(
                                icon: Icons.mark_email_unread_outlined,
                                label: pendingOwnerRequests == 1
                                    ? '1 Anfrage offen'
                                    : '$pendingOwnerRequests Anfragen offen',
                                theme: theme,
                                colorScheme: colorScheme,
                                color: Colors.orange,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CreateEventPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Event erstellen'),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                        Tab(text: 'Meine Events'),
                        Tab(text: 'Einladungen'),
                        Tab(text: 'Offene Events'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildTabContent(
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
                          'Du hast noch keine Events erstellt. Über den Button oben kannst du direkt dein erstes Event planen.',
                        ),
                      ),
                      _buildTabContent(
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
                        theme: theme,
                        colorScheme: colorScheme,
                        docs: openEvents,
                        view: EventDetailView.openEvent,
                        currentUserId: currentUserId,
                        statusResolver: (_) => 'open',
                        emptyState: const _EventEmptyState(
                          icon: Icons.public_off_outlined,
                          title: 'Keine offenen Events',
                          subtitle:
                          'Aktuell gibt es keine offenen Events für dich. Neue öffentliche Aktivitäten erscheinen später hier.',
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
  final String locationText;
  final Timestamp? scheduledAt;
  final List<_EventHighlightData> highlights;
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
    required this.locationText,
    required this.scheduledAt,
    required this.highlights,
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
                      if (highlights.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: highlights
                              .map(
                                (highlight) => _EventHighlightChip(
                              icon: highlight.icon,
                              label: highlight.label,
                              color: highlight.color,
                              theme: theme,
                            ),
                          )
                              .toList(),
                        ),
                      ],
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
                          if (locationText.trim().isNotEmpty)
                            _EventInfoChip(
                              icon: Icons.place_outlined,
                              label: locationText,
                              theme: theme,
                              colorScheme: colorScheme,
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

class _EventHighlightData {
  final IconData icon;
  final String label;
  final Color color;

  const _EventHighlightData({
    required this.icon,
    required this.label,
    required this.color,
  });
}

class _EventHighlightChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final ThemeData theme;

  const _EventHighlightChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Color? color;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.theme,
    required this.colorScheme,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolvedColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: resolvedColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _EventInfoChip({
    required this.icon,
    required this.label,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
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
