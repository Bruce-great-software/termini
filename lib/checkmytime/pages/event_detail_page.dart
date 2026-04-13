import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:termini/checkmytime/pages/create_event_page.dart';
import 'package:termini/checkmytime/services/notification_dispatch_service.dart';

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
  String? _ownerActionUserId;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _resolvedLocationText(Map<String, dynamic> data) {
    final candidates = [
      data['exactLocationText'],
      data['exactLocationAddress'],
      data['locationText'],
      data['location'],
      data['approxLocationText'],
    ];

    for (final candidate in candidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    return '';
  }

  Uri _buildGoogleMapsDirectionsUri(Map<String, dynamic> data) {
    final lat = _parseDouble(data['exactLocationLat']);
    final lng = _parseDouble(data['exactLocationLng']);
    final locationText = _resolvedLocationText(data);

    if (lat != null && lng != null) {
      return Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent('$lat,$lng')}',
      );
    }

    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(locationText)}',
    );
  }

  Future<void> _openNavigation(Map<String, dynamic> data) async {
    final lat = _parseDouble(data['exactLocationLat']);
    final lng = _parseDouble(data['exactLocationLng']);
    final locationText = _resolvedLocationText(data);

    if (locationText.isEmpty && (lat == null || lng == null)) {
      _showMessage('Für dieses Event ist kein navigierbarer Ort hinterlegt.');
      return;
    }

    final uri = _buildGoogleMapsDirectionsUri(data);

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _showMessage('Google Maps konnte nicht geöffnet werden.');
      }
    } catch (_) {
      _showMessage('Google Maps konnte nicht geöffnet werden.');
    }
  }

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

  int _acceptedCount(Map<String, dynamic> data) {
    final acceptedUserIds = List<String>.from(
      data['acceptedUserIds'] ?? const [],
    );
    if (acceptedUserIds.isNotEmpty) {
      return acceptedUserIds.length;
    }

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );

    return responseMap.values
        .where((value) => value.toString().trim() == 'accepted')
        .length;
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

  Future<void> _sendJoinRequest() async {
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

      final memberIds = <String>{
        ...List<String>.from(data['memberIds'] ?? const []),
      }..add(_currentUserId);

      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      )..[_currentUserId] = 'pending';

      final accepted = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
      }..remove(_currentUserId);

      final maybe = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      }..remove(_currentUserId);

      final declined = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      }..remove(_currentUserId);

      final participantIds = <String>{
        ...List<String>.from(data['participantIds'] ?? const []),
      }..remove(_currentUserId);

      await docRef.update({
        'memberIds': memberIds.toList(),
        'responseMap': responseMap,
        'acceptedUserIds': accepted.toList(),
        'maybeUserIds': maybe.toList(),
        'declinedUserIds': declined.toList(),
        'participantIds': participantIds.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deine Anfrage wurde gesendet.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Anfrage konnte nicht gesendet werden.'),
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

  Future<void> _joinDirectly() async {
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

      if (!_hasFreeSpots(data)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Für dieses Event sind aktuell keine Plätze frei.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final createdBy = (data['createdBy'] ?? '').toString().trim();

      final memberIds = <String>{
        ...List<String>.from(data['memberIds'] ?? const []),
        _currentUserId,
      };

      final accepted = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
        _currentUserId,
      };

      final maybe = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      }..remove(_currentUserId);

      final declined = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      }..remove(_currentUserId);

      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      )..[_currentUserId] = 'accepted';

      final participantIds = <String>{
        ...List<String>.from(data['participantIds'] ?? const []),
        createdBy,
        _currentUserId,
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Du bist jetzt dabei.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Beitritt konnte nicht durchgeführt werden.'),
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

  Future<void> _withdrawRequest() async {
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

      final memberIds = <String>{
        ...List<String>.from(data['memberIds'] ?? const []),
      }..remove(_currentUserId);

      final accepted = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
      }..remove(_currentUserId);

      final maybe = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      }..remove(_currentUserId);

      final declined = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      }..remove(_currentUserId);

      final participantIds = <String>{
        ...List<String>.from(data['participantIds'] ?? const []),
      }..remove(_currentUserId);

      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      )..remove(_currentUserId);

      await docRef.update({
        'memberIds': memberIds.toList(),
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
          content: Text('Deine Anfrage wurde zurückgezogen.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Anfrage konnte nicht zurückgezogen werden.'),
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
    final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
    final declined = List<String>.from(data['declinedUserIds'] ?? const []);

    if (accepted.contains(userId)) return 'accepted';
    if (maybe.contains(userId)) return 'maybe';
    if (declined.contains(userId)) return 'declined';

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    final mapped = (responseMap[userId] ?? '').toString().trim();
    if (mapped.isNotEmpty) return mapped;

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
      ...List<String>.from(data['acceptedUserIds'] ?? const []),
      ...List<String>.from(data['maybeUserIds'] ?? const []),
      ...List<String>.from(data['declinedUserIds'] ?? const []),
      createdBy,
    }..removeWhere((id) => id.trim().isEmpty);

    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    memberIds.addAll(
      responseMap.keys.map((key) => key.trim()).where((id) => id.isNotEmpty),
    );

    final accepted = <String>{};
    final maybe = <String>{};
    final declined = <String>{};
    final pending = <String>{};

    for (final userId in memberIds) {
      if (userId == createdBy) continue;

      switch (_responseForUser(data, userId)) {
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


  Future<void> _handleOwnerRequestDecision({
    required String requestUserId,
    required bool accepted,
  }) async {
    if (_currentUserId.isEmpty || _isUpdatingStatus) return;

    setState(() {
      _isUpdatingStatus = true;
      _ownerActionUserId = requestUserId;
    });

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      if (createdBy != _currentUserId) {
        throw StateError('Nur der Ersteller darf Anfragen verwalten.');
      }

      final eventTitle = (data['title'] ?? 'Event').toString().trim();
      final createdByName = (data['createdByName'] ?? '').toString().trim();

      final memberIds = <String>{
        ...List<String>.from(data['memberIds'] ?? const []),
      };
      final acceptedIds = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
      };
      final maybeIds = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      };
      final declinedIds = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      };
      final participantIds = <String>{
        ...List<String>.from(data['participantIds'] ?? const []),
      };
      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      );

      acceptedIds.remove(requestUserId);
      maybeIds.remove(requestUserId);
      declinedIds.remove(requestUserId);
      participantIds.remove(requestUserId);

      if (accepted) {
        acceptedIds.add(requestUserId);
        memberIds.add(requestUserId);
        participantIds.add(requestUserId);
        participantIds.add(createdBy);
        responseMap[requestUserId] = 'accepted';
      } else {
        declinedIds.add(requestUserId);
        memberIds.remove(requestUserId);
        responseMap[requestUserId] = 'declined';
      }

      await docRef.update({
        'memberIds': memberIds.toList(),
        'acceptedUserIds': acceptedIds.toList(),
        'maybeUserIds': maybeIds.toList(),
        'declinedUserIds': declinedIds.toList(),
        'participantIds': participantIds.toList(),
        'responseMap': responseMap,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await NotificationDispatchService.instance.queueEventJoinDecisionNotification(
        recipientUserId: requestUserId,
        senderId: createdBy,
        senderName: createdByName,
        eventId: widget.eventId,
        eventTitle: eventTitle,
        accepted: accepted,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? 'Die Anfrage wurde angenommen.'
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
          _isUpdatingStatus = false;
          _ownerActionUserId = null;
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
            final location = _resolvedLocationText(data);
            final exactLat = _parseDouble(data['exactLocationLat']);
            final exactLng = _parseDouble(data['exactLocationLng']);
            final hasNavigableLocation =
                location.isNotEmpty || (exactLat != null && exactLng != null);
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
            final joinMode = _normalizeJoinMode(data);
            final hasExistingResponse = _hasExistingResponseEntry(data, _currentUserId);
            final participantCount = _acceptedCount(data);
            final maxParticipants = _maxParticipants(data);
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
                                  icon: Icons.group_outlined,
                                  label: maxParticipants != null && maxParticipants > 0
                                      ? '$participantCount/$maxParticipants Teilnehmer'
                                      : '$participantCount Teilnehmer',
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
                if (hasNavigableLocation) ...[
                  const SizedBox(height: 14),
                  _DetailSection(
                    title: 'Ort & Navigation',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.place_outlined,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    location.isNotEmpty
                                        ? location
                                        : '${exactLat?.toStringAsFixed(6)}, ${exactLng?.toStringAsFixed(6)}',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (exactLat != null && exactLng != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '${exactLat.toStringAsFixed(6)}, ${exactLng.toStringAsFixed(6)}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () => _openNavigation(data),
                          icon: const Icon(Icons.navigation_outlined),
                          label: const Text('Navigation starten'),
                        ),
                      ],
                    ),
                  ),
                ],
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
                  isUpdatingStatus: _isUpdatingStatus,
                  ownerActionUserId: _ownerActionUserId,
                  onOwnerDecision: ({required userId, required accepted}) =>
                      _handleOwnerRequestDecision(
                        requestUserId: userId,
                        accepted: accepted,
                      ),
                ),
                const SizedBox(height: 14),
                _buildActionSection(
                  context: context,
                  theme: theme,
                  colorScheme: colorScheme,
                  data: data,
                  currentUserResponse: currentUserResponse,
                  joinMode: joinMode,
                  hasExistingResponse: hasExistingResponse,
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
    required Map<String, dynamic> data,
    required String currentUserResponse,
    required String joinMode,
    required bool hasExistingResponse,
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

    if (joinMode == 'invite_only' && !hasExistingResponse) {
      return _DetailSection(
        title: 'Teilnahme',
        child: Text(
          'Dieses Event ist nur auf Einladung verfügbar.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (joinMode == 'request' && !hasExistingResponse) {
      return _DetailSection(
        title: 'Teilnahme',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Du kannst dem Ersteller eine Teilnahme-Anfrage senden. Sobald sie bestätigt wird, erscheint dein Status in den Übersichten.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _isUpdatingStatus ? null : _sendJoinRequest,
              icon: _isUpdatingStatus
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
          ],
        ),
      );
    }

    if (joinMode == 'request' && hasExistingResponse && currentUserResponse == 'pending') {
      return _DetailSection(
        title: 'Deine Anfrage',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Deine Anfrage wurde gesendet und wartet auf eine Rückmeldung.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.hourglass_top_rounded, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Anfrage gesendet',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isUpdatingStatus ? null : _withdrawRequest,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Anfrage zurückziehen'),
            ),
          ],
        ),
      );
    }

    if (joinMode == 'request' && currentUserResponse == 'accepted') {
      return _DetailSection(
        title: 'Teilnahme bestätigt',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Deine Anfrage wurde bestätigt. Du bist jetzt dabei.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Du bist dabei',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _setResponseStatus('declined'),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Teilnahme absagen'),
            ),
          ],
        ),
      );
    }

    if (joinMode == 'request' && currentUserResponse == 'declined') {
      return _DetailSection(
        title: 'Deine Anfrage',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Deine Anfrage wurde vom Ersteller abgelehnt. Du kannst diesem Event aktuell nicht direkt beitreten.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (joinMode == 'direct' && !hasExistingResponse) {
      return _DetailSection(
        title: 'Teilnahme',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _hasFreeSpots(data)
                  ? 'Du kannst diesem Event direkt beitreten.'
                  : 'Aktuell sind keine freien Plätze mehr verfügbar.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _isUpdatingStatus || !_hasFreeSpots(data) ? null : _joinDirectly,
              icon: _isUpdatingStatus
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.login_rounded),
              label: const Text('Direkt beitreten'),
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
  final bool isUpdatingStatus;
  final String? ownerActionUserId;
  final Future<void> Function({required String userId, required bool accepted})? onOwnerDecision;

  const _ParticipantGroupsSection({
    required this.createdBy,
    required this.createdByName,
    required this.acceptedIds,
    required this.maybeIds,
    required this.pendingIds,
    required this.declinedIds,
    required this.currentUserId,
    required this.isOwner,
    required this.isUpdatingStatus,
    required this.ownerActionUserId,
    this.onOwnerDecision,
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
                    userId: createdBy,
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
                    userId: id,
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
                    userId: id,
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Vielleicht',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Ausstehend',
                emptyLabel: 'Keine offenen Antworten.',
                actionBuilder: isOwner && onOwnerDecision != null
                    ? (person) {
                  if (person.isCurrentUser) return null;
                  final isBusy = isUpdatingStatus && ownerActionUserId == person.userId;
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isUpdatingStatus
                                ? null
                                : () => onOwnerDecision!(
                              userId: person.userId,
                              accepted: true,
                            ),
                            icon: isBusy
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Icon(Icons.check_rounded),
                            label: const Text('Annehmen'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isUpdatingStatus
                                ? null
                                : () => onOwnerDecision!(
                              userId: person.userId,
                              accepted: false,
                            ),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Ablehnen'),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                    : null,
                people: pendingIds
                    .map(
                      (id) => _ParticipantItemData(
                    userId: id,
                    name: loadedNames[id] ?? 'Unbekannt',
                    status: 'Ausstehend',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Abgelehnt',
                emptyLabel: 'Bisher keine Ablehnungen.',
                people: declinedIds
                    .map(
                      (id) => _ParticipantItemData(
                    userId: id,
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
  final String userId;
  final String name;
  final String status;
  final bool isCurrentUser;

  const _ParticipantItemData({
    required this.userId,
    required this.name,
    required this.status,
    required this.isCurrentUser,
  });
}

class _ParticipantGroup extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final List<_ParticipantItemData> people;
  final Widget? Function(_ParticipantItemData person)? actionBuilder;

  const _ParticipantGroup({
    required this.title,
    required this.emptyLabel,
    required this.people,
    this.actionBuilder,
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
                (person) {
              final extraAction = actionBuilder?.call(person);
              return Padding(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                      if (extraAction != null) extraAction,
                    ],
                  ),
                ),
              );
            },
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

