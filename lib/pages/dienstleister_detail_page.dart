import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/cupertino.dart';

/// ---- Brand / Farben ----
const Color kBrandOrange = Color(0xFFFF7A00); // Buttonfarbe
const double kBottomBarHeight = 76.0;

/// ---------------------------------------------------------------
/// Angebot-Modell
/// ---------------------------------------------------------------
class Offer {
  final String id;
  final String kategorie;
  final List<String> leistungen;   // sortiert, Original-Schreibweise
  final List<String> leistungenLc; // sortiert, lowercased (für Vergleiche)
  final bool isBundle;
  final String? comboKey;
  final Map<String, dynamic> zielgruppen;

  /// Nur noch diese Spalte für Varianten verwenden.
  /// Für eine konkrete Variante (z. B. "Seiten auf Null") enthält das Offer
  /// genau 1 Element – die gewählte Variante. Basiseinträge haben eine leere Liste.
  final List<String> varianten;

  /// Gespeicherter Titel (z. B. "Haare – Schneiden (Seiten auf Null)")
  final String titleDisplay;

  Offer({
    required this.id,
    required this.kategorie,
    required this.leistungen,
    required this.leistungenLc,
    required this.isBundle,
    required this.comboKey,
    required this.zielgruppen,
    required this.varianten,
    required this.titleDisplay,
  });

  factory Offer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final kat = (d['kategorie'] as String? ?? '').trim();

    // Leistungen normalisieren
    List<String> ls = [];
    if (d['leistungenSortiert'] is List) {
      ls = List<String>.from(d['leistungenSortiert']);
    } else if (d['leistungen'] is List) {
      ls = List<String>.from(d['leistungen']);
    } else {
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

    // Nur noch 'varianten' verwenden (Liste von Strings).
    // Fallback: falls 'varianten' fehlt, einmalig aus alten 'variantenProLeistung' ableiten.
    List<String> vars = [];
    if (d['varianten'] is List) {
      vars = List<String>.from(d['varianten'])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (d['variantenProLeistung'] is Map) {
      final m = Map<String, dynamic>.from(d['variantenProLeistung']);
      vars = m.values
          .map((v) => v.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

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
      varianten: vars,
      titleDisplay: display,
    );
  }

  double? priceFor(String zg) {
    final v = zielgruppen[zg];
    if (v is Map && v['preis'] != null) {
      final p = (v['preis'] as num).toDouble();
      return p > 0 ? p : null;
    }
    return null;
  }

  int? durationFor(String zg) {
    final v = zielgruppen[zg];
    if (v is Map && v['dauer'] != null) {
      final d = (v['dauer'] as num).toInt();
      return d > 0 ? d : null;
    }
    return null;
  }
}

/// ---------------------------------------------------------------
/// Datenträger für einen Abschnitt (blauer Balken + Inhalt)
/// ---------------------------------------------------------------
class SectionData {
  final String title;           // z. B. "Haare"
  final List<Widget> children;  // Angebots-Widgets unter dem Balken
  SectionData(this.title, this.children);
}

/// ---------------------------------------------------------------
/// Interner Warenkorb-Eintrag
/// ---------------------------------------------------------------
class _CartItem {
  final String kategorie;
  final String leistung;   // Normalisierter Teil (z. B. "Schneiden")
  final double? preis;     // Preis des konkret gewählten Angebots (Basis ODER Variante)
  final int? dauer;
  final String zielgruppe;
  final String? varianteLabel; // <<— Name der gewählten Variante (für Chip)

  const _CartItem({
    required this.kategorie,
    required this.leistung,
    required this.preis,
    required this.dauer,
    required this.zielgruppe,
    this.varianteLabel,
  });
}

/// ---------------------------------------------------------------
/// Variante-Option fürs BottomSheet
/// ---------------------------------------------------------------
class _VariantOption {
  final String label; // z. B. "Seiten auf Null"
  final String lc;
  final Offer offer;  // konkretes Offer (Basis oder Variante)

  const _VariantOption({
    required this.label,
    required this.lc,
    required this.offer,
  });
}

/// ---------------------------------------------------------------
/// Key-Helfer: unterscheidet Zielgruppe!
/// ---------------------------------------------------------------
String _keyFor({
  required String zielgruppe,
  required String category,
  required String partLc,
}) =>
    '${zielgruppe.toLowerCase()}|${category.toLowerCase()}|$partLc';

/// ---------------------------------------------------------------
/// Scroll-Wrapper mit Chips oben (Kategorien) + Sektionen
/// ---------------------------------------------------------------
class LinkedChipsWithSections extends StatefulWidget {
  final List<SectionData> sections;
  final int initialIndex;
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
  final itemScrollController = ItemScrollController();
  final itemPositionsListener = ItemPositionsListener.create();
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

    const double kTopTolerance = 0.02;
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
                  selectedColor: Colors.blueAccent.withAlpha(36),
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

/// ---------------------------------------------------------------
/// Detailseite
/// ---------------------------------------------------------------
class DienstleisterDetailPage extends StatefulWidget {
  final Map<String, dynamic> dienstleister;
  final String selektierteZielgruppe;
  final String selektierteKategorie;

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

  // === Zielgruppen-Mix verhindern ============================================
  bool _hasItemsFromOtherZielgruppe(String zg) {
    final map = _selectedVN.value;
    if (map.isEmpty) return false;
    return map.values.any((it) => it.zielgruppe != zg);
  }

  void _showWrongGroupSnack(String other) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Du hast bereits Angebote für $other ausgewählt. '
              'Entferne diese zuerst, um Angebote für $_zielgruppe zu wählen.',
        ),
      ),
    );
  }
  // ===========================================================================

  void _toggleSelection(String key, _CartItem item) {
    final map = Map<String, _CartItem>.from(_selectedVN.value);

    if (!map.containsKey(key)) {
      // Beim Hinzufügen prüfen, ob schon Items anderer Zielgruppe liegen
      if (_hasItemsFromOtherZielgruppe(item.zielgruppe)) {
        final other = map.values.first.zielgruppe;
        _showWrongGroupSnack(other);
        return;
      }
      map[key] = item;
    } else {
      map.remove(key);
    }

    _selectedVN.value = map;
  }

  /// Combo-Helper: (de)selektiert alle Einzel-Leistungen der Kombi
  void _toggleCombo({
    required String category,
    required List<String> partsOriginal, // Original-Schreibweise
    required List<String> partsLc, // lowercased
    required Map<String, Offer> singlesByKey, // '$cat|$partLc' -> Offer (Basis)
  }) {
    final zg = _zielgruppe;

    // Zielgruppen-Mix blockieren
    if (_hasItemsFromOtherZielgruppe(zg)) {
      final other = _selectedVN.value.values.first.zielgruppe;
      _showWrongGroupSnack(other);
      return;
    }

    final map = Map<String, _CartItem>.from(_selectedVN.value);
    final keys = <String>[];
    for (int i = 0; i < partsLc.length; i++) {
      keys.add(_keyFor(zielgruppe: zg, category: category, partLc: partsLc[i]));
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
        final key = _keyFor(zielgruppe: zg, category: category, partLc: lc);
        if (!map.containsKey(key)) {
          final single = singlesByKey['$category|$lc'];
          final preis = single?.priceFor(zg); // Basispreis, wenn vorhanden
          final dauer = single?.durationFor(zg);
          map[key] = _CartItem(
            kategorie: category,
            leistung: display,
            preis: preis,
            dauer: dauer,
            zielgruppe: zg,
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

  /// Öffnet das Varianten-Sheet für eine Basisleistung.
  /// [base] ist das Basis-Offer (varianten.isEmpty).
  /// [variantOffersForPart] sind alle Varianten-Offers für diese Basisleistung.
  Future<void> _openVariantSheet({
    required Offer base,
    required String category,
    required List<Offer> variantOffersForPart,
    String? preselectVarLc, // optional: vorher gewählte Variante
  }) async {
    final zg = _zielgruppe;
    final partDisplay = base.leistungen.first;
    final partLc = base.leistungenLc.first;

    final basePreis = base.priceFor(zg);

    // Header
    final headerTitle = '$category – $partDisplay';

    // Optionen vorbereiten
    final options = <_VariantOption>[];
    final byLabel = <String, Offer>{};
    for (final v in variantOffersForPart) {
      if (v.varianten.isEmpty) continue;
      final label = v.varianten.first.trim();
      if (label.isEmpty) continue;
      byLabel[label] = v;
    }
    final sortedLabels = byLabel.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // lc -> Offer & lc -> Original-Label
    final Map<String, Offer> variantsByLc = {
      for (final label in sortedLabels) label.toLowerCase(): byLabel[label]!,
    };
    final Map<String, String> labelsByLc = {
      for (final label in sortedLabels) label.toLowerCase(): label,
    };

    for (final label in sortedLabels) {
      options.add(_VariantOption(label: label, lc: label.toLowerCase(), offer: byLabel[label]!));
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // ---- WICHTIG: selectedVarLc außerhalb des StatefulBuilder halten
        String? selectedVarLc = preselectVarLc;

        final key = _keyFor(zielgruppe: zg, category: category, partLc: partLc);
        final alreadySelected = _selectedVN.value.containsKey(key);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    headerTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    basePreis != null ? _formatEuro(basePreis) : '–',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),

                const Divider(height: 1),
                const SizedBox(height: 12),
                const Text(
                  'Variante wählen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),

                // Alles, was sich bei Auswahl ändern muss, in EINEN StatefulBuilder packen
                StatefulBuilder(
                  builder: (ctx2, setSheetState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Variantenliste
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final opt = options[i];
                              final o = opt.offer;
                              final preis = o.priceFor(zg);
                              final dauer = o.durationFor(zg);

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Radio<String?>(
                                  value: opt.lc,
                                  groupValue: selectedVarLc,
                                  onChanged: (val) => setSheetState(() => selectedVarLc = val),
                                ),
                                title: Text(
                                  opt.label,
                                  overflow: TextOverflow.ellipsis,
                                  // optional: leicht hervorheben
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),

                                trailing: Text(
                                  '${_preisText(preis)}${_dauerText(dauer)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                onTap: () => setSheetState(() => selectedVarLc = opt.lc),
                              );
                            },
                          ),
                        ),

                        // Optional: Auswahl entfernen
                        if (alreadySelected) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                final map = Map<String, _CartItem>.from(_selectedVN.value);
                                map.remove(key);
                                _selectedVN.value = map;
                                Navigator.pop(ctx);
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Auswahl entfernen'),
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        // Dynamischer Button
                        SafeArea(
                          top: false,
                          child: SizedBox(
                            height: 52,
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kBrandOrange,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              onPressed: () {
                                final Offer chosen = selectedVarLc == null
                                    ? base
                                    : (variantsByLc[selectedVarLc] ?? base);

                                final item = _CartItem(
                                  kategorie: category,
                                  leistung: base.leistungen.first,
                                  preis: chosen.priceFor(zg),
                                  dauer: chosen.durationFor(zg),
                                  zielgruppe: zg,
                                  varianteLabel:
                                  selectedVarLc == null ? null : labelsByLc[selectedVarLc],
                                );

                                final map = Map<String, _CartItem>.from(_selectedVN.value);

                                if (_hasItemsFromOtherZielgruppe(zg)) {
                                  final other = map.values.first.zielgruppe;
                                  Navigator.pop(ctx);
                                  _showWrongGroupSnack(other);
                                  return;
                                }

                                map[key] = item;
                                _selectedVN.value = map;
                                Navigator.pop(ctx);
                              },
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Center(
                                      child: Text(
                                        'Hinzufügen',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Preis passt sich dynamisch an selectedVarLc an
                                  Text(
                                    (() {
                                      final Offer chosen = selectedVarLc == null
                                          ? base
                                          : (variantsByLc[selectedVarLc] ?? base);
                                      final price = chosen.priceFor(zg);
                                      return price == null ? '' : _formatEuro(price);
                                    })(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
          pressedColor: Colors.white.withAlpha(38),
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

          // Singles = genau 1 Leistung
          final singles = all.where((o) => !o.isBundle && o.leistungen.length == 1).toList();

          // In der Liste zeigen wir NUR die Basiseinträge (varianten.isEmpty)
          final singlesBase = singles.where((o) => o.varianten.isEmpty).toList();

          // Varianten-Offers = Singles mit genau 1 Variante
          final singleVariants = singles.where((o) => o.varianten.length == 1).toList();

          // Bundles
          final bundles = all.where((o) => o.isBundle && o.leistungen.length >= 2).toList();

          // ---------- SYNTHETISCHE BASIS-EINTRÄGE AUS VARIANTEN ----------
          // gruppiere Varianten nach (Kategorie|Teil)
          final Map<String, List<Offer>> variantsByPart = {};
          for (final v in singleVariants) {
            final key = '${v.kategorie}|${v.leistungenLc.first}';
            variantsByPart.putIfAbsent(key, () => <Offer>[]).add(v);
          }

          // Prüfe je Gruppe, ob es einen echten Basis-Eintrag gibt, sonst erstellen
          final List<Offer> syntheticBases = [];
          final Set<String> existingBaseKeys = {
            for (final s in singlesBase) '${s.kategorie}|${s.leistungenLc.first}'
          };

          variantsByPart.forEach((key, list) {
            if (!existingBaseKeys.contains(key) && list.isNotEmpty) {
              final sample = list.first;
              final cat = sample.kategorie;
              final partDisplay = sample.leistungen.first; // Original-Schreibweise
              final partLc = sample.leistungenLc.first;

              // Zielgruppen-Map aus MIN(Preis/Dauer) über alle Varianten
              final Map<String, dynamic> zgMap = {};
              // sammle alle ZG keys, die in irgendeiner Variante vorkommen
              final Set<String> allZgs = {};
              for (final o in list) {
                allZgs.addAll(o.zielgruppen.keys.map((e) => e.toString()));
              }
              for (final zg in allZgs) {
                double? minPrice;
                int? minDur;
                for (final o in list) {
                  final p = o.priceFor(zg);
                  final d = o.durationFor(zg);
                  if (p != null) minPrice = (minPrice == null) ? p : (p < minPrice! ? p : minPrice);
                  if (d != null) minDur = (minDur == null) ? d : (d < minDur! ? d : minDur);
                }
                if (minPrice != null || minDur != null) {
                  zgMap[zg] = {
                    if (minPrice != null) 'preis': minPrice,
                    if (minDur != null) 'dauer': minDur,
                  };
                }
              }

              syntheticBases.add(
                Offer(
                  id: 'synthetic:$key',
                  kategorie: cat,
                  leistungen: [partDisplay],
                  leistungenLc: [partLc],
                  isBundle: false,
                  comboKey: null,
                  zielgruppen: zgMap,
                  varianten: const [], // echte Basis hat leere Variantenliste
                  titleDisplay: '$cat – $partDisplay',
                ),
              );
            }
          });

          // Singles-Basis final (echte + synthetische)
          final singlesBaseFinal = [...singlesBase, ...syntheticBases];

          // Indizes
          // 1) Basis-Single: '$cat|$partLc' -> Offer
          final Map<String, Offer> singleBaseIndex = {
            for (final s in singlesBaseFinal) '${s.kategorie}|${s.leistungenLc.first}': s
          };

          // 2) Varianten-Offer: '$cat|$partLc|$varLc' -> Offer
          final Map<String, Offer> singleVariantIndex = {
            for (final s in singleVariants)
              '${s.kategorie}|${s.leistungenLc.first}|${s.varianten.first.toLowerCase()}': s
          };

          // 3) Verfügbare Varianten je Basis: '$cat|$partLc' -> Set<String>
          final Map<String, Set<String>> variantsAvailable = {};
          for (final v in singleVariants) {
            final key = '${v.kategorie}|${v.leistungenLc.first}';
            variantsAvailable.putIfAbsent(key, () => <String>{});
            if (v.varianten.isNotEmpty) {
              variantsAvailable[key]!.add(v.varianten.first);
            }
          }

          // ---- Anzeige: Singles & Kombis – Kategorien-Union aufbauen ----

          // Singles (Basis) nach Kategorie – nur wenn für Zielgruppe vorhanden
          final Map<String, List<Offer>> singlesByCategory = {};
          for (final s in singlesBaseFinal) {
            final hasZg =
                (s.priceFor(_zielgruppe) != null) || (s.durationFor(_zielgruppe) != null);
            if (!hasZg) continue;
            singlesByCategory.putIfAbsent(s.kategorie, () => []).add(s);
          }

          // Kombi-Angebote nach Kategorie – **unabhängig** davon, ob Singles existieren
          final Map<String, List<Offer>> combosByCategory = {};
          for (final b in bundles) {
            final hasZg =
                (b.priceFor(_zielgruppe) != null) || (b.durationFor(_zielgruppe) != null);
            if (!hasZg) continue;
            combosByCategory.putIfAbsent(b.kategorie, () => []).add(b);
          }

          // Kategorien = Union
          final kategorien = <String>{
            ...singlesByCategory.keys,
            ...combosByCategory.keys,
          }.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          final sections = <SectionData>[];
          for (final kat in kategorien) {
            final items = [...(singlesByCategory[kat] ?? const <Offer>[])]
              ..sort(
                    (a, b) => a.titleDisplay.toLowerCase().compareTo(b.titleDisplay.toLowerCase()),
              );

            final children = <Widget>[];

            // ---------- Singles rendern ----------
            for (final offer in items) {
              final partDisplay = offer.leistungen.first; // z. B. "Schneiden"
              final partLc = offer.leistungenLc.first;
              final uiTitle = offer.titleDisplay; // "Haare – Schneiden"
              final preis = offer.priceFor(_zielgruppe);
              final dauer = offer.durationFor(_zielgruppe);

              if (preis == null && dauer == null) continue;

              final key = _keyFor(
                zielgruppe: _zielgruppe,
                category: kat,
                partLc: partLc,
              );

              final variantKey = '$kat|$partLc';
              final hasVariants = (variantsAvailable[variantKey]?.isNotEmpty ?? false);

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
                        // Titel + (optional) Variante + Preis/Dauer
                        Expanded(
                          child: ValueListenableBuilder<Map<String, _CartItem>>(
                            valueListenable: _selectedVN,
                            builder: (_, map, __) {
                              final selKey = _keyFor(
                                zielgruppe: _zielgruppe,
                                category: kat,
                                partLc: partLc,
                              );
                              final selectedItem = map[selKey];

                              // dynamische Werte: wenn Variante gewählt, nimm deren Preis/Dauer
                              final effectivePrice = selectedItem?.preis ?? preis;
                              final effectiveDuration = selectedItem?.dauer ?? dauer;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Titel
                                  Text(
                                    uiTitle,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),

                                  // Gewählte Variante als Chip (nur anzeigen, wenn vorhanden)
                                  if ((selectedItem?.varianteLabel?.trim().isNotEmpty ?? false)) ...[
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () {
                                        // Sheet mit vorselektierter Variante öffnen
                                        final variantsForPart = <Offer>[];
                                        final labels = variantsAvailable[variantKey] ?? {};
                                        for (final label in labels) {
                                          final o = singleVariantIndex[
                                          '$kat|$partLc|${label.toLowerCase()}'];
                                          if (o != null) variantsForPart.add(o);
                                        }
                                        _openVariantSheet(
                                          base: offer,
                                          category: kat,
                                          variantOffersForPart: variantsForPart,
                                          preselectVarLc:
                                          selectedItem!.varianteLabel!.toLowerCase(),
                                        );
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: kBrandOrange, width: 1.5),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          selectedItem!.varianteLabel!,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: kBrandOrange,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 6),

                                  // Preis & Dauer – dynamisch nach Auswahl
                                  Text(
                                    '${_preisText(effectivePrice)}${_dauerText(effectiveDuration)}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        // Trailing-Icon reaktiv
                        ValueListenableBuilder<Map<String, _CartItem>>(
                          valueListenable: _selectedVN,
                          builder: (_, map, __) {
                            final selected = map.containsKey(key);

                            return IconButton(
                              tooltip: selected
                                  ? 'Entfernen'
                                  : (hasVariants ? 'Variante wählen' : 'Hinzufügen'),
                              onPressed: () {
                                if (hasVariants) {
                                  if (selected) {
                                    // Wenn bereits ausgewählt -> abwählen
                                    final newMap =
                                    Map<String, _CartItem>.from(_selectedVN.value);
                                    newMap.remove(key);
                                    _selectedVN.value = newMap;
                                  } else {
                                    // Noch nicht ausgewählt -> Varianten-Sheet öffnen
                                    final variantsForPart = <Offer>[];
                                    final labels = variantsAvailable[variantKey] ?? {};
                                    for (final label in labels) {
                                      final o = singleVariantIndex[
                                      '$kat|$partLc|${label.toLowerCase()}'];
                                      if (o != null) variantsForPart.add(o);
                                    }
                                    _openVariantSheet(
                                      base: offer,
                                      category: kat,
                                      variantOffersForPart: variantsForPart,
                                    );
                                  }
                                } else {
                                  // Keine Varianten: normal toggeln
                                  _toggleSelection(
                                    key,
                                    _CartItem(
                                      kategorie: kat,
                                      leistung: partDisplay,
                                      preis: preis,
                                      dauer: dauer,
                                      zielgruppe: _zielgruppe,
                                    ),
                                  );
                                }
                              },
                              icon: Icon(
                                  selected ? Icons.check_circle : Icons.add_circle_outline),
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

            // ---------- Kombi-Angebote rendern (immer, auch ohne Singles) ----------
            final combosForCat = [...(combosByCategory[kat] ?? const <Offer>[])]
              ..sort((a, b) =>
                  a.titleDisplay.toLowerCase().compareTo(b.titleDisplay.toLowerCase()));

            if (combosForCat.isNotEmpty) {
              children.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Kombi-Angebote',
                    style: TextStyle(
                      color: Colors.black.withAlpha(140),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );

              for (final combo in combosForCat) {
                final preis = combo.priceFor(_zielgruppe);
                final dauer = combo.durationFor(_zielgruppe);
                final subtitle = '${_preisText(preis)}${_dauerText(dauer)}';
                final displayName = combo.titleDisplay;

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
                                  displayName,
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
                          ValueListenableBuilder<Map<String, _CartItem>>(
                            valueListenable: _selectedVN,
                            builder: (_, map, __) {
                              final zg = _zielgruppe;
                              final allSelected = combo.leistungenLc.every(
                                    (lc) => map.containsKey(
                                  _keyFor(zielgruppe: zg, category: kat, partLc: lc),
                                ),
                              );
                              return IconButton(
                                tooltip: 'Kombi auswählen',
                                onPressed: () {
                                  _toggleCombo(
                                    category: kat,
                                    partsOriginal: combo.leistungen,
                                    partsLc: combo.leistungenLc,
                                    singlesByKey: singleBaseIndex,
                                  );
                                },
                                icon: Icon(allSelected
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline),
                                color: allSelected ? Colors.blueAccent : null,
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

          // ---- Total mit Zielgruppen-Bezug je Item berechnen ----
          double computeTotal(Map<String, _CartItem> map) {
            if (map.isEmpty) return 0.0;

            // Nach (Kategorie, Zielgruppe) gruppieren
            final byGroup = <String, List<_CartItem>>{};
            map.forEach((_, item) {
              final gKey = '${item.kategorie}|${item.zielgruppe}';
              byGroup.putIfAbsent(gKey, () => []).add(item);
            });

            double total = 0.0;

            byGroup.forEach((groupKey, groupItems) {
              final split = groupKey.split('|');
              final cat = split[0];
              final zg = split.length > 1 ? split[1] : 'Damen';

              // normalisierte Teile dieser Gruppe (Reihenfolge = groupItems)
              final partsLc = groupItems.map((e) => e.leistung.toLowerCase()).toList();

              // Greedy: größte Bundles zuerst
              final catBundles = bundles.where((b) => b.kategorie == cat).toList()
                ..sort((a, b) => b.leistungenLc.length.compareTo(a.leistungenLc.length));

              final used = List<bool>.filled(partsLc.length, false);

              // Versuche Bundles zu „legen“
              for (final b in catBundles) {
                final needed = b.leistungenLc;
                final idxs = <int>[];

                for (final n in needed) {
                  int found = -1;
                  for (int i = 0; i < partsLc.length; i++) {
                    if (!used[i] && partsLc[i] == n) {
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
                  final bundlePrice = b.priceFor(zg);
                  if (bundlePrice != null) {
                    for (final i in idxs) used[i] = true;
                    total += bundlePrice;
                  }
                }
              }

              // Restliche Singles: **IMMER** Preis aus gewähltem Item,
              // erst wenn null, fallback auf Basis-Single-Index.
              for (int i = 0; i < partsLc.length; i++) {
                if (!used[i]) {
                  final lc = partsLc[i];
                  final item = groupItems[i];
                  double? p = item.preis;
                  p ??= singleBaseIndex['$cat|$lc']?.priceFor(zg);
                  if (p != null) total += p;
                }
              }
            });

            return total;
          }

          // Inhalt + fixierte Bottom-Bar
          return Stack(
            children: [
              const LinkedChipsWithSections(sections: []),

              LinkedChipsWithSections(
                sections: sections,
                initialIndex: initialIndex,
                extraBottom: kBottomBarHeight + 12,
              ),

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

/// ---------------------------------------------------------------
/// Bottom-Bar (Warenkorb / CTA)
/// ---------------------------------------------------------------
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(46),
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
            const Expanded(
              child: Center(
                child: Text(
                  'Zur Buchung',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
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
