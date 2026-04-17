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
  bool _isCancelling = false;
  bool _isTogglingClosed = false;
  bool _hasMarkedInviteSeen = false;
  bool _hasLocallyMarkedInviteSeen = false;
  bool _hasMarkedEventViewed = false;
  bool _isTogglingInterest = false;
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

  Map<String, dynamic> _inviteSeenAtMap(Map<String, dynamic> data) {
    return Map<String, dynamic>.from(
      data['inviteSeenAtMap'] ?? const <String, dynamic>{},
    );
  }

  Map<String, dynamic> _eventViewAtMap(Map<String, dynamic> data) {
    return Map<String, dynamic>.from(
      data['eventViewAtMap'] ?? const <String, dynamic>{},
    );
  }

  Set<String> _eventViewerUserIds(Map<String, dynamic> data) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final viewerIds = <String>{
      ...List<String>.from(data['eventViewerUserIds'] ?? const []),
      ..._eventViewAtMap(data).keys.map((id) => id.trim()),
    }..removeWhere((id) => id.trim().isEmpty || id == createdBy);

    return viewerIds;
  }

  bool _hasViewedEvent(Map<String, dynamic> data, String userId) {
    if (userId.trim().isEmpty) return false;
    return _eventViewerUserIds(data).contains(userId);
  }

  Set<String> _interestedUserIds(Map<String, dynamic> data) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final eventRelatedIds = <String>{
      ...List<String>.from(data['memberIds'] ?? const []),
      ...List<String>.from(data['invitedUserIds'] ?? const []),
      ...List<String>.from(data['participantIds'] ?? const []),
      ...List<String>.from(data['acceptedUserIds'] ?? const []),
      ...List<String>.from(data['maybeUserIds'] ?? const []),
      ...List<String>.from(data['declinedUserIds'] ?? const []),
      ...Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      ).keys.map((id) => id.trim()),
    };

    final interestedIds = <String>{
      ...List<String>.from(data['interestedUserIds'] ?? const []),
      ...Map<String, dynamic>.from(
        data['interestedAtMap'] ?? const <String, dynamic>{},
      ).keys.map((id) => id.trim()),
    }..removeWhere(
          (id) => id.trim().isEmpty || id == createdBy || eventRelatedIds.contains(id),
    );

    return interestedIds;
  }

  bool _isInterestedInEvent(Map<String, dynamic> data, String userId) {
    if (userId.trim().isEmpty) return false;
    return _interestedUserIds(data).contains(userId);
  }

  String _interestCountText(Map<String, dynamic> data) {
    final count = _interestedUserIds(data).length;
    if (count == 1) return '1 interessiert';
    return '$count interessiert';
  }

  String _viewCountText(Map<String, dynamic> data) {
    final count = _eventViewerUserIds(data).length;
    if (count == 1) return '1 Besucher';
    return '$count Besucher';
  }

  Future<void> _toggleInterest(Map<String, dynamic> data) async {
    if (_currentUserId.isEmpty || _isTogglingInterest) return;

    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy == _currentUserId) return;

    setState(() {
      _isTogglingInterest = true;
    });

    final isInterested = _isInterestedInEvent(data, _currentUserId);

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId);

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isInterested) {
        updates['interestedUserIds'] = FieldValue.arrayRemove([_currentUserId]);
        updates['interestedAtMap.$_currentUserId'] = FieldValue.delete();
      } else {
        updates['interestedUserIds'] = FieldValue.arrayUnion([_currentUserId]);
        updates['interestedAtMap.$_currentUserId'] = FieldValue.serverTimestamp();
      }

      await docRef.update(updates);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isInterested
                ? 'Das Event wurde aus „Interessiert“ entfernt.'
                : 'Das Event wurde zu „Interessiert“ hinzugefügt.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Interessiert-Status konnte nicht aktualisiert werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingInterest = false;
        });
      }
    }
  }

  Future<void> _markEventViewedIfNeeded(Map<String, dynamic> data) async {
    if (_hasMarkedEventViewed || _currentUserId.isEmpty) return;

    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy == _currentUserId) {
      _hasMarkedEventViewed = true;
      return;
    }

    if (_hasViewedEvent(data, _currentUserId)) {
      _hasMarkedEventViewed = true;
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .update({
        'eventViewerUserIds': FieldValue.arrayUnion([_currentUserId]),
        'eventViewAtMap.$_currentUserId': FieldValue.serverTimestamp(),
      });
      _hasMarkedEventViewed = true;
    } catch (_) {}
  }

  Set<String> _invitedUserIds(Map<String, dynamic> data) {
    return <String>{
      ...List<String>.from(data['invitedUserIds'] ?? const []),
    }..removeWhere((id) => id.trim().isEmpty);
  }

  bool _isInvitedUser(Map<String, dynamic> data, String userId) {
    if (userId.trim().isEmpty) return false;
    return _invitedUserIds(data).contains(userId);
  }

  bool _isPendingInviteForUser(Map<String, dynamic> data, String userId) {
    if (!_isInvitedUser(data, userId)) return false;
    final response = _responseForUser(data, userId);
    return response != 'accepted' && response != 'maybe' && response != 'declined';
  }

  bool _isPendingJoinRequestForUser(Map<String, dynamic> data, String userId) {
    if (userId.trim().isEmpty) return false;
    if (_isPendingInviteForUser(data, userId)) return false;
    return _responseForUser(data, userId) == 'pending';
  }

  bool _hasSeenInvite(Map<String, dynamic> data, String userId) {
    if (userId.trim().isEmpty) return false;
    if (userId == _currentUserId && _hasLocallyMarkedInviteSeen) return true;

    final seenMap = _inviteSeenAtMap(data);
    if (seenMap[userId] != null) return true;

    final response = _responseForUser(data, userId);
    return response == 'accepted' || response == 'maybe' || response == 'declined';
  }

  Future<void> _markInviteAsSeenIfNeeded(Map<String, dynamic> data) async {
    if (_hasMarkedInviteSeen || _currentUserId.isEmpty) return;

    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy == _currentUserId) return;

    final invitedUserIds = _invitedUserIds(data);
    if (!invitedUserIds.contains(_currentUserId)) return;

    if (_hasSeenInvite(data, _currentUserId)) {
      _hasMarkedInviteSeen = true;
      return;
    }

    if (!_hasLocallyMarkedInviteSeen && mounted) {
      setState(() {
        _hasLocallyMarkedInviteSeen = true;
      });
    }

    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .update({
        'inviteSeenAtMap.$_currentUserId': FieldValue.serverTimestamp(),
      });
      _hasMarkedInviteSeen = true;
    } catch (_) {}
  }

  _InviteProgressCounts _inviteProgressCounts(Map<String, dynamic> data) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final invitedIds = <String>{
      ...List<String>.from(data['invitedUserIds'] ?? const []),
    }..removeWhere((id) => id.trim().isEmpty || id == createdBy);

    final acceptedIds = <String>{
      ...List<String>.from(data['acceptedUserIds'] ?? const []),
    };
    final maybeIds = <String>{
      ...List<String>.from(data['maybeUserIds'] ?? const []),
    };
    final declinedIds = <String>{
      ...List<String>.from(data['declinedUserIds'] ?? const []),
    };

    final seenCount = invitedIds.where((id) => _hasSeenInvite(data, id)).length;
    final acceptedCount = invitedIds.where(acceptedIds.contains).length;
    final maybeCount = invitedIds.where(maybeIds.contains).length;
    final declinedCount = invitedIds.where(declinedIds.contains).length;

    return _InviteProgressCounts(
      invitedCount: invitedIds.length,
      seenCount: seenCount,
      acceptedCount: acceptedCount,
      maybeCount: maybeCount,
      declinedCount: declinedCount,
    );
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

  bool _isCancelledEvent(Map<String, dynamic> data) {
    return _overallStatus(data) == 'cancelled';
  }

  bool _isClosedEvent(Map<String, dynamic> data) {
    return data['isClosed'] == true;
  }

  bool _isParticipationLocked(Map<String, dynamic> data) {
    return _isCancelledEvent(data) || _isClosedEvent(data);
  }

  String _participationLockedMessage(Map<String, dynamic> data) {
    if (_isCancelledEvent(data)) return 'Dieses Event wurde abgesagt.';
    if (_isClosedEvent(data)) return 'Dieses Event ist aktuell geschlossen.';
    return 'Aktion derzeit nicht möglich.';
  }

  Map<String, dynamic> _buildInterestRemovalUpdate(String userId) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return const <String, dynamic>{};

    return <String, dynamic>{
      'interestedUserIds': FieldValue.arrayRemove([trimmedUserId]),
      'interestedAtMap.$trimmedUserId': FieldValue.delete(),
    };
  }

  Set<String> _eventRecipientUserIds(Map<String, dynamic> data) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final recipientIds = <String>{
      ...List<String>.from(data['memberIds'] ?? const []),
      ...List<String>.from(data['invitedUserIds'] ?? const []),
      ...List<String>.from(data['participantIds'] ?? const []),
      ...List<String>.from(data['acceptedUserIds'] ?? const []),
      ...List<String>.from(data['maybeUserIds'] ?? const []),
      ...List<String>.from(data['declinedUserIds'] ?? const []),
      ...Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      ).keys,
    }..removeWhere((id) => id.trim().isEmpty || id == createdBy);

    return recipientIds;
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

      if (_isParticipationLocked(data)) {
        _showMessage(_participationLockedMessage(data));
        return;
      }

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
        ..._buildInterestRemovalUpdate(_currentUserId),
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

      if (_isParticipationLocked(data)) {
        _showMessage(_participationLockedMessage(data));
        return;
      }

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
        ..._buildInterestRemovalUpdate(_currentUserId),
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

      if (_isParticipationLocked(data)) {
        _showMessage(_participationLockedMessage(data));
        return;
      }

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
        return 'Abgelehnt';
      case 'invited':
        return 'Eingeladen';
      case 'seen':
        return 'Gesehen';
      case 'cancelled':
        return 'Abgesagt';
      case 'closed':
        return 'Geschlossen';
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
      case 'closed':
        return Colors.blueGrey;
      case 'open':
        return colorScheme.primary;
      case 'done':
        return Colors.teal;
      case 'invited':
      case 'seen':
      case 'pending':
      default:
        return colorScheme.primary;
    }
  }

  _ParticipantBuckets _participantBuckets(Map<String, dynamic> data) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final invitedUserIds = _invitedUserIds(data);
    final memberIds = <String>{
      ...List<String>.from(data['memberIds'] ?? const []),
      ...invitedUserIds,
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
    final invitedPending = <String>{};
    final requestPending = <String>{};

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
          if (invitedUserIds.contains(userId)) {
            invitedPending.add(userId);
          } else {
            requestPending.add(userId);
          }
          break;
      }
    }

    invitedPending.removeAll(accepted);
    invitedPending.removeAll(maybe);
    invitedPending.removeAll(declined);
    requestPending.removeAll(accepted);
    requestPending.removeAll(maybe);
    requestPending.removeAll(declined);

    return _ParticipantBuckets(
      accepted: accepted.toList()..sort(),
      maybe: maybe.toList()..sort(),
      invitedPending: invitedPending.toList()..sort(),
      requestPending: requestPending.toList()..sort(),
      declined: declined.toList()..sort(),
    );
  }

  String _currentHeaderStatus(Map<String, dynamic> data) {
    final overallStatus = _overallStatus(data);
    if (overallStatus == 'cancelled') return 'cancelled';
    if (_isClosedEvent(data)) return 'closed';

    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy == _currentUserId) {
      return overallStatus;
    }

    if (_isPendingInviteForUser(data, _currentUserId)) {
      return _hasSeenInvite(data, _currentUserId) ? 'seen' : 'invited';
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

      if (_isParticipationLocked(data)) {
        _showMessage(_participationLockedMessage(data));
        return;
      }

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
        ..._buildInterestRemovalUpdate(_currentUserId),
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

      if (_isParticipationLocked(data)) {
        _showMessage(_participationLockedMessage(data));
        return;
      }

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
        ..._buildInterestRemovalUpdate(requestUserId),
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


  Future<void> _removeParticipant({
    required String participantUserId,
    required String participantName,
  }) async {
    if (_currentUserId.isEmpty || _isUpdatingStatus) return;

    final trimmedParticipantId = participantUserId.trim();
    if (trimmedParticipantId.isEmpty || trimmedParticipantId == _currentUserId) {
      return;
    }

    final displayName = participantName.trim().isEmpty
        ? 'diese Person'
        : participantName.trim();

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Teilnehmer entfernen'),
        content: Text(
          'Möchtest du $displayName wirklich aus diesem Event entfernen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    ) ??
        false;

    if (!shouldRemove) return;

    setState(() {
      _isUpdatingStatus = true;
      _ownerActionUserId = trimmedParticipantId;
    });

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      if (_isCancelledEvent(data)) {
        _showMessage('Dieses Event wurde abgesagt.');
        return;
      }

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      if (createdBy != _currentUserId) {
        throw StateError('Nur der Ersteller darf Teilnehmer entfernen.');
      }

      if (trimmedParticipantId == createdBy) {
        throw StateError('Der Ersteller kann nicht entfernt werden.');
      }

      final eventTitle = (data['title'] ?? 'Event').toString().trim();
      final createdByName = (data['createdByName'] ?? '').toString().trim();

      final memberIds = <String>{
        ...List<String>.from(data['memberIds'] ?? const []),
      }..remove(trimmedParticipantId);

      final acceptedIds = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
      }..remove(trimmedParticipantId);

      final maybeIds = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      }..remove(trimmedParticipantId);

      final declinedIds = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      }..remove(trimmedParticipantId);

      final participantIds = <String>{
        ...List<String>.from(data['participantIds'] ?? const []),
      }..remove(trimmedParticipantId);

      final invitedUserIds = <String>{
        ...List<String>.from(data['invitedUserIds'] ?? const []),
      }..remove(trimmedParticipantId);

      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      )..remove(trimmedParticipantId);

      final inviteSeenAtMap = Map<String, dynamic>.from(
        data['inviteSeenAtMap'] ?? const <String, dynamic>{},
      )..remove(trimmedParticipantId);

      await docRef.update({
        'memberIds': memberIds.toList(),
        'acceptedUserIds': acceptedIds.toList(),
        'maybeUserIds': maybeIds.toList(),
        'declinedUserIds': declinedIds.toList(),
        'participantIds': participantIds.toList(),
        'invitedUserIds': invitedUserIds.toList(),
        'responseMap': responseMap,
        'inviteSeenAtMap': inviteSeenAtMap,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await NotificationDispatchService.instance
          .queueEventParticipantRemovedNotification(
        recipientUserId: trimmedParticipantId,
        senderId: createdBy,
        senderName: createdByName,
        eventId: widget.eventId,
        eventTitle: eventTitle,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$displayName wurde entfernt.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Teilnehmer konnte nicht entfernt werden.'),
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

  Future<void> _cancelEvent() async {
    if (_isCancelling) return;

    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Event absagen'),
        content: const Text(
          'Möchtest du dieses Event wirklich absagen? Das Event bleibt sichtbar, aber neue Teilnahmen und Antworten sind danach nicht mehr möglich.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Zurück'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Absagen'),
          ),
        ],
      ),
    ) ??
        false;

    if (!shouldCancel) return;

    setState(() {
      _isCancelling = true;
    });

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      if (createdBy != _currentUserId) {
        throw StateError('Nur der Ersteller darf dieses Event absagen.');
      }

      if (_isCancelledEvent(data)) {
        _showMessage('Dieses Event wurde bereits abgesagt.');
        return;
      }

      final createdByName = (data['createdByName'] ?? '').toString().trim();
      final eventTitle = (data['title'] ?? 'Event').toString().trim();
      final recipientUserIds = _eventRecipientUserIds(data);

      await docRef.update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': _currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (recipientUserIds.isNotEmpty) {
        await NotificationDispatchService.instance.queueEventDeletedNotifications(
          recipientUserIds: recipientUserIds,
          senderId: _currentUserId,
          senderName: createdByName,
          eventId: widget.eventId,
          eventTitle: eventTitle,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Event wurde abgesagt.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Event konnte nicht abgesagt werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }
  }


  Future<void> _closeEvent() async {
    if (_isTogglingClosed) return;

    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Event schließen'),
        content: const Text(
          'Möchtest du dieses Event schließen? Das Event bleibt sichtbar, aber neue Teilnahmen und Antworten sind bis zum Wiederöffnen nicht mehr möglich.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Schließen'),
          ),
        ],
      ),
    ) ??
        false;

    if (!shouldClose) return;

    setState(() {
      _isTogglingClosed = true;
    });

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      if (createdBy != _currentUserId) {
        throw StateError('Nur der Ersteller darf dieses Event schließen.');
      }

      if (_isCancelledEvent(data)) {
        _showMessage('Dieses Event wurde bereits abgesagt.');
        return;
      }

      if (_isClosedEvent(data)) {
        _showMessage('Dieses Event ist bereits geschlossen.');
        return;
      }

      await docRef.update({
        'isClosed': true,
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': _currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Event wurde geschlossen.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Event konnte nicht geschlossen werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingClosed = false;
        });
      }
    }
  }

  Future<void> _reopenEvent() async {
    if (_isTogglingClosed) return;

    final shouldReopen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Event wieder öffnen'),
        content: const Text(
          'Möchtest du dieses Event wieder öffnen? Danach sind neue Teilnahmen und Antworten wieder möglich.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wieder öffnen'),
          ),
        ],
      ),
    ) ??
        false;

    if (!shouldReopen) return;

    setState(() {
      _isTogglingClosed = true;
    });

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      if (createdBy != _currentUserId) {
        throw StateError('Nur der Ersteller darf dieses Event wieder öffnen.');
      }

      if (_isCancelledEvent(data)) {
        _showMessage('Ein abgesagtes Event kann nicht wieder geöffnet werden.');
        return;
      }

      if (!_isClosedEvent(data)) {
        _showMessage('Dieses Event ist bereits geöffnet.');
        return;
      }

      await docRef.update({
        'isClosed': false,
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': _currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Event wurde wieder geöffnet.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Event konnte nicht wieder geöffnet werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingClosed = false;
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
            final isInterested = _isInterestedInEvent(data, _currentUserId);
            final canToggleInterest = !isOwner &&
                !hasExistingResponse &&
                !_isPendingInviteForUser(data, _currentUserId) &&
                !_isCancelledEvent(data);
            final isCancelled = _isCancelledEvent(data);
            final isClosed = _isClosedEvent(data);
            final inviteProgressCounts = _inviteProgressCounts(data);
            final effectiveInviteSeenAtMap = _inviteSeenAtMap(data);
            if (_hasLocallyMarkedInviteSeen && _currentUserId.isNotEmpty) {
              effectiveInviteSeenAtMap[_currentUserId] = true;
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _markEventViewedIfNeeded(data);
              _markInviteAsSeenIfNeeded(data);
            });

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
                                    onTap: () => _openNavigation(data),
                                  ),
                                _DetailChip(
                                  icon: isInterested
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  label: _interestCountText(data),
                                  onTap: canToggleInterest && !_isTogglingInterest
                                      ? () => _toggleInterest(data)
                                      : null,
                                ),
                                _DetailChip(
                                  icon: Icons.visibility_outlined,
                                  label: _viewCountText(data),
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
                if (isCancelled) ...[
                  const SizedBox(height: 14),
                  _DetailSection(
                    title: 'Status',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.error.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.event_busy_outlined,
                            color: colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isOwner
                                  ? 'Du hast dieses Event abgesagt. Es bleibt sichtbar, aber neue Teilnahmen und Antworten sind deaktiviert.'
                                  : 'Dieses Event wurde vom Ersteller abgesagt. Neue Teilnahmen und Antworten sind nicht mehr möglich.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (isClosed) ...[
                  const SizedBox(height: 14),
                  _DetailSection(
                    title: 'Status',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.blueGrey.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isOwner
                                  ? 'Du hast dieses Event geschlossen. Es bleibt sichtbar, aber neue Teilnahmen und Antworten sind bis zum Wiederöffnen pausiert.'
                                  : 'Dieses Event ist aktuell geschlossen. Neue Teilnahmen und Antworten sind momentan nicht möglich.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _DetailSection(
                  title: joinMode == 'invite_only' && isOwner
                      ? 'Einladungsstatus'
                      : 'Teilnehmerstatus',
                  child: joinMode == 'invite_only' && isOwner
                      ? _InviteProgressOverview(counts: inviteProgressCounts)
                      : Wrap(
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
                      if (participantBuckets.invitedPending.isNotEmpty)
                        _StatusCounterChip(
                          icon: Icons.mark_email_unread_outlined,
                          label: 'Eingeladen',
                          count: participantBuckets.invitedPending.length,
                        ),
                      _StatusCounterChip(
                        icon: Icons.mail_outline,
                        label: 'Ausstehend',
                        count: participantBuckets.requestPending.length,
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
                  invitedPendingIds: participantBuckets.invitedPending,
                  requestPendingIds: participantBuckets.requestPending,
                  declinedIds: participantBuckets.declined,
                  invitedUserIds: _invitedUserIds(data),
                  currentUserId: _currentUserId,
                  isOwner: isOwner,
                  joinMode: joinMode,
                  inviteSeenAtMap: effectiveInviteSeenAtMap,
                  isUpdatingStatus: _isUpdatingStatus,
                  ownerActionUserId: _ownerActionUserId,
                  eventCancelled: isCancelled,
                  eventClosed: isClosed,
                  onOwnerDecision: ({required userId, required accepted}) =>
                      _handleOwnerRequestDecision(
                        requestUserId: userId,
                        accepted: accepted,
                      ),
                  onRemoveParticipant: ({
                    required userId,
                    required userName,
                  }) =>
                      _removeParticipant(
                        participantUserId: userId,
                        participantName: userName,
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
                  isCancelled: isCancelled,
                  isClosed: isClosed,
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
    required bool isCancelled,
    required bool isClosed,
  }) {
    if (isOwner) {
      return _DetailSection(
        title: 'Aktionen',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isCancelled) ...[
              OutlinedButton.icon(
                onPressed: _openEditPage,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Event bearbeiten'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _isTogglingClosed
                    ? null
                    : (isClosed ? _reopenEvent : _closeEvent),
                icon: _isTogglingClosed
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : Icon(
                  isClosed
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                ),
                label: Text(
                  isClosed ? 'Event wieder öffnen' : 'Event schließen',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isCancelling || _isTogglingClosed ? null : _cancelEvent,
                icon: _isCancelling
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.event_busy_outlined),
                label: const Text('Event absagen'),
              ),
            ] else ...[
              Text(
                'Dieses Event wurde bereits abgesagt und ist für die Teilnehmer weiterhin nachvollziehbar.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _isDeleting ? null : _deleteEvent,
                icon: _isDeleting
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.delete_outline),
                label: const Text('Event endgültig löschen'),
              ),
            ],
          ],
        ),
      );
    }

    if (isCancelled) {
      return _DetailSection(
        title: 'Teilnahme',
        child: Text(
          'Dieses Event wurde abgesagt. Neue Teilnahmen und Antworten sind nicht mehr möglich.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (isClosed) {
      return _DetailSection(
        title: 'Teilnahme',
        child: Text(
          'Dieses Event ist aktuell geschlossen. Neue Teilnahmen und Antworten sind erst nach dem Wiederöffnen wieder möglich.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final isInvitedCurrentUser = _isInvitedUser(data, _currentUserId);
    final hasPendingInvite = _isPendingInviteForUser(data, _currentUserId);

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

    if (isInvitedCurrentUser) {
      return _DetailSection(
        title: 'Deine Einladung',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasPendingInvite
                  ? 'Du wurdest vom Ersteller eingeladen. Antworte hier direkt auf die Einladung.'
                  : 'Du wurdest vom Ersteller eingeladen. Deine Antwort wird sofort in den Übersichten aktualisiert.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            if (hasPendingInvite) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mail_outline, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      _hasSeenInvite(data, _currentUserId) ? 'Einladung geöffnet' : 'Einladung erhalten',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
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

class _InviteProgressCounts {
  final int invitedCount;
  final int seenCount;
  final int acceptedCount;
  final int maybeCount;
  final int declinedCount;

  const _InviteProgressCounts({
    required this.invitedCount,
    required this.seenCount,
    required this.acceptedCount,
    required this.maybeCount,
    required this.declinedCount,
  });
}

class _HomeStyleBadge extends StatelessWidget {
  final String label;

  const _HomeStyleBadge({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFB7E61D),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.black87,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ParticipantBuckets {
  final List<String> accepted;
  final List<String> maybe;
  final List<String> invitedPending;
  final List<String> requestPending;
  final List<String> declined;

  const _ParticipantBuckets({
    required this.accepted,
    required this.maybe,
    required this.invitedPending,
    required this.requestPending,
    required this.declined,
  });
}

class _ParticipantGroupsSection extends StatelessWidget {
  final String createdBy;
  final String createdByName;
  final List<String> acceptedIds;
  final List<String> maybeIds;
  final List<String> invitedPendingIds;
  final List<String> requestPendingIds;
  final List<String> declinedIds;
  final Set<String> invitedUserIds;
  final String currentUserId;
  final bool isOwner;
  final String joinMode;
  final Map<String, dynamic> inviteSeenAtMap;
  final bool isUpdatingStatus;
  final String? ownerActionUserId;
  final bool eventCancelled;
  final bool eventClosed;
  final Future<void> Function({required String userId, required bool accepted})? onOwnerDecision;
  final Future<void> Function({
  required String userId,
  required String userName,
  })? onRemoveParticipant;

  const _ParticipantGroupsSection({
    required this.createdBy,
    required this.createdByName,
    required this.acceptedIds,
    required this.maybeIds,
    required this.invitedPendingIds,
    required this.requestPendingIds,
    required this.declinedIds,
    required this.invitedUserIds,
    required this.currentUserId,
    required this.isOwner,
    required this.joinMode,
    required this.inviteSeenAtMap,
    required this.isUpdatingStatus,
    required this.ownerActionUserId,
    required this.eventCancelled,
    required this.eventClosed,
    this.onOwnerDecision,
    this.onRemoveParticipant,
  });

  Future<Map<String, _ParticipantUserData>> _loadUserData(Set<String> ids) async {
    final result = <String, _ParticipantUserData>{};

    for (final id in ids) {
      if (id.trim().isEmpty) continue;
      try {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(id).get();
        final data = doc.data() ?? <String, dynamic>{};
        final name =
        (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final imageUrl =
        (data['profileImageUrl'] ?? '').toString().trim();
        result[id] = _ParticipantUserData(
          name: name.isEmpty ? 'Unbekannt' : name,
          imageUrl: imageUrl,
        );
      } catch (_) {
        result[id] = const _ParticipantUserData(
          name: 'Unbekannt',
          imageUrl: '',
        );
      }
    }

    return result;
  }

  String _inviteStageForPendingUser(String userId) {
    if (inviteSeenAtMap[userId] != null) return 'seen';
    return 'invited';
  }

  @override
  Widget build(BuildContext context) {
    final idsToLoad = <String>{
      createdBy,
      ...acceptedIds,
      ...maybeIds,
      ...invitedPendingIds,
      ...requestPendingIds,
      ...declinedIds,
    }..removeWhere((id) => id.trim().isEmpty);

    final isInviteOnlyOwnerView = isOwner && joinMode == 'invite_only';
    final showInvitedGroup = invitedPendingIds.isNotEmpty || joinMode == 'invite_only';
    final showRequestPendingGroup = requestPendingIds.isNotEmpty || joinMode == 'request';

    return FutureBuilder<Map<String, _ParticipantUserData>>(
      future: _loadUserData(idsToLoad),
      builder: (context, snapshot) {
        final loadedUsers = snapshot.data ?? <String, _ParticipantUserData>{};
        final resolvedCreatorName = createdByName.isNotEmpty
            ? createdByName
            : (loadedUsers[createdBy]?.name ?? 'Unbekannt');

        return _DetailSection(
          title: 'Teilnehmer & Antworten',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ParticipantGroup(
                title: 'Erstellt von',
                emptyLabel: 'Kein Ersteller hinterlegt.',
                joinMode: joinMode,
                people: [
                  _ParticipantItemData(
                    userId: createdBy,
                    name: resolvedCreatorName,
                    imageUrl: loadedUsers[createdBy]?.imageUrl ?? '',
                    status: 'Ersteller',
                    inviteStage: 'creator',
                    isCurrentUser: createdBy == currentUserId,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: isInviteOnlyOwnerView ? 'Angenommen' : 'Bestätigt',
                emptyLabel: isInviteOnlyOwnerView
                    ? 'Noch keine angenommenen Einladungen.'
                    : 'Noch keine Bestätigungen.',
                joinMode: joinMode,
                actionBuilder: !eventCancelled &&
                    isOwner &&
                    onRemoveParticipant != null
                    ? (person) {
                  if (person.isCurrentUser) return null;
                  final isBusy = isUpdatingStatus &&
                      ownerActionUserId == person.userId;
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: OutlinedButton.icon(
                      onPressed: isUpdatingStatus
                          ? null
                          : () => onRemoveParticipant!(
                        userId: person.userId,
                        userName: person.name,
                      ),
                      icon: isBusy
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                          : const Icon(Icons.person_remove_outlined),
                      label: const Text('Teilnehmer entfernen'),
                    ),
                  );
                }
                    : null,
                people: acceptedIds
                    .map(
                      (id) => _ParticipantItemData(
                    userId: id,
                    name: loadedUsers[id]?.name ?? 'Unbekannt',
                    status: isInviteOnlyOwnerView ? 'Angenommen' : 'Bestätigt',
                    inviteStage: invitedUserIds.contains(id) ? 'accepted' : 'pending',
                    imageUrl: loadedUsers[id]?.imageUrl ?? '',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Vielleicht',
                emptyLabel: 'Noch keine Vielleicht-Antworten.',
                joinMode: joinMode,
                people: maybeIds
                    .map(
                      (id) => _ParticipantItemData(
                    userId: id,
                    name: loadedUsers[id]?.name ?? 'Unbekannt',
                    status: 'Vielleicht',
                    inviteStage: invitedUserIds.contains(id) ? 'maybe' : 'pending',
                    imageUrl: loadedUsers[id]?.imageUrl ?? '',
                    isCurrentUser: id == currentUserId,
                  ),
                )
                    .toList(),
              ),
              if (showInvitedGroup) ...[
                const SizedBox(height: 12),
                _ParticipantGroup(
                  title: 'Eingeladen',
                  emptyLabel: 'Keine offenen Einladungen.',
                  joinMode: joinMode,
                  actionBuilder: !eventCancelled && isOwner && onRemoveParticipant != null
                      ? (person) {
                    if (person.isCurrentUser) return null;
                    final isBusy = isUpdatingStatus &&
                        ownerActionUserId == person.userId;
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OutlinedButton.icon(
                        onPressed: isUpdatingStatus
                            ? null
                            : () => onRemoveParticipant!(
                          userId: person.userId,
                          userName: person.name,
                        ),
                        icon: isBusy
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.person_remove_outlined),
                        label: const Text('Einladung zurückziehen'),
                      ),
                    );
                  }
                      : null,
                  people: invitedPendingIds
                      .map(
                        (id) {
                      final hasSeenInvite = inviteSeenAtMap[id] != null;

                      return _ParticipantItemData(
                        userId: id,
                        name: loadedUsers[id]?.name ?? 'Unbekannt',
                        status: hasSeenInvite ? 'Gesehen' : 'Eingeladen',
                        inviteStage: _inviteStageForPendingUser(id),
                        imageUrl: loadedUsers[id]?.imageUrl ?? '',
                        isCurrentUser: id == currentUserId,
                      );
                    },
                  )
                      .toList(),
                ),
              ],
              if (showRequestPendingGroup) ...[
                const SizedBox(height: 12),
                _ParticipantGroup(
                  title: 'Ausstehend',
                  emptyLabel: 'Keine offenen Antworten.',
                  joinMode: joinMode,
                  actionBuilder: !eventCancelled && isOwner && joinMode == 'request' && onOwnerDecision != null
                      ? (person) {
                    if (person.isCurrentUser) return null;
                    final isBusy = isUpdatingStatus &&
                        ownerActionUserId == person.userId;

                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: isUpdatingStatus || eventClosed
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
                              onPressed: isUpdatingStatus || eventClosed
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
                  people: requestPendingIds
                      .map(
                        (id) => _ParticipantItemData(
                      userId: id,
                      name: loadedUsers[id]?.name ?? 'Unbekannt',
                      status: 'Ausstehend',
                      inviteStage: 'pending',
                      imageUrl: loadedUsers[id]?.imageUrl ?? '',
                      isCurrentUser: id == currentUserId,
                    ),
                  )
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              _ParticipantGroup(
                title: 'Abgelehnt',
                emptyLabel: 'Bisher keine Ablehnungen.',
                joinMode: joinMode,
                people: declinedIds
                    .map(
                      (id) => _ParticipantItemData(
                    userId: id,
                    name: loadedUsers[id]?.name ?? 'Unbekannt',
                    status: 'Abgelehnt',
                    inviteStage: invitedUserIds.contains(id) ? 'declined' : 'pending',
                    imageUrl: loadedUsers[id]?.imageUrl ?? '',
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

class _ParticipantUserData {
  final String name;
  final String imageUrl;

  const _ParticipantUserData({
    required this.name,
    required this.imageUrl,
  });
}

class _ParticipantItemData {
  final String userId;
  final String name;
  final String imageUrl;
  final String status;
  final String inviteStage;
  final bool isCurrentUser;

  const _ParticipantItemData({
    required this.userId,
    required this.name,
    required this.imageUrl,
    required this.status,
    required this.inviteStage,
    required this.isCurrentUser,
  });
}

class _ParticipantGroup extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final String joinMode;
  final List<_ParticipantItemData> people;
  final Widget? Function(_ParticipantItemData person)? actionBuilder;

  const _ParticipantGroup({
    required this.title,
    required this.emptyLabel,
    required this.joinMode,
    required this.people,
    this.actionBuilder,
  });

  Color _badgeColor(BuildContext context, String status) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (status) {
      case 'Ersteller':
      case 'Ausstehend':
      case 'Eingeladen':
      case 'Gesehen':
        return colorScheme.primary;
      case 'Bestätigt':
      case 'Angenommen':
        return Colors.green;
      case 'Vielleicht':
        return Colors.orange;
      case 'Abgelehnt':
        return colorScheme.error;
      default:
        return colorScheme.primary;
    }
  }

  bool _showInviteTimeline(_ParticipantItemData person) {
    return person.inviteStage != 'creator' && person.inviteStage != 'pending';
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
                            backgroundImage: person.imageUrl.isNotEmpty
                                ? NetworkImage(person.imageUrl)
                                : null,
                            child: person.imageUrl.isNotEmpty
                                ? null
                                : Text(
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
                          if (person.status == 'Gesehen')
                            const _HomeStyleBadge(label: 'Gesehen')
                          else
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
                      if (_showInviteTimeline(person)) ...[
                        const SizedBox(height: 12),
                        _InviteProgressTimeline(stage: person.inviteStage),
                      ],
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

class _InviteProgressOverview extends StatelessWidget {
  final _InviteProgressCounts counts;

  const _InviteProgressOverview({
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final invitedTotal = counts.invitedCount == 0 ? 1 : counts.invitedCount;

    Widget buildMetric({
      required String label,
      required int count,
      required Color color,
      required double value,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$count/${counts.invitedCount}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fortschritt deiner Einladungen',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        _InviteProgressFlowHeader(),
        const SizedBox(height: 16),
        buildMetric(
          label: 'Gesehen',
          count: counts.seenCount,
          color: colorScheme.primary,
          value: counts.seenCount / invitedTotal,
        ),
        const SizedBox(height: 12),
        buildMetric(
          label: 'Angenommen',
          count: counts.acceptedCount,
          color: Colors.green,
          value: counts.acceptedCount / invitedTotal,
        ),
        if (counts.maybeCount > 0) ...[
          const SizedBox(height: 12),
          buildMetric(
            label: 'Vielleicht',
            count: counts.maybeCount,
            color: Colors.orange,
            value: counts.maybeCount / invitedTotal,
          ),
        ],
        const SizedBox(height: 12),
        buildMetric(
          label: 'Abgelehnt',
          count: counts.declinedCount,
          color: colorScheme.error,
          value: counts.declinedCount / invitedTotal,
        ),
      ],
    );
  }
}

class _InviteProgressFlowHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget buildStep(String text, {required bool active, Color? activeColor}) {
      final color = active ? (activeColor ?? colorScheme.primary) : colorScheme.outline;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.10) : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.28) : colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: active ? color : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        buildStep('Eingeladen', active: true),
        Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
        buildStep('Gesehen', active: true),
        Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
        buildStep('Angenommen', active: true, activeColor: Colors.green),
      ],
    );
  }
}

class _InviteProgressTimeline extends StatelessWidget {
  final String stage;

  const _InviteProgressTimeline({
    required this.stage,
  });

  bool _isActive(String step) {
    switch (stage) {
      case 'accepted':
      case 'declined':
      case 'maybe':
        return true;
      case 'seen':
        return step != 'final';
      case 'invited':
      default:
        return step == 'invited';
    }
  }

  Color _finalColor(BuildContext context) {
    switch (stage) {
      case 'accepted':
        return Colors.green;
      case 'declined':
        return Theme.of(context).colorScheme.error;
      case 'maybe':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _finalLabel() {
    switch (stage) {
      case 'accepted':
        return 'Angenommen';
      case 'declined':
        return 'Abgelehnt';
      case 'maybe':
        return 'Vielleicht';
      default:
        return 'Angenommen';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final invitedActive = _isActive('invited');
    final seenActive = _isActive('seen');
    final finalActive = _isActive('final');
    final finalColor = finalActive ? _finalColor(context) : colorScheme.outline;

    Widget dot({
      required bool active,
      required Color activeColor,
    }) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? activeColor : colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: active ? activeColor : colorScheme.outlineVariant,
            width: 1.5,
          ),
        ),
      );
    }

    Widget line({
      required bool active,
      required Color activeColor,
    }) {
      return Expanded(
        child: Container(
          height: 2,
          color: active ? activeColor : colorScheme.outlineVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            dot(active: invitedActive, activeColor: primary),
            line(active: seenActive, activeColor: primary),
            dot(active: seenActive, activeColor: primary),
            line(active: finalActive, activeColor: finalColor),
            dot(active: finalActive, activeColor: finalColor),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Eingeladen',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: invitedActive ? primary : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                'Gesehen',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: seenActive ? primary : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                _finalLabel(),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: finalActive ? finalColor : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
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
  final VoidCallback? onTap;

  const _DetailChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final chipChild = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    final decoratedChild = Ink(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: chipChild,
    );

    if (onTap == null) {
      return decoratedChild;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: decoratedChild,
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

