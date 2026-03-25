import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class KundenTerminDetailPage extends StatefulWidget {
  const KundenTerminDetailPage({
    super.key,
    required this.terminId,
    this.initialData,
  });

  final String terminId;
  final Map<String, dynamic>? initialData;

  @override
  State<KundenTerminDetailPage> createState() => _KundenTerminDetailPageState();
}

class _KundenTerminDetailPageState extends State<KundenTerminDetailPage> {
  bool _isCancelling = false;

  Future<void> _cancelTermin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);
    try {
      await FirebaseFirestore.instance.collection('termine').doc(widget.terminId).update({
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
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('termine')
          .doc(widget.terminId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = {
          ...?widget.initialData,
          ...?(snapshot.data?.data()),
        };

        final status = _readString(data['status'], fallback: '');
        final canCancel = status.toLowerCase() == 'bestaetigt';

        final startAt = _parseDateTime(
          dateValue: data['datum'],
          timeValue: data['startZeit'],
          timestampValue: data['startAt'],
        );
        final endAt = _parseDateTime(
          dateValue: data['datum'],
          timeValue: data['endZeit'],
          timestampValue: data['endAt'],
        );

        final dateText = startAt != null
            ? _capitalize(DateFormat('EEEE, d. MMMM', 'de_DE').format(startAt))
            : _readString(data['datum'], fallback: '-');
        final timeText = _buildTimeRange(
          startAt: startAt,
          endAt: endAt,
          startFallback: _readString(data['startZeit'], fallback: '-'),
          endFallback: _readString(data['endZeit'], fallback: '-'),
        );

        final dienstleisterName =
        _readString(data['dienstleisterName'], fallback: 'Dienstleister');
        final mitarbeiterName =
        _readString(data['mitarbeiterName'], fallback: 'Mitarbeiter');

        final leistungen = _readString(data['titel'], fallback: '-');
        final preis = _readString(data['preis'], fallback: '-');
        final dauer = _readString(data['dauer'], fallback: '-');

        return Scaffold(
          appBar: AppBar(
            title: const Text('Informationen zum Termin'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'Datum', value: dateText),
                      _InfoRow(label: 'Uhrzeit', value: timeText),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('Dienstleister'),
                      const SizedBox(height: 8),
                      _InfoRow(label: 'Name', value: dienstleisterName),
                      _InfoRow(label: 'Mitarbeiter', value: mitarbeiterName),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('Leistung'),
                      const SizedBox(height: 8),
                      _InfoRow(label: 'Leistung', value: leistungen),
                      _InfoRow(label: 'Preis', value: preis),
                      _InfoRow(label: 'Dauer', value: dauer),
                      _InfoRow(label: 'Status', value: status.isNotEmpty ? status : '-'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: canCancel
              ? SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isCancelling ? null : _cancelTermin,
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
                        valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
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
      },
    );
  }

  static String _buildTimeRange({
    required DateTime? startAt,
    required DateTime? endAt,
    required String startFallback,
    required String endFallback,
  }) {
    final start = startAt != null
        ? DateFormat('HH:mm', 'de_DE').format(startAt)
        : startFallback;
    final end = endAt != null ? DateFormat('HH:mm', 'de_DE').format(endAt) : endFallback;

    if (start == '-' && end == '-') return '-';
    if (end == '-') return start;
    return '$start – $end';
  }

  static DateTime? _parseDateTime({
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

    if (timestampValue is Timestamp) return timestampValue.toDate();
    if (timestampValue is DateTime) return timestampValue;
    if (timestampValue is String) {
      final normalized = timestampValue.trim();
      if (normalized.isNotEmpty) {
        return DateTime.tryParse(normalized);
      }
    }

    return null;
  }

  static DateTime? _parseStoredDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return DateTime(date.year, date.month, date.day);
    }
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
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

  static String _readString(dynamic value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

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
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalize(String text) {
  if (text.isEmpty) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}