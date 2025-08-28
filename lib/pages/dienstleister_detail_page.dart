import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:math' as math;


/// Datenträger für einen Abschnitt (blauer Balken + Inhalt)
class SectionData {
  final String title;           // z. B. "Augenbrauen"
  final List<Widget> children;  // Angebots-Widgets unter dem Balken
  SectionData(this.title, this.children);
}

class LinkedChipsWithSections extends StatefulWidget {
  final List<SectionData> sections;
  final int initialIndex;

  const LinkedChipsWithSections({
    super.key,
    required this.sections,
    this.initialIndex = 0,
  });

  @override
  State<LinkedChipsWithSections> createState() => _LinkedChipsWithSectionsState();
}

class _LinkedChipsWithSectionsState extends State<LinkedChipsWithSections> {
  // Controller für die Abschnitte (VERTIKAL)
  final itemScrollController = ItemScrollController();
  final itemPositionsListener = ItemPositionsListener.create();

  // Controller für die Chips (HORIZONTAL)
  final chipScrollController = ItemScrollController();

  late int activeChip;
  bool _programmaticScroll = false;

  int get _spacerIndex => widget.sections.length;

  @override
  void initState() {
    super.initState();
    activeChip = (widget.initialIndex >= 0 &&
        widget.initialIndex < widget.sections.length)
        ? widget.initialIndex
        : 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (activeChip != 0) {
        _scrollTo(activeChip);
      } else {
        _scrollChipTo(activeChip); // gleich links einrasten
      }
    });

    // Wie nah an "ganz oben" der Header sein muss, damit der Chip aktiv wird
    const double kTopTolerance = 0.02; // = 2% der Listenhöhe

    itemPositionsListener.itemPositions.addListener(() {
      if (_programmaticScroll) return;
      final positions = itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;

      // Spacer ignorieren – nur echte Abschnitte betrachten
      final visible = positions
          .where((p) => p.index < widget.sections.length)
          .toList();
      if (visible.isEmpty) return;

      // Kandidaten, deren Kopf bereits "am/über" Top ist (<= Toleranz)
      final atTopOrBeyond = visible
          .where((p) => p.itemLeadingEdge <= kTopTolerance)
          .toList();

      int? idx;
      if (atTopOrBeyond.isNotEmpty) {
        // Nimm den *letzten* Abschnitt, der die Toplinie erreicht/überschritten hat
        final best = atTopOrBeyond.reduce((a, b) => a.index > b.index ? a : b);
        idx = best.index;
      } else {
        // Noch keiner "am Top": nichts umschalten (alter aktiver Chip bleibt)
        idx = null;
      }

      if (idx != null && idx != activeChip) {
        setState(() => activeChip = idx!);
        _scrollChipTo(activeChip); // Chip ganz links einrasten
      }
    });
  }

  Future<void> _scrollChipTo(int index) async {
    if (!chipScrollController.isAttached) return;
    await chipScrollController.scrollTo(
      index: index,
      alignment: 0.0, // exakt an den linken Rand
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _scrollTo(int index) async {
    final clamped = index.clamp(0, widget.sections.length - 1);
    setState(() => activeChip = clamped);
    _scrollChipTo(clamped);

    _programmaticScroll = true;
    try {
      await itemScrollController.scrollTo(
        index: clamped,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _programmaticScroll = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // CHIPS – kein Außen-Padding, kein "separated": spacing nur rechts im Item!
        SizedBox(
          height: 48,
          child: ScrollablePositionedList.builder(
            scrollDirection: Axis.horizontal,
            itemScrollController: chipScrollController,
            itemCount: widget.sections.length,
            itemBuilder: (context, i) {
              final title = widget.sections[i].title;
              final sel = activeChip == i;
              return Padding(
                padding: const EdgeInsets.only(right: 8), // nur rechts Abstand
                child: ChoiceChip(
                  label: Text(title),
                  selected: sel,
                  onSelected: (_) => _scrollTo(i),
                  selectedColor: Colors.blueAccent.withOpacity(.14),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.blueAccent : Colors.black,
                  ),
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: sel ? Colors.blueAccent : Colors.black54,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // ABSCHNITTE (+ Spacer am Ende, damit der letzte Block oben einrasten kann)
        Expanded(
          child: ScrollablePositionedList.builder(
            itemScrollController: itemScrollController,
            itemPositionsListener: itemPositionsListener,
            itemCount: widget.sections.length + 1, // +1 = Spacer am Ende
            itemBuilder: (context, index) {
              if (index == _spacerIndex) {
                // genug Platz, damit der letzte Abschnitt bis GANZ nach oben scrollen kann
                final viewH   = MediaQuery.of(context).size.height;
                const chipsH  = 48.0 + 8.0; // Chip-Reihe + Abstand darunter
                final safeBtm = MediaQuery.of(context).padding.bottom;

                // Mindestens (Viewport - Chips), aber nie kleiner als 220
                final extra = math.max(220.0, viewH - chipsH);

                return SizedBox(height: extra + safeBtm);
              }
              final section = widget.sections[index];
              return _SectionBlock(section: section);
            },
          ),
        ),

      ],
    );
  }
}


class _SectionBlock extends StatelessWidget {
  final SectionData section;
  const _SectionBlock({required this.section});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Blauer Balken
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF4E8DF5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            section.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Inhalt
        ...section.children,
        const SizedBox(height: 8),
      ],
    );
  }
}


class DienstleisterDetailPage extends StatefulWidget {
  final Map<String, dynamic> dienstleister;
  final String selektierteZielgruppe;   // momentan ungenutzt
  final String selektierteKategorie;    // wird jetzt fürs initiale Scrollen genutzt

  const DienstleisterDetailPage({
    super.key,
    required this.dienstleister,
    required this.selektierteZielgruppe,
    required this.selektierteKategorie,
  });

  @override
  State<DienstleisterDetailPage> createState() => _DienstleisterDetailPageState();
}

class _DienstleisterDetailPageState extends State<DienstleisterDetailPage> {
  // ---- Preis/Dauer Helfer ----------------------------------------------------
  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned =
      v.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
      if (cleaned.isEmpty) return null;
      return double.tryParse(cleaned);
    }
    return null;
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[^0-9\-]'), '');
      if (cleaned.isEmpty) return null;
      return int.tryParse(cleaned);
    }
    return null;
  }

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

  // ----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final String dienstleisterId = widget.dienstleister['id'] as String;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        centerTitle: true,
        title: Text(
          (widget.dienstleister['name'] as String?) ?? 'Profil',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
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
            return const Center(child: Text('Keine Angebote vorhanden.'));
          }

          // Angebote aufbereiten: gruppiert nach Kategorie, dann je Leistung ein Eintrag
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final doc in snap.data!.docs) {
            final data = doc.data();
            final kategorie = (data['kategorie'] as String?)?.trim();
            if (kategorie == null || kategorie.isEmpty) continue;

            final (minPreis, minDauer) = _minPreisUndDauer(data);

            final list = (data['leistungen'] is List)
                ? List<String>.from(data['leistungen'])
                : <String>[];

            if (list.isEmpty) {
              final titel = (data['titel'] as String?) ?? '';
              final parts = titel.split(RegExp(r'\s*[–—-]\s*'));
              if (parts.length >= 2) {
                list.add(parts.sublist(1).join(' – ').trim());
              } else if (titel.isNotEmpty) {
                list.add(titel.trim());
              }
            }

            for (final l in list) {
              final name = (l as String?)?.trim();
              if (name == null || name.isEmpty) continue;
              grouped.putIfAbsent(kategorie, () => []);
              grouped[kategorie]!.add({
                'leistung': name,
                'preis': minPreis,
                'dauer': minDauer,
              });
            }
          }

          // Kategorien sortieren (Anzeigereihenfolge = Chip-/Abschnitts-Reihenfolge)
          final kategorien = grouped.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          // SectionData für jede Kategorie bauen
          final sections = <SectionData>[];
          for (final kat in kategorien) {
            final items = grouped[kat]!..sort((a, b) =>
                (a['leistung'] as String)
                    .toLowerCase()
                    .compareTo((b['leistung'] as String).toLowerCase()));

            final children = items.map((e) {
              final name = e['leistung'] as String;
              final preis = e['preis'] as double?;
              final dauer = e['dauer'] as int?;
              final subtitle = '${_preisText(preis)}${_dauerText(dauer)}';

              return Padding(
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
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          // TODO: später in Warenkorb legen
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
              );
            }).toList();

            sections.add(SectionData(kat, children));
          }

          // initialen Index aus selektierterKategorie ableiten (falls übergeben)
          int initialIndex = 0;
          final selKat = widget.selektierteKategorie.trim();
          if (selKat.isNotEmpty && kategorien.contains(selKat)) {
            initialIndex = kategorien.indexOf(selKat);
          }

          return LinkedChipsWithSections(
            sections: sections,
            initialIndex: initialIndex,
          );
        },
      ),
    );
  }
}
