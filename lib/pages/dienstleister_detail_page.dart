import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/cupertino.dart';

/// ---- Brand / Farben (Lieferando-ähnlich) ----
const Color kBrandOrange = Color(0xFFFF7A00); // Buttonfarbe
const double kBottomBarHeight = 76.0;

/// ---- Angebot-Modell ----
class Offer {
  final String id;
  final String kategorie;
  final List<String> leistungen;      // sortiert, Original-Schreibweise
  final List<String> leistungenLc;    // sortiert, lowercased (für Logik)
  final bool isBundle;
  final String? comboKey;
  final Map<String, dynamic> zielgruppen;

  /// Angezeigter Titel aus Firestore (Feld "titel")
  final String titleDisplay;

  /// Optional: Varianten je Leistung (falls vorhanden)
  final Map<String, String> variantenByLeistung;

  Offer({
    required this.id,
    required this.kategorie,
    required this.leistungen,
    required this.leistungenLc,
    required this.isBundle,
    required this.comboKey,
    required this.zielgruppen,
    required this.variantenByLeistung,
    required this.titleDisplay,
  });

  factory Offer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final kat = (d['kategorie'] as String? ?? '').trim();

    // Leistungen bestimmen
    List<String> ls = [];
    if (d['leistungenSortiert'] is List) {
      ls = List<String>.from(d['leistungenSortiert']);
    } else if (d['leistungen'] is List) {
      ls = List<String>.from(d['leistungen']);
    } else {
      // Fallback aus Titel ableiten
      final t = (d['titel'] as String? ?? '');
      final parts = t.split(RegExp(r'\s*[–—-]\s*'));
      if (parts.length >= 2) {
        ls = [parts.sublist(1).join(' – ').trim()];
      } else if (t.isNotEmpty) {
        ls = [t.trim()];
      }
    }
    ls = ls.where((e) => e.trim().isNotEmpty).toList();
    final lsSorted = [...ls]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final lsLc = lsSorted.map((e) => e.toLowerCase()).toList();

    final bool bundleFlag = (d['isBundle'] == true) || lsSorted.length > 1;
    final String? ck =
        (d['comboKey'] as String?)?.toLowerCase() ?? (bundleFlag ? lsLc.join('|') : null);

    // Varianten kompatibel einlesen (optional)
    final Map<String, String> vbl = {};
    if (d['variantenProLeistung'] is Map) {
      final raw = Map<String, dynamic>.from(d['variantenProLeistung']);
      raw.forEach((k, v) {
        final key = (k ?? '').toString().trim();
        final val = (v ?? '').toString().trim();
        if (key.isNotEmpty && val.isNotEmpty) vbl[key] = val;
      });
    } else if (d['variantenByLeistung'] is Map) {
      final raw = Map<String, dynamic>.from(d['variantenByLeistung']);
      raw.forEach((k, v) {
        final key = (k ?? '').toString().trim();
        final val = (v ?? '').toString().trim();
        if (key.isNotEmpty && val.isNotEmpty) vbl[key] = val;
      });
    }

    // Gespeicherten Titel bevorzugen
    String display = (d['titel'] as String?)?.trim() ?? '';
    if (display.isEmpty) {
      display = (kat.isNotEmpty && lsSorted.isNotEmpty)
          ? '$kat – ${lsSorted.join(' & ')}'
          : (lsSorted.isNotEmpty ? lsSorted.join(' & ') : kat);
    }

    return Offer(
      id: doc.id,
      kategorie: kat,
      leistungen: lsSorted,
      leistungenLc: lsLc,
      isBundle: bundleFlag,
      comboKey: ck,
      zielgruppen: Map<String, dynamic>.from(d['zielgruppen'] ?? const {}),
      variantenByLeistung: vbl,
      titleDisplay: display,
    );
  }

  /// Preis für Zielgruppe – nur wenn > 0 vorhanden, sonst null
  double? priceFor(String zg) {
    final v = zielgruppen[zg];
    if (v is Map && v['preis'] != null) {
      final p = (v['preis'] as num).toDouble();
      return p > 0 ? p : null;
    }
    return null;
  }

  /// Dauer für Zielgruppe – nur wenn > 0 vorhanden, sonst null
  int? durationFor(String zg) {
    final v = zielgruppen[zg];
    if (v is Map && v['dauer'] != null) {
      final d = (v['dauer'] as num).toInt();
      return d > 0 ? d : null;
    }
    return null;
  }
}

/// Datenträger für einen Abschnitt (blauer Balken + Inhalt)
class SectionData {
  final String title;           // z. B. "Augenbrauen"
  final List<Widget> children;  // Angebots-Widgets unter dem Balken
  SectionData(this.title, this.children);
}

/// Interner Warenkorb-Eintrag
class _CartItem {
  final String kategorie;
  final String leistung; // Basis-Leistung (ohne Variante) – wichtig für Bundle-Logik!
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
    activeChip = (widget.initialIndex >= 0 && widget.initialIndex < widget.sections.length)
        ? widget.initialIndex
        : 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (activeChip != 0) {
        _scrollTo(activeChip);
      } else {
        _scrollChipTo(activeChip);
      }
    });

    const double kTopTolerance = 0.02; // = 2% der Listenhöhe
    itemPositionsListener.itemPositions.addListener(() {
      if (_programmaticScroll) return;
      final positions = itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;

      final visible = positions.where((p) => p.index < widget.sections.length).toList();
      if (visible.isEmpty) return;

      final atTopOrBeyond = visible.where((p) => p.itemLeadingEdge <= kTopTolerance).toList();

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
      'Damen': Padding(padding: pad, child: Text('Damen', style: label('Damen'))),
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

  /// Combo-Helper: (de)selektiert alle Einzel-Leistungen der Kombi
  void _toggleCombo({
    required String category,
    required List<String> partsOriginal, // Original-Schreibweise
    required List<String> partsLc,       // lowercased
    required Map<String, Offer> singlesByKey, // '$cat|$partLc' -> Offer
  }) {
    final map = Map<String, _CartItem>.from(_selectedVN.value);
    final keys = <String>[];
    for (int i = 0; i < partsLc.length; i++) {
      final k = '${category.toLowerCase()}|${partsLc[i]}';
      keys.add(k);
    }
    final allSelected = keys.every(map.containsKey);

    if (allSelected) {
      for (final k in keys) {
        map.remove(k);
      }
    } else {
      for (int i = 0; i < partsLc.length; i++) {
        final lc = partsLc[i];
        final display = partsOriginal[i];
        final key = '${category.toLowerCase()}|$lc';
        if (!map.containsKey(key)) {
          final single = singlesByKey['$category|$lc'];
          final preis = single?.priceFor(_zielgruppe);
          final dauer = single?.durationFor(_zielgruppe);
          map[key] = _CartItem(
            kategorie: category,
            leistung: display,
            preis: preis,
            dauer: dauer,
            zielgruppe: _zielgruppe,
          );
        }
      }
    }
    _selectedVN.value = map;
  }

  String _formatEuro(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return '$s €';
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

          // ---- Docs in Modelle umwandeln, Singles/Bundles trennen ----
          final all = snap.data!.docs.map((d) => Offer.fromDoc(d)).toList();
          final singles = all.where((o) => !o.isBundle && o.leistungen.length == 1).toList();
          final bundles = all.where((o) => o.isBundle && o.leistungen.length >= 2).toList();

          // Indexe für schnelle Zugriffe
          final Map<String, Offer> singleIndex = {
            for (final s in singles) '${s.kategorie}|${s.leistungenLc.first}': s
          };

          // ---- Anzeige: NUR Singles gruppiert nach Kategorie ----
          final Map<String, List<Offer>> groupedSingles = {};
          for (final s in singles) {
            // Nur aufnehmen, wenn für die aktuelle Zielgruppe etwas gesetzt ist
            final hasZg =
                (s.priceFor(_zielgruppe) != null) || (s.durationFor(_zielgruppe) != null);
            if (!hasZg) continue;
            groupedSingles.putIfAbsent(s.kategorie, () => []).add(s);
          }

          final kategorien = groupedSingles.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          final sections = <SectionData>[];
          for (final kat in kategorien) {
            // ---- Singles (sichtbar) – sortiert nach gespeicherten Titeln ----
            final items = [...groupedSingles[kat]!]..sort(
                  (a, b) => a.titleDisplay.toLowerCase().compareTo(b.titleDisplay.toLowerCase()),
            );

            final children = <Widget>[];

            for (final offer in items) {
              final baseName = offer.leistungen.first;          // Basis für Key/Preis-Logik
              final baseLc = offer.leistungenLc.first;
              final preis = offer.priceFor(_zielgruppe);
              final dauer = offer.durationFor(_zielgruppe);

              // Sicherheitsfilter: falls doch nichts hinterlegt, nicht anzeigen
              if (preis == null && dauer == null) continue;

              final subtitle = '${_preisText(preis)}${_dauerText(dauer)}';
              final key = '${kat.toLowerCase()}|$baseLc';

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
                        // Titel + Subtitel
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // *** HIER: gespeicherten Titel zeigen ***
                              Text(
                                offer.titleDisplay,
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
                                    leistung: baseName, // Basis-Leistung (ohne Variante!)
                                    preis: preis,
                                    dauer: dauer,
                                    zielgruppe: _zielgruppe,
                                  ),
                                );
                              },
                              icon: Icon(
                                selected ? Icons.check_circle : Icons.add_circle_outline,
                              ),
                              color: selected ? Colors.blueAccent : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // ---- Kombi-Angebote (nur wenn mindestens 1 Teil fehlt) ----
            final combosForCat = bundles.where((b) => b.kategorie == kat).toList()
              ..sort((a, b) =>
                  a.titleDisplay.toLowerCase().compareTo(b.titleDisplay.toLowerCase()));

            final combosToShow = <Offer>[];
            for (final combo in combosForCat) {
              // Für die Zielgruppe muss es Daten geben
              final hasZg =
                  (combo.priceFor(_zielgruppe) != null) || (combo.durationFor(_zielgruppe) != null);
              if (!hasZg) continue;

              // Prüfen, ob ALLE Teile als Single existieren (mit Daten für ZG)
              final allPartsHaveSingle = combo.leistungenLc.every((partLc) {
                final s = singleIndex['$kat|$partLc'];
                if (s == null) return false;
                return (s.priceFor(_zielgruppe) != null) || (s.durationFor(_zielgruppe) != null);
              });

              // Nur zeigen, wenn mindestens ein Teil fehlt
              if (!allPartsHaveSingle) combosToShow.add(combo);
            }

            if (combosToShow.isNotEmpty) {
              // Subheader
              children.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Kombi-Angebote',
                    style: TextStyle(
                      color: Colors.black.withOpacity(.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );

              for (final combo in combosToShow) {
                final preis = combo.priceFor(_zielgruppe);
                final dauer = combo.durationFor(_zielgruppe);
                final subtitle = '${_preisText(preis)}${_dauerText(dauer)}';

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
                          // Titel + Subtitel
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // *** HIER: gespeicherten Titel zeigen ***
                                Text(
                                  combo.titleDisplay,
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

                          // Status = ausgewählt, wenn ALLE Teile ausgewählt sind
                          ValueListenableBuilder<Map<String, _CartItem>>(
                            valueListenable: _selectedVN,
                            builder: (_, map, __) {
                              final allSelected = combo.leistungenLc.every(
                                    (lc) => map.containsKey('${kat.toLowerCase()}|$lc'),
                              );
                              return IconButton(
                                onPressed: () {
                                  _toggleCombo(
                                    category: kat,
                                    partsOriginal: combo.leistungen,
                                    partsLc: combo.leistungenLc,
                                    singlesByKey: singleIndex,
                                  );
                                },
                                icon: Icon(
                                  allSelected
                                      ? Icons.check_circle
                                      : Icons.add_circle_outline,
                                ),
                                color: allSelected ? Colors.blueAccent : null,
                                tooltip: 'Kombi auswählen',
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
            }

            if (children.isNotEmpty) {
              sections.add(SectionData(kat, children));
            }
          }

          int initialIndex = 0;
          final selKat = widget.selektierteKategorie.trim();
          if (selKat.isNotEmpty && kategorien.contains(selKat)) {
            initialIndex = kategorien.indexOf(selKat);
          }

          // ---- Hilfsfunktion: Total mit Bundle-Override berechnen ----
          double computeTotal(Map<String, _CartItem> map) {
            if (map.isEmpty) return 0.0;

            // Auswahl nach Kategorie bündeln
            final byCat = <String, List<String>>{};
            map.forEach((key, item) {
              final cat = item.kategorie;
              byCat.putIfAbsent(cat, () => []).add(item.leistung);
            });

            double total = 0.0;

            byCat.forEach((cat, titles) {
              final titlesLc = titles.map((e) => e.toLowerCase()).toList()..sort();

              // Greedy: größte Bundles zuerst
              final catBundles = bundles.where((b) => b.kategorie == cat).toList()
                ..sort((a, b) => b.leistungenLc.length.compareTo(a.leistungenLc.length));

              final used = List<bool>.filled(titlesLc.length, false);

              // Versuche Bundles zu „legen“
              for (final b in catBundles) {
                final needed = b.leistungenLc;
                final idxs = <int>[];

                for (final n in needed) {
                  int found = -1;
                  for (int i = 0; i < titlesLc.length; i++) {
                    if (!used[i] && titlesLc[i] == n) {
                      found = i;
                      break;
                    }
                  }
                  if (found == -1) {
                    idxs.clear();
                    break;
                  }
                  idxs.add(found);
                }

                if (idxs.isNotEmpty && idxs.length == needed.length) {
                  for (final i in idxs) used[i] = true;
                  total += (b.priceFor(_zielgruppe) ?? 0.0);
                }
              }

              // Restliche Singles
              for (int i = 0; i < titlesLc.length; i++) {
                if (!used[i]) {
                  final single = singleIndex['$cat|${titlesLc[i]}'];
                  if (single != null) total += (single.priceFor(_zielgruppe) ?? 0.0);
                }
              }
            });

            return total;
          }

          // Inhalt + fixierte Bottom-Bar
          return Stack(
            children: [
              // Platzhalter
              const LinkedChipsWithSections(sections: []),

              // Echte Liste
              LinkedChipsWithSections(
                sections: sections,
                initialIndex: initialIndex,
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
                    final total = hasSelection ? computeTotal(map) : 0.0;
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Zur Buchung (${map.length}) – ${_formatEuro(total)}',
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
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.shopping_basket_outlined, size: 22, color: Colors.white),
                ),
                Positioned(
                  right: -3,
                  top: -3,
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
