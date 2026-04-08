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

  String _formatCardHeaderDate(Timestamp? timestamp) {
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
      if (value.isNotEmpty) {
        return value;
      }
    }

    return 'Ganztägig';
  }

  String _inviteStatusLabel(Map<String, dynamic> data, String currentUserId) {
    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);

    if (accepted.contains(currentUserId)) return 'Zugesagt';
    if (maybe.contains(currentUserId)) return 'Vielleicht';
    if (declined.contains(currentUserId)) return 'Abgesagt';
    return 'Eingeladen';
  }

  Color _inviteStatusColor(ColorScheme colorScheme, String statusLabel) {
    switch (statusLabel) {
      case 'Zugesagt':
        return Colors.green;
      case 'Vielleicht':
        return Colors.orange;
      case 'Abgesagt':
        return colorScheme.error;
      case 'Eingeladen':
      default:
        return colorScheme.primary;
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortEvents(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final sorted = docs.toList();
    sorted.sort((a, b) {
      final aDate = a.data()['eventDate'] as Timestamp?;
      final bDate = b.data()['eventDate'] as Timestamp?;

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return sorted;
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

            final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                snapshot.data?.docs ?? [];

            final myEvents = _sortEvents(
              docs.where((doc) {
                final data = doc.data();
                return (data['createdBy'] ?? '').toString() == currentUserId;
              }),
            );

            final invitedEvents = _sortEvents(
              docs.where((doc) {
                final data = doc.data();
                final invited = List<String>.from(
                  data['invitedUserIds'] ?? const [],
                );
                return invited.contains(currentUserId);
              }),
            );

            final openEvents = _sortEvents(
              docs.where((doc) {
                final data = doc.data();
                final createdBy = (data['createdBy'] ?? '').toString();
                final invited = List<String>.from(
                  data['invitedUserIds'] ?? const [],
                );
                final type = (data['type'] ?? 'open').toString();

                return type == 'open' &&
                    createdBy != currentUserId &&
                    !invited.contains(currentUserId);
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
                          'Hier planst du später gemeinsame Aktivitäten, Einladungen und offene Unternehmungen mit anderen Personen.',
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
                        color: colorScheme.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(16),
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
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _EventTabView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        items: myEvents,
                        emptyState: const _EventEmptyState(
                          icon: Icons.event_busy_outlined,
                          title: 'Noch keine eigenen Events',
                          subtitle:
                          'Sobald du dein erstes Event erstellst, erscheint es hier in deiner Übersicht.',
                        ),
                        itemBuilder: (doc) => _EventCard(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EventDetailPage(
                                  eventId: doc.id,
                                  view: EventDetailView.myEvent,
                                ),
                              ),
                            );
                          },
                          data: doc.data(),
                          colorScheme: colorScheme,
                          theme: theme,
                          headerDate: _formatCardHeaderDate,
                          shortDate: _formatShortDate,
                          timeLabel: _formatTime(doc.data()),
                          statusLabel: 'Geplant',
                          statusColor: colorScheme.primary,
                          subtitlePrefix: 'Erstellt von dir',
                        ),
                      ),
                      _EventTabView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        items: invitedEvents,
                        emptyState: const _EventEmptyState(
                          icon: Icons.mail_outline_rounded,
                          title: 'Keine Einladungen',
                          subtitle:
                          'Hier erscheinen Events, zu denen dich andere Personen eingeladen haben.',
                        ),
                        itemBuilder: (doc) {
                          final data = doc.data();
                          final status = _inviteStatusLabel(data, currentUserId);
                          return _EventCard(
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EventDetailPage(
                                    eventId: doc.id,
                                    view: EventDetailView.invitation,
                                  ),
                                ),
                              );
                            },
                            data: data,
                            colorScheme: colorScheme,
                            theme: theme,
                            headerDate: _formatCardHeaderDate,
                            shortDate: _formatShortDate,
                            timeLabel: _formatTime(data),
                            statusLabel: status,
                            statusColor:
                            _inviteStatusColor(colorScheme, status),
                            subtitlePrefix:
                            'Einladung von ${(data['createdByName'] ?? 'Unbekannt').toString().trim()}',
                          );
                        },
                      ),
                      _EventTabView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        items: openEvents,
                        emptyState: const _EventEmptyState(
                          icon: Icons.public_off_outlined,
                          title: 'Keine offenen Events',
                          subtitle:
                          'Aktuell gibt es keine offenen Events für dich. Neue öffentliche Aktivitäten erscheinen später hier.',
                        ),
                        itemBuilder: (doc) => _EventCard(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EventDetailPage(
                                  eventId: doc.id,
                                  view: EventDetailView.openEvent,
                                ),
                              ),
                            );
                          },
                          data: doc.data(),
                          colorScheme: colorScheme,
                          theme: theme,
                          headerDate: _formatCardHeaderDate,
                          shortDate: _formatShortDate,
                          timeLabel: _formatTime(doc.data()),
                          statusLabel: 'Offen',
                          statusColor: colorScheme.primary,
                          subtitlePrefix:
                          'Öffentlich von ${(doc.data()['createdByName'] ?? 'Unbekannt').toString().trim()}',
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

class _EventTabView extends StatelessWidget {
  final EdgeInsets padding;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> items;
  final Widget emptyState;
  final Widget Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)
  itemBuilder;

  const _EventTabView({
    required this.padding,
    required this.items,
    required this.emptyState,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: padding,
        children: [emptyState],
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: padding,
      itemCount: items.length,
      itemBuilder: (context, index) => itemBuilder(items[index]),
    );
  }
}

class _EventCard extends StatelessWidget {
  final VoidCallback? onTap;
  final Map<String, dynamic> data;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final String Function(Timestamp?) headerDate;
  final String Function(Timestamp?) shortDate;
  final String timeLabel;
  final String statusLabel;
  final Color statusColor;
  final String subtitlePrefix;

  const _EventCard({
    this.onTap,
    required this.data,
    required this.colorScheme,
    required this.theme,
    required this.headerDate,
    required this.shortDate,
    required this.timeLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.subtitlePrefix,
  });

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Event').toString().trim();
    final description = (data['description'] ?? '').toString().trim();
    final location = (data['location'] ?? '').toString().trim();
    final createdByName = (data['createdByName'] ?? 'Unbekannt').toString().trim();
    final eventDate = data['eventDate'] as Timestamp?;
    final invited = List<String>.from(data['invitedUserIds'] ?? const []);
    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);

    final summaryChips = <Widget>[
      _EventMetaChip(
        icon: Icons.group_outlined,
        label: '${accepted.length} zugesagt',
      ),
      if (invited.isNotEmpty)
        _EventMetaChip(
          icon: Icons.mail_outline,
          label: '${invited.length} eingeladen',
        ),
      if (maybe.isNotEmpty)
        _EventMetaChip(
          icon: Icons.help_outline,
          label: '${maybe.length} vielleicht',
        ),
      if (declined.isNotEmpty)
        _EventMetaChip(
          icon: Icons.close,
          label: '${declined.length} abgesagt',
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.95),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
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
                        headerDate(eventDate),
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
                      timeLabel,
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
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: colorScheme.primary.withOpacity(0.10),
                          child: Icon(
                            Icons.celebration_outlined,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subtitlePrefix,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Datum: ${shortDate(eventDate)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (location.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Ort: $location',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (createdByName.isNotEmpty &&
                                  !subtitlePrefix.contains(createdByName)) ...[
                                const SizedBox(height: 4),
                                Text(
                                  createdByName,
                                  style: theme.textTheme.bodySmall?.copyWith(
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
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (summaryChips.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: summaryChips,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _EventMetaChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.08),
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
