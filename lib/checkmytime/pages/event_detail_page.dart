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
  bool _isModeratingRequest = false;
  String _moderatingUserId = '';

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  Timestamp? _scheduledTimestamp(Map<String, dynamic> data) {
    return data['scheduledAt'] as Timestamp? ?? data['eventDate'] as Timestamp?;
  }

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

    final scheduledAt = _scheduledTimestamp(data)?.toDate();
    if (scheduledAt != null &&
        (scheduledAt.hour != 0 || scheduledAt.minute != 0)) {
      return DateFormat('HH:mm', 'de_DE').format(scheduledAt);
    }

    return 'Ganztägig';
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

  String _overallStatus(Map<String, dynamic> data) {
    final raw = (data['status'] ?? '').toString().trim();
    if (raw.isEmpty) return 'pending';
    return raw;
  }

  String _responseForUser(Map<String, dynamic> data, String userId) {
    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    final mapped = (responseMap[userId] ?? '').toString().trim();
    if (mapped.isNotEmpty) return mapped;

    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);

    if (accepted.contains(userId)) return 'accepted';
    if (maybe.contains(userId)) return 'maybe';
    if (declined.contains(userId)) return 'declined';
    return 'pending';
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

  _ParticipantBuckets _participantBuckets(Map<String, dynamic> data) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final memberIds = <String>{
      ...List<String>.from(data['memberIds'] ?? const []),
      ...List<String>.from(data['invitedUserIds'] ?? const []),
      ...List<String>.from(data['participantIds'] ?? const []),
      createdBy,
    }..removeWhere((id) => id.trim().isEmpty);

    final accepted = <String>{};
    final maybe = <String>{};
    final declined = <String>{};
    final pending = <String>{};

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );

    if (responseMap.isNotEmpty) {
      for (final entry in responseMap.entries) {
        final userId = entry.key.trim();
        if (userId.isEmpty) continue;
        memberIds.add(userId);
        switch (entry.value.toString().trim()) {
          case 'accepted':
            accepted.add(userId);
            break;
          case 'maybe':
            maybe.add(userId);
            break;
          case 'declined':
            declined.add(userId);
            break;
          case 'pending':
          default:
            pending.add(userId);
            break;
        }
      }
    } else {
      accepted.addAll(List<String>.from(data['acceptedUserIds'] ?? const []));
      maybe.addAll(List<String>.from(data['maybeUserIds'] ?? const []));
      declined.addAll(List<String>.from(data['declinedUserIds'] ?? const []));
      pending.addAll(List<String>.from(data['invitedUserIds'] ?? const []));
    }

    accepted.remove(createdBy);
    maybe.remove(createdBy);
    declined.remove(createdBy);
    pending.remove(createdBy);

    pending.removeAll(accepted);
    pending.removeAll(maybe);
    pending.removeAll(declined);

    return _ParticipantBuckets(
      accepted: accepted.toList()..sort(),
      maybe: maybe.toList()..sort(),
      pending: pending.toList()..sort(),
      declined: declined.toList()..sort(),
    );
  }

  String _currentHeaderStatus(Map<String, dynamic> data) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy == _currentUserId) {
      return _overallStatus(data);
    }
    return _responseForUser(data, _currentUserId);
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
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      final accepted = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
      };
      final maybe = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      };
      final declined = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      };
      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      );

      accepted.remove(_currentUserId);
      maybe.remove(_currentUserId);
      declined.remove(_currentUserId);

      switch (statusKey) {
        case 'accepted':
          accepted.add(_currentUserId);
          responseMap[_currentUserId] = 'accepted';
          break;
        case 'maybe':
          maybe.add(_currentUserId);
          responseMap[_currentUserId] = 'maybe';
          break;
        case 'declined':
          declined.add(_currentUserId);
          responseMap[_currentUserId] = 'declined';
          break;
        case 'clear':
        default:
          responseMap[_currentUserId] = 'pending';
          break;
      }

      final participantIds = <String>{createdBy, ...accepted}
        ..removeWhere((id) => id.trim().isEmpty);

      await docRef.update({
        'acceptedUserIds': accepted.toList(),
        'maybeUserIds': maybe.toList(),
        'declinedUserIds': declined.toList(),
        'participantIds': participantIds.toList(),
        'responseMap': responseMap,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dein Status wurde aktualisiert.'),
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

  Future<void> _setOwnerParticipantStatus({
    required String userId,
    required String statusKey,
  }) async {
    if (userId.trim().isEmpty || _isModeratingRequest) return;

    setState(() {
      _isModeratingRequest = true;
      _moderatingUserId = userId;
    });

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      final accepted = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
      };
      final maybe = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      };
      final declined = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      };
      final memberIds = <String>{
        ...List<String>.from(data['memberIds'] ?? const []),
      };
      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      );

      accepted.remove(userId);
      maybe.remove(userId);
      declined.remove(userId);
      memberIds.remove(userId);

      switch (statusKey) {
        case 'accepted':
          accepted.add(userId);
          memberIds.add(userId);
          responseMap[userId] = 'accepted';
          break;
        case 'declined':
          declined.add(userId);
          responseMap[userId] = 'declined';
          break;
        default:
          responseMap[userId] = 'pending';
          break;
      }

      final participantIds = <String>{createdBy, ...accepted}
        ..removeWhere((id) => id.trim().isEmpty);

      await docRef.update({
        'acceptedUserIds': accepted.toList(),
        'maybeUserIds': maybe.toList(),
        'declinedUserIds': declined.toList(),
        'memberIds': memberIds.toList(),
        'participantIds': participantIds.toList(),
        'responseMap': responseMap,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      final wasAccepted = statusKey == 'accepted';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasAccepted
                ? 'Die Anfrage wurde bestätigt.'
                : 'Die Anfrage wurde abgelehnt.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Anfrage konnte nicht aktualisiert werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isModeratingRequest = false;
          _moderatingUserId = '';
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
        title: const Text('Event-Details'),
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
            final location =
            (data['locationText'] ?? data['location'] ?? '').toString().trim();
            final createdBy = (data['createdBy'] ?? '').toString().trim();
            final createdByName =
            (data['createdByName'] ?? 'Unbekannt').toString().trim();
            final scheduledAt = _scheduledTimestamp(data);
            final kindLabel = _kindLabel(data);
            final kindColor = _kindColor(colorScheme, data);
            final rawHeaderStatus = _currentHeaderStatus(data);
            final statusLabel = _statusLabel(rawHeaderStatus);
            final statusColor = _statusColor(colorScheme, rawHeaderStatus);
            final participantBuckets = _participantBuckets(data);
            final currentUserResponse = _responseForUser(data, _currentUserId);
            final isOwner = createdBy == _currentUserId;

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
                                _formatHeaderDate(scheduledAt),
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
                                  kindColor.withValues(alpha: 0.10),
                                  child: Icon(
                                    Icons.celebration_outlined,
                                    color: kindColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: kindColor.withValues(
                                                alpha: 0.10,
                                              ),
                                              borderRadius:
                                              BorderRadius.circular(999),
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
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                alpha: 0.10,
                                              ),
                                              borderRadius:
                                              BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              statusLabel,
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                color: statusColor,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        title,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (description.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          description,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color:
                                            colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
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
                                  label: _formatShortDate(scheduledAt),
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
                                  label: createdByName.isEmpty
                                      ? 'Unbekannt'
                                      : createdByName,
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
                  title: 'Teilnehmerstatus',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusCounterChip(
                        icon: Icons.check_circle_outline,
                        label: 'Bestätigt',
                        count: participantBuckets.accepted.length,
                        color: Colors.green,
                      ),
                      _StatusCounterChip(
                        icon: Icons.help_outline,
                        label: 'Vielleicht',
                        count: participantBuckets.maybe.length,
                        color: Colors.orange,
                      ),
                      _StatusCounterChip(
                        icon: Icons.mail_outline,
                        label: 'Ausstehend',
                        count: participantBuckets.pending.length,
                      ),
                      _StatusCounterChip(
                        icon: Icons.cancel_outlined,
                        label: 'Abgelehnt',
                        count: participantBuckets.declined.length,
                        color: colorScheme.error,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _ParticipantGroupsSection(
                  createdBy: createdBy,
                  createdByName: createdByName,
                  acceptedIds: participantBuckets.accepted,
                  maybeIds: participantBuckets.maybe,
                  pendingIds: participantBuckets.pending,
                  declinedIds: participantBuckets.declined,
                  currentUserId: _currentUserId,
                  isOwner: isOwner,
                  moderatingUserId: _moderatingUserId,
                  onAcceptPending: (userId) => _setOwnerParticipantStatus(
                    userId: userId,
                    statusKey: 'accepted',
                  ),
                  onDeclinePending: (userId) => _setOwnerParticipantStatus(
                    userId: userId,
                    statusKey: 'declined',
                  ),
                ),
                const SizedBox(height: 14),
                _buildActionSection(
                  context: context,
                  theme: theme,
                  colorScheme: colorScheme,
                  currentUserResponse: currentUserResponse,
                  isOwner: isOwner,
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
    required String currentUserResponse,
    required bool isOwner,
  }) {
    if (isOwner) {
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
    }

    return _DetailSection(
      title: 'Deine Antwort',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Du kannst hier direkt zusagen, vielleicht markieren oder absagen. Deine Antwort wird sofort in den Übersichten aktualisiert.',
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
                icon: Icons.check_circle_outline,
                isSelected: currentUserResponse == 'accepted',
                color: Colors.green,
                isLoading: _isUpdatingStatus,
                onPressed: () => _setResponseStatus('accepted'),
              ),
              _ResponseButton(
                label: 'Vielleicht',
                icon: Icons.help_outline,
                isSelected: currentUserResponse == 'maybe',
                color: Colors.orange,
                isLoading: _isUpdatingStatus,
                onPressed: () => _setResponseStatus('maybe'),
              ),
              _ResponseButton(
                label: 'Absagen',
                icon: Icons.cancel_outlined,
                isSelected: currentUserResponse == 'declined',
                color: colorScheme.error,
                isLoading: _isUpdatingStatus,
                onPressed: () => _setResponseStatus('declined'),
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

class _ParticipantBuckets {
  final List<String> accepted;
  final List<String> maybe;
  final List<String> pending;
  final List<String> declined;

  const _ParticipantBuckets({
    required this.accepted,
    required this.maybe,
    required this.pending,
    required this.declined,
  });
}

class _ParticipantGroupsSection extends StatelessWidget {
  final String createdBy;
  final String createdByName;
  final List<String> acceptedIds;
  final List<String> maybeIds;
  final List<String> pendingIds;
  final List<String> declinedIds;
  final String currentUserId;
  final bool isOwner;
  final String moderatingUserId;
  final ValueChanged<String> onAcceptPending;
  final ValueChanged<String> onDeclinePending;

  const _ParticipantGroupsSection({
    required this.createdBy,
    required this.createdByName,
    required this.acceptedIds,
    required this.maybeIds,
    required this.pendingIds,
    required this.declinedIds,
    required this.currentUserId,
    required this.isOwner,
    required this.moderatingUserId,
    required this.onAcceptPending,
    required this.onDeclinePending,
  });

  Future<Map<String, String>> _loadNames(Set<String> ids) async {
    final result = <String, String>{};

    for (final id in ids) {
      if (id.trim().isEmpty) continue;
      try {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(id).get();
        final data = doc.data() ?? <String, dynamic>{};
        final name =
        (data['displayName'] ?? data['name'] ?? '').toString().trim();
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
      ...pendingIds,
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
          title: 'Teilnehmer & Antworten',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ParticipantGroup(
                title: 'Erstellt von',
                emptyLabel: 'Kein Ersteller hinterlegt.',
                people: [
                  _ParticipantItemData(
                    id: createdBy,
                    name: resolvedCreatorName,
                    status: 'Ersteller',
                    isCurrentUser: createdBy == currentUserId,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Bestätigt',
                emptyLabel: 'Noch keine Bestätigungen.',
                people: acceptedIds
                    .map(
                      (id) => _ParticipantItemData(
                    id: id,
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Bestätigt',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Vielleicht',
                emptyLabel: 'Noch keine Vielleicht-Antworten.',
                people: maybeIds
                    .map(
                      (id) => _ParticipantItemData(
                    id: id,
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Vielleicht',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: isOwner ? 'Anfragen' : 'Ausstehend',
                emptyLabel: isOwner
                    ? 'Aktuell liegen keine offenen Anfragen vor.'
                    : 'Keine offenen Antworten.',
                people: pendingIds
                    .map(
                      (id) => _ParticipantItemData(
                    id: id,
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Ausstehend',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
                showOwnerActions: isOwner,
                moderatingUserId: moderatingUserId,
                onAccept: onAcceptPending,
                onDecline: onDeclinePending,
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Abgelehnt',
                emptyLabel: 'Bisher keine Ablehnungen.',
                people: declinedIds
                    .map(
                      (id) => _ParticipantItemData(
                    id: id,
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Abgelehnt',
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
  final String id;
  final String name;
  final String status;
  final bool isCurrentUser;

  const _ParticipantItemData({
    required this.id,
    required this.name,
    required this.status,
    required this.isCurrentUser,
  });
}

class _ParticipantGroup extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final List<_ParticipantItemData> people;
  final bool showOwnerActions;
  final String moderatingUserId;
  final ValueChanged<String>? onAccept;
  final ValueChanged<String>? onDecline;

  const _ParticipantGroup({
    required this.title,
    required this.emptyLabel,
    required this.people,
    this.showOwnerActions = false,
    this.moderatingUserId = '',
    this.onAccept,
    this.onDecline,
  });

  Color _badgeColor(BuildContext context, String status) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (status) {
      case 'Ersteller':
      case 'Ausstehend':
        return colorScheme.primary;
      case 'Bestätigt':
        return Colors.green;
      case 'Vielleicht':
        return Colors.orange;
      case 'Abgelehnt':
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                      colorScheme.primary.withValues(alpha: 0.10),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                          if (showOwnerActions && person.status == 'Ausstehend') ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: moderatingUserId == person.id
                                      ? null
                                      : () => onDecline?.call(person.id),
                                  icon: moderatingUserId == person.id
                                      ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : const Icon(Icons.close_rounded),
                                  label: const Text('Ablehnen'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colorScheme.error,
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: moderatingUserId == person.id
                                      ? null
                                      : () => onAccept?.call(person.id),
                                  icon: moderatingUserId == person.id
                                      ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                      : const Icon(Icons.check_rounded),
                                  label: const Text('Bestätigen'),
                                ),
                              ],
                            ),
                          ],
                        ],
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
