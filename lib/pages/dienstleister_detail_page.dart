import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';

/// ---- Brand / Farben (Lieferando-ähnlich) ----
const Color kBrandOrange = Color(0xFFFF7A00); // Buttonfarbe
const double kBottomBarHeight = 76.0;

/// Datenträger für einen Abschnitt (blauer Balken + Inhalt)
class SectionData {
  final String title;           // z. B. "Augenbrauen"
  final List<Widget> children;  // Angebots-Widgets unter dem Balken
  SectionData(this.title, this.children);
}

/// Interner Warenkorb-Eintrag
class _CartItem {
  final String kategorie;
  final String leistung;
  final double? preis;
  final int? dauer;
  final String zielgruppe;
  const _CartItem({
    required this.kategorie,
    required this.leistung,
    required this.preis,
    required this.dauer,
    required this.zielgruppe,
  });
}

class LinkedChipsWithSections extends StatefulWidget {
  final List<SectionData> sections;
  final int initialIndex;

  /// fixiertes Extra am Listenende, damit die Bottom-Bar nichts verdeckt
  final double extraBottom;

  const LinkedChipsWithSections({
    super.key,
    required this.sections,
    this.initialIndex = 0,
    this.extraBottom = 0.0,
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

    const double kTopTolerance = 0.02; // = 2% der Listenhöhe

    itemPositionsListener.itemPositions.addListener(() {
      if (_programmaticScroll) return;
      final positions = itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;

      final visible =
      positions.where((p) => p.index < widget.sections.length).toList();
      if (visible.isEmpty) return;

      final atTopOrBeyond =
      visible.where((p) => p.itemLeadingEdge <= kTopTolerance).toList();

      int? idx;
      if (atTopOrBeyond.isNotEmpty) {
        final best = atTopOrBeyond.reduce((a, b) => a.index > b.index ? a : b);
        idx = best.index;
      } else {
        idx = null;
      }

      if (idx != null && idx != activeChip) {
        setState(() => activeChip = idx!);
        _scrollChipTo(activeChip);
      }
    });
  }

  Future<void> _scrollChipTo(int index) async {
    if (!chipScrollController.isAttached) return;
    await chipScrollController.scrollTo(
      index: index,
      alignment: 0.0,
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
                padding: const EdgeInsets.only(right: 8),
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

        Expanded(
          child: ScrollablePositionedList.builder(
            itemScrollController: itemScrollController,
            itemPositionsListener: itemPositionsListener,
            itemCount: widget.sections.length + 1,
            itemBuilder: (context, index) {
              if (index == _spacerIndex) {
                // fester Platz am Ende, damit die Bottom-Bar nichts überlappt
                return SizedBox(height: widget.extraBottom);
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
        ...section.children,
        const SizedBox(height: 8),
      ],
    );
  }
}

class DienstleisterDetailPage extends StatefulWidget {
  final Map<String, dynamic> dienstleister;
  final String selektierteZielgruppe;   // momentan ungenutzt
  final String selektierteKategorie;    // fürs initiale Scrollen

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
  String _zielgruppe = 'Damen';

  /// Auswahl als ValueNotifier -> verhindert kompletten Rebuild der Liste
  final ValueNotifier<Map<String, _CartItem>> _selectedVN =
  ValueNotifier<Map<String, _CartItem>>({});

  Map<String, Widget> _zielgruppenSegments() {
    TextStyle label(String value) => TextStyle(
      fontWeight: FontWeight.w600,
      color: _zielgruppe == value ? Colors.white : Colors.blueAccent,
    );
    const EdgeInsets pad = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
    return {
      'Damen':  Padding(padding: pad, child: Text('Damen',  style: label('Damen'))),
      'Herren': Padding(padding: pad, child: Text('Herren', style: label('Herren'))),
      'Kinder': Padding(padding: pad, child: Text('Kinder', style: label('Kinder'))),
    };
  }

  void _toggleSelection(String key, _CartItem item) {
    final map = Map<String, _CartItem>.from(_selectedVN.value);
    if (map.containsKey(key)) {
      map.remove(key);
    } else {
      map[key] = item;
    }
    _selectedVN.value = map; // triggert nur die Listener
  }

  double? _sumSelectedPrices(Map<String, _CartItem> map) {
    double total = 0;
    bool hasAny = false;
    for (final entry in map.values) {
      if (entry.preis != null) {
        total += entry.preis!;
        hasAny = true;
      }
    }
    return hasAny ? total : null;
  }

  String _formatEuro(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return '$s €';
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
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

  (double?, int?) _preisUndDauerFuerZielgruppe(Map<String, dynamic> data, String zielgruppe) {
    double? preis;
    int? dauer;
    final zg = data['zielgruppen'];
    if (zg is Map) {
      final g = zg[zielgruppe];
      if (g is Map) {
        preis = _toDouble(g['preis']);
        dauer = _toInt(g['dauer']);
      }
    }
    preis ??= _toDouble(data['preis']);
    dauer ??= _toInt(data['dauer']);
    return (preis, dauer);
  }

  String _preisText(double? p) {
    if (p == null) return '–';
    final s = p.toStringAsFixed(2).replaceAll('.', ',');
    return 'ab $s €';
  }

  String _dauerText(int? d) => d == null ? '' : ' • ${d.toString()} Min';

  @override
  Widget build(BuildContext context) {
    final String dienstleisterId = widget.dienstleister['id'] as String;

    return Scaffold(
      // AppBar: Segment-Control anstelle des Standorts
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: CupertinoSegmentedControl<String>(
          children: _zielgruppenSegments(),
          groupValue: _zielgruppe,
          onValueChanged: (v) => setState(() => _zielgruppe = v),
          borderColor: Colors.white,
          selectedColor: Colors.blueAccent,
          unselectedColor: Colors.white,
          pressedColor: Colors.white.withOpacity(.15),
          padding: EdgeInsets.zero,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              (widget.dienstleister['name'] as String?) ?? 'Profil',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
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

          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final doc in snap.data!.docs) {
            final data = doc.data();
            final kategorie = (data['kategorie'] as String?)?.trim();
            if (kategorie == null || kategorie.isEmpty) continue;

            final (preisZG, dauerZG) =
            _preisUndDauerFuerZielgruppe(data, _zielgruppe);
            if (preisZG == null && dauerZG == null) continue;

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
                'preis': preisZG,
                'dauer': dauerZG,
              });
            }
          }

          final kategorien = grouped.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          final sections = <SectionData>[];
          for (final kat in kategorien) {
            final items = grouped[kat]!
              ..sort((a, b) => (a['leistung'] as String)
                  .toLowerCase()
                  .compareTo((b['leistung'] as String).toLowerCase()));

            final children = items.map((e) {
              final name = e['leistung'] as String;
              final preis = e['preis'] as double?;
              final dauer = e['dauer'] as int?;
              final subtitle = '${_preisText(preis)}${_dauerText(dauer)}';
              final key = '${kat.toLowerCase()}|${name.toLowerCase()}';

              // Einzelnes Tile liest die Auswahl reaktiv aus dem ValueNotifier
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
                      // Titel + Subtitel
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),

                      // Trailing-Icon reaktiv (nur dieser Teil baut neu)
                      ValueListenableBuilder<Map<String, _CartItem>>(
                        valueListenable: _selectedVN,
                        builder: (_, map, __) {
                          final selected = map.containsKey(key);
                          return IconButton(
                            onPressed: () {
                              _toggleSelection(
                                key,
                                _CartItem(
                                  kategorie: kat,
                                  leistung: name,
                                  preis: preis,
                                  dauer: dauer,
                                  zielgruppe: _zielgruppe,
                                ),
                              );
                            },
                            icon: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                            ),
                            color: selected ? Colors.blueAccent : null,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            }).toList();

            if (children.isNotEmpty) {
              sections.add(SectionData(kat, children));
            }
          }

          int initialIndex = 0;
          final selKat = widget.selektierteKategorie.trim();
          if (selKat.isNotEmpty && kategorien.contains(selKat)) {
            initialIndex = kategorien.indexOf(selKat);
          }

          // Inhalt + fixierte Bottom-Bar
          return Stack(
            children: [
              // WICHTIG: fester extraBottom -> kein Layout-Shift -> kein „nach oben springen“
              const LinkedChipsWithSections(
                sections: [], // Placeholder, wird unten ersetzt
              ),

              // Wir müssen das echte Widget mit Daten rendern:
              LinkedChipsWithSections(
                sections: sections,
                initialIndex: initialIndex,
                // Immer Platz für die Bottom-Bar lassen, auch wenn sie (noch) unsichtbar ist
                extraBottom: kBottomBarHeight + 12,
              ),

              // ---- Buchungsleiste im Lieferando-Stil (reaktiv) ----
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ValueListenableBuilder<Map<String, _CartItem>>(
                  valueListenable: _selectedVN,
                  builder: (context, map, _) {
                    final hasSelection = map.isNotEmpty;
                    final total = _sumSelectedPrices(map);
                    return IgnorePointer(
                      ignoring: !hasSelection,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        height: hasSelection ? kBottomBarHeight : 0,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: SafeArea(
                          top: false,
                          child: hasSelection
                              ? _BookingBar(
                            count: map.length,
                            total: total,
                            onPressed: () {
                              // TODO: zur Buchungs-/Checkout-Seite navigieren
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Zur Buchung (${map.length})',
                                  ),
                                ),
                              );
                            },
                          )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Pill-Button wie im Screenshot:
/// Links Icon mit Count-Badge, Mitte "Zur Buchung", Rechts Preis.
class _BookingBar extends StatelessWidget {
  final int count;
  final double? total;
  final VoidCallback onPressed;

  const _BookingBar({
    required this.count,
    required this.total,
    required this.onPressed,
  });

  String _formatEuro(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return '$s €';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: kBrandOrange,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: onPressed,
        child: Row(
          children: [
            // Linker Kreis mit Icon + Badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.shopping_basket_outlined,
                      size: 22, color: Colors.white),
                ),
                Positioned(
                  right: -3, top: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBrandOrange, width: 2),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kBrandOrange,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 12),

            // Mitte: "Zur Buchung" zentriert
            Expanded(
              child: Center(
                child: Text(
                  'Zur Buchung',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),

            // Rechts: Gesamtpreis
            Text(
              total == null ? '' : _formatEuro(total!),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
