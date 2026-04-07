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

class _ContactThreadPageState extends State<ContactThreadPage> {
  final Set<String> _updatingAppointmentIds = <String>{};

  String _resolvedContactName = '';
  String _resolvedPhoneNumber = '';
  String _profileImageUrl = '';

  String get _threadId {
    final ids = [FirebaseAuth.instance.currentUser?.uid ?? '', widget.contactId]
      ..sort();
    return '${ids[0]}_${ids[1]}';
  }

  @override
  void initState() {
    super.initState();
    _resolvedContactName = widget.contactName.trim();
    _resolvedPhoneNumber = widget.phoneNumber.trim();
    _loadContactProfile();
    _markThreadAsRead();
    _markIncomingAppointmentsAsRead();
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

  Widget _buildMessagesTab({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 56,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                'Nachrichten mit $safeName',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hier bauen wir als Nächstes den Chat-Verlauf zwischen dir und $safeName ein.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
        : (_resolvedContactName.isEmpty ? widget.contactName : _resolvedContactName)
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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
                    border:
                    Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: TabBar(
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
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
