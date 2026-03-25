import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'kunden_termin_detail_page.dart';

class KundenTerminePage extends StatelessWidget {
  const KundenTerminePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meine Termine')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Bitte melde dich an, um deine Termine zu sehen.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Meine Termine'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Anstehende Termine'),
              Tab(text: 'Vergangene Termine'),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('termine')
              .where('kundeId', isEqualTo: user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Termine konnten nicht geladen werden.'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = (snapshot.data?.docs ?? const [])
                .map((d) => _Termin.fromMap(d.id, d.data()))
                .where((t) => t.startAt != null)
                .toList();

            items.sort((a, b) => a.startAt!.compareTo(b.startAt!));

            final now = DateTime.now();
            final upcoming = items
                .where(
                  (t) =>
                      t.status.toLowerCase() == 'bestaetigt' &&
                      !t.startAt!.isBefore(now),
                )
                .toList();
            final past = items
                .where(
                  (t) =>
                      t.status.toLowerCase() != 'bestaetigt' ||
                      t.startAt!.isBefore(now),
                )
                .toList()
              ..sort((a, b) => b.startAt!.compareTo(a.startAt!));

            return TabBarView(
              children: [
                _TermineList(
                  termine: upcoming,
                  emptyText: 'Du hast keine anstehenden Termine.',
                ),
                _TermineList(
                  termine: past,
                  emptyText: 'Du hast keine vergangenen Termine.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TermineList extends StatelessWidget {
  final List<_Termin> termine;
  final String emptyText;

  const _TermineList({required this.termine, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (termine.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyText, textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: termine.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final termin = termine[index];
        return _TerminCard(termin: termin);
      },
    );
  }
}

class _TerminCard extends StatelessWidget {
  final _Termin termin;

  const _TerminCard({required this.termin});

  @override
  Widget build(BuildContext context) {
    final dt = termin.startAt!;
    final dateText = _capitalize(DateFormat('EEEE, d. MMMM', 'de_DE').format(dt));
    final timeText = DateFormat('HH:mm', 'de_DE').format(dt);

    final theme = Theme.of(context);
    const headerColor = Color(0xFF1F3A57);

    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => KundenTerminDetailPage(
                terminId: termin.id,
                initialData: termin.toMap(),
              ),
            ),
          );
        },
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(color: headerColor),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.access_time, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    timeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _MitarbeiterAvatar(
                    mitarbeiterId: termin.mitarbeiterId,
                    fallbackName: termin.mitarbeiterName,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          termin.dienstleisterName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          termin.mitarbeiterName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (termin.status.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            termin.status,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegacyKundenTerminDetailPage extends StatefulWidget {
  final _Termin termin;

  const _LegacyKundenTerminDetailPage({super.key, required this.termin});

  @override
  State<_LegacyKundenTerminDetailPage> createState() =>
      _LegacyKundenTerminDetailPageState();
}

class _LegacyKundenTerminDetailPageState
    extends State<_LegacyKundenTerminDetailPage> {
  bool _isCancelling = false;

  bool get _isPast {
    final startAt = widget.termin.startAt;
    if (startAt == null) return true;
    return startAt.isBefore(DateTime.now());
  }

  bool get _canCancel {
    return widget.termin.status.toLowerCase() == 'bestaetigt' && !_isPast;
  }

  Future<void> _onCancelPressed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: const Text('Möchtest du den Termin wirklich absagen?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Absagen'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isCancelling = true);
    try {
      await FirebaseFirestore.instance.collection('termine').doc(widget.termin.id).update({
        'status': 'storniert',
        'storniertVon': 'kunde',
        'updatedAt': Timestamp.now(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Termin wurde abgesagt')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final startAt = widget.termin.startAt;
    final dateText = startAt != null
        ? _capitalize(DateFormat('EEEE, d. MMMM y', 'de_DE').format(startAt))
        : widget.termin.datum;
    final startText = startAt != null
        ? DateFormat('HH:mm', 'de_DE').format(startAt)
        : widget.termin.startZeit;

    return Scaffold(
      appBar: AppBar(title: const Text('Termindetails')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Card(
          elevation: 0.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.termin.titel,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 16),
                _DetailRow(label: 'Status', value: widget.termin.status),
                _DetailRow(label: 'Datum', value: dateText),
                _DetailRow(label: 'Von', value: startText),
                _DetailRow(
                  label: 'Bis',
                  value: widget.termin.endZeit.isNotEmpty ? widget.termin.endZeit : '-',
                ),
                _DetailRow(label: 'Dienstleister', value: widget.termin.dienstleisterName),
                _DetailRow(label: 'Mitarbeiter', value: widget.termin.mitarbeiterName),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _canCancel
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isCancelling ? null : _onCancelPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: _isCancelling
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Termin absagen',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _MitarbeiterAvatar extends StatelessWidget {
  final String? mitarbeiterId;
  final String fallbackName;

  const _MitarbeiterAvatar({
    required this.mitarbeiterId,
    required this.fallbackName,
  });

  @override
  Widget build(BuildContext context) {
    final employeeId = mitarbeiterId?.trim() ?? '';
    if (employeeId.isEmpty) {
      return _buildFallbackAvatar(context);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(employeeId).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final profileImageUrl = (data?['profileImageUrl'] as String?)?.trim() ?? '';

        if (profileImageUrl.isNotEmpty) {
          return CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: NetworkImage(profileImageUrl),
          );
        }

        return _buildFallbackAvatar(context);
      },
    );
  }

  Widget _buildFallbackAvatar(BuildContext context) {
    final initials = _initialsFromName(fallbackName);
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.grey.shade200,
      child: Text(
        initials,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Termin {
  final String id;
  final String titel;
  final DateTime? startAt;
  final String datum;
  final String startZeit;
  final String endZeit;
  final String status;
  final String? mitarbeiterId;
  final String dienstleisterName;
  final String mitarbeiterName;

  const _Termin({
    required this.id,
    required this.titel,
    required this.startAt,
    required this.datum,
    required this.startZeit,
    required this.endZeit,
    required this.status,
    required this.mitarbeiterId,
    required this.dienstleisterName,
    required this.mitarbeiterName,
  });

  factory _Termin.fromMap(String id, Map<String, dynamic> data) {
    return _Termin(
      id: id,
      titel: _readString(data['titel'], 'Termin'),
      startAt: _parseTerminStartAt(
        dateValue: data['datum'],
        timeValue: data['startZeit'],
        timestampValue: data['startAt'],
      ),
      datum: _readString(data['datum'], ''),
      startZeit: _readString(data['startZeit'], ''),
      endZeit: _readString(data['endZeit'], ''),
      status: _readString(data['status'], 'bestaetigt'),
      mitarbeiterId: _readNullableString(data['mitarbeiterId']),
      dienstleisterName: _readString(data['dienstleisterName'], 'Dienstleister'),
      mitarbeiterName: _readString(data['mitarbeiterName'], 'Mitarbeiter'),
    );
  }

  static DateTime? _parseTerminStartAt({
    required dynamic dateValue,
    required dynamic timeValue,
    required dynamic timestampValue,
  }) {
    final parsedDate = _parseStoredDate(dateValue);
    final parsedTime = _parseStoredTime(timeValue);

    if (parsedDate != null && parsedTime != null) {
      return DateTime(
        parsedDate.year,
        parsedDate.month,
        parsedDate.day,
        parsedTime.hour,
        parsedTime.minute,
      );
    }

    return _parseTimestampFallback(timestampValue);
  }

  static DateTime? _parseTimestampFallback(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) return null;
      return DateTime.tryParse(normalized);
    }
    return null;
  }

  static DateTime? _parseStoredDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return DateTime(date.year, date.month, date.day);
    }
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) return null;

      final parsed = DateTime.tryParse(normalized);
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }

      final parts = normalized.split(RegExp(r'[-./]'));
      if (parts.length == 3) {
        final first = int.tryParse(parts[0]);
        final second = int.tryParse(parts[1]);
        final third = int.tryParse(parts[2]);
        if (first != null && second != null && third != null) {
          if (parts[0].length == 4) {
            return DateTime(first, second, third);
          }
          return DateTime(third, second, first);
        }
      }
    }
    return null;
  }

  static TimeOfDay? _parseStoredTime(dynamic value) {
    if (value is TimeOfDay) return value;
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) return null;

      final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(normalized);
      if (match == null) return null;

      final hour = int.tryParse(match.group(1)!);
      final minute = int.tryParse(match.group(2)!);
      if (hour == null || minute == null) return null;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

      return TimeOfDay(hour: hour, minute: minute);
    }
    return null;
  }

  static String _readString(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  static String? _readNullableString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'titel': titel,
      'datum': datum,
      'startZeit': startZeit,
      'endZeit': endZeit,
      'startAt': startAt != null ? Timestamp.fromDate(startAt!) : null,
      'status': status,
      'mitarbeiterId': mitarbeiterId,
      'dienstleisterName': dienstleisterName,
      'mitarbeiterName': mitarbeiterName,
    };
  }
}

String _capitalize(String text) {
  if (text.isEmpty) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

String _initialsFromName(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}
