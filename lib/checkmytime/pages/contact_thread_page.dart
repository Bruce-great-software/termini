import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/pages/create_appointment_page.dart';

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
  final Set<String> _updatingAppointmentIds = <String>{};
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
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChanged);
    _resolvedContactName = widget.contactName.trim();
    _resolvedPhoneNumber = widget.phoneNumber.trim();
    _loadContactProfile();
    _markThreadAsRead();
    _markIncomingAppointmentsAsRead();
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

    if (_tabController.index == 1) {
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

  Future<void> _markIncomingAppointmentsAsRead() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('threadId', isEqualTo: _threadId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      var hasUpdates = false;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final createdBy = (data['createdBy'] ?? '').toString();
        final status = (data['status'] ?? '').toString();
        final isReadByRecipient = data['isReadByRecipient'] == true;

        if (createdBy == widget.contactId &&
            status == 'pending' &&
            !isReadByRecipient) {
          batch.update(doc.reference, {
            'isReadByRecipient': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        await batch.commit();
      }
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
      // still keep the UI responsive; count will be retried on next rebuild/tab switch
    } finally {
      _isMarkingIncomingMessagesAsRead = false;
    }
  }

  Future<void> _openCreateAppointmentPage(String safeName) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateAppointmentPage(
          contactId: widget.contactId,
          contactName: safeName,
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

  String _statusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Bestätigt';
      case 'declined':
        return 'Abgelehnt';
      case 'pending':
      default:
        return 'Ausstehend';
    }
  }

  Color _statusColor(ColorScheme colorScheme, String status) {
    switch (status) {
      case 'accepted':
        return Colors.green;
      case 'declined':
        return colorScheme.error;
      case 'pending':
      default:
        return colorScheme.primary;
    }
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

  Future<void> _updateAppointmentStatus({
    required String appointmentId,
    required String newStatus,
    required String title,
  }) async {
    if (_updatingAppointmentIds.contains(appointmentId)) return;

    setState(() {
      _updatingAppointmentIds.add(appointmentId);
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('not logged in');
      }

      final batch = firestore.batch();

      batch.update(
        firestore.collection('appointments').doc(appointmentId),
        {
          'status': newStatus,
          'isReadByRecipient': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      batch.set(
        firestore.collection('contact_threads').doc(_threadId),
        {
          'lastStatus': newStatus,
          'lastAppointmentTitle': title,
          'lastInteractionType': 'appointment',
          'lastInteractionAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'unreadCountFor_$currentUserId': 0,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;
      _showMessage(
        newStatus == 'accepted'
            ? 'Termin wurde angenommen.'
            : 'Termin wurde abgelehnt.',
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('Status konnte nicht aktualisiert werden.');
    } finally {
      if (!mounted) return;
      setState(() {
        _updatingAppointmentIds.remove(appointmentId);
      });
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

      _messageController.clear();
      _scheduleScrollToBottom();
    } catch (_) {
      if (!mounted) return;
      _showMessage('Nachricht konnte nicht gesendet werden.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isSendingMessage = false;
      });
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
      backgroundColor: colorScheme.primary.withOpacity(0.12),
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

  Widget _buildAppointmentsActionCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openCreateAppointmentPage(safeName),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.primary.withOpacity(0.10),
                  child: Icon(
                    Icons.calendar_month_outlined,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Termin vorschlagen',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Plane direkt mit $safeName einen gemeinsamen Termin.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
  }) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.15),
            ),
          ),
          child: Text(
            'Hier siehst du gemeinsame Terminanfragen, bestätigte Termine und Änderungen mit $safeName.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 28),
        Icon(
          Icons.event_note_outlined,
          size: 72,
          color: colorScheme.primary.withOpacity(0.70),
        ),
        const SizedBox(height: 18),
        Text(
          'Noch keine gemeinsamen Termine',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Sobald du mit $safeName einen Termin erstellst, erscheint er hier in einem gemeinsamen Verlauf.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCompactAppointmentCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
    required String title,
    required String status,
    required Timestamp? appointmentAt,
    required bool isCreatedByMe,
    required bool isUpdating,
    required VoidCallback? onAccept,
    required VoidCallback? onDecline,
  }) {
    final statusColor = _statusColor(colorScheme, status);

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
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.95),
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
                    _formatDateHeader(appointmentAt),
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
                  _formatTime(appointmentAt),
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
                          Text(
                            safeName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isCreatedByMe
                                ? 'Von dir vorgeschlagen'
                                : 'Eingegangen von $safeName',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
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
                        color: statusColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isCreatedByMe && status == 'pending') ...[
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
                            onPressed: onDecline,
                            child: const Text('Ablehnen'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: onAccept,
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

  Widget _buildAppointmentsTab({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
    required String currentUserId,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('threadId', isEqualTo: _threadId)
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
              'Fehler beim Laden der Termine.',
              style: theme.textTheme.bodyLarge,
            ),
          );
        }

        final docs = [...snapshot.data?.docs ?? []]
          ..sort((a, b) {
            final aTs = a.data()['appointmentAt'] as Timestamp?;
            final bTs = b.data()['appointmentAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return aTs.compareTo(bTs);
          });

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _buildAppointmentsActionCard(
              theme: theme,
              colorScheme: colorScheme,
              safeName: safeName,
            ),
            const SizedBox(height: 20),
            if (docs.isEmpty)
              _buildEmptyState(
                theme: theme,
                colorScheme: colorScheme,
                safeName: safeName,
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.15),
                  ),
                ),
                child: Text(
                  'Gemeinsame Termine mit $safeName',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              ...docs.map((doc) {
                final data = doc.data();
                final createdBy = (data['createdBy'] ?? '').toString();
                final title = (data['title'] ?? 'Termin').toString().trim();
                final status = (data['status'] ?? 'pending').toString();
                final appointmentAt = data['appointmentAt'] as Timestamp?;
                final isCreatedByMe = createdBy == currentUserId;
                final isUpdating = _updatingAppointmentIds.contains(doc.id);

                return _buildCompactAppointmentCard(
                  theme: theme,
                  colorScheme: colorScheme,
                  safeName: safeName,
                  title: title,
                  status: status,
                  appointmentAt: appointmentAt,
                  isCreatedByMe: isCreatedByMe,
                  isUpdating: isUpdating,
                  onAccept: (!isCreatedByMe && status == 'pending')
                      ? () => _updateAppointmentStatus(
                    appointmentId: doc.id,
                    newStatus: 'accepted',
                    title: title,
                  )
                      : null,
                  onDecline: (!isCreatedByMe && status == 'pending')
                      ? () => _updateAppointmentStatus(
                    appointmentId: doc.id,
                    newStatus: 'declined',
                    title: title,
                  )
                      : null,
                );
              }),
            ],
          ],
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
          color: colorScheme.surfaceVariant.withOpacity(0.9),
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
    final bubbleColor = isMe
        ? colorScheme.primary.withOpacity(0.14)
        : colorScheme.surface;
    final bubbleAlignment =
    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final rowAlignment = isMe ? MainAxisAlignment.end : MainAxisAlignment.start;
    final timeColor = isMe
        ? colorScheme.primary.withOpacity(0.85)
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
                    ? colorScheme.primary.withOpacity(0.18)
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

              if (_tabController.index == 1) {
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

                if (lastDate == null || !_isSameDay(lastDate!, messageDate)) {
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
                      fillColor: colorScheme.surfaceVariant.withOpacity(0.45),
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
                          color: colorScheme.primary.withOpacity(0.25),
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
                    color: colorScheme.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  labelStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: const [
                    Tab(text: 'Termine'),
                    Tab(text: 'Nachrichten'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAppointmentsTab(
                    theme: theme,
                    colorScheme: colorScheme,
                    safeName: safeName,
                    currentUserId: currentUserId,
                  ),
                  _buildMessagesTab(
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
