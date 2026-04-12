import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationDispatchService {
  NotificationDispatchService._();

  static final NotificationDispatchService instance =
  NotificationDispatchService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> queueChatMessageNotification({
    required String recipientUserId,
    required String senderId,
    required String senderName,
    required String senderPhoneNumber,
    required String messageText,
  }) async {
    final safeSenderName = _fallback(senderName, 'Neue Nachricht');
    final safeMessageText = messageText.trim();
    final body = safeMessageText.isEmpty
        ? '$safeSenderName hat dir eine Nachricht geschickt.'
        : _truncate(safeMessageText);

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_messages_v2',
      title: safeSenderName,
      body: body,
      data: {
        'type': 'message',
        'route': 'chat',
        'contactId': senderId,
        'contactName': safeSenderName,
        'phoneNumber': senderPhoneNumber,
      },
    );
  }

  Future<void> queueAppointmentNotification({
    required String recipientUserId,
    required String senderId,
    required String senderName,
    required String senderPhoneNumber,
    required String appointmentId,
    required String appointmentTitle,
  }) async {
    final safeSenderName = _fallback(senderName, 'CheckMyTime');
    final safeAppointmentTitle = _fallback(appointmentTitle, 'Neue Planung');

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_appointments_v2',
      title: 'Neue Planung',
      body: '$safeSenderName: $safeAppointmentTitle',
      data: {
        'type': 'appointment',
        'route': 'events',
        'appointmentId': appointmentId,
        'contactId': senderId,
        'contactName': safeSenderName,
        'phoneNumber': senderPhoneNumber,
      },
    );
  }

  Future<void> queueEventInviteNotifications({
    required Iterable<String> recipientUserIds,
    required String senderId,
    required String senderName,
    required String eventId,
    required String eventTitle,
  }) async {
    final safeSenderName = _fallback(senderName, 'CheckMyTime');
    final safeEventTitle = _fallback(eventTitle, 'Neues Event');

    for (final recipientUserId in recipientUserIds) {
      final trimmedRecipient = recipientUserId.trim();
      if (trimmedRecipient.isEmpty) continue;

      await _queueNotification(
        recipientUserId: trimmedRecipient,
        channelId: 'incoming_event_invites_v2',
        title: 'Neue Event-Einladung',
        body: '$safeSenderName hat dich zu "$safeEventTitle" eingeladen.',
        data: {
          'type': 'event_invite',
          'route': 'event_detail',
          'eventId': eventId,
          'senderId': senderId,
          'senderName': safeSenderName,
        },
      );
    }
  }


  Future<void> queueEventJoinRequestNotification({
    required String recipientUserId,
    required String requesterUserId,
    required String requesterName,
    required String eventId,
    required String eventTitle,
  }) async {
    final safeRequesterName = _fallback(requesterName, 'Jemand');
    final safeEventTitle = _fallback(eventTitle, 'deinem Event');

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_event_requests_v2',
      title: 'Neue Teilnahme-Anfrage',
      body: '$safeRequesterName möchte an "${safeEventTitle}" teilnehmen.',
      data: {
        'type': 'event_join_request',
        'route': 'event_detail',
        'eventId': eventId,
        'senderId': requesterUserId,
        'senderName': safeRequesterName,
      },
    );
  }

  Future<void> _queueNotification({
    required String recipientUserId,
    required String channelId,
    required String title,
    required String body,
    required Map<String, Object?> data,
  }) async {
    final trimmedRecipient = recipientUserId.trim();
    if (trimmedRecipient.isEmpty) return;

    final payload = <String, String>{
      for (final entry in data.entries)
        entry.key: entry.value?.toString().trim() ?? '',
    };

    await _firestore.collection('notification_requests').add({
      'recipientUserId': trimmedRecipient,
      'title': title.trim(),
      'body': body.trim(),
      'channelId': channelId,
      'status': 'pending',
      'data': payload,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _fallback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _truncate(String value, [int maxLength = 140]) {
    final trimmed = value.trim();
    if (trimmed.length <= maxLength) return trimmed;
    return '${trimmed.substring(0, maxLength - 1)}…';
  }
}
