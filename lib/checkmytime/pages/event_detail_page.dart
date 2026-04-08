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

  String _userStatus(Map<String, dynamic> data) {
    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);

    if (accepted.contains(_currentUserId)) return 'Zugesagt';
    if (maybe.contains(_currentUserId)) return 'Vielleicht';
    if (declined.contains(_currentUserId)) return 'Abgesagt';

    if (widget.view == EventDetailView.myEvent) return 'Geplant';
    if (widget.view == EventDetailView.openEvent) return 'Offen';
    return 'Eingeladen';
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
      case 'Offen':
      case 'Eingeladen':
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
      await FirebaseFirestore.instance.collection('events').doc(widget.eventId).update({
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
      }

      await FirebaseFirestore.instance.collection('events').doc(widget.eventId).update(updateData);

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
      if (!mounted) return;
      setState(() {
        _isUpdatingStatus = false;
      });
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
      await FirebaseFirestore.instance.collection('events').doc(widget.eventId).delete();
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
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
      });
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

  Future<List<_ParticipantItem>> _loadParticipants(Map<String, dynamic> data) async {
    final firestore = FirebaseFirestore.instance;

    final createdById = (data['createdBy'] ?? '').toString().trim();
    final createdByName = (data['createdByName'] ?? 'Unbekannt').toString().trim();

    final invited = List<String>.from(data['invitedUserIds'] ?? const []);
    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);

    final allIds = <String>{
      if (createdById.isNotEmpty) createdById,
      ...invited,
      ...accepted,
      ...maybe,
      ...declined,
    };

    final participants = <_ParticipantItem>[];

    for (final userId in allIds) {
      try {
        final userDoc = await firestore.collection('users').doc(userId).get();
        final userData = userDoc.data() ?? <String, dynamic>{};

        final fallbackName = userId == createdById ? createdByName : 'Unbekannt';
        final name = (userData['displayName'] ?? userData['name'] ?? fallbackName)
            .toString()
            .trim();
        final phone = (userData['phoneNumber'] ?? '').toString().trim();
        final imageUrl = (userData['profileImageUrl'] ?? '').toString().trim();

        participants.add(
          _ParticipantItem(
            id: userId,
            name: name.isEmpty ? fallbackName : name,
            phone: phone,
            imageUrl: imageUrl,
            status: _resolveParticipantStatus(
              userId: userId,
              createdById: createdById,
              invited: invited,
              accepted: accepted,
              maybe: maybe,
              declined: declined,
            ),
          ),
        );
      } catch (_) {
        participants.add(
          _ParticipantItem(
            id: userId,
            name: userId == createdById && createdByName.isNotEmpty
                ? createdByName
                : 'Unbekannt',
            phone: '',
            imageUrl: '',
            status: _resolveParticipantStatus(
              userId: userId,
              createdById: createdById,
              invited: invited,
              accepted: accepted,
              maybe: maybe,
              declined: declined,
            ),
          ),
        );
      }
    }

    participants.sort((a, b) {
      if (a.status == _ParticipantStatus.organizer &&
          b.status != _ParticipantStatus.organizer) {
        return -1;
      }
      if (b.status == _ParticipantStatus.organizer &&
          a.status != _ParticipantStatus.organizer) {
        return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return participants;
  }

  _ParticipantStatus _resolveParticipantStatus({
    required String userId,
    required String createdById,
    required List<String> invited,
    required List<String> accepted,
    required List<String> maybe,
    required List<String> declined,
  }) {
    if (userId == createdById) return _ParticipantStatus.organizer;
    if (accepted.contains(userId)) return _ParticipantStatus.accepted;
    if (maybe.contains(userId)) return _ParticipantStatus.maybe;
    if (declined.contains(userId)) return _ParticipantStatus.declined;
    if (invited.contains(userId)) return _ParticipantStatus.invited;
    return _ParticipantStatus.invited;
  }

  Color _participantStatusColor(
      ColorScheme colorScheme,
      _ParticipantStatus status,
      ) {
    switch (status) {
      case _ParticipantStatus.organizer:
        return colorScheme.primary;
      case _ParticipantStatus.accepted:
        return Colors.green;
      case _ParticipantStatus.maybe:
        return Colors.orange;
      case _ParticipantStatus.declined:
        return colorScheme.error;
      case _ParticipantStatus.invited:
        return colorScheme.secondary;
    }
  }

  String _participantStatusLabel(_ParticipantStatus status) {
    switch (status) {
      case _ParticipantStatus.organizer:
        return 'Veranstalter';
      case _ParticipantStatus.accepted:
        return 'Zugesagt';
      case _ParticipantStatus.maybe:
        return 'Vielleicht';
      case _ParticipantStatus.declined:
        return 'Abgesagt';
      case _ParticipantStatus.invited:
        return 'Eingeladen';
    }
  }

  IconData _participantStatusIcon(_ParticipantStatus status) {
    switch (status) {
      case _ParticipantStatus.organizer:
        return Icons.star_outline;
      case _ParticipantStatus.accepted:
        return Icons.check_circle_outline;
      case _ParticipantStatus.maybe:
        return Icons.help_outline;
      case _ParticipantStatus.declined:
        return Icons.cancel_outlined;
      case _ParticipantStatus.invited:
        return Icons.mail_outline;
    }
  }

  Widget _buildParticipantsSection({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required Map<String, dynamic> data,
    required int invitedCount,
    required int acceptedCount,
    required int maybeCount,
    required int declinedCount,
  }) {
    return _DetailSection(
      title: 'Teilnehmer & Einladungen',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusCounterChip(
                icon: Icons.mail_outline,
                label: 'Einladungen',
                count: invitedCount,
              ),
              _StatusCounterChip(
                icon: Icons.check_circle_outline,
                label: 'Zugesagt',
                count: acceptedCount,
                color: Colors.green,
              ),
              _StatusCounterChip(
                icon: Icons.help_outline,
                label: 'Vielleicht',
                count: maybeCount,
                color: Colors.orange,
              ),
              _StatusCounterChip(
                icon: Icons.cancel_outlined,
                label: 'Abgesagt',
                count: declinedCount,
                color: colorScheme.error,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<_ParticipantItem>>(
            future: _loadParticipants(data),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final participants = snapshot.data ?? const <_ParticipantItem>[];
              if (participants.isEmpty) {
                return Text(
                  'Für dieses Event wurden noch keine Personen hinterlegt.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              }

              final organizer = participants
                  .where((item) => item.status == _ParticipantStatus.organizer)
                  .toList();
              final accepted = participants
                  .where((item) => item.status == _ParticipantStatus.accepted)
                  .toList();
              final maybe = participants
                  .where((item) => item.status == _ParticipantStatus.maybe)
                  .toList();
              final invited = participants
                  .where((item) => item.status == _ParticipantStatus.invited)
                  .toList();
              final declined = participants
                  .where((item) => item.status == _ParticipantStatus.declined)
                  .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (organizer.isNotEmpty) ...[
                    _ParticipantGroup(
                      title: 'Veranstalter',
                      items: organizer,
                      theme: theme,
                      colorScheme: colorScheme,
                      statusLabel: _participantStatusLabel,
                      statusColor: _participantStatusColor,
                      statusIcon: _participantStatusIcon,
                      currentUserId: _currentUserId,
                    ),
                  ],
                  if (accepted.isNotEmpty) ...[
                    if (organizer.isNotEmpty) const SizedBox(height: 14),
                    _ParticipantGroup(
                      title: 'Zugesagt',
                      items: accepted,
                      theme: theme,
                      colorScheme: colorScheme,
                      statusLabel: _participantStatusLabel,
                      statusColor: _participantStatusColor,
                      statusIcon: _participantStatusIcon,
                      currentUserId: _currentUserId,
                    ),
                  ],
                  if (maybe.isNotEmpty) ...[
                    if (organizer.isNotEmpty || accepted.isNotEmpty)
                      const SizedBox(height: 14),
                    _ParticipantGroup(
                      title: 'Vielleicht',
                      items: maybe,
                      theme: theme,
                      colorScheme: colorScheme,
                      statusLabel: _participantStatusLabel,
                      statusColor: _participantStatusColor,
                      statusIcon: _participantStatusIcon,
                      currentUserId: _currentUserId,
                    ),
                  ],
                  if (invited.isNotEmpty) ...[
                    if (organizer.isNotEmpty ||
                        accepted.isNotEmpty ||
                        maybe.isNotEmpty)
                      const SizedBox(height: 14),
                    _ParticipantGroup(
                      title: 'Eingeladen',
                      items: invited,
                      theme: theme,
                      colorScheme: colorScheme,
                      statusLabel: _participantStatusLabel,
                      statusColor: _participantStatusColor,
                      statusIcon: _participantStatusIcon,
                      currentUserId: _currentUserId,
                    ),
                  ],
                  if (declined.isNotEmpty) ...[
                    if (organizer.isNotEmpty ||
                        accepted.isNotEmpty ||
                        maybe.isNotEmpty ||
                        invited.isNotEmpty)
                      const SizedBox(height: 14),
                    _ParticipantGroup(
                      title: 'Abgesagt',
                      items: declined,
                      theme: theme,
                      colorScheme: colorScheme,
                      statusLabel: _participantStatusLabel,
                      statusColor: _participantStatusColor,
                      statusIcon: _participantStatusIcon,
                      currentUserId: _currentUserId,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
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
            final createdByName =
            (data['createdByName'] ?? 'Unbekannt').toString().trim();
            final rawType = (data['type'] ?? 'open').toString().trim();
            final eventDate = data['eventDate'] as Timestamp?;
            final invited = List<String>.from(data['invitedUserIds'] ?? const []);
            final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
            final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
            final declined = List<String>.from(data['declinedUserIds'] ?? const []);

            final userStatus = _userStatus(data);
            final userStatusColor = _statusColor(colorScheme, userStatus);

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
                          color: colorScheme.primary.withOpacity(0.95),
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
                                  colorScheme.primary.withOpacity(0.10),
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
                                        _eventTypeLabel(rawType),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        title,
                                        style: theme.textTheme.headlineSmall?.copyWith(
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
                                    color: userStatusColor.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    userStatus,
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: userStatusColor,
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
                _buildParticipantsSection(
                  theme: theme,
                  colorScheme: colorScheme,
                  data: data,
                  invitedCount: invited.length,
                  acceptedCount: accepted.length,
                  maybeCount: maybe.length,
                  declinedCount: declined.length,
                ),
                const SizedBox(height: 14),
                _buildActionSection(
                  context: context,
                  theme: theme,
                  colorScheme: colorScheme,
                  currentStatus: userStatus,
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
              Text(
                'Du kannst auf diese Einladung direkt reagieren.',
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
                    label: 'Zusagen',
                    icon: Icons.check,
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
                    icon: Icons.close,
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
                'Du kannst Interesse zeigen oder direkt teilnehmen.',
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
                ],
              ),
            ],
          ),
        );
    }
  }
}

enum _ParticipantStatus {
  organizer,
  accepted,
  maybe,
  invited,
  declined,
}

class _ParticipantItem {
  final String id;
  final String name;
  final String phone;
  final String imageUrl;
  final _ParticipantStatus status;

  const _ParticipantItem({
    required this.id,
    required this.name,
    required this.phone,
    required this.imageUrl,
    required this.status,
  });
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: resolvedColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolvedColor),
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

class _ParticipantGroup extends StatelessWidget {
  final String title;
  final List<_ParticipantItem> items;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final String Function(_ParticipantStatus status) statusLabel;
  final Color Function(ColorScheme colorScheme, _ParticipantStatus status)
  statusColor;
  final IconData Function(_ParticipantStatus status) statusIcon;
  final String currentUserId;

  const _ParticipantGroup({
    required this.title,
    required this.items,
    required this.theme,
    required this.colorScheme,
    required this.statusLabel,
    required this.statusColor,
    required this.statusIcon,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${items.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...items.map(
              (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ParticipantTile(
              item: item,
              isCurrentUser: item.id == currentUserId,
              theme: theme,
              colorScheme: colorScheme,
              statusLabel: statusLabel(item.status),
              resolvedStatusColor: statusColor(colorScheme, item.status),
              statusIcon: statusIcon(item.status),
            ),
          ),
        ),
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final _ParticipantItem item;
  final bool isCurrentUser;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final String statusLabel;
  final Color resolvedStatusColor;
  final IconData statusIcon;

  const _ParticipantTile({
    required this.item,
    required this.isCurrentUser,
    required this.theme,
    required this.colorScheme,
    required this.statusLabel,
    required this.resolvedStatusColor,
    required this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];

    if (isCurrentUser) {
      subtitleParts.add('Du');
    }

    if (item.phone.isNotEmpty) {
      subtitleParts.add(item.phone);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: colorScheme.primary.withOpacity(0.10),
            backgroundImage:
            item.imageUrl.isNotEmpty ? NetworkImage(item.imageUrl) : null,
            child: item.imageUrl.isEmpty
                ? Icon(Icons.person_outline, color: colorScheme.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitleParts.join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: resolvedStatusColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: resolvedStatusColor),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: resolvedStatusColor,
                    fontWeight: FontWeight.w700,
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
    if (isSelected) {
      return FilledButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : Icon(icon),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
        label: Text(label),
      );
    }

    return OutlinedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: Icon(icon, color: color),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.35)),
      ),
      label: Text(label),
    );
  }
}
