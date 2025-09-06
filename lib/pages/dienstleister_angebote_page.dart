import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DienstleisterAngebotePage extends StatelessWidget {
  const DienstleisterAngebotePage({super.key});

  // ---------- Helfer: Preis/Dauer aus Dokument ------------------------------
  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
      return s.isEmpty ? null : double.tryParse(s);
    }
    return null;
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final s = v.replaceAll(RegExp(r'[^0-9\-]'), '');
      return s.isEmpty ? null : int.tryParse(s);
    }
    return null;
  }

  /// Ermittelt den kleinsten Preis & die kleinste Dauer über alle Zielgruppen
  /// (oder nutzt die Felder `preis`/`dauer`, falls vorhanden).
  (double?, int?) _minPreisUndDauer(Map<String, dynamic> data) {
    double? preis = _toDouble(data['preis']);
    int? dauer = _toInt(data['dauer']);

    if (data['zielgruppen'] is Map) {
      final zg = Map<String, dynamic>.from(data['zielgruppen']);
      final preise = <double>[];
      final dauern = <int>[];

      for (final entry in zg.values) {
        if (entry is Map) {
          final p = _toDouble(entry['preis']);
          final d = _toInt(entry['dauer']);
          if (p != null) preise.add(p);
          if (d != null) dauern.add(d);
        }
      }
      if (preise.isNotEmpty) {
        final minP = preise.reduce((a, b) => a < b ? a : b);
        preis = (preis == null) ? minP : (minP < preis ? minP : preis);
      }
      if (dauern.isNotEmpty) {
        final minD = dauern.reduce((a, b) => a < b ? a : b);
        dauer = (dauer == null) ? minD : (minD < dauer ? minD : dauer);
      }
    }
    return (preis, dauer);
  }

  String _preisText(double? p) {
    if (p == null) return '–';
    final s = p.toStringAsFixed(2).replaceAll('.', ',');
    return 'ab $s €';
  }

  String _dauerText(int? d) => d == null ? '' : ' • ${d.toString()} Min';

  /// Fallback-Titel aus Kategorie + Leistungen, wenn `titel` fehlt.
  String _fallbackTitel(Map<String, dynamic> data) {
    final kat = (data['kategorie'] as String?)?.trim() ?? 'Sonstiges';
    final ls = (data['leistungen'] is List)
        ? List<String>.from(data['leistungen']).where((e) => e.trim().isNotEmpty).toList()
        : <String>[];
    if (ls.isEmpty) return kat;
    return '$kat – ${ls.join(' & ')}';
  }

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final String? dienstleisterId = FirebaseAuth.instance.currentUser?.uid;
    if (dienstleisterId == null) {
      return const Scaffold(body: Center(child: Text('Nicht eingeloggt')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Leistungen'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('angebote')
            .where('dienstleisterId', isEqualTo: dienstleisterId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('Noch keine Leistungen erstellt.'));
          }

          // Nach Kategorie gruppieren
          final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final doc in snap.data!.docs) {
            final data = doc.data();
            final kat = (data['kategorie'] as String?)?.trim();
            final key = (kat == null || kat.isEmpty) ? 'Sonstiges' : kat;
            grouped.putIfAbsent(key, () => []).add(doc);
          }

          final kategorien = grouped.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          final children = <Widget>[];
          for (final kat in kategorien) {
            final docs = grouped[kat]!..sort((a, b) {
              final at = (a.data()['titel'] as String?) ?? _fallbackTitel(a.data());
              final bt = (b.data()['titel'] as String?) ?? _fallbackTitel(b.data());
              return at.toLowerCase().compareTo(bt.toLowerCase());
            });

            // Kategorien-Header (blauer Balken)
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    kat,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            );

            // Einträge der Kategorie
            for (final doc in docs) {
              final data = doc.data();
              final titel = (data['titel'] as String?) ?? _fallbackTitel(data);
              final (minPreis, minDauer) = _minPreisUndDauer(data);
              final subtitle = '${_preisText(minPreis)}${_dauerText(minDauer)}';

              children.add(
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE5E5E5)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: const TextStyle(color: Colors.black54, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Löschen',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Angebot löschen?'),
                                content: Text('„$titel“ wirklich löschen?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Abbrechen'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Löschen'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await FirebaseFirestore.instance
                                  .collection('angebote')
                                  .doc(doc.id)
                                  .delete();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            children.add(const SizedBox(height: 8));
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: children,
          );
        },
      ),
    );
  }
}
