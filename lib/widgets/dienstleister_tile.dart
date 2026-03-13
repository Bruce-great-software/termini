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

  // ---------------- Helper: Format ----------------
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

  // ---------------- Helper: Farben ----------------
  static const String _zgDamen  = 'Damen';
  static const String _zgHerren = 'Herren';
  static const String _zgKinder = 'Kinder';

  Color _colorForZielgruppe(String? z) {
    switch (z) {
      case _zgDamen:
        return const Color(0xFFE91E63); // Pink
      case _zgKinder:
        return const Color(0xFFFFC107); // Gelb (Amber)
      case _zgHerren:
      default:
        return Colors.blueAccent;       // Blau
    }
  }

  /// Versucht zuerst offer['chipColor'] (Color oder int), sonst Zielgruppe, sonst Blau.
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
    final logoUrl  = data['logoUrl'];
    final name     = (data['name'] ?? 'Kein Name').toString();
    final adresse  = (data['adresse'] ?? '').toString();
    final plz      = (data['plz'] ?? '').toString();
    final ort      = (data['ort'] ?? '').toString();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Quelle: Prop > data['matchedOffers'] > []
    final List<Map<String, dynamic>> offers =
        matchedOffers ??
            ((data['matchedOffers'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
                const <Map<String, dynamic>>[]);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Logo + Stammdaten
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo links
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: (logoUrl != null && logoUrl.toString().isNotEmpty)
                          ? Image.network(
                        logoUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.storefront,
                          size: 30,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                          : Icon(
                        Icons.storefront,
                        size: 30,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Name, Adresse, Entfernung
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (adresse.isNotEmpty) adresse,
                            [plz, ort].where((s) => s.isNotEmpty).join(' ')
                          ]
                              .where((s) => s.toString().trim().isNotEmpty)
                              .join(', '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (distance is num) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.place,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${distance.toStringAsFixed(1)} km entfernt',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
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

              // -------------------- NEU: Angebote gruppiert pro Titel --------------------
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

                // Gruppieren: title -> zielgruppe -> offer
                Builder(builder: (_) {
                  final Map<String, Map<String, Map<String, dynamic>>> grouped = {};
                  for (final o in offers) {
                    final title = (o['titel'] ?? o['name'] ?? '').toString().trim();
                    final zg = (o['zielgruppe'] ?? '').toString().trim();
                    if (title.isEmpty) continue;
                    if (!grouped.containsKey(title)) grouped[title] = {};
                    if (zg.isNotEmpty) grouped[title]![zg] = o;
                  }

                  const zielgruppenOrder = <String>[_zgDamen, _zgHerren, _zgKinder];

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
                                if (offer == null) return const SizedBox.shrink();

                                final dauer = _fmtDauer(offer['dauer']);
                                final preis = _fmtPreis(offer['preis']);
                                final chipColor = _resolveChipColor(offer);

                                return Chip(
                                  backgroundColor: chipColor.withOpacity(0.12),
                                  side: BorderSide(color: chipColor.withOpacity(0.4)),
                                  label: Text(
                                    [zg, if (dauer.isNotEmpty) dauer, if (preis.isNotEmpty) preis]
                                        .join(' • '),
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
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}