import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityService {
  ActivityService._();

  static final ActivityService instance = ActivityService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> recordEventCreated({
    required String actorUserId,
    required String actorName,
    required String actorImageUrl,
    required String eventId,
    required String eventTitle,
    required DateTime? eventDate,
    required bool isProfilePublic,
  }) async {
    await _firestore.collection('activities').add({
      'actorUserId': actorUserId.trim(),
      'actorName': _fallback(actorName, 'Jemand'),
      'actorImageUrl': actorImageUrl.trim(),
      'type': 'event_created',
      'eventId': eventId.trim(),
      'eventTitle': _fallback(eventTitle, 'Event'),
      'eventDate': eventDate != null ? Timestamp.fromDate(eventDate) : null,
      'audience': isProfilePublic ? 'public' : 'followers',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Wird aufgerufen, sobald ein Nutzer einem Event beitritt (Status "accepted").
  /// Die Aktivität erscheint im Feed aller Follower des Nutzers.
  Future<void> recordEventJoined({
    required String actorUserId,
    required String actorName,
    required String actorImageUrl,
    required String eventId,
    required String eventTitle,
    required DateTime? eventDate,
    required bool isProfilePublic,
  }) async {
    // Duplikate vermeiden: nur einen Eintrag pro Nutzer+Event.
    final existing = await _firestore
        .collection('activities')
        .where('actorUserId', isEqualTo: actorUserId.trim())
        .where('type', isEqualTo: 'event_joined')
        .where('eventId', isEqualTo: eventId.trim())
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;

    await _firestore.collection('activities').add({
      'actorUserId': actorUserId.trim(),
      'actorName': _fallback(actorName, 'Jemand'),
      'actorImageUrl': actorImageUrl.trim(),
      'type': 'event_joined',
      'eventId': eventId.trim(),
      'eventTitle': _fallback(eventTitle, 'Event'),
      'eventDate': eventDate != null ? Timestamp.fromDate(eventDate) : null,
      'audience': isProfilePublic ? 'public' : 'followers',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordProfileUpdated({
    required String actorUserId,
    required String actorName,
    required String actorImageUrl,
    required bool isProfilePublic,
  }) async {
    await _firestore.collection('activities').add({
      'actorUserId': actorUserId.trim(),
      'actorName': _fallback(actorName, 'Jemand'),
      'actorImageUrl': actorImageUrl.trim(),
      'type': 'profile_updated',
      'audience': isProfilePublic ? 'public' : 'followers',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _fallback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
}
