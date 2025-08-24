import 'package:flutter/material.dart';

class DienstleisterTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  /// Optional: bereits gefilterte/ passende Angebote aus der Sammlung `angebote`.
  /// Erwartetes Schema je Eintrag:
  /// { 'titel': String, 'dauer': num?, 'preis': num? }
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

  @override
  Widget build(BuildContext context) {
    final distance = data['distance'];
    final logoUrl = data['logoUrl'];
    final name = (data['name'] ?? 'Kein Name').toString();
    final adresse = (data['adresse'] ?? '').toString();
    final plz = (data['plz'] ?? '').toString();
    final ort = (data['ort'] ?? '').toString();

    // Farbton der AppBar übernehmen
    const Color appBarColor = Colors.blueAccent;


    // Quelle: Prop > data['matchedOffers'] > []
    final List<Map<String, dynamic>> offers =
        matchedOffers ??
            ((data['matchedOffers'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
                const <Map<String, dynamic>>[]);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Logo + Stammdaten
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo links
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: (logoUrl != null && logoUrl.toString().isNotEmpty)
                        ? Image.network(
                      logoUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.store,
                                size: 30, color: Colors.grey),
                          ),
                    )
                        : Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.store,
                          size: 30, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name, Adresse, Entfernung
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (adresse.isNotEmpty) adresse,
                            [plz, ort].where((s) => s.isNotEmpty).join(' ')
                          ]
                              .where((s) => s.toString().trim().isNotEmpty)
                              .join(', '),
                          style: const TextStyle(color: Colors.black54),
                        ),
                        if (distance is num)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${distance.toStringAsFixed(1)} km entfernt',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // Liste der passenden Angebote unter dem Anbieter (als "Chips" in AppBar-Blau)
              if (offers.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.local_offer, size: 18, color: appBarColor),
                    const SizedBox(width: 6),
                    Text(
                      'Passende Angebote',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: appBarColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: offers.map((o) {
                    final titel = (o['titel'] ?? o['name'] ?? '').toString();
                    final dauer = _fmtDauer(o['dauer']);
                    final preis = _fmtPreis(o['preis']);

                    final parts = <String>[];
                    if (titel.isNotEmpty) parts.add(titel);
                    if (dauer.isNotEmpty) parts.add(dauer);
                    if (preis.isNotEmpty) parts.add(preis);
                    final label = parts.join(' · ');

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: appBarColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: appBarColor),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: appBarColor,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
