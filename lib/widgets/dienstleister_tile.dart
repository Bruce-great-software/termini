import 'package:flutter/material.dart';

class DienstleisterTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  /// Optional: bereits gefilterte/ passende Angebote aus der Sammlung `angebote`.
  /// Erwartetes Schema je Eintrag:
  /// { 'titel': String, 'dauer': num?, 'preis': num?, 'zielgruppe': String?, 'chipColor': Color|int? }
  final List<Map<String, dynamic>>? matchedOffers;

  const DienstleisterTile({
    super.key,
    required this.data,
    required this.onTap,
    this.matchedOffers,
  });

  String _fmtPreis(dynamic v) {
    if (v == null) return '';
    if (v is int) return '$v €';
    if (v is double) {
      final isWhole = v.truncateToDouble() == v;
      return isWhole ? '${v.toStringAsFixed(0)} €' : '${v.toStringAsFixed(2)} €';
    }
    return '$v €';
  }

  String _fmtDauer(dynamic v) {
    if (v == null) return '';
    if (v is int) return '$v Min.';
    if (v is double) return '${v.round()} Min.';
    return '$v Min.';
  }

  static const String _zgDamen = 'Damen';
  static const String _zgHerren = 'Herren';
  static const String _zgKinder = 'Kinder';

  Color _colorForZielgruppe(String? z) {
    switch (z) {
      case _zgDamen:
        return const Color(0xFFE91E63);
      case _zgKinder:
        return const Color(0xFFFFC107);
      case _zgHerren:
      default:
        return Colors.blueAccent;
    }
  }

  Color _resolveChipColor(Map<String, dynamic> offer) {
    final dynamic c = offer['chipColor'];
    if (c is Color) return c;
    if (c is int) return Color(c);
    final zg = offer['zielgruppe'] as String?;
    return _colorForZielgruppe(zg);
  }

  @override
  Widget build(BuildContext context) {
    final distance = data['distance'];
    final String logoUrl = (data['logoUrl'] ?? '').toString().trim();
    final name = (data['name'] ?? 'Kein Name').toString();
    final adresse = (data['adresse'] ?? '').toString();
    final plz = (data['plz'] ?? '').toString();
    final ort = (data['ort'] ?? '').toString();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rating = (data['rating'] is num) ? (data['rating'] as num).toDouble() : null;
    final category = (data['kategorie'] ?? data['branche'] ?? '').toString().trim();
    final bool? isOpen = data['isOpenNow'] is bool ? data['isOpenNow'] as bool : null;

    final List<Map<String, dynamic>> offers =
        matchedOffers ??
            ((data['matchedOffers'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
                const <Map<String, dynamic>>[]);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.08),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: logoUrl.isNotEmpty
                              ? Image.network(
                            logoUrl,
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.storefront,
                                size: 34,
                                color: colorScheme.onSurfaceVariant,
                              );
                            },
                          )
                              : Icon(
                            Icons.storefront,
                            size: 34,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: .1,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              [
                                if (adresse.isNotEmpty) adresse,
                                [plz, ort].where((s) => s.isNotEmpty).join(' ')
                              ]
                                  .where((s) => s.toString().trim().isNotEmpty)
                                  .join(', '),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.25,
                              ),
                            ),
                            if (rating != null || category.isNotEmpty || isOpen != null) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (rating != null)
                                    _MetaChip(
                                      icon: Icons.star_rounded,
                                      text: rating.toStringAsFixed(1),
                                      color: const Color(0xFFFFB300),
                                    ),
                                  if (category.isNotEmpty)
                                    _MetaChip(
                                      icon: Icons.sell_outlined,
                                      text: category,
                                      color: colorScheme.primary,
                                    ),
                                  if (isOpen != null)
                                    _MetaChip(
                                      icon: Icons.schedule_rounded,
                                      text: isOpen ? 'Geöffnet' : 'Geschlossen',
                                      color: isOpen ? const Color(0xFF2E7D32) : Colors.grey,
                                    ),
                                ],
                              ),
                            ],
                            if (distance is num) ...[
                              Container(
                                margin: const EdgeInsets.only(top: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.place_rounded,
                                      size: 15,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${distance.toStringAsFixed(1)} km entfernt',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (offers.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Divider(height: 1, color: colorScheme.outlineVariant),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.local_offer, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Passende Angebote',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (_) {
                        final Map<String, Map<String, Map<String, dynamic>>> grouped = {};
                        for (final o in offers) {
                          final title = (o['titel'] ?? o['name'] ?? '').toString().trim();
                          final zg = (o['zielgruppe'] ?? '').toString().trim();
                          if (title.isEmpty) continue;
                          grouped.putIfAbsent(title, () => {});
                          if (zg.isNotEmpty) {
                            grouped[title]![zg] = o;
                          }
                        }

                        const zielgruppenOrder = <String>[
                          _zgDamen,
                          _zgHerren,
                          _zgKinder,
                        ];

                        return Column(
                          children: grouped.entries.map((entry) {
                            final title = entry.key;
                            final byGroup = entry.value;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: zielgruppenOrder.map((zg) {
                                      final offer = byGroup[zg];
                                      if (offer == null) {
                                        return const SizedBox.shrink();
                                      }

                                      final dauer = _fmtDauer(offer['dauer']);
                                      final preis = _fmtPreis(offer['preis']);
                                      final chipColor = _resolveChipColor(offer);

                                      return Chip(
                                        backgroundColor: chipColor.withOpacity(0.12),
                                        side: BorderSide(color: chipColor.withOpacity(0.4)),
                                        label: Text(
                                          [
                                            zg,
                                            if (dauer.isNotEmpty) dauer,
                                            if (preis.isNotEmpty) preis,
                                          ].join(' • '),
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}