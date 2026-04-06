import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';

class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({super.key});

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

  String _formatAppointmentTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Kein Datum';
    return DateFormat('dd.MM.yyyy · HH:mm', 'de_DE').format(timestamp.toDate());
  }

  String _otherParticipantId(
      List<dynamic> participants,
      String currentUserId,
      String fallbackContactId,
      ) {
    for (final participant in participants) {
      final id = participant.toString();
      if (id != currentUserId) return id;
    }
    return fallbackContactId;
  }

  Future<_AppointmentContactInfo> _resolveContactInfo({
    required String currentUserId,
    required Map<String, dynamic> data,
  }) async {
    final participants = List<String>.from(data['participants'] ?? const []);
    final fallbackContactId = (data['contactId'] ?? '').toString();
    final otherId = _otherParticipantId(participants, currentUserId, fallbackContactId);

    var name = '';
    var phone = '';

    try {
      if (otherId.isNotEmpty) {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(otherId).get();
        final userData = doc.data();

        if (userData != null) {
          name = (userData['displayName'] ?? userData['name'] ?? '')
              .toString()
              .trim();
          phone = (userData['phoneNumber'] ?? '').toString().trim();
        }
      }
    } catch (_) {}

    if (name.isEmpty) {
      final rawName = (data['contactName'] ?? '').toString().trim();
      name = rawName.isEmpty ? 'Unbekannt' : rawName;
    }

    return _AppointmentContactInfo(
      contactId: otherId,
      contactName: name,
      phoneNumber: phone,
    );
  }

  Future<void> _openAppointmentContact({
    required BuildContext context,
    required String currentUserId,
    required Map<String, dynamic> data,
  }) async {
    final info = await _resolveContactInfo(
      currentUserId: currentUserId,
      data: data,
    );

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactThreadPage(
          contactId: info.contactId,
          contactName: info.contactName,
          phoneNumber: info.phoneNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (currentUserId == null) {
      return const Center(
        child: Text('Du bist aktuell nicht eingeloggt.'),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('participants', arrayContains: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text('Fehler beim Laden der Termine.'),
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

        if (docs.isEmpty) {
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
                      Icons.calendar_month_outlined,
                      size: 72,
                      color: colorScheme.primary.withOpacity(0.70),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Noch keine Termine',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hier erscheinen später alle offenen, bestätigten und abgelehnten Termine aus deinen Kontakten.',
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

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'Alle Termine',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hier siehst du deine gesamte Terminübersicht über alle Kontakte hinweg.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ...docs.map((doc) {
              final data = doc.data();
              final title = (data['title'] ?? 'Termin').toString().trim();
              final status = (data['status'] ?? 'pending').toString();
              final appointmentAt = data['appointmentAt'] as Timestamp?;
              final createdBy = (data['createdBy'] ?? '').toString();
              final isCreatedByMe = createdBy == currentUserId;
              final statusColor = _statusColor(colorScheme, status);

              return FutureBuilder<_AppointmentContactInfo>(
                future: _resolveContactInfo(
                  currentUserId: currentUserId,
                  data: data,
                ),
                builder: (context, contactSnapshot) {
                  final info = contactSnapshot.data;
                  final contactName = info?.contactName ?? 'Lädt...';

                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: contactSnapshot.connectionState == ConnectionState.done
                          ? () => _openAppointmentContact(
                        context: context,
                        currentUserId: currentUserId,
                        data: data,
                      )
                          : null,
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
                                        contactName,
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
                            const SizedBox(height: 10),
                            Text(
                              isCreatedByMe
                                  ? 'Von dir vorgeschlagen'
                                  : 'Eingegangen von $contactName',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }
}

class _AppointmentContactInfo {
  final String contactId;
  final String contactName;
  final String phoneNumber;

  const _AppointmentContactInfo({
    required this.contactId,
    required this.contactName,
    required this.phoneNumber,
  });
}
