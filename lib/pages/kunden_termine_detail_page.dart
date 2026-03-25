import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class KundenTermineDetailPage extends StatefulWidget {
  final String terminId;
  final DateTime startAt;
  final String? mitarbeiterId;
  final String dienstleisterName;
  final String mitarbeiterName;
  final String status;

  const KundenTermineDetailPage({
    super.key,
    required this.terminId,
    required this.startAt,
    required this.mitarbeiterId,
    required this.dienstleisterName,
    required this.mitarbeiterName,
    required this.status,
  });

  @override
  State<KundenTermineDetailPage> createState() => _KundenTermineDetailPageState();
}

class _KundenTermineDetailPageState extends State<KundenTermineDetailPage> {
  bool _isCancelling = false;

  Future<void> _cancelTermin() async {
    if (_isCancelling) return;

    setState(() {
      _isCancelling = true;
    });

    try {
      await FirebaseFirestore.instance.collection('termine').doc(widget.terminId).update({
        'status': 'abgesagt',
        'abgesagtAm': Timestamp.now(),
        'abgesagtVon': 'kunde',
      });

      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (!mounted) return;
      setState(() {
        _isCancelling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _capitalize(DateFormat('EEEE, d. MMMM', 'de_DE').format(widget.startAt));
    final timeText = DateFormat('HH:mm', 'de_DE').format(widget.startAt);

    final theme = Theme.of(context);
    const headerColor = Color(0xFF1F3A57);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informationen zum Termin'),
      ),
      body: SafeArea(
        child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('termine').doc(widget.terminId).get(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? const <String, dynamic>{};
            final leistungsPositionen = _parseLeistungsPositionen(data['leistungsPositionen']);
            final grouped = <String, List<_LeistungsPosition>>{};
            for (final position in leistungsPositionen) {
              grouped.putIfAbsent(position.category, () => <_LeistungsPosition>[]).add(position);
            }

            final totalPrice = _toDouble(data['preisGesamt']);
            final totalDuration = _toInt(data['dauerGesamt']);
            final currentStatus = (data['status'] as String?)?.trim().toLowerCase();
            final isCancelled = currentStatus == 'abgesagt' || widget.status.trim().toLowerCase() == 'abgesagt';

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Material(
                          color: Colors.white,
                          elevation: 1,
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
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
                                      mitarbeiterId: widget.mitarbeiterId,
                                      fallbackName: widget.mitarbeiterName,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.dienstleisterName,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            widget.mitarbeiterName,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            (data['status'] as String?)?.trim().isNotEmpty == true
                                                ? (data['status'] as String).trim()
                                                : widget.status,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: Colors.grey.shade700,
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '2. Gebuchte Leistungen',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (grouped.isNotEmpty)
                          ...grouped.entries.map(
                            (categoryEntry) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Material(
                                color: Colors.white,
                                elevation: 1,
                                borderRadius: BorderRadius.circular(8),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      color: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Text(
                                        categoryEntry.key,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    ...categoryEntry.value.map(
                                      (position) => Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: const BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(color: Color(0xFFE9EAED)),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    position.title,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      color: Color(0xFF101828),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _formatEuro(position.price),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF101828),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (position.subtitle.trim().isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                position.subtitle,
                                                style: const TextStyle(color: Color(0xFF667085)),
                                              ),
                                            ],
                                            const SizedBox(height: 6),
                                            Text(
                                              '${position.duration} Min',
                                              style: const TextStyle(
                                                color: Color(0xFF344054),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (grouped.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE9EAED)),
                            ),
                            child: Text(
                              'Keine Leistungen verfügbar.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF667085),
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE4E7EC)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Gesamtdauer',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    '${totalDuration ?? 0} Min',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Gesamtpreis',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    _formatEuro(totalPrice),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isCancelled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isCancelling ? null : _cancelTermin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF443A),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFFF443A),
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        child: _isCancelling
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Termin absagen'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LeistungsPosition {
  final String category;
  final String title;
  final String subtitle;
  final double? price;
  final double? originalPrice;
  final int duration;

  const _LeistungsPosition({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.originalPrice,
    required this.duration,
  });
}

List<_LeistungsPosition> _parseLeistungsPositionen(dynamic raw) {
  if (raw is! List) return const [];

  return raw.whereType<Map>().map((item) {
    final map = Map<String, dynamic>.from(item.cast<dynamic, dynamic>());
    return _LeistungsPosition(
      category: (map['category'] as String?)?.trim().isNotEmpty == true
          ? (map['category'] as String).trim()
          : 'Sonstiges',
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? (map['title'] as String).trim()
          : 'Leistung',
      subtitle: ((map['subtitle'] as String?) ?? '').trim(),
      price: _toDouble(map['price']),
      originalPrice: _toDouble(map['originalPrice']),
      duration: _toInt(map['duration']) ?? 0,
    );
  }).toList(growable: false);
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

String _capitalize(String text) {
  if (text.isEmpty) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

String _initialsFromName(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

String _formatEuro(double? value) {
  final formatter = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  if (value == null) return formatter.format(0);
  return formatter.format(value);
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }
  return null;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
