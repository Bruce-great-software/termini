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

  Future<void> queueEventJoinRequestNotification({
    required String recipientUserId,
    required String requesterId,
    required String requesterName,
    required String eventId,
    required String eventTitle,
  }) async {
    final safeRequesterName = _fallback(requesterName, 'Jemand');
    final safeEventTitle = _fallback(eventTitle, 'deinem Event');

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_event_updates_v2',
      title: 'Neue Teilnahme-Anfrage',
      body: '$safeRequesterName möchte bei "$safeEventTitle" mitmachen.',
      data: {
        'type': 'event_join_request',
        'route': 'event_detail',
        'eventId': eventId,
        'senderId': requesterId,
        'senderName': safeRequesterName,
      },
    );
  }

  Future<void> queueEventDirectJoinNotification({
    required String recipientUserId,
    required String joiningUserId,
    required String joiningUserName,
    required String eventId,
    required String eventTitle,
  }) async {
    final safeJoiningUserName = _fallback(joiningUserName, 'Jemand');
    final safeEventTitle = _fallback(eventTitle, 'deinem Event');

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_event_updates_v2',
      title: 'Neuer Teilnehmer',
      body: '$safeJoiningUserName ist "$safeEventTitle" beigetreten.',
      data: {
        'type': 'event_direct_join',
        'route': 'event_detail',
        'eventId': eventId,
        'senderId': joiningUserId,
        'senderName': safeJoiningUserName,
      },
    );
  }

  Future<void> queueEventResponseUpdateNotification({
    required String recipientUserId,
    required String senderId,
    required String senderName,
    required String eventId,
    required String eventTitle,
    required String statusKey,
  }) async {
    final safeSenderName = _fallback(senderName, 'Jemand');
    final safeEventTitle = _fallback(eventTitle, 'deinem Event');
    final normalizedStatus = statusKey.trim().toLowerCase();

    String title;
    String body;
    String type;

    switch (normalizedStatus) {
      case 'accepted':
        title = 'Teilnahme bestätigt';
        body = '$safeSenderName hat für "$safeEventTitle" zugesagt.';
        type = 'event_response_accepted';
        break;
      case 'maybe':
        title = 'Teilnahme aktualisiert';
        body = '$safeSenderName ist sich bei "$safeEventTitle" noch unsicher.';
        type = 'event_response_maybe';
        break;
      case 'declined':
        title = 'Teilnahme abgesagt';
        body = '$safeSenderName hat "$safeEventTitle" abgesagt.';
        type = 'event_response_declined';
        break;
      default:
        return;
    }

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_event_updates_v2',
      title: title,
      body: body,
      data: {
        'type': type,
        'route': 'event_detail',
        'eventId': eventId,
        'senderId': senderId,
        'senderName': safeSenderName,
      },
    );
  }

  Future<void> queueEventRequestWithdrawnNotification({
    required String recipientUserId,
    required String requesterId,
    required String requesterName,
    required String eventId,
    required String eventTitle,
  }) async {
    final safeRequesterName = _fallback(requesterName, 'Jemand');
    final safeEventTitle = _fallback(eventTitle, 'deinem Event');

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_event_updates_v2',
      title: 'Anfrage zurückgezogen',
      body: '$safeRequesterName hat die Anfrage für "$safeEventTitle" zurückgezogen.',
      data: {
        'type': 'event_join_request_withdrawn',
        'route': 'event_detail',
        'eventId': eventId,
        'senderId': requesterId,
        'senderName': safeRequesterName,
      },
    );
  }

  Future<void> queueEventJoinDecisionNotification({
    required String recipientUserId,
    required String senderId,
    required String senderName,
    required String eventId,
    required String eventTitle,
    required bool accepted,
  }) async {
    final safeSenderName = _fallback(senderName, 'CheckMyTime');
    final safeEventTitle = _fallback(eventTitle, 'Event');

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_event_updates_v2',
      title: accepted ? 'Anfrage angenommen' : 'Anfrage abgelehnt',
      body: accepted
          ? '$safeSenderName hat deine Anfrage für "$safeEventTitle" angenommen.'
          : '$safeSenderName hat deine Anfrage für "$safeEventTitle" abgelehnt.',
      data: {
        'type': accepted
            ? 'event_join_request_accepted'
            : 'event_join_request_declined',
        'route': 'event_detail',
        'eventId': eventId,
        'senderId': senderId,
        'senderName': safeSenderName,
      },
    );
  }

  Future<void> queueEventParticipantRemovedNotification({
    required String recipientUserId,
    required String senderId,
    required String senderName,
    required String eventId,
    required String eventTitle,
  }) async {
    final safeSenderName = _fallback(senderName, 'CheckMyTime');
    final safeEventTitle = _fallback(eventTitle, 'Event');

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_event_updates_v2',
      title: 'Aus Event entfernt',
      body: '$safeSenderName hat dich aus "$safeEventTitle" entfernt.',
      data: {
        'type': 'event_participant_removed',
        'route': 'events',
        'eventId': eventId,
        'senderId': senderId,
        'senderName': safeSenderName,
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

  Future<void> queueEventUpdatedNotifications({
    required Iterable<String> recipientUserIds,
    required String senderId,
    required String senderName,
    required String eventId,
    required String eventTitle,
  }) async {
    final safeSenderName = _fallback(senderName, 'CheckMyTime');
    final safeEventTitle = _fallback(eventTitle, 'Event');

    for (final recipientUserId in recipientUserIds) {
      final trimmedRecipient = recipientUserId.trim();
      if (trimmedRecipient.isEmpty) continue;

      await _queueNotification(
        recipientUserId: trimmedRecipient,
        channelId: 'incoming_event_updates_v2',
        title: 'Event aktualisiert',
        body: '$safeSenderName hat "$safeEventTitle" aktualisiert.',
        data: {
          'type': 'event_updated',
          'route': 'event_detail',
          'eventId': eventId,
          'senderId': senderId,
          'senderName': safeSenderName,
        },
      );
    }
  }

  Future<void> queueEventDeletedNotifications({
    required Iterable<String> recipientUserIds,
    required String senderId,
    required String senderName,
    required String eventId,
    required String eventTitle,
  }) async {
    final safeSenderName = _fallback(senderName, 'CheckMyTime');
    final safeEventTitle = _fallback(eventTitle, 'Event');

    for (final recipientUserId in recipientUserIds) {
      final trimmedRecipient = recipientUserId.trim();
      if (trimmedRecipient.isEmpty) continue;

      await _queueNotification(
        recipientUserId: trimmedRecipient,
        channelId: 'incoming_event_updates_v2',
        title: 'Event abgesagt',
        body: '$safeSenderName hat "$safeEventTitle" abgesagt.',
        data: {
          'type': 'event_deleted',
          'route': 'events',
          'eventId': eventId,
          'senderId': senderId,
          'senderName': safeSenderName,
        },
      );
    }
  }


  Future<void> queueFollowRequestNotification({
    required String recipientUserId,
    required String senderId,
    required String senderName,
  }) async {
    final safeName = _fallback(senderName, 'Jemand');

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_follow_v2',
      title: 'Neue Follow-Anfrage',
      body: '$safeName möchte dir auf CheckMyTime folgen.',
      data: {
        'type': 'follow_request',
        'route': 'user_page',
        'userId': senderId,
        'senderId': senderId,
        'senderName': safeName,
      },
    );
  }

  Future<void> queueFollowAcceptedNotification({
    required String recipientUserId,
    required String accepterId,
    required String accepterName,
  }) async {
    final safeName = _fallback(accepterName, 'Jemand');

    await _queueNotification(
      recipientUserId: recipientUserId,
      channelId: 'incoming_follow_v2',
      title: 'Anfrage angenommen',
      body: '$safeName hat deine Follow-Anfrage angenommen.',
      data: {
        'type': 'follow_request_accepted',
        'route': 'user_page',
        'userId': accepterId,
        'senderId': accepterId,
        'senderName': safeName,
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
