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
  final Set<String> _updatingEventIds = <String>{};

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

  bool _isEventUpdating(String eventId) => _updatingEventIds.contains(eventId);

  void _setEventUpdating(String eventId, bool isUpdating) {
    if (!mounted || eventId.trim().isEmpty) return;
    setState(() {
      if (isUpdating) {
        _updatingEventIds.add(eventId);
      } else {
        _updatingEventIds.remove(eventId);
      }
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
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


  bool _hasExistingResponseEntry(Map<String, dynamic> data, String userId) {
    if (userId.trim().isEmpty) return false;

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    if (responseMap.containsKey(userId)) return true;

    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);
    final invited = List<String>.from(data['invitedUserIds'] ?? const []);
    final memberIds = List<String>.from(data['memberIds'] ?? const []);
    final participantIds = List<String>.from(data['participantIds'] ?? const []);

    return accepted.contains(userId) ||
        maybe.contains(userId) ||
        declined.contains(userId) ||
        invited.contains(userId) ||
        memberIds.contains(userId) ||
        participantIds.contains(userId);
  }

  int? _maxParticipants(Map<String, dynamic> data) {
    final rawMax = data['maxParticipants'];
    if (rawMax is int) return rawMax;
    return int.tryParse((rawMax ?? '').toString().trim());
  }

  bool _hasFreeSpots(Map<String, dynamic> data) {
    if (data['hasParticipantLimit'] != true) return true;
    final maxParticipants = _maxParticipants(data);
    if (maxParticipants == null || maxParticipants <= 0) return true;
    return _acceptedCount(data) < maxParticipants;
  }

  Future<void> _sendJoinRequest(String eventId, String userId) async {
    if (userId.trim().isEmpty || _isEventUpdating(eventId)) return;
    _setEventUpdating(eventId, true);

    try {
      final docRef = FirebaseFirestore.instance.collection('events').doc(eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final memberIds = <String>{
        ...List<String>.from(data['memberIds'] ?? const []),
      }..add(userId);

      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      )..[userId] = 'pending';

      final accepted = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
      }..remove(userId);

      final maybe = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      }..remove(userId);

      final declined = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      }..remove(userId);

      final participantIds = <String>{
        ...List<String>.from(data['participantIds'] ?? const []),
      }..remove(userId);

      await docRef.update({
        'memberIds': memberIds.toList(),
        'responseMap': responseMap,
        'acceptedUserIds': accepted.toList(),
        'maybeUserIds': maybe.toList(),
        'declinedUserIds': declined.toList(),
        'participantIds': participantIds.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _showSnack('Deine Anfrage wurde gesendet.');
    } catch (_) {
      _showSnack('Die Anfrage konnte nicht gesendet werden.');
    } finally {
      _setEventUpdating(eventId, false);
    }
  }

  Future<void> _joinDirectly(String eventId, String userId) async {
    if (userId.trim().isEmpty || _isEventUpdating(eventId)) return;
    _setEventUpdating(eventId, true);

    try {
      final docRef = FirebaseFirestore.instance.collection('events').doc(eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      if (!_hasFreeSpots(data)) {
        _showSnack('Für dieses Event sind aktuell keine Plätze frei.');
        return;
      }

      final createdBy = (data['createdBy'] ?? '').toString().trim();

      final memberIds = <String>{
        ...List<String>.from(data['memberIds'] ?? const []),
        userId,
      };

      final accepted = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
        userId,
      };

      final maybe = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      }..remove(userId);

      final declined = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      }..remove(userId);

      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      )..[userId] = 'accepted';

      final participantIds = <String>{
        ...List<String>.from(data['participantIds'] ?? const []),
        createdBy,
        userId,
      }..removeWhere((id) => id.trim().isEmpty);

      await docRef.update({
        'memberIds': memberIds.toList(),
        'acceptedUserIds': accepted.toList(),
        'maybeUserIds': maybe.toList(),
        'declinedUserIds': declined.toList(),
        'participantIds': participantIds.toList(),
        'responseMap': responseMap,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _showSnack('Du bist jetzt dabei.');
    } catch (_) {
      _showSnack('Der Beitritt konnte nicht durchgeführt werden.');
    } finally {
      _setEventUpdating(eventId, false);
    }
  }

  Future<void> _withdrawRequest(String eventId, String userId) async {
    if (userId.trim().isEmpty || _isEventUpdating(eventId)) return;
    _setEventUpdating(eventId, true);

    try {
      final docRef = FirebaseFirestore.instance.collection('events').doc(eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final memberIds = <String>{
        ...List<String>.from(data['memberIds'] ?? const []),
      }..remove(userId);

      final accepted = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
      }..remove(userId);

      final maybe = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      }..remove(userId);

      final declined = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      }..remove(userId);

      final participantIds = <String>{
        ...List<String>.from(data['participantIds'] ?? const []),
      }..remove(userId);

      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      )..remove(userId);

      await docRef.update({
        'memberIds': memberIds.toList(),
        'acceptedUserIds': accepted.toList(),
        'maybeUserIds': maybe.toList(),
        'declinedUserIds': declined.toList(),
        'participantIds': participantIds.toList(),
        'responseMap': responseMap,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _showSnack('Deine Anfrage wurde zurückgezogen.');
    } catch (_) {
      _showSnack('Die Anfrage konnte nicht zurückgezogen werden.');
    } finally {
      _setEventUpdating(eventId, false);
    }
  }

  Future<void> _setResponseStatus({
    required String eventId,
    required String userId,
    required String statusKey,
  }) async {
    if (userId.trim().isEmpty || _isEventUpdating(eventId)) return;
    _setEventUpdating(eventId, true);

    try {
      final docRef = FirebaseFirestore.instance.collection('events').doc(eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      final joinMode = _normalizeJoinMode(data);
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
      final previousStatus = _responseForUser(data, userId);

      if (joinMode == 'request' &&
          previousStatus == 'declined' &&
          statusKey == 'accepted') {
        _showSnack(
          'Deine Anfrage wurde abgelehnt. Du kannst aktuell nicht selbst zusagen.',
        );
        return;
      }

      accepted.remove(userId);
      maybe.remove(userId);
      declined.remove(userId);

      switch (statusKey) {
        case 'accepted':
          accepted.add(userId);
          responseMap[userId] = 'accepted';
          break;
        case 'maybe':
          maybe.add(userId);
          responseMap[userId] = 'maybe';
          break;
        case 'declined':
          declined.add(userId);
          responseMap[userId] = 'declined';
          break;
        case 'clear':
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
        'participantIds': participantIds.toList(),
        'responseMap': responseMap,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _showSnack('Dein Status wurde aktualisiert.');
    } catch (_) {
      _showSnack('Der Status konnte nicht aktualisiert werden.');
    } finally {
      _setEventUpdating(eventId, false);
    }
  }

  Widget? _buildQuickActions({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String eventId,
    required Map<String, dynamic> data,
    required EventDetailView view,
    required String currentUserId,
  }) {
    if (view == EventDetailView.myEvent) return null;

    final joinMode = _normalizeJoinMode(data);
    final currentResponse = _responseForUser(data, currentUserId);
    final hasExistingResponse = _hasExistingResponseEntry(data, currentUserId);
    final isUpdating = _isEventUpdating(eventId);

    if (view == EventDetailView.invitation) {
      if (joinMode == 'request' &&
          hasExistingResponse &&
          currentResponse == 'pending') {
        return _EventQuickActions(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: isUpdating
                    ? null
                    : () => _withdrawRequest(eventId, currentUserId),
                icon: isUpdating
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.undo_rounded),
                label: const Text('Anfrage zurückziehen'),
              ),
            ],
          ),
        );
      }

      return _EventQuickActions(
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _CardResponseButton(
              label: 'Zusagen',
              icon: Icons.check_circle_outline,
              isSelected: currentResponse == 'accepted',
              color: Colors.green,
              isLoading: isUpdating,
              onPressed: () => _setResponseStatus(
                eventId: eventId,
                userId: currentUserId,
                statusKey: 'accepted',
              ),
            ),
            _CardResponseButton(
              label: 'Vielleicht',
              icon: Icons.help_outline,
              isSelected: currentResponse == 'maybe',
              color: Colors.orange,
              isLoading: isUpdating,
              onPressed: () => _setResponseStatus(
                eventId: eventId,
                userId: currentUserId,
                statusKey: 'maybe',
              ),
            ),
            _CardResponseButton(
              label: 'Absagen',
              icon: Icons.cancel_outlined,
              isSelected: currentResponse == 'declined',
              color: colorScheme.error,
              isLoading: isUpdating,
              onPressed: () => _setResponseStatus(
                eventId: eventId,
                userId: currentUserId,
                statusKey: 'declined',
              ),
            ),
          ],
        ),
      );
    }

    if (joinMode == 'request' && !hasExistingResponse) {
      return _EventQuickActions(
        child: FilledButton.icon(
          onPressed: isUpdating
              ? null
              : () => _sendJoinRequest(eventId, currentUserId),
          icon: isUpdating
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.mail_outline),
          label: const Text('Anfrage senden'),
        ),
      );
    }

    if (joinMode == 'request' && currentResponse == 'pending') {
      return _EventQuickActions(
        child: OutlinedButton.icon(
          onPressed: isUpdating
              ? null
              : () => _withdrawRequest(eventId, currentUserId),
          icon: isUpdating
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.undo_rounded),
          label: const Text('Anfrage zurückziehen'),
        ),
      );
    }

    if (joinMode == 'direct' && !hasExistingResponse) {
      return _EventQuickActions(
        child: FilledButton.icon(
          onPressed: isUpdating || !_hasFreeSpots(data)
              ? null
              : () => _joinDirectly(eventId, currentUserId),
          icon: isUpdating
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.login_rounded),
          label: Text(
            _hasFreeSpots(data) ? 'Direkt beitreten' : 'Keine Plätze frei',
          ),
        ),
      );
    }

    if (joinMode == 'invite_only' && !hasExistingResponse) {
      return null;
    }

    return _EventQuickActions(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _CardResponseButton(
            label: 'Zusagen',
            icon: Icons.check_circle_outline,
            isSelected: currentResponse == 'accepted',
            color: Colors.green,
            isLoading: isUpdating,
            onPressed: () => _setResponseStatus(
              eventId: eventId,
              userId: currentUserId,
              statusKey: 'accepted',
            ),
          ),
          _CardResponseButton(
            label: 'Vielleicht',
            icon: Icons.help_outline,
            isSelected: currentResponse == 'maybe',
            color: Colors.orange,
            isLoading: isUpdating,
            onPressed: () => _setResponseStatus(
              eventId: eventId,
              userId: currentUserId,
              statusKey: 'maybe',
            ),
          ),
          _CardResponseButton(
            label: 'Absagen',
            icon: Icons.cancel_outlined,
            isSelected: currentResponse == 'declined',
            color: colorScheme.error,
            isLoading: isUpdating,
            onPressed: () => _setResponseStatus(
              eventId: eventId,
              userId: currentUserId,
              statusKey: 'declined',
            ),
          ),
        ],
      ),
    );
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
          quickActions: _buildQuickActions(
            theme: theme,
            colorScheme: colorScheme,
            eventId: doc.id,
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
  final Widget? quickActions;
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
    required this.quickActions,
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
                      if (quickActions != null) ...[
                        const SizedBox(height: 12),
                        quickActions!,
                      ],
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

class _EventQuickActions extends StatelessWidget {
  final Widget child;

  const _EventQuickActions({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _CardResponseButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final bool isLoading;
  final VoidCallback onPressed;

  const _CardResponseButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    )
        : Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label),
      ],
    );

    if (isSelected) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
        onPressed: isLoading ? null : onPressed,
        child: child,
      );
    }

    return OutlinedButton(
      style: OutlinedButton.styleFrom(foregroundColor: color),
      onPressed: isLoading ? null : onPressed,
      child: child,
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
