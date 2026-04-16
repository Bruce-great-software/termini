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
