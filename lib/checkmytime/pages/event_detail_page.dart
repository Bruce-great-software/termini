import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/pages/create_event_page.dart';

/// Legt fest, aus welchem Tab die Detailseite geöffnet wurde.
enum EventDetailView {
  myEvent,
  invitation,
  openEvent,
}

class EventDetailPage extends StatefulWidget {
  final String eventId;
  final EventDetailView view;

  const EventDetailPage({
    super.key,
    required this.eventId,
    required this.view,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  bool _isUpdatingStatus = false;
  bool _isDeleting = false;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _formatHeaderDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    return DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(timestamp.toDate());
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

    return 'Ganztägig';
  }

  String _eventTypeLabel(String rawType) {
    switch (rawType) {
      case 'private':
        return 'Privat';
      case 'invite':
        return 'Einladung';
      case 'open':
      default:
        return 'Offenes Event';
    }
  }

  String _currentUserStatus(Map<String, dynamic> data) {
    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);

    if (accepted.contains(_currentUserId)) return 'Zugesagt';
    if (maybe.contains(_currentUserId)) return 'Vielleicht';
    if (declined.contains(_currentUserId)) return 'Abgesagt';

    switch (widget.view) {
      case EventDetailView.myEvent:
        return 'Geplant';
      case EventDetailView.invitation:
        return 'Eingeladen';
      case EventDetailView.openEvent:
        return 'Offen';
    }
  }

  Color _statusColor(ColorScheme colorScheme, String label) {
    switch (label) {
      case 'Zugesagt':
        return Colors.green;
      case 'Vielleicht':
        return Colors.orange;
      case 'Abgesagt':
        return colorScheme.error;
      case 'Geplant':
      case 'Eingeladen':
      case 'Offen':
      default:
        return colorScheme.primary;
    }
  }

  Future<void> _setResponseStatus(String statusKey) async {
    if (_currentUserId.isEmpty || _isUpdatingStatus) return;

    setState(() {
      _isUpdatingStatus = true;
    });

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId);

      await docRef.update({
        'acceptedUserIds': FieldValue.arrayRemove([_currentUserId]),
        'maybeUserIds': FieldValue.arrayRemove([_currentUserId]),
        'declinedUserIds': FieldValue.arrayRemove([_currentUserId]),
      });

      final Map<String, dynamic> updateData = {
        'updatedAt': FieldValue.serverTimestamp(),
      };

      switch (statusKey) {
        case 'accepted':
          updateData['acceptedUserIds'] = FieldValue.arrayUnion([_currentUserId]);
          break;
        case 'maybe':
          updateData['maybeUserIds'] = FieldValue.arrayUnion([_currentUserId]);
          break;
        case 'declined':
          updateData['declinedUserIds'] = FieldValue.arrayUnion([_currentUserId]);
          break;
        case 'clear':
          break;
      }

      await docRef.update(updateData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dein Event-Status wurde aktualisiert.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Status konnte nicht aktualisiert werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingStatus = false;
        });
      }
    }
  }

  Future<void> _deleteEvent() async {
    if (_isDeleting) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Event löschen'),
        content: const Text(
          'Möchtest du dieses Event wirklich löschen? Dieser Schritt kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    ) ??
        false;

    if (!shouldDelete) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .delete();

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Event wurde gelöscht.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Event konnte nicht gelöscht werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Future<void> _openEditPage() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateEventPage(eventId: widget.eventId),
      ),
    );

    if (result != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Das Event wurde aktualisiert.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Details'),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('events')
              .doc(widget.eventId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text('Fehler beim Laden des Events.'),
              );
            }

            final data = snapshot.data?.data();
            if (data == null) {
              return const Center(
                child: Text('Dieses Event wurde nicht gefunden.'),
              );
            }

            final title = (data['title'] ?? 'Event').toString().trim();
            final description = (data['description'] ?? '').toString().trim();
            final location = (data['location'] ?? '').toString().trim();
            final createdBy = (data['createdBy'] ?? '').toString().trim();
            final createdByName =
            (data['createdByName'] ?? 'Unbekannt').toString().trim();
            final rawType = (data['type'] ?? 'open').toString().trim();
            final eventDate = data['eventDate'] as Timestamp?;
            final invited = List<String>.from(data['invitedUserIds'] ?? const []);
            final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
            final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
            final declined = List<String>.from(data['declinedUserIds'] ?? const []);

            final pendingInvited = invited
                .where(
                  (id) =>
              !accepted.contains(id) &&
                  !maybe.contains(id) &&
                  !declined.contains(id),
            )
                .toList();

            final currentStatus = _currentUserStatus(data);
            final currentStatusColor =
            _statusColor(colorScheme, currentStatus);

            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.95),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
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
                                _formatHeaderDate(eventDate),
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
                              _formatTime(data),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor:
                                  colorScheme.primary.withValues(alpha: 0.10),
                                  child: Icon(
                                    Icons.celebration_outlined,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _eventTypeLabel(rawType),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        title,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                    currentStatusColor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    currentStatus,
                                    style:
                                    theme.textTheme.labelMedium?.copyWith(
                                      color: currentStatusColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _DetailChip(
                                  icon: Icons.event_outlined,
                                  label: _formatShortDate(eventDate),
                                ),
                                _DetailChip(
                                  icon: Icons.schedule_outlined,
                                  label: _formatTime(data),
                                ),
                                if (location.isNotEmpty)
                                  _DetailChip(
                                    icon: Icons.place_outlined,
                                    label: location,
                                  ),
                                _DetailChip(
                                  icon: Icons.person_outline,
                                  label: createdByName,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _DetailSection(
                  title: 'Beschreibung',
                  child: Text(
                    description.isEmpty
                        ? 'Für dieses Event wurde noch keine Beschreibung hinterlegt.'
                        : description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _DetailSection(
                  title: 'Teilnehmerstatus',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusCounterChip(
                        icon: Icons.mail_outline,
                        label: 'Einladungen',
                        count: invited.length,
                      ),
                      _StatusCounterChip(
                        icon: Icons.check_circle_outline,
                        label: 'Zugesagt',
                        count: accepted.length,
                        color: Colors.green,
                      ),
                      _StatusCounterChip(
                        icon: Icons.help_outline,
                        label: 'Vielleicht',
                        count: maybe.length,
                        color: Colors.orange,
                      ),
                      _StatusCounterChip(
                        icon: Icons.cancel_outlined,
                        label: 'Abgesagt',
                        count: declined.length,
                        color: colorScheme.error,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _ParticipantGroupsSection(
                  createdBy: createdBy,
                  createdByName: createdByName,
                  acceptedIds: accepted,
                  maybeIds: maybe,
                  pendingInvitedIds: pendingInvited,
                  declinedIds: declined,
                  currentUserId: _currentUserId,
                ),
                const SizedBox(height: 14),
                _buildActionSection(
                  context: context,
                  theme: theme,
                  colorScheme: colorScheme,
                  currentStatus: currentStatus,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildActionSection({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String currentStatus,
  }) {
    switch (widget.view) {
      case EventDetailView.myEvent:
        return _DetailSection(
          title: 'Aktionen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _openEditPage,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Event bearbeiten'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _isDeleting ? null : _deleteEvent,
                icon: _isDeleting
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.delete_outline),
                label: const Text('Event löschen'),
              ),
            ],
          ),
        );
      case EventDetailView.invitation:
        return _DetailSection(
          title: 'Deine Antwort',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ResponseButton(
                    label: 'Zusagen',
                    icon: Icons.check_circle_outline,
                    isSelected: currentStatus == 'Zugesagt',
                    color: Colors.green,
                    isLoading: _isUpdatingStatus,
                    onPressed: () => _setResponseStatus('accepted'),
                  ),
                  _ResponseButton(
                    label: 'Vielleicht',
                    icon: Icons.help_outline,
                    isSelected: currentStatus == 'Vielleicht',
                    color: Colors.orange,
                    isLoading: _isUpdatingStatus,
                    onPressed: () => _setResponseStatus('maybe'),
                  ),
                  _ResponseButton(
                    label: 'Absagen',
                    icon: Icons.cancel_outlined,
                    isSelected: currentStatus == 'Abgesagt',
                    color: colorScheme.error,
                    isLoading: _isUpdatingStatus,
                    onPressed: () => _setResponseStatus('declined'),
                  ),
                ],
              ),
            ],
          ),
        );
      case EventDetailView.openEvent:
        return _DetailSection(
          title: 'Teilnahme',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Du kannst Interesse zeigen oder direkt teilnehmen. Dein Status wird danach sofort in der Übersicht aktualisiert.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ResponseButton(
                    label: 'Interesse',
                    icon: Icons.favorite_border,
                    isSelected: currentStatus == 'Vielleicht',
                    color: Colors.orange,
                    isLoading: _isUpdatingStatus,
                    onPressed: () => _setResponseStatus('maybe'),
                  ),
                  _ResponseButton(
                    label: 'Teilnehmen',
                    icon: Icons.check_circle_outline,
                    isSelected: currentStatus == 'Zugesagt',
                    color: Colors.green,
                    isLoading: _isUpdatingStatus,
                    onPressed: () => _setResponseStatus('accepted'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isUpdatingStatus
                        ? null
                        : () => _setResponseStatus('clear'),
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Zurücksetzen'),
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }
}

class _ParticipantGroupsSection extends StatelessWidget {
  final String createdBy;
  final String createdByName;
  final List<String> acceptedIds;
  final List<String> maybeIds;
  final List<String> pendingInvitedIds;
  final List<String> declinedIds;
  final String currentUserId;

  const _ParticipantGroupsSection({
    required this.createdBy,
    required this.createdByName,
    required this.acceptedIds,
    required this.maybeIds,
    required this.pendingInvitedIds,
    required this.declinedIds,
    required this.currentUserId,
  });

  Future<Map<String, String>> _loadNames(Set<String> ids) async {
    final result = <String, String>{};

    for (final id in ids) {
      if (id.trim().isEmpty) continue;
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
        final data = doc.data() ?? <String, dynamic>{};
        final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        result[id] = name.isEmpty ? 'Unbekannt' : name;
      } catch (_) {
        result[id] = 'Unbekannt';
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final idsToLoad = <String>{
      createdBy,
      ...acceptedIds,
      ...maybeIds,
      ...pendingInvitedIds,
      ...declinedIds,
    }..removeWhere((id) => id.trim().isEmpty);

    return FutureBuilder<Map<String, String>>(
      future: _loadNames(idsToLoad),
      builder: (context, snapshot) {
        final loadedNames = snapshot.data ?? <String, String>{};
        final resolvedCreatorName = createdByName.isNotEmpty
            ? createdByName
            : (loadedNames[createdBy] ?? 'Unbekannt');

        return _DetailSection(
          title: 'Teilnehmer & Einladungen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ParticipantGroup(
                title: 'Veranstalter',
                emptyLabel: 'Kein Veranstalter hinterlegt.',
                people: [
                  _ParticipantItemData(
                    name: resolvedCreatorName,
                    status: 'Veranstalter',
                    isCurrentUser: createdBy == currentUserId,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Zugesagt',
                emptyLabel: 'Noch keine Zusagen.',
                people: acceptedIds
                    .map(
                      (id) => _ParticipantItemData(
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Zugesagt',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Vielleicht',
                emptyLabel: 'Noch keine Interessenten.',
                people: maybeIds
                    .map(
                      (id) => _ParticipantItemData(
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Vielleicht',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Eingeladen',
                emptyLabel: 'Aktuell keine offenen Einladungen.',
                people: pendingInvitedIds
                    .map(
                      (id) => _ParticipantItemData(
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Eingeladen',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Abgesagt',
                emptyLabel: 'Bisher keine Absagen.',
                people: declinedIds
                    .map(
                      (id) => _ParticipantItemData(
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Abgesagt',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ParticipantItemData {
  final String name;
  final String status;
  final bool isCurrentUser;

  const _ParticipantItemData({
    required this.name,
    required this.status,
    required this.isCurrentUser,
  });
}

class _ParticipantGroup extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final List<_ParticipantItemData> people;

  const _ParticipantGroup({
    required this.title,
    required this.emptyLabel,
    required this.people,
  });

  Color _badgeColor(BuildContext context, String status) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (status) {
      case 'Veranstalter':
      case 'Eingeladen':
        return colorScheme.primary;
      case 'Zugesagt':
        return Colors.green;
      case 'Vielleicht':
        return Colors.orange;
      case 'Abgesagt':
        return colorScheme.error;
      default:
        return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (people.isEmpty)
          Text(
            emptyLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...people.map(
                (person) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: colorScheme.primary.withValues(alpha: 0.10),
                      child: Text(
                        person.name.isNotEmpty
                            ? person.name.characters.first.toUpperCase()
                            : '?',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        person.isCurrentUser
                            ? '${person.name} (Du)'
                            : person.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _badgeColor(context, person.status)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        person.status,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: _badgeColor(context, person.status),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
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

class _StatusCounterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color? color;

  const _StatusCounterChip({
    required this.icon,
    required this.label,
    required this.count,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedColor = color ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: resolvedColor),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
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

class _ResponseButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final bool isLoading;
  final VoidCallback onPressed;

  const _ResponseButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: isSelected ? color : color.withValues(alpha: 0.10),
        foregroundColor: isSelected ? Colors.white : color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: isLoading && isSelected
          ? const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      )
          : Icon(icon),
      label: Text(label),
    );
  }
}
