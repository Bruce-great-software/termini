import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';
import 'package:termini/checkmytime/pages/event_detail_page.dart';
import 'package:termini/checkmytime/pages/user_page.dart';
import 'package:termini/checkmytime/services/notification_dispatch_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAllAsRead(silent: true);
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _safeDocs(
      AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
      ) {
    if (snapshot.hasError) return const [];
    return snapshot.data?.docs ?? const [];
  }

  bool _isEventInviteNotificationType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'event_invite':
      case 'event_invitation':
      case 'plan_invite':
      case 'plan_invitation':
      case 'planning_invite':
      case 'invitation':
        return true;
      default:
        return false;
    }
  }

  bool _isEventCancellationNotificationType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'event_cancelled':
      case 'event_canceled':
      case 'plan_cancelled':
      case 'plan_canceled':
      case 'event_cancel':
      case 'plan_cancel':
        return true;
      default:
        return false;
    }
  }

  Future<void> _markAllAsRead({bool silent = false}) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      var hasUpdates = false;

      final notificationsSnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('toUserId', isEqualTo: currentUserId)
          .where('read', isEqualTo: false)
          .get();

      for (final doc in notificationsSnapshot.docs) {
        batch.update(doc.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
        hasUpdates = true;
      }

      final eventSnapshots = await Future.wait([
        FirebaseFirestore.instance
            .collection('events')
            .where('invitedUserIds', arrayContains: currentUserId)
            .get(),
        FirebaseFirestore.instance
            .collection('events')
            .where('memberIds', arrayContains: currentUserId)
            .get(),
        FirebaseFirestore.instance
            .collection('events')
            .where('acceptedUserIds', arrayContains: currentUserId)
            .get(),
        FirebaseFirestore.instance
            .collection('events')
            .where('maybeUserIds', arrayContains: currentUserId)
            .get(),
      ]);

      final handledEventIds = <String>{};
      for (final snapshot in eventSnapshots) {
        for (final doc in snapshot.docs) {
          if (!handledEventIds.add(doc.id)) continue;
          final data = doc.data();
          final update = <String, dynamic>{};

          if (_isUnseenPendingEventInvite(data, currentUserId)) {
            update['inviteSeenAtMap.$currentUserId'] =
                FieldValue.serverTimestamp();
            if (_isLegacyUnreadPlanInvite(data, currentUserId)) {
              update['isReadByRecipient'] = true;
            }
          }

          if (_isUnseenCancelledEvent(data, currentUserId)) {
            update['cancellationSeenAtMap.$currentUserId'] =
                FieldValue.serverTimestamp();
          }

          if (update.isNotEmpty) {
            update['updatedAt'] = FieldValue.serverTimestamp();
            batch.set(doc.reference, update, SetOptions(merge: true));
            hasUpdates = true;
          }
        }
      }

      if (!hasUpdates) return;

      await batch.commit();

      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alle Mitteilungen wurden als gelesen markiert.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mitteilungen konnten nicht aktualisiert werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<String> _loadCurrentUserDisplayName() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return 'Jemand';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      final data = doc.data() ?? <String, dynamic>{};
      final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
      return name.isEmpty ? 'Jemand' : name;
    } catch (_) {
      return 'Jemand';
    }
  }


  Future<Map<String, String>> _loadUserNamesByIds(List<String> userIds) async {
    final ids = userIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const <String, String>{};

    final result = <String, String>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, (i + 10).clamp(0, ids.length));
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        result[doc.id] = name.isEmpty ? 'Jemand' : name;
      }
    }
    return result;
  }

  Future<void> _respondToFollowRequest({
    required String requesterUserId,
    String? notificationId,
    required bool accept,
  }) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || requesterUserId.trim().isEmpty) return;

    try {
      final notificationsRef = FirebaseFirestore.instance.collection('notifications');
      Future<List<DocumentReference<Map<String, dynamic>>>> matchingFollowRequestRefs() async {
        if (notificationId != null && notificationId.trim().isNotEmpty) {
          return [notificationsRef.doc(notificationId)];
        }

        final snapshot = await notificationsRef
            .where('toUserId', isEqualTo: currentUserId)
            .where('fromUserId', isEqualTo: requesterUserId)
            .where('type', isEqualTo: 'follow_request')
            .limit(10)
            .get();

        return snapshot.docs
            .where((doc) => ((doc.data()['status'] ?? 'pending').toString().trim().toLowerCase() == 'pending'))
            .map((doc) => doc.reference)
            .toList();
      }

      if (accept) {
        final myName = await _loadCurrentUserDisplayName();
        final batch = FirebaseFirestore.instance.batch();
        final currentUserRef =
        FirebaseFirestore.instance.collection('users').doc(currentUserId);
        final requesterRef =
        FirebaseFirestore.instance.collection('users').doc(requesterUserId);

        batch.set(
          currentUserRef,
          {
            'pendingFollowerIds': FieldValue.arrayRemove([requesterUserId]),
            'followerIds': FieldValue.arrayUnion([requesterUserId]),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        batch.set(
          requesterRef,
          {
            'followingIds': FieldValue.arrayUnion([currentUserId]),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        for (final ref in await matchingFollowRequestRefs()) {
          batch.update(ref, {
            'status': 'accepted',
            'read': true,
            'readAt': FieldValue.serverTimestamp(),
            'handledAt': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();

        await FirebaseFirestore.instance.collection('notifications').add({
          'type': 'follow_request_accepted',
          'toUserId': requesterUserId,
          'fromUserId': currentUserId,
          'fromUserName': myName,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });

        try {
          await NotificationDispatchService.instance.queueFollowAcceptedNotification(
            recipientUserId: requesterUserId,
            accepterId: currentUserId,
            accepterName: myName,
          );
        } catch (_) {}

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Follow-Anfrage angenommen.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(currentUserId).set({
        'pendingFollowerIds': FieldValue.arrayRemove([requesterUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      for (final ref in await matchingFollowRequestRefs()) {
        await ref.update({
          'status': 'declined',
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
          'handledAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follow-Anfrage abgelehnt.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follow-Anfrage konnte nicht bearbeitet werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _currentUserId;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          'Mitteilungen',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          TextButton(
            onPressed: currentUserId == null ? null : () => _markAllAsRead(),
            child: Text(
              'Alle gelesen',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: currentUserId == null
            ? Center(
          child: Text(
            'Du bist aktuell nicht eingeloggt.',
            style: theme.textTheme.bodyLarge,
          ),
        )
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('contact_threads')
              .where('participantMap.$currentUserId', isEqualTo: true)
              .snapshots(),
          builder: (context, threadSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('events')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, eventSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('notifications')
                      .where('toUserId', isEqualTo: currentUserId)
                      .limit(100)
                      .snapshots(),
                  builder: (context, notifSnapshot) {
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUserId)
                          .snapshots(),
                      builder: (context, userSnapshot) {
                        final isInitialLoading =
                            !threadSnapshot.hasData &&
                                !eventSnapshot.hasData &&
                                !notifSnapshot.hasData &&
                                !userSnapshot.hasData;

                        if (isInitialLoading &&
                            (threadSnapshot.connectionState == ConnectionState.waiting ||
                                eventSnapshot.connectionState == ConnectionState.waiting ||
                                notifSnapshot.connectionState == ConnectionState.waiting ||
                                userSnapshot.connectionState == ConnectionState.waiting)) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (userSnapshot.hasError && !userSnapshot.hasData) {
                          return Center(
                            child: Text(
                              'Mitteilungen konnten nicht geladen werden.',
                              style: theme.textTheme.bodyLarge,
                            ),
                          );
                        }

                        final currentUserData =
                            userSnapshot.data?.data() ?? const <String, dynamic>{};
                        final pendingFollowerIds = List<String>.from(
                          currentUserData['pendingFollowerIds'] ?? const [],
                        );

                        return FutureBuilder<Map<String, String>>(
                          future: _loadUserNamesByIds(pendingFollowerIds),
                          builder: (context, pendingNamesSnapshot) {
                            final notifications = _buildNotifications(
                              context: context,
                              currentUserId: currentUserId,
                              threadDocs: _safeDocs(threadSnapshot),
                              eventDocs: _safeDocs(eventSnapshot),
                              notifDocs: _safeDocs(notifSnapshot),
                              currentUserData: currentUserData,
                              pendingFollowerNames: pendingNamesSnapshot.data ?? const <String, String>{},
                            );

                            if (notifications.isEmpty) {
                              return _NotificationsEmptyState(
                                theme: theme,
                                colorScheme: colorScheme,
                              );
                            }

                            final grouped = <String, List<_NotificationItem>>{};
                            for (final item in notifications) {
                              final key = _sectionLabel(item.timestamp);
                              grouped.putIfAbsent(
                                key,
                                    () => <_NotificationItem>[],
                              ).add(item);
                            }

                            return ListView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              children: grouped.entries.map((entry) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 22),
                                  child: _NotificationSection(
                                    title: entry.key,
                                    items: entry.value,
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<_NotificationItem> _buildNotifications({
    required BuildContext context,
    required String currentUserId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> threadDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> eventDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs = const [],
    Map<String, dynamic> currentUserData = const <String, dynamic>{},
    Map<String, String> pendingFollowerNames = const <String, String>{},
  }) {
    final notifications = <_NotificationItem>[];
    final primary = Theme.of(context).colorScheme.primary;
    final renderedInviteEventIds = <String>{};
    final renderedCancelledEventIds = <String>{};

    // Notifications aus der notifications-Collection
    for (final doc in notifDocs) {
      final data = doc.data();
      if ((data['toUserId'] ?? '') != currentUserId) continue;

      final type = (data['type'] ?? '').toString().trim();
      final fromUserId = (data['fromUserId'] ?? '').toString().trim();
      final fromUserName =
      (data['fromUserName'] ?? 'Jemand').toString().trim();
      final timestamp = data['createdAt'] as Timestamp?;
      final notificationStatus =
      (data['status'] ?? 'pending').toString().trim().toLowerCase();

      if (type == 'follow_request') {
        notifications.add(
          _NotificationItem(
            title: 'Neue Follow-Anfrage',
            subtitle: '$fromUserName möchte dir auf CheckMyTime folgen.',
            timestamp: timestamp?.toDate() ?? DateTime.now(),
            icon: Icons.person_add_outlined,
            accentColor: primary,
            iconBackground: const Color(0xFFEDEBFF),
            iconColor: primary,
            onTap: () {
              if (fromUserId.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserPage(userId: fromUserId),
                ),
              );
            },
            actions: notificationStatus == 'pending'
                ? [
              _NotificationAction(
                label: 'Ablehnen',
                isPrimary: false,
                onTap: () => _respondToFollowRequest(
                  requesterUserId: fromUserId,
                  notificationId: doc.id,
                  accept: false,
                ),
              ),
              _NotificationAction(
                label: 'Annehmen',
                isPrimary: true,
                onTap: () => _respondToFollowRequest(
                  requesterUserId: fromUserId,
                  notificationId: doc.id,
                  accept: true,
                ),
              ),
            ]
                : const [],
          ),
        );
        continue;
      }

      if (type == 'follow_request_accepted') {
        notifications.add(
          _NotificationItem(
            title: 'Anfrage angenommen',
            subtitle: '$fromUserName hat deine Follow-Anfrage angenommen.',
            timestamp: timestamp?.toDate() ?? DateTime.now(),
            icon: Icons.favorite_outline_rounded,
            accentColor: const Color(0xFF19B35E),
            iconBackground: const Color(0xFFEAF8EF),
            iconColor: const Color(0xFF19B35E),
            onTap: () {
              if (fromUserId.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserPage(userId: fromUserId),
                ),
              );
            },
          ),
        );
        continue;
      }

      if (_isEventInviteNotificationType(type)) {
        final eventId = (data['eventId'] ?? '').toString().trim();
        if (eventId.isNotEmpty) {
          renderedInviteEventIds.add(eventId);
        }

        final title = (data['title'] ?? 'Event-Einladung erhalten')
            .toString()
            .trim();
        final body = (data['body'] ?? 'Du hast eine neue Event-Einladung erhalten.')
            .toString()
            .trim();

        notifications.add(
          _NotificationItem(
            title: title.isEmpty ? 'Event-Einladung erhalten' : title,
            subtitle: body.isEmpty
                ? 'Du hast eine neue Event-Einladung erhalten.'
                : body,
            timestamp: timestamp?.toDate() ?? DateTime.now(),
            icon: Icons.calendar_month_outlined,
            accentColor: primary,
            iconBackground: const Color(0xFFEDEBFF),
            iconColor: primary,
            onTap: () {
              if (eventId.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailPage(
                    eventId: eventId,
                    view: EventDetailView.invitation,
                  ),
                ),
              );
            },
          ),
        );
        continue;
      }

      if (_isEventCancellationNotificationType(type)) {
        final eventId = (data['eventId'] ?? '').toString().trim();
        if (eventId.isNotEmpty) {
          renderedCancelledEventIds.add(eventId);
        }

        final title = (data['title'] ?? 'Event abgesagt')
            .toString()
            .trim();
        final body =
        (data['body'] ?? 'Ein Event, an dem du beteiligt warst, wurde abgesagt.')
            .toString()
            .trim();

        notifications.add(
          _NotificationItem(
            title: title.isEmpty ? 'Event abgesagt' : title,
            subtitle: body.isEmpty
                ? 'Ein Event, an dem du beteiligt warst, wurde abgesagt.'
                : body,
            timestamp: timestamp?.toDate() ?? DateTime.now(),
            icon: Icons.event_busy_rounded,
            accentColor: const Color(0xFFE46B46),
            iconBackground: const Color(0xFFFFECE8),
            iconColor: const Color(0xFFE46B46),
            onTap: () {
              if (eventId.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailPage(
                    eventId: eventId,
                    view: EventDetailView.invitation,
                  ),
                ),
              );
            },
          ),
        );
        continue;
      }
    }

    final pendingFollowerIds = List<String>.from(
      currentUserData['pendingFollowerIds'] ?? const [],
    );
    final renderedPendingFollowUserIds = notifDocs
        .where((doc) {
      final data = doc.data();
      return (data['type'] ?? '').toString().trim() == 'follow_request' &&
          (data['toUserId'] ?? '').toString().trim() == currentUserId &&
          ((data['status'] ?? 'pending').toString().trim().toLowerCase() == 'pending');
    })
        .map((doc) => (doc.data()['fromUserId'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final requesterUserId in pendingFollowerIds) {
      if (renderedPendingFollowUserIds.contains(requesterUserId)) continue;
      final requesterName = pendingFollowerNames[requesterUserId] ?? 'Jemand';
      notifications.add(
        _NotificationItem(
          title: 'Neue Follow-Anfrage',
          subtitle: '$requesterName möchte dir auf CheckMyTime folgen.',
          timestamp: DateTime.now(),
          icon: Icons.person_add_outlined,
          accentColor: primary,
          iconBackground: const Color(0xFFEDEBFF),
          iconColor: primary,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserPage(userId: requesterUserId),
              ),
            );
          },
          actions: [
            _NotificationAction(
              label: 'Ablehnen',
              isPrimary: false,
              onTap: () => _respondToFollowRequest(
                requesterUserId: requesterUserId,
                accept: false,
              ),
            ),
            _NotificationAction(
              label: 'Annehmen',
              isPrimary: true,
              onTap: () => _respondToFollowRequest(
                requesterUserId: requesterUserId,
                accept: true,
              ),
            ),
          ],
        ),
      );
    }

    for (final doc in threadDocs) {
      final data = doc.data();
      if (data['hiddenFor_$currentUserId'] == true) continue;

      final unreadCount = (data['unreadCountFor_$currentUserId'] ?? 0) as int;
      if (unreadCount <= 0) continue;

      final participants = List<String>.from(data['participants'] ?? const []);
      final otherParticipantId = _otherParticipantId(participants, currentUserId);
      final contactNames = Map<String, dynamic>.from(data['contactNames'] ?? const {});
      final contactPhones = Map<String, dynamic>.from(data['contactPhones'] ?? const {});
      final contactName =
      (contactNames[otherParticipantId] ?? 'Kontakt').toString().trim();
      final phoneNumber = (contactPhones[otherParticipantId] ?? '').toString().trim();
      final previewText = _threadPreviewText(data);
      final timestamp =
          data['updatedAt'] as Timestamp? ?? data['lastInteractionAt'] as Timestamp?;

      notifications.add(
        _NotificationItem(
          title: unreadCount == 1 ? 'Neue Nachricht' : '$unreadCount neue Nachrichten',
          subtitle: '$contactName: $previewText',
          timestamp: timestamp?.toDate() ?? DateTime.now(),
          icon: Icons.chat_bubble_outline_rounded,
          accentColor: primary,
          iconBackground: const Color(0xFFEDEBFF),
          iconColor: primary,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ContactThreadPage(
                  contactId: otherParticipantId,
                  contactName: contactName.isEmpty ? 'Kontakt' : contactName,
                  phoneNumber: phoneNumber,
                ),
              ),
            );
          },
        ),
      );
    }

    for (final doc in eventDocs) {
      final data = doc.data();
      final title = (data['title'] ?? 'Event').toString().trim();
      final timestamp =
          data['updatedAt'] as Timestamp? ??
              data['createdAt'] as Timestamp? ??
              data['eventDate'] as Timestamp?;

      if (_isUnseenPendingEventInvite(data, currentUserId) &&
          !renderedInviteEventIds.contains(doc.id)) {
        notifications.add(
          _NotificationItem(
            title: 'Event-Einladung erhalten',
            subtitle: 'Du wurdest zu „$title“ eingeladen.',
            timestamp: timestamp?.toDate() ?? DateTime.now(),
            icon: Icons.calendar_month_outlined,
            accentColor: primary,
            iconBackground: const Color(0xFFEDEBFF),
            iconColor: primary,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailPage(
                    eventId: doc.id,
                    view: EventDetailView.invitation,
                  ),
                ),
              );
            },
          ),
        );
      }

      if (_isUnseenCancelledEvent(data, currentUserId) &&
          !renderedCancelledEventIds.contains(doc.id)) {
        notifications.add(
          _NotificationItem(
            title: 'Event abgesagt',
            subtitle: '„$title“ wurde abgesagt.',
            timestamp: timestamp?.toDate() ?? DateTime.now(),
            icon: Icons.event_busy_rounded,
            accentColor: const Color(0xFFE46B46),
            iconBackground: const Color(0xFFFFECE8),
            iconColor: const Color(0xFFE46B46),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailPage(
                    eventId: doc.id,
                    view: EventDetailView.invitation,
                  ),
                ),
              );
            },
          ),
        );
      }

      final joinDecision = _joinDecisionStatusForRequester(data, currentUserId);
      if (joinDecision != null) {
        final isAccepted = joinDecision == 'accepted';
        notifications.add(
          _NotificationItem(
            title: isAccepted ? 'Anfrage angenommen' : 'Anfrage abgelehnt',
            subtitle:
            'Deine Anfrage für „$title“ wurde ${isAccepted ? 'angenommen' : 'abgelehnt'}.',
            timestamp: timestamp?.toDate() ?? DateTime.now(),
            icon: isAccepted
                ? Icons.check_circle_outline_rounded
                : Icons.cancel_outlined,
            accentColor:
            isAccepted ? const Color(0xFF19B35E) : const Color(0xFFE46B46),
            iconBackground:
            isAccepted ? const Color(0xFFEAF8EF) : const Color(0xFFFFECE8),
            iconColor:
            isAccepted ? const Color(0xFF19B35E) : const Color(0xFFE46B46),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailPage(
                    eventId: doc.id,
                    view: EventDetailView.invitation,
                  ),
                ),
              );
            },
          ),
        );
      }

      final pendingOwnerCount = _pendingOwnerRequestCount(data, currentUserId);
      if (pendingOwnerCount > 0) {
        notifications.add(
          _NotificationItem(
            title: pendingOwnerCount == 1
                ? 'Neue Teilnahme-Anfrage'
                : '$pendingOwnerCount neue Teilnahme-Anfragen',
            subtitle:
            'Für „$title“ wartet ${pendingOwnerCount == 1 ? 'eine neue Anfrage' : '$pendingOwnerCount neue Anfragen'}.',
            timestamp: timestamp?.toDate() ?? DateTime.now(),
            icon: Icons.group_add_outlined,
            accentColor: primary,
            iconBackground: const Color(0xFFEDEBFF),
            iconColor: primary,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailPage(
                    eventId: doc.id,
                    view: EventDetailView.myEvent,
                  ),
                ),
              );
            },
          ),
        );
      }

      final ownerResponseStatus = _ownerResponseStatusForOwner(data, currentUserId);
      if (ownerResponseStatus != null) {
        final isAccepted = ownerResponseStatus == 'accepted';
        final isDeclined = ownerResponseStatus == 'declined';
        final accent = isAccepted
            ? const Color(0xFF19B35E)
            : isDeclined
            ? const Color(0xFFE46B46)
            : const Color(0xFFE39B2E);
        final background = isAccepted
            ? const Color(0xFFEAF8EF)
            : isDeclined
            ? const Color(0xFFFFECE8)
            : const Color(0xFFFFF4E6);

        notifications.add(
          _NotificationItem(
            title: isAccepted
                ? 'Teilnahme bestätigt'
                : isDeclined
                ? 'Teilnahme abgesagt'
                : 'Teilnahme aktualisiert',
            subtitle: 'Bei „$title“ gab es eine neue Rückmeldung.',
            timestamp: timestamp?.toDate() ?? DateTime.now(),
            icon: isAccepted
                ? Icons.check_circle_outline_rounded
                : isDeclined
                ? Icons.close_rounded
                : Icons.info_outline_rounded,
            accentColor: accent,
            iconBackground: background,
            iconColor: accent,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailPage(
                    eventId: doc.id,
                    view: EventDetailView.myEvent,
                  ),
                ),
              );
            },
          ),
        );
      }
    }

    notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return notifications;
  }

  static String _otherParticipantId(List<String> participants, String currentUserId) {
    for (final id in participants) {
      if (id != currentUserId) return id;
    }
    return '';
  }

  static String _threadPreviewText(Map<String, dynamic> data) {
    final lastMessageType = (data['lastMessageType'] ??
        data['messageType'] ??
        data['lastInteractionType'] ??
        '')
        .toString()
        .trim()
        .toLowerCase();

    final typingBy = (data['typingBy'] ?? data['typingUserId'] ?? '').toString().trim();
    final typingAt =
        data['typingAt'] as Timestamp? ?? data['typingUpdatedAt'] as Timestamp?;
    final isTypingFresh = typingBy.isNotEmpty &&
        typingAt != null &&
        DateTime.now().difference(typingAt.toDate()) <= const Duration(seconds: 8);

    if (isTypingFresh) {
      return 'Schreibt gerade…';
    }

    if (lastMessageType == 'audio' || lastMessageType == 'voice') {
      return 'Sprachnachricht';
    }

    final previewCandidates = [
      data['lastMessageText'],
      data['lastMessage'],
      data['lastMessagePreview'],
      data['lastText'],
      data['lastInteractionText'],
      data['lastAppointmentTitle'],
    ];

    for (final candidate in previewCandidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    return 'Neue Aktivität';
  }

  static bool _isPendingEventInvite(Map<String, dynamic> data, String currentUserId) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final invitedUserIds = List<String>.from(data['invitedUserIds'] ?? const []);
    final acceptedUserIds = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybeUserIds = List<String>.from(data['maybeUserIds'] ?? const []);
    final declinedUserIds = List<String>.from(data['declinedUserIds'] ?? const []);

    if (createdBy == currentUserId) return false;
    if (!invitedUserIds.contains(currentUserId)) return false;
    if (acceptedUserIds.contains(currentUserId)) return false;
    if (maybeUserIds.contains(currentUserId)) return false;
    if (declinedUserIds.contains(currentUserId)) return false;
    return true;
  }

  static Map<String, dynamic> _inviteSeenAtMap(Map<String, dynamic> data) {
    return Map<String, dynamic>.from(data['inviteSeenAtMap'] ?? const <String, dynamic>{});
  }

  static String _responseForUser(Map<String, dynamic> data, String currentUserId) {
    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    final directResponse =
    (responseMap[currentUserId] ?? '').toString().trim().toLowerCase();

    final acceptedUserIds = List<String>.from(data['acceptedUserIds'] ?? const []);
    final maybeUserIds = List<String>.from(data['maybeUserIds'] ?? const []);
    final declinedUserIds = List<String>.from(data['declinedUserIds'] ?? const []);

    if (acceptedUserIds.contains(currentUserId)) return 'accepted';
    if (maybeUserIds.contains(currentUserId)) return 'maybe';
    if (declinedUserIds.contains(currentUserId)) return 'declined';
    if (directResponse.isNotEmpty) return directResponse;
    return 'pending';
  }

  static bool _hasSeenInvite(Map<String, dynamic> data, String currentUserId) {
    if (currentUserId.trim().isEmpty) return false;
    final seenMap = _inviteSeenAtMap(data);
    if (seenMap[currentUserId] != null) return true;

    final response = _responseForUser(data, currentUserId);
    return response == 'accepted' || response == 'maybe' || response == 'declined';
  }

  static bool _isLegacyUnreadPlanInvite(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    final memberIds = List<String>.from(data['memberIds'] ?? const []);

    if (createdBy.isEmpty || createdBy == currentUserId) return false;
    if (!memberIds.contains(currentUserId)) return false;
    return data['isReadByRecipient'] != true;
  }

  static bool _isUnseenPendingEventInvite(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    return (_isPendingEventInvite(data, currentUserId) &&
        !_hasSeenInvite(data, currentUserId)) ||
        _isLegacyUnreadPlanInvite(data, currentUserId);
  }


  static bool _isCancelledEventStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'cancelled' || normalized == 'canceled';
  }

  static Map<String, dynamic> _cancellationSeenAtMap(
      Map<String, dynamic> data,
      ) {
    return Map<String, dynamic>.from(
      data['cancellationSeenAtMap'] ?? const <String, dynamic>{},
    );
  }

  static bool _isUserAffectedByCancelledEvent(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy.isEmpty || createdBy == currentUserId) return false;

    final invitedUserIds = List<String>.from(
      data['invitedUserIds'] ?? const [],
    );
    final memberIds = List<String>.from(data['memberIds'] ?? const []);
    final acceptedUserIds = List<String>.from(
      data['acceptedUserIds'] ?? const [],
    );
    final maybeUserIds = List<String>.from(data['maybeUserIds'] ?? const []);
    final declinedUserIds = List<String>.from(
      data['declinedUserIds'] ?? const [],
    );
    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    final response =
    (responseMap[currentUserId] ?? '').toString().trim().toLowerCase();

    if (declinedUserIds.contains(currentUserId) || response == 'declined') {
      return false;
    }

    return invitedUserIds.contains(currentUserId) ||
        memberIds.contains(currentUserId) ||
        acceptedUserIds.contains(currentUserId) ||
        maybeUserIds.contains(currentUserId) ||
        responseMap.containsKey(currentUserId);
  }

  static bool _hasSeenCancelledEvent(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    if (currentUserId.trim().isEmpty) return false;
    final seenMap = _cancellationSeenAtMap(data);
    return seenMap[currentUserId] != null;
  }

  static bool _isUnseenCancelledEvent(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final eventStatus = (data['status'] ?? '').toString();
    return _isCancelledEventStatus(eventStatus) &&
        _isUserAffectedByCancelledEvent(data, currentUserId) &&
        !_hasSeenCancelledEvent(data, currentUserId);
  }

  static String? _joinDecisionStatusForRequester(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy == currentUserId) return null;

    final joinMode = (data['joinMode'] ?? '').toString().trim().toLowerCase();
    if (joinMode != 'request') return null;

    final response = _responseForUser(data, currentUserId);
    if (response == 'accepted' || response == 'declined') {
      return response;
    }
    return null;
  }

  static int _pendingOwnerRequestCount(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy != currentUserId) return 0;

    final explicitRequestUserIds = List<String>.from(data['requestUserIds'] ?? const []);
    if (explicitRequestUserIds.isNotEmpty) {
      return explicitRequestUserIds.where((id) => id != currentUserId).length;
    }

    final joinMode = (data['joinMode'] ?? '').toString().trim().toLowerCase();
    if (joinMode != 'request') return 0;

    final responseMap =
    Map<String, dynamic>.from(data['responseMap'] ?? const <String, dynamic>{});

    return responseMap.entries.where((entry) {
      return entry.key != currentUserId &&
          entry.value.toString().trim().toLowerCase() == 'pending';
    }).length;
  }

  static String? _ownerResponseStatusForOwner(
      Map<String, dynamic> data,
      String currentUserId,
      ) {
    final createdBy = (data['createdBy'] ?? '').toString().trim();
    if (createdBy != currentUserId) return null;

    final responseMap =
    Map<String, dynamic>.from(data['responseMap'] ?? const <String, dynamic>{});
    final userIds = <String>{
      ...List<String>.from(data['invitedUserIds'] ?? const []),
      ...List<String>.from(data['memberIds'] ?? const []),
      ...List<String>.from(data['acceptedUserIds'] ?? const []),
      ...List<String>.from(data['maybeUserIds'] ?? const []),
      ...List<String>.from(data['declinedUserIds'] ?? const []),
      ...responseMap.keys.map((key) => key.toString().trim()),
    }..removeWhere((id) => id.trim().isEmpty || id == currentUserId);

    for (final userId in userIds) {
      if (List<String>.from(data['acceptedUserIds'] ?? const []).contains(userId)) {
        return 'accepted';
      }
      if (List<String>.from(data['declinedUserIds'] ?? const []).contains(userId)) {
        return 'declined';
      }
      if (List<String>.from(data['maybeUserIds'] ?? const []).contains(userId)) {
        return 'maybe';
      }

      final status = (responseMap[userId] ?? '').toString().trim().toLowerCase();
      if (status.isNotEmpty && status != 'pending') {
        return status;
      }
    }

    return null;
  }

  static String _sectionLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(date.year, date.month, date.day);

    if (target == today) return 'HEUTE';
    if (target == yesterday) return 'GESTERN';
    return DateFormat('dd. MMMM', 'de_DE').format(target).toUpperCase();
  }
}

class _NotificationSection extends StatelessWidget {
  final String title;
  final List<_NotificationItem> items;

  const _NotificationSection({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isLast = index == items.length - 1;
              return _NotificationRow(
                item: item,
                showDivider: !isLast,
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _NotificationItem {
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final IconData icon;
  final Color accentColor;
  final Color iconBackground;
  final Color iconColor;
  final VoidCallback onTap;
  final List<_NotificationAction> actions;

  const _NotificationItem({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.accentColor,
    required this.iconBackground,
    required this.iconColor,
    required this.onTap,
    this.actions = const [],
  });
}

class _NotificationAction {
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  const _NotificationAction({
    required this.label,
    required this.isPrimary,
    required this.onTap,
  });
}

class _NotificationRow extends StatelessWidget {
  final _NotificationItem item;
  final bool showDivider;

  const _NotificationRow({
    required this.item,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    height: 48,
                    decoration: BoxDecoration(
                      color: item.accentColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: item.iconBackground,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.icon,
                      color: item.iconColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              DateFormat('HH:mm', 'de_DE').format(item.timestamp),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.subtitle,
                          maxLines: item.actions.isEmpty ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                        if (item.actions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: item.actions.map((action) {
                              if (action.isPrimary) {
                                return FilledButton(
                                  onPressed: action.onTap,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                  ),
                                  child: Text(action.label),
                                );
                              }

                              return OutlinedButton(
                                onPressed: action.onTap,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                                child: Text(action.label),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (showDivider) ...[
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.65),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _NotificationsEmptyState({
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.notifications_none_rounded,
            size: 36,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Keine Mitteilungen',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Neue Nachrichten, Einladungen und Reaktionen auf deine Events erscheinen später hier.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
