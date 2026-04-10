import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/pages/create_event_page.dart';
import 'package:termini/checkmytime/services/notification_dispatch_service.dart';

class ContactThreadPage extends StatefulWidget {
  final String contactId;
  final String contactName;
  final String phoneNumber;

  const ContactThreadPage({
    super.key,
    required this.contactId,
    required this.contactName,
    required this.phoneNumber,
  });

  @override
  State<ContactThreadPage> createState() => _ContactThreadPageState();
}

class _ContactThreadPageState extends State<ContactThreadPage>
    with SingleTickerProviderStateMixin {
  final Set<String> _updatingEventIds = <String>{};
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();

  late final TabController _tabController;

  String _resolvedContactName = '';
  String _resolvedPhoneNumber = '';
  String _profileImageUrl = '';

  bool _isSendingMessage = false;
  bool _isMarkingIncomingMessagesAsRead = false;
  int _lastRenderedMessageCount = -1;

  String get _threadId {
    final ids = [FirebaseAuth.instance.currentUser?.uid ?? '', widget.contactId]
      ..sort();
    return '${ids[0]}_${ids[1]}';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0)
      ..addListener(_handleTabChanged);
    _resolvedContactName = widget.contactName.trim();
    _resolvedPhoneNumber = widget.phoneNumber.trim();
    _loadContactProfile();
    _markThreadAsRead();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _messageController.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;

    if (_tabController.index == 0) {
      _markIncomingMessagesAsRead();
      _scheduleScrollToBottom();
    }
  }

  Future<void> _loadContactProfile() async {
    if (widget.contactId.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.contactId)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;

      setState(() {
        final firestoreName =
        (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final firestorePhone = (data['phoneNumber'] ?? '').toString().trim();
        final firestoreImage =
        (data['profileImageUrl'] ?? '').toString().trim();

        if (firestoreName.isNotEmpty) {
          _resolvedContactName = firestoreName;
        }
        if (firestorePhone.isNotEmpty) {
          _resolvedPhoneNumber = firestorePhone;
        }
        _profileImageUrl = firestoreImage;
      });
    } catch (_) {}
  }

  Future<void> _markThreadAsRead() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || widget.contactId.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(_threadId)
          .set({
        'unreadCountFor_$currentUserId': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _markIncomingMessagesAsRead() async {
    if (_isMarkingIncomingMessagesAsRead) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || widget.contactId.isEmpty) return;

    _isMarkingIncomingMessagesAsRead = true;

    try {
      final unreadSnapshot = await FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(_threadId)
          .collection('messages')
          .where('receiverId', isEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      if (unreadSnapshot.docs.isEmpty) {
        await FirebaseFirestore.instance
            .collection('contact_threads')
            .doc(_threadId)
            .set({
          'unreadCountFor_$currentUserId': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      final batch = FirebaseFirestore.instance.batch();

      for (final doc in unreadSnapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      batch.set(
        FirebaseFirestore.instance.collection('contact_threads').doc(_threadId),
        {
          'unreadCountFor_$currentUserId': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (_) {
      // ignore and retry next time the thread becomes active
    } finally {
      _isMarkingIncomingMessagesAsRead = false;
    }
  }

  Future<void> _openCreateEventPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateEventPage(
          initialSelectedUserId: widget.contactId,
          initialSelectedUserName: _resolvedContactName.isEmpty
              ? widget.contactName
              : _resolvedContactName,
          initialSelectedUserPhone: _resolvedPhoneNumber.isEmpty
              ? widget.phoneNumber
              : _resolvedPhoneNumber,
          initialSelectedUserImageUrl:
          _profileImageUrl.isEmpty ? null : _profileImageUrl,
        ),
      ),
    );
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _scheduleScrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScrollController.hasClients) return;

      final maxScrollExtent = _messagesScrollController.position.maxScrollExtent;

      if (animated) {
        _messagesScrollController.animateTo(
          maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _messagesScrollController.jumpTo(maxScrollExtent);
      }
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateHeader(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    return DateFormat('EEEE, d. MMMM', 'de_DE').format(timestamp.toDate());
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '--:--';
    return DateFormat('HH:mm', 'de_DE').format(timestamp.toDate());
  }

  String _formatMessageBubbleTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    return DateFormat('HH:mm', 'de_DE').format(timestamp.toDate());
  }

  String _formatMessageDayChip(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(date.year, date.month, date.day);

    if (target == today) return 'Heute';
    if (target == yesterday) return 'Gestern';
    return DateFormat('EEEE, d. MMMM', 'de_DE').format(date);
  }

  String _kindLabel(String kind) {
    switch (kind) {
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

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'appointment':
        return Icons.event_available_rounded;
      case 'activity':
        return Icons.groups_2_outlined;
      case 'service':
        return Icons.content_cut_rounded;
      case 'open':
      default:
        return Icons.celebration_outlined;
    }
  }

  Timestamp? _eventTimestamp(Map<String, dynamic> data) {
    return data['scheduledAt'] as Timestamp? ?? data['eventDate'] as Timestamp?;
  }

  String _eventKind(Map<String, dynamic> data) {
    final kind = (data['kind'] ?? data['type'] ?? 'open').toString().trim();
    return kind.isEmpty ? 'open' : kind;
  }

  bool _listContainsUser(dynamic value, String userId) {
    if (userId.isEmpty) return false;
    if (value is Iterable) {
      return value.map((e) => e.toString()).contains(userId);
    }
    return false;
  }

  bool _eventContainsUser(Map<String, dynamic> data, String userId) {
    if (userId.isEmpty) return false;

    if ((data['createdBy'] ?? '').toString() == userId) {
      return true;
    }

    final responseMap = data['responseMap'];
    if (responseMap is Map && responseMap.containsKey(userId)) {
      return true;
    }

    return _listContainsUser(data['memberIds'], userId) ||
        _listContainsUser(data['participantIds'], userId) ||
        _listContainsUser(data['invitedUserIds'], userId) ||
        _listContainsUser(data['acceptedUserIds'], userId) ||
        _listContainsUser(data['maybeUserIds'], userId) ||
        _listContainsUser(data['declinedUserIds'], userId);
  }

  String _responseForUser(Map<String, dynamic> data, String userId) {
    final responseMap = data['responseMap'];
    if (responseMap is Map && responseMap[userId] != null) {
      final mapped = responseMap[userId].toString().trim();
      if (mapped.isNotEmpty) return mapped;
    }

    if ((data['createdBy'] ?? '').toString() == userId) {
      return 'accepted';
    }
    if (_listContainsUser(data['acceptedUserIds'], userId) ||
        _listContainsUser(data['participantIds'], userId)) {
      return 'accepted';
    }
    if (_listContainsUser(data['maybeUserIds'], userId)) {
      return 'maybe';
    }
    if (_listContainsUser(data['declinedUserIds'], userId)) {
      return 'declined';
    }
    if (_listContainsUser(data['invitedUserIds'], userId) ||
        _listContainsUser(data['memberIds'], userId)) {
      return 'pending';
    }
    return 'pending';
  }

  String _responseLabel(String response) {
    switch (response) {
      case 'accepted':
        return 'Bestätigt';
      case 'declined':
        return 'Abgelehnt';
      case 'maybe':
        return 'Vielleicht';
      case 'pending':
      default:
        return 'Ausstehend';
    }
  }

  Color _responseColor(ColorScheme colorScheme, String response) {
    switch (response) {
      case 'accepted':
        return Colors.green;
      case 'declined':
        return colorScheme.error;
      case 'maybe':
        return Colors.orange;
      case 'pending':
      default:
        return colorScheme.primary;
    }
  }

  Future<void> _updateEventResponseStatus({
    required String eventId,
    required String newStatus,
    required String title,
  }) async {
    if (_updatingEventIds.contains(eventId)) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    setState(() {
      _updatingEventIds.add(eventId);
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final docRef = firestore.collection('events').doc(eventId);
      final snapshot = await docRef.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      final accepted = List<String>.from(data['acceptedUserIds'] ?? const []);
      final maybe = List<String>.from(data['maybeUserIds'] ?? const []);
      final declined = List<String>.from(data['declinedUserIds'] ?? const []);
      final participantIds = List<String>.from(data['participantIds'] ?? const []);
      final invitedUserIds = List<String>.from(data['invitedUserIds'] ?? const []);
      final memberIds = List<String>.from(data['memberIds'] ?? const []);
      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      );

      accepted.remove(currentUserId);
      maybe.remove(currentUserId);
      declined.remove(currentUserId);
      participantIds.remove(currentUserId);

      if (newStatus == 'accepted') {
        accepted.add(currentUserId);
        participantIds.add(currentUserId);
      } else if (newStatus == 'maybe') {
        maybe.add(currentUserId);
      } else if (newStatus == 'declined') {
        declined.add(currentUserId);
      }

      if (!invitedUserIds.contains(currentUserId) &&
          (newStatus == 'accepted' || newStatus == 'maybe' || newStatus == 'declined')) {
        invitedUserIds.add(currentUserId);
      }
      if (!memberIds.contains(currentUserId)) {
        memberIds.add(currentUserId);
      }

      responseMap[currentUserId] = newStatus;

      await docRef.update({
        'acceptedUserIds': accepted.toSet().toList(),
        'maybeUserIds': maybe.toSet().toList(),
        'declinedUserIds': declined.toSet().toList(),
        'participantIds': participantIds.toSet().toList(),
        'invitedUserIds': invitedUserIds.toSet().toList(),
        'memberIds': memberIds.toSet().toList(),
        'responseMap': responseMap,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showMessage(
        newStatus == 'accepted'
            ? 'Planung wurde angenommen.'
            : 'Planung wurde abgelehnt.',
      );

      try {
        final currentUserDoc = await firestore.collection('users').doc(currentUserId).get();
        final currentUserData = currentUserDoc.data() ?? <String, dynamic>{};
        final senderName = (currentUserData['displayName'] ?? currentUserData['name'] ?? 'Unbekannt')
            .toString()
            .trim();

        await NotificationDispatchService.instance.queueEventInviteNotifications(
          recipientUserIds: [(data['createdBy'] ?? '').toString()].where((id) => id.isNotEmpty).toList(),
          senderId: currentUserId,
          senderName: senderName.isEmpty ? 'Unbekannt' : senderName,
          eventId: eventId,
          eventTitle: title,
        );
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      _showMessage('Status konnte nicht aktualisiert werden.');
    } finally {
      if (mounted) {
        setState(() {
          _updatingEventIds.remove(eventId);
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSendingMessage) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid;
    if (currentUserId == null || widget.contactId.isEmpty) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSendingMessage = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final participants = [currentUserId, widget.contactId]..sort();

      final currentUserDoc =
      await firestore.collection('users').doc(currentUserId).get();
      final contactUserDoc =
      await firestore.collection('users').doc(widget.contactId).get();
      final threadRef = firestore.collection('contact_threads').doc(_threadId);
      final existingThread = await threadRef.get();
      final messageRef = threadRef.collection('messages').doc();

      final currentUserData = currentUserDoc.data() ?? <String, dynamic>{};
      final contactUserData = contactUserDoc.data() ?? <String, dynamic>{};

      final currentUserName =
      (currentUserData['displayName'] ?? currentUserData['name'] ?? 'Ich')
          .toString()
          .trim();
      final currentUserPhone =
      (currentUserData['phoneNumber'] ?? '').toString().trim();
      final contactName =
      (contactUserData['displayName'] ??
          contactUserData['name'] ??
          widget.contactName)
          .toString()
          .trim();
      final contactPhone =
      (contactUserData['phoneNumber'] ?? '').toString().trim();

      final batch = firestore.batch();

      batch.set(messageRef, {
        'threadId': _threadId,
        'text': text,
        'type': 'text',
        'senderId': currentUserId,
        'receiverId': widget.contactId,
        'participants': participants,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final threadData = <String, dynamic>{
        'participants': participants,
        'participantMap': {
          for (final id in participants) id: true,
        },
        'contactNames': {
          currentUserId: currentUserName.isEmpty ? 'Ich' : currentUserName,
          widget.contactId:
          contactName.isEmpty ? widget.contactName : contactName,
        },
        'contactPhones': {
          currentUserId: currentUserPhone,
          widget.contactId: contactPhone,
        },
        'lastMessageText': text,
        'lastInteractionType': 'message',
        'lastInteractionAt': FieldValue.serverTimestamp(),
        'lastCreatedBy': currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
        'hiddenFor_$currentUserId': false,
        'hiddenFor_${widget.contactId}': false,
        'unreadCountFor_$currentUserId': 0,
        'unreadCountFor_${widget.contactId}': FieldValue.increment(1),
      };

      if (!existingThread.exists) {
        threadData['createdAt'] = FieldValue.serverTimestamp();
      }

      batch.set(threadRef, threadData, SetOptions(merge: true));

      await batch.commit();

      try {
        await NotificationDispatchService.instance.queueChatMessageNotification(
          recipientUserId: widget.contactId,
          senderId: currentUserId,
          senderName: currentUserName.isEmpty ? 'Ich' : currentUserName,
          senderPhoneNumber: currentUserPhone,
          messageText: text,
        );
      } catch (_) {}

      _messageController.clear();
      _scheduleScrollToBottom();
    } catch (_) {
      if (!mounted) return;
      _showMessage('Nachricht konnte nicht gesendet werden.');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  Widget _buildHeaderAvatar(ColorScheme colorScheme, String safeName) {
    if (_profileImageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(_profileImageUrl),
      );
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      child: Text(
        safeName.characters.first.toUpperCase(),
        style: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildContactAvatar(ThemeData theme, String safeName) {
    if (_profileImageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(_profileImageUrl),
      );
    }

    return CircleAvatar(
      radius: 22,
      child: Text(
        safeName.characters.first.toUpperCase(),
        style: theme.textTheme.labelLarge,
      ),
    );
  }

  Widget _buildPlansIntroCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        'Hier siehst du alle gemeinsamen Planungen mit $safeName – Termine, Treffen, Dienstleistungen und Events.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPlansEmptyState({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
  }) {
    return Column(
      children: [
        _buildPlansIntroCard(
          theme: theme,
          colorScheme: colorScheme,
          safeName: safeName,
        ),
        const SizedBox(height: 28),
        Icon(
          Icons.event_note_outlined,
          size: 72,
          color: colorScheme.primary.withValues(alpha: 0.70),
        ),
        const SizedBox(height: 18),
        Text(
          'Noch keine gemeinsamen Planungen',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Über das Kalender-Icon oben rechts kannst du direkt mit $safeName etwas planen.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
    required String eventId,
    required Map<String, dynamic> data,
    required String currentUserId,
  }) {
    final createdBy = (data['createdBy'] ?? '').toString();
    final title = (data['title'] ?? 'Event').toString().trim();
    final description = (data['description'] ?? '').toString().trim();
    final timestamp = _eventTimestamp(data);
    final kind = _eventKind(data);
    final myResponse = _responseForUser(data, currentUserId);
    final contactResponse = _responseForUser(data, widget.contactId);
    final isCreatedByMe = createdBy == currentUserId;
    final visibleResponse = isCreatedByMe ? contactResponse : myResponse;
    final statusColor = _responseColor(colorScheme, visibleResponse);
    final isUpdating = _updatingEventIds.contains(eventId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    _formatDateHeader(timestamp),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.schedule_outlined,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(timestamp),
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
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildContactAvatar(theme, safeName),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  safeName,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _kindIcon(kind),
                                      size: 14,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _kindLabel(kind),
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title.isEmpty ? 'Ohne Titel' : title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isCreatedByMe
                                ? 'Von dir erstellt'
                                : 'Von $safeName vorgeschlagen',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              description,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
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
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _responseLabel(visibleResponse),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isCreatedByMe && myResponse == 'pending') ...[
                  const SizedBox(height: 14),
                  if (isUpdating)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _updateEventResponseStatus(
                              eventId: eventId,
                              newStatus: 'declined',
                              title: title,
                            ),
                            child: const Text('Ablehnen'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _updateEventResponseStatus(
                              eventId: eventId,
                              newStatus: 'accepted',
                              title: title,
                            ),
                            child: const Text('Annehmen'),
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeSharedPlanDocs({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> createdByMeDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> createdByContactDocs,
    required String currentUserId,
  }) {
    final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    for (final doc in createdByMeDocs) {
      final data = doc.data();
      if (_eventContainsUser(data, widget.contactId)) {
        merged[doc.id] = doc;
      }
    }

    for (final doc in createdByContactDocs) {
      final data = doc.data();
      if (_eventContainsUser(data, currentUserId)) {
        merged[doc.id] = doc;
      }
    }

    final result = merged.values.toList()
      ..sort((a, b) {
        final aTs = _eventTimestamp(a.data());
        final bTs = _eventTimestamp(b.data());
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return aTs.compareTo(bTs);
      });

    return result;
  }

  Widget _buildPlansTab({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
    required String currentUserId,
  }) {
    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('events')
          .where('createdBy', isEqualTo: currentUserId)
          .snapshots(),
      builder: (context, mySnapshot) {
        if (mySnapshot.hasError) {
          return Center(
            child: Text(
              'Fehler beim Laden der Planungen.',
              style: theme.textTheme.bodyLarge,
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore
              .collection('events')
              .where('createdBy', isEqualTo: widget.contactId)
              .snapshots(),
          builder: (context, contactSnapshot) {
            if (mySnapshot.connectionState == ConnectionState.waiting ||
                contactSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (contactSnapshot.hasError) {
              return Center(
                child: Text(
                  'Fehler beim Laden der Planungen.',
                  style: theme.textTheme.bodyLarge,
                ),
              );
            }

            final docs = _mergeSharedPlanDocs(
              createdByMeDocs: mySnapshot.data?.docs ?? const [],
              createdByContactDocs: contactSnapshot.data?.docs ?? const [],
              currentUserId: currentUserId,
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (docs.isEmpty)
                  _buildPlansEmptyState(
                    theme: theme,
                    colorScheme: colorScheme,
                    safeName: safeName,
                  )
                else ...[
                  _buildPlansIntroCard(
                    theme: theme,
                    colorScheme: colorScheme,
                    safeName: safeName,
                  ),
                  const SizedBox(height: 20),
                  ...docs.map(
                        (doc) => _buildPlanCard(
                      theme: theme,
                      colorScheme: colorScheme,
                      safeName: safeName,
                      eventId: doc.id,
                      data: doc.data(),
                      currentUserId: currentUserId,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMessagesEmptyState({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 60,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'Noch keine Nachrichten',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Schreib $safeName die erste Nachricht.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String label,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String text,
    required bool isMe,
    required Timestamp? createdAt,
    required bool isRead,
  }) {
    final bubbleColor =
    isMe ? colorScheme.primary.withValues(alpha: 0.14) : colorScheme.surface;
    final bubbleAlignment =
    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final rowAlignment = isMe ? MainAxisAlignment.end : MainAxisAlignment.start;
    final timeColor = isMe
        ? colorScheme.primary.withValues(alpha: 0.85)
        : colorScheme.onSurfaceVariant;

    return Row(
      mainAxisAlignment: rowAlignment,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
              border: Border.all(
                color: isMe
                    ? colorScheme.primary.withValues(alpha: 0.18)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: bubbleAlignment,
              children: [
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatMessageBubbleTime(createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: timeColor,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Icon(
                        isRead ? Icons.done_all : Icons.done,
                        size: 15,
                        color: timeColor,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessagesTab({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
    required String currentUserId,
  }) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('contact_threads')
                .doc(_threadId)
                .collection('messages')
                .orderBy('createdAt')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Fehler beim Laden der Nachrichten.',
                    style: theme.textTheme.bodyLarge,
                  ),
                );
              }

              final docs = [...snapshot.data?.docs ?? []]
                ..sort((a, b) {
                  final aTs = a.data()['createdAt'] as Timestamp?;
                  final bTs = b.data()['createdAt'] as Timestamp?;
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return -1;
                  if (bTs == null) return 1;
                  return aTs.compareTo(bTs);
                });

              if (_tabController.index == 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markIncomingMessagesAsRead();
                });
              }

              if (_lastRenderedMessageCount != docs.length) {
                _lastRenderedMessageCount = docs.length;
                _scheduleScrollToBottom(animated: docs.length > 1);
              }

              if (docs.isEmpty) {
                return _buildMessagesEmptyState(
                  theme: theme,
                  colorScheme: colorScheme,
                  safeName: safeName,
                );
              }

              final children = <Widget>[];
              DateTime? lastDate;

              for (final doc in docs) {
                final data = doc.data();
                final text = (data['text'] ?? '').toString().trim();
                if (text.isEmpty) continue;

                final senderId = (data['senderId'] ?? '').toString();
                final isMe = senderId == currentUserId;
                final createdAt = data['createdAt'] as Timestamp?;
                final isRead = data['isRead'] == true;
                final messageDate =
                    createdAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

                if (lastDate == null || !_isSameDay(lastDate, messageDate)) {
                  children.add(
                    _buildDateChip(
                      theme: theme,
                      colorScheme: colorScheme,
                      label: _formatMessageDayChip(messageDate),
                    ),
                  );
                  lastDate = messageDate;
                }

                children.add(
                  _buildMessageBubble(
                    theme: theme,
                    colorScheme: colorScheme,
                    text: text,
                    isMe: isMe,
                    createdAt: createdAt,
                    isRead: isRead,
                  ),
                );
              }

              return ListView(
                controller: _messagesScrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: children,
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onTap: _scheduleScrollToBottom,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Nachricht schreiben',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isSendingMessage ? null : _sendMessage,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: _isSendingMessage
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.send_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid;
    final safeName = (_resolvedContactName.isEmpty
        ? widget.contactName
        : _resolvedContactName)
        .trim()
        .isEmpty
        ? 'Unbekannt'
        : (_resolvedContactName.isEmpty
        ? widget.contactName
        : _resolvedContactName)
        .trim();
    final safePhone = (_resolvedPhoneNumber.isEmpty
        ? widget.phoneNumber
        : _resolvedPhoneNumber)
        .trim()
        .isEmpty
        ? 'Keine Nummer vorhanden'
        : (_resolvedPhoneNumber.isEmpty
        ? widget.phoneNumber
        : _resolvedPhoneNumber)
        .trim();

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 32,
        titleSpacing: 8,
        title: Row(
          children: [
            _buildHeaderAvatar(colorScheme, safeName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    safeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    safePhone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openCreateEventPage,
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Plan erstellen',
          ),
          IconButton(
            onPressed: () =>
                _showMessage('Weitere Optionen kommen als Nächstes.'),
            icon: const Icon(Icons.more_vert),
          ),
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
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                    borderRadius: BorderRadius.circular(16),
                  ),
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  labelStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: const [
                    Tab(text: 'Chat'),
                    Tab(text: 'Planungen'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildMessagesTab(
                    theme: theme,
                    colorScheme: colorScheme,
                    safeName: safeName,
                    currentUserId: currentUserId,
                  ),
                  _buildPlansTab(
                    theme: theme,
                    colorScheme: colorScheme,
                    safeName: safeName,
                    currentUserId: currentUserId,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
