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
        final raw = <String, dynamic>{
          ...?widget.initialData,
          ...?(snapshot.data?.data()),
        };
        final termin = _TerminDetailData.fromMap(widget.terminId, raw);

        final statusLc = termin.status.toLowerCase();
        final isPast = termin.startAt?.isBefore(DateTime.now()) ?? true;
        final canCancel = statusLc == 'bestaetigt' && !isPast;

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text('Informationen zum Termin'),
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DateTimeHeaderBar(termin: termin),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProviderCard(termin: termin),
                      const SizedBox(height: 14),
                      _ServicesSection(services: termin.services),
                      const SizedBox(height: 14),
                      _SummarySection(
                        totalPrice: termin.totalPrice,
                        totalDuration: termin.totalDuration,
                      ),
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
                                  width: 18,
                                  height: 18,
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
}

class _DateTimeHeaderBar extends StatelessWidget {
  const _DateTimeHeaderBar({required this.termin});

  final _TerminDetailData termin;

  @override
  Widget build(BuildContext context) {
    final startAt = termin.startAt;
    final endAt = termin.endAt;

    final dateText = startAt != null
        ? _capitalize(DateFormat('EEEE, d. MMMM', 'de_DE').format(startAt))
        : termin.datum;

    final startText = startAt != null
        ? DateFormat('HH:mm', 'de_DE').format(startAt)
        : termin.startZeit;
    final endText = endAt != null ? DateFormat('HH:mm', 'de_DE').format(endAt) : termin.endZeit;
    final timeText = endText.isNotEmpty ? '$startText – $endText' : startText;

    return Container(
      color: const Color(0xFF1F3A57),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dateText.isNotEmpty ? dateText : '-',
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
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.termin});

  final _TerminDetailData termin;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _EmployeeAvatar(
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
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    termin.mitarbeiterName,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    termin.status,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}

class _ServicesSection extends StatelessWidget {
  const _ServicesSection({required this.services});

  final List<_BookedService> services;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<_BookedService>>{};
    for (final service in services) {
      final key = service.category.isNotEmpty ? service.category : 'Leistungen';
      grouped.putIfAbsent(key, () => []).add(service);
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gebuchte Leistungen',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (services.isEmpty)
              Text(
                'Keine Leistungsdaten verfügbar.',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else
              ...grouped.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...entry.value.map((service) {
                        final hasSubInfo =
                            service.duration.isNotEmpty || service.variant.isNotEmpty;
                        final subInfo = [
                          if (service.duration.isNotEmpty) service.duration,
                          if (service.variant.isNotEmpty) service.variant,
                        ].join(' • ');

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      service.title,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    service.price,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              if (hasSubInfo) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subInfo,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.totalPrice,
    required this.totalDuration,
  });

  final String totalPrice;
  final String totalDuration;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SummaryRow(label: 'Gesamtpreis', value: totalPrice),
            const SizedBox(height: 8),
            _SummaryRow(label: 'Gesamtdauer', value: totalDuration),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
        Text(
          value.isNotEmpty ? value : '-',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _EmployeeAvatar extends StatelessWidget {
  const _EmployeeAvatar({
    required this.mitarbeiterId,
    required this.fallbackName,
  });

  final String? mitarbeiterId;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    final employeeId = mitarbeiterId?.trim() ?? '';
    if (employeeId.isEmpty) {
      return _fallbackAvatar();
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(employeeId).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final profileImageUrl = (data?['profileImageUrl'] as String?)?.trim() ?? '';

        if (profileImageUrl.isNotEmpty) {
          return CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE5E7EB),
            backgroundImage: NetworkImage(profileImageUrl),
          );
        }

        return _fallbackAvatar();
      },
    );
  }

  CircleAvatar _fallbackAvatar() {
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFE5E7EB),
      child: Text(
        _initialsFromName(fallbackName),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TerminDetailData {
  const _TerminDetailData({
    required this.id,
    required this.status,
    required this.datum,
    required this.startZeit,
    required this.endZeit,
    required this.startAt,
    required this.endAt,
    required this.dienstleisterName,
    required this.mitarbeiterName,
    required this.mitarbeiterId,
    required this.services,
    required this.totalPrice,
    required this.totalDuration,
  });

  final String id;
  final String status;
  final String datum;
  final String startZeit;
  final String endZeit;
  final DateTime? startAt;
  final DateTime? endAt;
  final String dienstleisterName;
  final String mitarbeiterName;
  final String? mitarbeiterId;
  final List<_BookedService> services;
  final String totalPrice;
  final String totalDuration;

  factory _TerminDetailData.fromMap(String id, Map<String, dynamic> data) {
    final services = _BookedService.parseMany(data);

    final totalPrice = _readString(
      data['gesamtPreis'] ?? data['totalPrice'] ?? data['preisGesamt'],
    );
    final totalDuration = _readString(
      data['gesamtDauer'] ?? data['totalDuration'] ?? data['dauerGesamt'],
    );

    return _TerminDetailData(
      id: id,
      status: _readString(data['status'], fallback: 'bestaetigt'),
      datum: _readString(data['datum']),
      startZeit: _readString(data['startZeit']),
      endZeit: _readString(data['endZeit']),
      startAt: _parseDateTime(
        dateValue: data['datum'],
        timeValue: data['startZeit'],
        timestampValue: data['startAt'],
      ),
      endAt: _parseDateTime(
        dateValue: data['datum'],
        timeValue: data['endZeit'],
        timestampValue: data['endAt'],
      ),
      dienstleisterName: _readString(data['dienstleisterName'], fallback: 'Dienstleister'),
      mitarbeiterName: _readString(data['mitarbeiterName'], fallback: 'Mitarbeiter'),
      mitarbeiterId: _readNullableString(data['mitarbeiterId']),
      services: services,
      totalPrice: totalPrice.isNotEmpty ? totalPrice : _BookedService.sumPriceLabel(services),
      totalDuration:
          totalDuration.isNotEmpty ? totalDuration : _BookedService.sumDurationLabel(services),
    );
  }
}

class _BookedService {
  const _BookedService({
    required this.category,
    required this.title,
    required this.price,
    required this.duration,
    required this.variant,
    required this.rawPrice,
    required this.rawDurationMinutes,
  });

  final String category;
  final String title;
  final String price;
  final String duration;
  final String variant;
  final double? rawPrice;
  final int? rawDurationMinutes;

  static List<_BookedService> parseMany(Map<String, dynamic> source) {
    final raw = source['services'] ?? source['leistungen'] ?? source['auswahl'] ?? source['items'];
    if (raw is! List) {
      final fallbackTitle = _readString(source['titel']);
      if (fallbackTitle.isEmpty) return const [];
      return [
        _BookedService(
          category: _readString(source['kategorie']),
          title: fallbackTitle,
          price: _readString(source['preis']),
          duration: _readString(source['dauer']),
          variant: _readString(source['variante']),
          rawPrice: _toDouble(source['preis']),
          rawDurationMinutes: _durationToMinutes(source['dauer']),
        ),
      ];
    }

    return raw.map<_BookedService>((entry) {
      final map = (entry is Map<String, dynamic>)
          ? entry
          : (entry is Map)
              ? Map<String, dynamic>.from(entry)
              : <String, dynamic>{};

      return _BookedService(
        category: _readString(map['kategorie'] ?? map['category']),
        title: _readString(map['titel'] ?? map['title'], fallback: 'Leistung'),
        price: _readString(map['preis'] ?? map['price']),
        duration: _readString(map['dauer'] ?? map['duration']),
        variant: _readString(map['variante'] ?? map['variant']),
        rawPrice: _toDouble(map['preis'] ?? map['price']),
        rawDurationMinutes: _durationToMinutes(map['dauer'] ?? map['duration']),
      );
    }).toList();
  }

  static String sumPriceLabel(List<_BookedService> services) {
    final prices = services.map((e) => e.rawPrice).whereType<double>().toList();
    if (prices.isEmpty) return '-';
    final sum = prices.fold<double>(0, (a, b) => a + b);
    return '${sum.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  static String sumDurationLabel(List<_BookedService> services) {
    final durations = services.map((e) => e.rawDurationMinutes).whereType<int>().toList();
    if (durations.isEmpty) return '-';
    final total = durations.fold<int>(0, (a, b) => a + b);
    final hours = total ~/ 60;
    final minutes = total % 60;
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}min';
    if (hours > 0) return '${hours}h';
    return '${minutes}min';
  }
}

DateTime? _parseDateTime({
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
    if (normalized.isNotEmpty) return DateTime.tryParse(normalized);
  }
  return null;
}

DateTime? _parseStoredDate(dynamic value) {
  if (value is Timestamp) {
    final d = value.toDate();
    return DateTime(d.year, d.month, d.day);
  }
  if (value is DateTime) return DateTime(value.year, value.month, value.day);
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;

    final iso = DateTime.tryParse(normalized);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    final parts = normalized.split(RegExp(r'[-./]'));
    if (parts.length == 3) {
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      final third = int.tryParse(parts[2]);
      if (first != null && second != null && third != null) {
        if (parts[0].length == 4) return DateTime(first, second, third);
        return DateTime(third, second, first);
      }
    }
  }
  return null;
}

TimeOfDay? _parseStoredTime(dynamic value) {
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

String _readString(dynamic value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is num) return value.toString();
  return fallback;
}

String? _readNullableString(dynamic value) {
  final str = _readString(value);
  return str.isEmpty ? null : str;
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final normalized = value.replaceAll(RegExp(r'[^0-9,.-]'), '').replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }
  return null;
}

int? _durationToMinutes(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    if (normalized.isEmpty) return null;

    final hourMinute = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(normalized);
    if (hourMinute != null) {
      final h = int.tryParse(hourMinute.group(1)!);
      final m = int.tryParse(hourMinute.group(2)!);
      if (h != null && m != null) return (h * 60) + m;
    }

    final minuteMatch = RegExp(r'(\d+)\s*min').firstMatch(normalized);
    final hourMatch = RegExp(r'(\d+)\s*h').firstMatch(normalized);
    final plainInt = int.tryParse(normalized);

    int total = 0;
    if (hourMatch != null) {
      total += (int.tryParse(hourMatch.group(1)!) ?? 0) * 60;
    }
    if (minuteMatch != null) {
      total += int.tryParse(minuteMatch.group(1)!) ?? 0;
    }

    if (total > 0) return total;
    return plainInt;
  }
  return null;
}

String _capitalize(String text) {
  if (text.isEmpty) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}
