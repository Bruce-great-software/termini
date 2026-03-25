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
  static const _headerColor = Color(0xFF1F3A57);

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
    final theme = Theme.of(context);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('termine').doc(widget.terminId).snapshots(),
      builder: (context, snapshot) {
        final data = {
          ...?widget.initialData,
          ...?(snapshot.data?.data()),
        };

        final status = _readString(data['status'], fallback: '');
        final statusLower = status.toLowerCase();

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

        final appointmentMoment = endAt ?? startAt;
        final isPast = appointmentMoment != null && appointmentMoment.isBefore(DateTime.now());
        final canCancel = statusLower == 'bestaetigt' && !isPast;

        final dateText = startAt != null
            ? _capitalize(DateFormat('EEEE, d. MMMM', 'de_DE').format(startAt))
            : _readString(data['datum'], fallback: '-');
        final timeText = _buildTimeRange(
          startAt: startAt,
          endAt: endAt,
          startFallback: _readString(data['startZeit'], fallback: '-'),
          endFallback: _readString(data['endZeit'], fallback: '-'),
        );

        final dienstleisterName = _readString(data['dienstleisterName'], fallback: 'Dienstleister');
        final mitarbeiterName = _readString(data['mitarbeiterName'], fallback: 'Mitarbeiter');
        final mitarbeiterId = _readNullableString(data['mitarbeiterId']);

        final services = _extractBookedServices(data);
        final groupedServices = _groupServicesByCategory(services);

        final totalPriceText = _resolveTotalPriceText(data, services);
        final totalDurationText = _resolveTotalDurationText(data, services);

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text('Informationen zum Termin'),
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, canCancel ? 112 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateTimeHeaderBar(dateText: dateText, timeText: timeText),
                const SizedBox(height: 12),
                Material(
                  color: Colors.white,
                  elevation: 1,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _MitarbeiterAvatar(
                          mitarbeiterId: mitarbeiterId,
                          fallbackName: mitarbeiterName,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dienstleisterName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mitarbeiterName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                status.isNotEmpty ? status : '-',
                                style: theme.textTheme.bodySmall?.copyWith(
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
                ),
                const SizedBox(height: 18),
                Text(
                  'Gebuchte Leistungen',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                _ServicesSection(groupedServices: groupedServices),
                const SizedBox(height: 18),
                _SummarySection(
                  totalPriceText: totalPriceText,
                  totalDurationText: totalDurationText,
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
      },
    );
  }
}

class _DateTimeHeaderBar extends StatelessWidget {
  const _DateTimeHeaderBar({
    required this.dateText,
    required this.timeText,
  });

  final String dateText;
  final String timeText;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(color: _KundenTerminDetailPageState._headerColor),
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
    );
  }
}

class _ServicesSection extends StatelessWidget {
  const _ServicesSection({required this.groupedServices});

  final Map<String, List<_BookedService>> groupedServices;

  @override
  Widget build(BuildContext context) {
    if (groupedServices.isEmpty) {
      return const _CardContainer(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Keine Leistungen hinterlegt.'),
        ),
      );
    }

    final groups = groupedServices.entries.toList();

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (groups[i].key.isNotEmpty) ...[
              Text(
                groups[i].key,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
            ],
            for (var j = 0; j < groups[i].value.length; j++) ...[
              _ServiceRow(service: groups[i].value[j]),
              if (j < groups[i].value.length - 1)
                Divider(height: 14, color: Colors.grey.shade300),
            ],
            if (i < groups.length - 1) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.grey.shade300),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service});

  final _BookedService service;

  @override
  Widget build(BuildContext context) {
    final subInfoParts = [
      if (service.variant.isNotEmpty) service.variant,
      if (service.durationText.isNotEmpty) service.durationText,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (subInfoParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subInfoParts.join(' • '),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            service.priceText,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.totalPriceText,
    required this.totalDurationText,
  });

  final String totalPriceText;
  final String totalDurationText;

  @override
  Widget build(BuildContext context) {
    return _CardContainer(
      child: Column(
        children: [
          _SummaryRow(label: 'Gesamtpreis', value: totalPriceText),
          const SizedBox(height: 10),
          _SummaryRow(label: 'Gesamtdauer', value: totalDurationText),
        ],
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
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _CardContainer extends StatelessWidget {
  const _CardContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0.7,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class _MitarbeiterAvatar extends StatelessWidget {
  const _MitarbeiterAvatar({
    required this.mitarbeiterId,
    required this.fallbackName,
  });

  final String? mitarbeiterId;
  final String fallbackName;

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

class _BookedService {
  const _BookedService({
    required this.category,
    required this.title,
    required this.priceText,
    required this.durationText,
    required this.durationMinutes,
    required this.variant,
    required this.numericPrice,
  });

  final String category;
  final String title;
  final String priceText;
  final String durationText;
  final int? durationMinutes;
  final String variant;
  final double? numericPrice;
}

Map<String, List<_BookedService>> _groupServicesByCategory(List<_BookedService> services) {
  if (services.isEmpty) return const {};

  final hasAnyCategory = services.any((service) => service.category.isNotEmpty);
  if (!hasAnyCategory) {
    return {'': services};
  }

  final grouped = <String, List<_BookedService>>{};
  for (final service in services) {
    final key = service.category;
    grouped.putIfAbsent(key, () => <_BookedService>[]).add(service);
  }
  return grouped;
}

List<_BookedService> _extractBookedServices(Map<String, dynamic> data) {
  final servicesRaw = data['services'] ?? data['leistungen'] ?? data['items'];
  final extracted = <_BookedService>[];

  if (servicesRaw is List) {
    for (final entry in servicesRaw) {
      final service = _parseServiceEntry(entry);
      if (service != null) {
        extracted.add(service);
      }
    }
  }

  if (extracted.isEmpty) {
    final fallbackTitle = _readString(
      data['titel'] ?? data['title'] ?? data['leistung'] ?? data['service'],
      fallback: '',
    );
    if (fallbackTitle.isNotEmpty) {
      final fallbackPrice = _displayPrice(
        data['preis'] ?? data['price'] ?? data['betrag'],
      );
      final fallbackDuration = _displayDuration(
        data['dauer'] ?? data['dauerMinuten'] ?? data['duration'] ?? data['durationMinutes'],
      );
      extracted.add(
        _BookedService(
          category: _readString(data['kategorie'], fallback: ''),
          title: fallbackTitle,
          priceText: fallbackPrice,
          durationText: fallbackDuration,
          durationMinutes: _parseDurationMinutes(
            data['dauer'] ?? data['dauerMinuten'] ?? data['duration'] ?? data['durationMinutes'],
          ),
          variant: _readString(data['variante'] ?? data['variant'], fallback: ''),
          numericPrice: _parseNumericPrice(data['preis'] ?? data['price'] ?? data['betrag']),
        ),
      );
    }
  }

  return extracted;
}

_BookedService? _parseServiceEntry(dynamic entry) {
  if (entry is String) {
    final title = entry.trim();
    if (title.isEmpty) return null;
    return _BookedService(
      category: '',
      title: title,
      priceText: '-',
      durationText: '',
      durationMinutes: null,
      variant: '',
      numericPrice: null,
    );
  }

  if (entry is! Map) return null;

  final map = Map<String, dynamic>.from(entry);
  final title = _readString(
    map['titel'] ?? map['title'] ?? map['name'] ?? map['leistung'] ?? map['service'],
    fallback: '-',
  );

  final priceValue = map['preis'] ?? map['price'] ?? map['betrag'];
  final durationValue = map['dauer'] ?? map['duration'] ?? map['dauerMinuten'] ?? map['durationMinutes'];

  final category = _readString(map['kategorie'] ?? map['category'], fallback: '');
  final variant = _readString(map['variante'] ?? map['variant'] ?? map['option'], fallback: '');

  return _BookedService(
    category: category,
    title: title,
    priceText: _displayPrice(priceValue),
    durationText: _displayDuration(durationValue),
    durationMinutes: _parseDurationMinutes(durationValue),
    variant: variant,
    numericPrice: _parseNumericPrice(priceValue),
  );
}

String _resolveTotalPriceText(Map<String, dynamic> data, List<_BookedService> services) {
  final explicitTotal = data['gesamtpreis'] ?? data['gesamtPreis'] ?? data['totalPreis'] ?? data['totalPrice'];
  if (explicitTotal != null) {
    return _displayPrice(explicitTotal);
  }

  final values = services.map((s) => s.numericPrice).whereType<double>().toList();
  if (values.isEmpty) return '-';

  final total = values.fold<double>(0, (sum, value) => sum + value);
  return NumberFormat.currency(locale: 'de_DE', symbol: '€').format(total);
}

String _resolveTotalDurationText(Map<String, dynamic> data, List<_BookedService> services) {
  final explicitTotal = data['gesamtdauer'] ?? data['gesamtDauer'] ?? data['totalDauer'] ?? data['totalDuration'];
  if (explicitTotal != null) {
    return _displayDuration(explicitTotal);
  }

  final minutes = services.map((s) => s.durationMinutes).whereType<int>().toList();
  if (minutes.isEmpty) return '-';

  return _formatMinutes(minutes.fold<int>(0, (sum, value) => sum + value));
}

String _buildTimeRange({
  required DateTime? startAt,
  required DateTime? endAt,
  required String startFallback,
  required String endFallback,
}) {
  final start = startAt != null ? DateFormat('HH:mm', 'de_DE').format(startAt) : startFallback;
  final end = endAt != null ? DateFormat('HH:mm', 'de_DE').format(endAt) : endFallback;

  if (start == '-' && end == '-') return '-';
  if (end == '-') return start;
  return '$start – $end';
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
    if (normalized.isNotEmpty) {
      return DateTime.tryParse(normalized);
    }
  }

  return null;
}

DateTime? _parseStoredDate(dynamic value) {
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

String _readString(dynamic value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return fallback;
}

String? _readNullableString(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

String _displayPrice(dynamic value) {
  if (value == null) return '-';
  if (value is num) {
    return NumberFormat.currency(locale: 'de_DE', symbol: '€').format(value.toDouble());
  }

  final text = value.toString().trim();
  if (text.isEmpty) return '-';

  final parsed = _parseNumericPrice(text);
  if (parsed != null) {
    return NumberFormat.currency(locale: 'de_DE', symbol: '€').format(parsed);
  }

  return text;
}

double? _parseNumericPrice(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is! String) return null;

  final normalized = value
      .replaceAll('€', '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('.', '')
      .replaceAll(',', '.');

  return double.tryParse(normalized);
}

String _displayDuration(dynamic value) {
  if (value == null) return '';
  if (value is num) {
    return _formatMinutes(value.round());
  }

  final text = value.toString().trim();
  if (text.isEmpty) return '';

  final minutes = _parseDurationMinutes(text);
  if (minutes != null) return _formatMinutes(minutes);

  return text;
}

int? _parseDurationMinutes(dynamic value) {
  if (value is num) return value.round();
  if (value is! String) return null;

  final text = value.trim().toLowerCase();
  if (text.isEmpty) return null;

  final hourMinuteMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
  if (hourMinuteMatch != null) {
    final h = int.tryParse(hourMinuteMatch.group(1)!);
    final m = int.tryParse(hourMinuteMatch.group(2)!);
    if (h != null && m != null) return (h * 60) + m;
  }

  final directDigits = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));
  if (directDigits == null) return null;

  if (text.contains('std') || text.contains('hour') || text == '${directDigits}h') {
    return directDigits * 60;
  }

  return directDigits;
}

String _formatMinutes(int minutes) {
  if (minutes <= 0) return '-';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins Min';
  if (mins == 0) return '$hours Std';
  return '$hours Std $mins Min';
}

String _capitalize(String text) {
  if (text.isEmpty) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}
