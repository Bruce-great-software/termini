import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  String _selectedFilter = 'all';

  bool _matchesFilter(String status) {
    if (_selectedFilter == 'all') return true;
    return status == _selectedFilter;
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
    final otherId =
    _otherParticipantId(participants, currentUserId, fallbackContactId);

    var name = '';
    var phone = '';
    var imageUrl = '';

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
          imageUrl = (userData['profileImageUrl'] ?? '').toString().trim();
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
      imageUrl: imageUrl,
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

  Widget _buildFilterChip({
    required String value,
    required String label,
    required int count,
  }) {
    final isSelected = _selectedFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text('$label ($count)'),
        onSelected: (_) {
          setState(() {
            _selectedFilter = value;
          });
        },
      ),
    );
  }

  Widget _buildContactAvatar({
    required _AppointmentContactInfo info,
    required ThemeData theme,
  }) {
    if (info.imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(info.imageUrl),
      );
    }

    final letter =
    info.contactName.isNotEmpty ? info.contactName.characters.first : '?';

    return CircleAvatar(
      radius: 22,
      child: Text(
        letter.toUpperCase(),
        style: theme.textTheme.labelLarge,
      ),
    );
  }

  Widget _buildCompactAppointmentCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required _AppointmentContactInfo info,
    required String title,
    required String status,
    required Timestamp? appointmentAt,
    required bool isCreatedByMe,
    required VoidCallback? onTap,
  }) {
    final statusColor = _statusColor(colorScheme, status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildContactAvatar(
                      info: info,
                      theme: theme,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.contactName,
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
                                : 'Eingegangen von ${info.contactName}',
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
              ),
            ],
          ),
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

        final pendingCount = docs
            .where((doc) => (doc.data()['status'] ?? 'pending') == 'pending')
            .length;
        final acceptedCount = docs
            .where((doc) => (doc.data()['status'] ?? 'pending') == 'accepted')
            .length;
        final declinedCount = docs
            .where((doc) => (doc.data()['status'] ?? 'pending') == 'declined')
            .length;

        final filteredDocs = docs.where((doc) {
          final status = (doc.data()['status'] ?? 'pending').toString();
          return _matchesFilter(status);
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'Alle Termine',
              style: theme.textTheme.headlineSmall?.copyWith(
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryStat(
                      label: 'Offen',
                      value: pendingCount.toString(),
                    ),
                  ),
                  Expanded(
                    child: _SummaryStat(
                      label: 'Bestätigt',
                      value: acceptedCount.toString(),
                    ),
                  ),
                  Expanded(
                    child: _SummaryStat(
                      label: 'Abgelehnt',
                      value: declinedCount.toString(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    value: 'all',
                    label: 'Alle',
                    count: docs.length,
                  ),
                  _buildFilterChip(
                    value: 'pending',
                    label: 'Ausstehend',
                    count: pendingCount,
                  ),
                  _buildFilterChip(
                    value: 'accepted',
                    label: 'Bestätigt',
                    count: acceptedCount,
                  ),
                  _buildFilterChip(
                    value: 'declined',
                    label: 'Abgelehnt',
                    count: declinedCount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (docs.isEmpty)
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
              )
            else if (filteredDocs.isEmpty)
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
                      Icons.filter_alt_off_outlined,
                      size: 56,
                      color: colorScheme.primary.withOpacity(0.70),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Keine Termine für diesen Filter',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...filteredDocs.map((doc) {
                final data = doc.data();
                final title = (data['title'] ?? 'Termin').toString().trim();
                final status = (data['status'] ?? 'pending').toString();
                final appointmentAt = data['appointmentAt'] as Timestamp?;
                final createdBy = (data['createdBy'] ?? '').toString();
                final isCreatedByMe = createdBy == currentUserId;

                return FutureBuilder<_AppointmentContactInfo>(
                  future: _resolveContactInfo(
                    currentUserId: currentUserId,
                    data: data,
                  ),
                  builder: (context, contactSnapshot) {
                    final info = contactSnapshot.data ??
                        const _AppointmentContactInfo(
                          contactId: '',
                          contactName: 'Lädt...',
                          phoneNumber: '',
                          imageUrl: '',
                        );

                    return _buildCompactAppointmentCard(
                      theme: theme,
                      colorScheme: colorScheme,
                      info: info,
                      title: title,
                      status: status,
                      appointmentAt: appointmentAt,
                      isCreatedByMe: isCreatedByMe,
                      onTap: contactSnapshot.connectionState ==
                          ConnectionState.done
                          ? () => _openAppointmentContact(
                        context: context,
                        currentUserId: currentUserId,
                        data: data,
                      )
                          : null,
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

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AppointmentContactInfo {
  final String contactId;
  final String contactName;
  final String phoneNumber;
  final String imageUrl;

  const _AppointmentContactInfo({
    required this.contactId,
    required this.contactName,
    required this.phoneNumber,
    required this.imageUrl,
  });
}
