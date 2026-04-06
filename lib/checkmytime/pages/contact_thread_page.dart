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

  @override
  void initState() {
    super.initState();
    _markIncomingAppointmentsAsRead();
  }

  Future<void> _markIncomingAppointmentsAsRead() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('participants', arrayContains: currentUserId)
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

  String _formatAppointmentTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    final dt = timestamp.toDate();
    return DateFormat('dd.MM.yyyy · HH:mm', 'de_DE').format(dt);
  }

  Future<void> _updateAppointmentStatus({
    required String appointmentId,
    required String newStatus,
  }) async {
    if (_updatingAppointmentIds.contains(appointmentId)) return;

    setState(() {
      _updatingAppointmentIds.add(appointmentId);
    });

    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update({
        'status': newStatus,
        'isReadByRecipient': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
            'Hier siehst du später gemeinsame Terminanfragen, bestätigte Termine und Änderungen mit $safeName.',
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
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _showMessage('Verlauf kommt als Nächstes.'),
          icon: const Icon(Icons.history),
          label: const Text('Verlauf kommt später'),
        ),
      ],
    );
  }

  Widget _buildAppointmentCard({
    required String appointmentId,
    required Map<String, dynamic> data,
    required bool isCreatedByMe,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final title = (data['title'] ?? 'Termin').toString().trim();
    final status = (data['status'] ?? 'pending').toString();
    final appointmentAt = data['appointmentAt'] as Timestamp?;
    final isUpdating = _updatingAppointmentIds.contains(appointmentId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCreatedByMe
                            ? 'Du hast einen Termin vorgeschlagen'
                            : '${widget.contactName} hat einen Termin vorgeschlagen',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatAppointmentTime(appointmentAt),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (!isCreatedByMe && status == 'pending') ...[
              const SizedBox(height: 16),
              if (isUpdating)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _updateAppointmentStatus(
                          appointmentId: appointmentId,
                          newStatus: 'declined',
                        ),
                        child: const Text('Ablehnen'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _updateAppointmentStatus(
                          appointmentId: appointmentId,
                          newStatus: 'accepted',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid;
    final safeName =
    widget.contactName.trim().isEmpty ? 'Unbekannt' : widget.contactName.trim();
    final safePhone = widget.phoneNumber.trim().isEmpty
        ? 'Keine Nummer vorhanden'
        : widget.phoneNumber.trim();
    final avatarLetter = safeName.characters.first.toUpperCase();

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 32,
        titleSpacing: 8,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primary.withOpacity(0.12),
              child: Text(
                avatarLetter,
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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
            onPressed: () => _showMessage('Weitere Optionen kommen als Nächstes.'),
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: currentUserId == null
                  ? Center(
                child: Text(
                  'Du bist aktuell nicht eingeloggt.',
                  style: theme.textTheme.bodyLarge,
                ),
              )
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('appointments')
                    .where('participants', arrayContains: currentUserId)
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

                  final docs = (snapshot.data?.docs ?? []).where((doc) {
                    final participants =
                    List<String>.from(doc.data()['participants'] ?? []);
                    return participants.contains(widget.contactId);
                  }).toList()
                    ..sort((a, b) {
                      final aTs = a.data()['appointmentAt'] as Timestamp?;
                      final bTs = b.data()['appointmentAt'] as Timestamp?;
                      if (aTs == null && bTs == null) return 0;
                      if (aTs == null) return 1;
                      if (bTs == null) return -1;
                      return aTs.compareTo(bTs);
                    });

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: docs.isEmpty
                        ? _buildEmptyState(
                      theme: theme,
                      colorScheme: colorScheme,
                      safeName: safeName,
                    )
                        : Column(
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
                          final createdBy =
                          (data['createdBy'] ?? '').toString();
                          return _buildAppointmentCard(
                            appointmentId: doc.id,
                            data: data,
                            isCreatedByMe: createdBy == currentUserId,
                            theme: theme,
                            colorScheme: colorScheme,
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CreateAppointmentPage(
                              contactId: widget.contactId,
                              contactName: safeName,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Termin vorschlagen'),
                    ),
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
