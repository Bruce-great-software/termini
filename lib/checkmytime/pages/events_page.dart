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
                final isOpenVisibility = visibility == 'open';

                return createdBy != currentUserId &&
                    !invited.contains(currentUserId) &&
                    !memberIds.contains(currentUserId) &&
                    (isOpenKind || isOpenVisibility);
              }),
            );

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
                          'Du hast noch keine Events erstellt. Über den Button oben kannst du direkt dein erstes Event planen.',
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
