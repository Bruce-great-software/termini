import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/leistung_erstellen_dialog.dart';

class DienstleisterAngebotePage extends StatelessWidget {
  const DienstleisterAngebotePage({
    super.key,
    this.showScaffold = true,
  });

  final bool showScaffold;

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value
          .replaceAll(RegExp(r'[^0-9,.-]'), '')
          .replaceAll(',', '.');
      return normalized.isEmpty ? null : double.tryParse(normalized);
    }
    return null;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final normalized = value.replaceAll(RegExp(r'[^0-9-]'), '');
      return normalized.isEmpty ? null : int.tryParse(normalized);
    }
    return null;
  }

  (double?, int?) _minPreisUndDauer(Map<String, dynamic> data) {
    double? preis = _toDouble(data['preis']);
    int? dauer = _toInt(data['dauer']);

    if (data['zielgruppen'] is Map) {
      final zielgruppen = Map<String, dynamic>.from(data['zielgruppen']);
      final preise = <double>[];
      final dauern = <int>[];

      for (final entry in zielgruppen.values) {
        if (entry is! Map) continue;

        final entryPreis = _toDouble(entry['preis']);
        final entryDauer = _toInt(entry['dauer']);
        if (entryPreis != null) preise.add(entryPreis);
        if (entryDauer != null) dauern.add(entryDauer);

        if (entry['varianten'] is! Map) continue;

        final varianten = Map<String, dynamic>.from(entry['varianten']);
        for (final variante in varianten.values) {
          if (variante is! Map) continue;
          final variantenPreis = _toDouble(variante['preis']);
          final variantenDauer = _toInt(variante['dauer']);
          if (variantenPreis != null) preise.add(variantenPreis);
          if (variantenDauer != null) dauern.add(variantenDauer);
        }
      }

      if (preise.isNotEmpty) {
        final minPreis = preise.reduce((a, b) => a < b ? a : b);
        preis = preis == null ? minPreis : (minPreis < preis ? minPreis : preis);
      }

      if (dauern.isNotEmpty) {
        final minDauer = dauern.reduce((a, b) => a < b ? a : b);
        dauer = dauer == null ? minDauer : (minDauer < dauer ? minDauer : dauer);
      }
    }

    return (preis, dauer);
  }

  String _preisText(double? preis) {
    if (preis == null) return '–';
    final formatted = preis.toStringAsFixed(2).replaceAll('.', ',');
    return 'ab $formatted €';
  }

  String _dauerText(int? dauer) => dauer == null ? '' : ' • $dauer Min';

  String _fallbackTitel(Map<String, dynamic> data) {
    final kategorie = (data['kategorie'] as String?)?.trim() ?? 'Sonstiges';
    final leistungen = (data['leistungen'] is List)
        ? List<String>.from(data['leistungen'])
            .where((entry) => entry.trim().isNotEmpty)
            .toList()
        : <String>[];

    if (leistungen.isEmpty) return kategorie;
    return '$kategorie – ${leistungen.join(' & ')}';
  }

  Widget _buildHeaderListView(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Meine Leistungen',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      const fallback = Center(child: Text('Nicht eingeloggt'));
      if (!showScaffold) return fallback;
      return const Scaffold(body: Center(child: Text('Nicht eingeloggt')));
    }

    final content = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('angebote')
          .where('dienstleisterId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildHeaderListView(
            const [
              SizedBox(height: 32),
              Center(child: Text('Noch keine Leistungen erstellt.')),
            ],
          );
        }

        final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final doc in snapshot.data!.docs) {
          final data = doc.data();
          final kategorie = (data['kategorie'] as String?)?.trim();
          final key = (kategorie == null || kategorie.isEmpty)
              ? 'Sonstiges'
              : kategorie;
          grouped.putIfAbsent(key, () => []).add(doc);
        }

        final kategorien = grouped.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        final children = <Widget>[];

        for (final kategorie in kategorien) {
          final docs = grouped[kategorie]!
            ..sort((a, b) {
              final at = (a.data()['titel'] as String?) ?? _fallbackTitel(a.data());
              final bt = (b.data()['titel'] as String?) ?? _fallbackTitel(b.data());
              return at.toLowerCase().compareTo(bt.toLowerCase());
            });

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
                  kategorie,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          );

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
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.black38),
                        onPressed: () => _showMehrSheetForDoc(
                          context: context,
                          docId: doc.id,
                          data: data,
                          titel: titel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          children.add(const SizedBox(height: 8));
        }

        return _buildHeaderListView(children);
      },
    );

    if (!showScaffold) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Leistungen'),
        centerTitle: true,
      ),
      body: content,
    );
  }

  void _showMehrSheetForDoc({
    required BuildContext context,
    required String docId,
    required Map<String, dynamic> data,
    required String titel,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Bearbeiten'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => LeistungErstellenDialog(
                    angebotId: docId,
                    initialData: data,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Löschen',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FirebaseFirestore.instance
                    .collection('angebote')
                    .doc(docId)
                    .delete();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('„$titel“ gelöscht')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Abbrechen'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }
}
