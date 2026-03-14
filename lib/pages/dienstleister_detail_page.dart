// dienstleister_detail_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/cupertino.dart';

import 'dart:ui' show FontFeature;

/// ---- Brand / Farben ----
const Color kBrandOrange = Color(0xFFFF7A00); // Buttonfarbe
const double kBottomBarHeight = 76.0;

/// ---- Layout-Konstanten ----
const double kDurColWidth = 72.0; // Mitte (Badge)
const double kRightColWidth = 144.0; // Rechts (Preis + Icon)

/// ---------------------------------------------------------------
/// Angebot-Modell
/// ---------------------------------------------------------------
class Offer {
  final String id;
  final String kategorie;
  final List<String> leistungen; // sortiert, Original-Schreibweise
  final List<String> leistungenLc; // sortiert, lowercased (für Vergleiche)
  final bool isBundle;
  final String? comboKey;
  final Map<String, dynamic> zielgruppen;

  /// Nur noch diese Spalte für Varianten verwenden (hier "Methoden").
  /// Für eine konkrete Methode enthält das Offer genau 1 Element.
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

    // Varianten (Methoden)
    List<String> vars = [];
    if (d['varianten'] is List) {
      vars = List<String>.from(d['varianten'])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (d['variantenProLeistung'] is Map) {
      final m = Map<String, dynamic>.from(d['variantenProLeistung']);
      vars = m.values.map((v) => v.toString().trim()).where((s) => s.isNotEmpty).toList();
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
  final String title; // z. B. "Haare"
  final List<Widget> children; // Angebots-Widgets unter dem Balken
  SectionData(this.title, this.children);
}

/// ---------------------------------------------------------------
/// Interner Warenkorb-Eintrag
/// ---------------------------------------------------------------
class _CartItem {
  final String kategorie;
  final String leistung;
  final double? preis; // Basis-/Variantenpreis des Items
  final int? dauer;
  final String zielgruppe;
  final String? varianteLabel; // z. B. "Neuschnitt • kurz"
  final int selectedAt;

  // fixierter grüner Preis zur Anzeige (klebt nach Auswahl)
  final double? lockedDisplayPrice;

  const _CartItem({
    required this.kategorie,
    required this.leistung,
    required this.preis,
    required this.dauer,
    required this.zielgruppe,
    this.varianteLabel,
    required this.selectedAt,
    this.lockedDisplayPrice,
  });
}

class _ComboSelection {
  final Offer bundle;
  final String zielgruppe;
  final int selectedAt;
  final double? preis;
  final int? dauer;
  final String? varianteLabel;

  const _ComboSelection({
    required this.bundle,
    required this.zielgruppe,
    required this.selectedAt,
    this.preis,
    this.dauer,
    this.varianteLabel,
  });
}


// Singlepreis eines Parts bestimmen (Variantenpreis > Basis > 0)
double _singlePriceOfPart({
  required String category,
  required String zielgruppe,
  required String partLc,
  required Map<String, _CartItem> selectionMap,
  required Map<String, Offer> singleBaseIndex,
}) {
  // bereits gewähltes Item?
  final it = selectionMap.values.firstWhere(
        (e) =>
    e.kategorie == category &&
        e.leistung.toLowerCase() == partLc &&
        e.zielgruppe == zielgruppe,
    orElse: () => const _CartItem(
      kategorie: '',
      leistung: '',
      preis: null,
      dauer: null,
      zielgruppe: '',
      selectedAt: 0,
    ),
  );
  if (it.kategorie.isNotEmpty && it.preis != null) return it.preis!;

  final p = singleBaseIndex['$category|$partLc']?.priceFor(zielgruppe);
  return p ?? 0.0;
}

// Restbetrag (locked price) für neues Item, wenn dadurch Bundle greift
double? _lockedPriceForNewSelection({
  required String category,
  required String zielgruppe,
  required String newPartLc,
  required Map<String, _CartItem> selectionMap,
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
  required double? newPartSinglePrice,
}) {
  if (newPartSinglePrice == null) return null;

  double? bestRemainder;

  for (final b in bundles) {
    if (b.kategorie != category) continue;
    if (!b.leistungenLc.contains(newPartLc)) continue;

    final others = b.leistungenLc.where((lc) => lc != newPartLc).toList();
    final allOthersSelected = others.every((lc) => selectionMap.values.any((it) =>
    it.kategorie == category &&
        it.zielgruppe == zielgruppe &&
        it.leistung.toLowerCase() == lc));
    if (!allOthersSelected) continue;

    final bundlePrice = b.priceFor(zielgruppe);
    if (bundlePrice == null) continue;

    double singlesSum = 0.0;
    for (final lc in b.leistungenLc) {
      if (lc == newPartLc) {
        singlesSum += newPartSinglePrice;
      } else {
        singlesSum += _singlePriceOfPart(
          category: category,
          zielgruppe: zielgruppe,
          partLc: lc,
          selectionMap: selectionMap,
          singleBaseIndex: singleBaseIndex,
        );
      }
    }
    if (bundlePrice >= singlesSum) continue;

    double othersContribution = 0.0;
    for (final lc in others) {
      final sel = selectionMap.values.firstWhere(
            (it) =>
        it.kategorie == category &&
            it.zielgruppe == zielgruppe &&
            it.leistung.toLowerCase() == lc,
        orElse: () => const _CartItem(
          kategorie: '',
          leistung: '',
          preis: null,
          dauer: null,
          zielgruppe: '',
          selectedAt: 0,
        ),
      );
      if (sel.kategorie.isNotEmpty && sel.lockedDisplayPrice != null) {
        othersContribution += sel.lockedDisplayPrice!;
      } else {
        othersContribution += _singlePriceOfPart(
          category: category,
          zielgruppe: zielgruppe,
          partLc: lc,
          selectionMap: selectionMap,
          singleBaseIndex: singleBaseIndex,
        );
      }
    }

    final remainder = (bundlePrice - othersContribution).clamp(0.0, double.infinity);
    if (bestRemainder == null || remainder < bestRemainder!) {
      bestRemainder = remainder;
    }
  }

  if (bestRemainder != null && bestRemainder! < newPartSinglePrice) {
    return bestRemainder;
  }
  return null;
}

// Vorschau-Preis, wenn dieses letzte Teil ein Bundle vervollständigt
double? _previewForLastMissingPart({
  required String category,
  required String zielgruppe,
  required String partLc,
  required Set<String> selectedPartsLc,
  required Map<String, _CartItem> selectionMap,
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
}) {
  double? best;

  for (final b in bundles) {
    if (b.kategorie != category) continue;
    if (!b.leistungenLc.contains(partLc)) continue;

    final others = b.leistungenLc.where((lc) => lc != partLc).toList();
    if (!others.every(selectedPartsLc.contains)) continue;

    final bundlePrice = b.priceFor(zielgruppe);
    if (bundlePrice == null) continue;

    double othersContribution = 0.0;
    for (final lc in others) {
      final sel = selectionMap.values.firstWhere(
            (it) =>
        it.kategorie == category &&
            it.zielgruppe == zielgruppe &&
            it.leistung.toLowerCase() == lc,
        orElse: () => const _CartItem(
          kategorie: '',
          leistung: '',
          preis: null,
          dauer: null,
          zielgruppe: '',
          selectedAt: 0,
        ),
      );
      if (sel.kategorie.isNotEmpty && sel.lockedDisplayPrice != null) {
        othersContribution += sel.lockedDisplayPrice!;
      } else {
        othersContribution += _singlePriceOfPart(
          category: category,
          zielgruppe: zielgruppe,
          partLc: lc,
          selectionMap: selectionMap,
          singleBaseIndex: singleBaseIndex,
        );
      }
    }

    final remainder = (bundlePrice - othersContribution).clamp(0.0, double.infinity);
    final singleOfThis = singleBaseIndex['$category|$partLc']?.priceFor(zielgruppe) ?? 0.0;
    if (remainder < singleOfThis) {
      if (best == null || remainder < best!) best = remainder;
    }
  }

  return best;
}

double? _previewForComboGroup({
  required Offer combo,
  required String category,
  required String zielgruppe,
  required Set<String> requiredBasePartsLc,
  required Set<String> selectedPartsLc,
  required Map<String, _CartItem> selectionMap,
  required Map<String, Offer> singleBaseIndex,
  double? bundlePriceOverride,
}) {
  if (!requiredBasePartsLc.every(selectedPartsLc.contains)) return null;

  final bundlePrice = bundlePriceOverride ?? combo.priceFor(zielgruppe);
  if (bundlePrice == null) return null;

  double baseContribution = 0.0;
  for (final baseLc in requiredBasePartsLc) {
    final sel = selectionMap.values.firstWhere(
          (it) =>
      it.kategorie == category &&
          it.zielgruppe == zielgruppe &&
          it.leistung.toLowerCase() == baseLc,
      orElse: () => const _CartItem(
        kategorie: '',
        leistung: '',
        preis: null,
        dauer: null,
        zielgruppe: '',
        selectedAt: 0,
      ),
    );
    if (sel.kategorie.isNotEmpty && sel.lockedDisplayPrice != null) {
      baseContribution += sel.lockedDisplayPrice!;
    } else {
      baseContribution += _singlePriceOfPart(
        category: category,
        zielgruppe: zielgruppe,
        partLc: baseLc,
        selectionMap: selectionMap,
        singleBaseIndex: singleBaseIndex,
      );
    }
  }

  return (bundlePrice - baseContribution).clamp(0.0, double.infinity);
}

/// ---------------------------------------------------------------
/// Methode-Option fürs BottomSheet
/// ---------------------------------------------------------------
class _VariantOption {
  final String label; // z. B. "Seiten auf Null"
  final String lc;
  final Offer offer; // konkretes Offer (Basis oder Methode)

  const _VariantOption({
    required this.label,
    required this.lc,
    required this.offer,
  });
}

/// Eine auswählbare Kombinations-Zeile im BottomSheet.
class _ComboRow {
  final Offer bundle; // das Bundle-Offer (für ab-Preis/Dauer)
  final List<String> extrasDisplay; // zusätzliche Teile (Anzeige)
  final List<String> extrasLc; // zusätzliche Teile (lowercased)

  const _ComboRow({
    required this.bundle,
    required this.extrasDisplay,
    required this.extrasLc,
  });
}

class _ComboGroupRow {
  final Offer bundle;
  final List<String> missingDisplay;
  final List<String> missingLc;
  final Set<String> requiredBaseLc;

  const _ComboGroupRow({
    required this.bundle,
    required this.missingDisplay,
    required this.missingLc,
    required this.requiredBaseLc,
  });
}

class _ComboOfferGroup {
  final String title;
  final String groupKey;
  final List<Offer> offers;

  const _ComboOfferGroup({
    required this.title,
    required this.groupKey,
    required this.offers,
  });
}

class _ComboMethodOption {
  final String label;
  final Offer offer;

  const _ComboMethodOption({
    required this.label,
    required this.offer,
  });
}

// Key-Helfer: unterscheidet Zielgruppe!
String _keyFor({
  required String zielgruppe,
  required String category,
  required String partLc,
}) =>
    '${zielgruppe.toLowerCase()}|${category.toLowerCase()}|$partLc';

String _comboSelectionKey({
  required String zielgruppe,
  required Offer combo,
}) {
  return '${zielgruppe.toLowerCase()}|${combo.kategorie.toLowerCase()}|${combo.id.toLowerCase()}';
}

String _comboGroupKey(Offer combo) {
  final key = combo.comboKey ?? combo.leistungenLc.join('|');
  return key.toLowerCase();
}

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
                  selectedColor: Colors.black,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.black,
                  ),
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: sel ? Colors.black : Colors.black54,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double stickyHeaderHeight = 44;

              return Stack(
                children: [
                  ScrollablePositionedList.builder(
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
                  if (widget.sections.isNotEmpty)
                    ValueListenableBuilder<Iterable<ItemPosition>>(
                      valueListenable: itemPositionsListener.itemPositions,
                      builder: (_, positions, __) {
                        ItemPosition? currentPosition;
                        for (final p in positions) {
                          if (p.index == activeChip) {
                            currentPosition = p;
                            break;
                          }
                        }
                        final showSticky =
                            currentPosition != null && currentPosition.itemLeadingEdge < 0;

                        final nextIndex = activeChip + 1;
                        ItemPosition? nextPosition;
                        if (nextIndex < widget.sections.length) {
                          for (final p in positions) {
                            if (p.index == nextIndex) {
                              nextPosition = p;
                              break;
                            }
                          }
                        }

                        double translateY = 0;
                        if (nextPosition != null) {
                          final nextTopPx =
                              nextPosition.itemLeadingEdge * constraints.maxHeight;
                          if (nextTopPx < stickyHeaderHeight) {
                            translateY = nextTopPx - stickyHeaderHeight;
                          }
                        }

                        if (!showSticky) {
                          return const SizedBox.shrink();
                        }

                        return IgnorePointer(
                          child: Transform.translate(
                            offset: Offset(0, translateY),
                            child: Container(
                              height: stickyHeaderHeight,
                              width: double.infinity,
                              color: Colors.black,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                widget.sections[activeChip].title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
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
          margin: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.black,
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

  final ValueNotifier<Map<String, _ComboSelection>> _selectedCombosVN =
  ValueNotifier<Map<String, _ComboSelection>>({});

  /// Auswahlreihenfolge hochzählen
  int _selectionTicker = 0;

  /// Expand-State für Leistungen mit Varianten
  final ValueNotifier<Set<String>> _expandedVariantGroupsVN =
      ValueNotifier<Set<String>>(<String>{});

  /// Abhängigkeiten für Kombi-Einzelteile (cat|partLc -> required parts)
  Map<String, List<Set<String>>> _comboDependencies = {};

  @override
  void dispose() {
    _selectedVN.dispose();
    _selectedCombosVN.dispose();
    _expandedVariantGroupsVN.dispose();
    super.dispose();
  }

  Map<String, Widget> _zielgruppenSegments() {
    TextStyle label(String value) => TextStyle(
      fontWeight: FontWeight.w600,
      color: _zielgruppe == value ? Colors.white : Colors.black,
    );

    Widget segment(String value) {
      final isActive = _zielgruppe == value;
      return Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive ? activeColorFor(value) : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(value, style: label(value)),
      );
    }

    return {
      'Damen': segment('Damen'),
      'Herren': segment('Herren'),
      'Kinder': segment('Kinder'),
    };
  }

  Color activeColorFor(String value) {
    switch (value) {
      case 'Damen':
        return Colors.pink;
      case 'Herren':
        return Colors.blue;
      case 'Kinder':
        return Colors.green;
      default:
        return Colors.black;
    }
  }

  // ===== Helpers für Haarlängen-Optionen =====================================

  /// prüft, ob für ein Offer in der ZG ein Varianten-Map existiert
  bool _hasSizeOptions(Offer o, String zg) {
    final v = o.zielgruppen[zg];
    if (v is Map) {
      final m = v['varianten'];
      return (m is Map) && m.isNotEmpty;
    }
    return false;
  }

  bool _hasZielgruppenData(Offer o, String zg) {
    return o.priceFor(zg) != null || o.durationFor(zg) != null || _hasSizeOptions(o, zg);
  }

  /// liefert Map<String, dynamic> der Varianten (kurz/mittel/lang -> {preis,dauer})
  Map<String, dynamic> _sizeMapForOffer(Offer o, String zg) {
    final v = o.zielgruppen[zg];
    if (v is Map && v['varianten'] is Map) {
      return Map<String, dynamic>.from(v['varianten'] as Map);
    }
    return const {};
  }

  /// sortiert Keys bevorzugt in Reihenfolge kurz, mittel, lang – sonst alphabetisch
  List<String> _sortedSizeKeys(Iterable<String> keys) {
    final order = const ['kurz', 'mittel', 'lang'];
    final lower = keys.map((e) => e.toString()).toList();
    lower.sort((a, b) {
      final ai = order.indexOf(a.toLowerCase());
      final bi = order.indexOf(b.toLowerCase());
      if (ai != -1 && bi != -1) return ai.compareTo(bi);
      if (ai != -1) return -1;
      if (bi != -1) return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return lower;
  }

  double? _sizePrice(Map<String, dynamic> sizeMap, String key) {
    final m = sizeMap[key];
    if (m is Map && m['preis'] != null) {
      final value = m['preis'];
      double? p;
      if (value is num) {
        p = value.toDouble();
      } else if (value is String) {
        final s = value.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
        p = s.isEmpty ? null : double.tryParse(s);
      }
      if (p == null) return null;
      return p > 0 ? p : null;
    }
    return null;
  }

  int? _sizeDuration(Map<String, dynamic> sizeMap, String key) {
    final m = sizeMap[key];
    if (m is Map && m['dauer'] != null) {
      final value = m['dauer'];
      int? d;
      if (value is int) {
        d = value;
      } else if (value is num) {
        d = value.toInt();
      } else if (value is String) {
        final s = value.replaceAll(RegExp(r'[^0-9\-]'), '');
        d = s.isEmpty ? null : int.tryParse(s);
      }
      if (d == null) return null;
      return d > 0 ? d : null;
    }
    return null;
  }

  double? _minSizePriceFor(Offer o, String zg) {
    final sizeMap = _sizeMapForOffer(o, zg);
    if (sizeMap.isEmpty) return null;
    double? minPrice;
    for (final key in sizeMap.keys) {
      final p = _sizePrice(sizeMap, key.toString());
      if (p == null) continue;
      minPrice = (minPrice == null || p < minPrice) ? p : minPrice;
    }
    return minPrice;
  }

  int? _minSizeDurationFor(Offer o, String zg) {
    final sizeMap = _sizeMapForOffer(o, zg);
    if (sizeMap.isEmpty) return null;
    int? minDuration;
    for (final key in sizeMap.keys) {
      final d = _sizeDuration(sizeMap, key.toString());
      if (d == null) continue;
      minDuration = (minDuration == null || d < minDuration) ? d : minDuration;
    }
    return minDuration;
  }

  List<String> _comboMethodLabels(Offer combo) {
    final labels = combo.varianten
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (labels.isNotEmpty) {
      return labels;
    }
    final match = RegExp(r'\(([^)]+)\)').firstMatch(combo.titleDisplay);
    final extracted = match?.group(1)?.trim();
    if (extracted != null && extracted.isNotEmpty) {
      return [extracted];
    }
    return const [];
  }

  String _comboMethodLabelSingle(Offer combo) {
    final labels = _comboMethodLabels(combo);
    if (labels.isNotEmpty) {
      return labels.first;
    }
    return 'Kombi-Angebot';
  }

  String? _comboMethodLabelForDisplay(Offer combo) {
    final labels = _comboMethodLabels(combo);
    if (labels.isEmpty) return null;
    return labels.join(' | ');
  }

  String? _comboVariantLabel({
    String? method,
    String? size,
  }) {
    if (method != null && size != null) return '$method • $size';
    if (method != null) return method;
    if (size != null) return size;
    return null;
  }

  double? _minSizePriceForVariants(List<Offer> offers, String zg) {
    double? minPrice;
    for (final offer in offers) {
      final p = _minSizePriceFor(offer, zg);
      if (p == null) continue;
      minPrice = (minPrice == null || p < minPrice) ? p : minPrice;
    }
    return minPrice;
  }

  int? _minSizeDurationForVariants(List<Offer> offers, String zg) {
    int? minDuration;
    for (final offer in offers) {
      final d = _minSizeDurationFor(offer, zg);
      if (d == null) continue;
      minDuration = (minDuration == null || d < minDuration) ? d : minDuration;
    }
    return minDuration;
  }

  double? _displayPriceFor(Offer o, String zg) {
    return o.priceFor(zg) ?? _minSizePriceFor(o, zg);
  }

  int? _displayDurationFor(Offer o, String zg) {
    return o.durationFor(zg) ?? _minSizeDurationFor(o, zg);
  }

  double? _minDisplayPriceForCombos(List<Offer> offers, String zg) {
    double? minPrice;
    for (final offer in offers) {
      final price = _displayPriceFor(offer, zg);
      if (price == null) continue;
      minPrice = (minPrice == null || price < minPrice) ? price : minPrice;
    }
    return minPrice;
  }

  int? _minDisplayDurationForCombos(List<Offer> offers, String zg) {
    int? minDuration;
    for (final offer in offers) {
      final duration = _displayDurationFor(offer, zg);
      if (duration == null) continue;
      minDuration = (minDuration == null || duration < minDuration) ? duration : minDuration;
    }
    return minDuration;
  }

  List<_ComboMethodOption> _comboMethodOptionsFor(List<Offer> offers) {
    final Map<String, Offer> byLabel = {};
    for (final combo in offers) {
      final label = _comboMethodLabelSingle(combo);
      final existing = byLabel[label];
      if (existing == null || _isBetterOfferForDisplay(combo, existing, _zielgruppe)) {
        byLabel[label] = combo;
      }
    }
    final labels = byLabel.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      for (final label in labels) _ComboMethodOption(label: label, offer: byLabel[label]!)
    ];
  }

  String? _selectedSizeKeyFromSelection({
    required Offer combo,
    required String category,
    required String zielgruppe,
    required Set<String> requiredBasePartsLc,
    required Map<String, _CartItem> selectionMap,
  }) {
    final sizeMap = _sizeMapForOffer(combo, zielgruppe);
    if (sizeMap.isEmpty) return null;

    final sizeKeys = _sortedSizeKeys(sizeMap.keys.map((e) => e.toString()));
    if (sizeKeys.isEmpty) return null;

    for (final key in sizeKeys) {
      final keyLc = key.toLowerCase();
      final match = selectionMap.values.firstWhere(
            (it) =>
        it.kategorie == category &&
            it.zielgruppe == zielgruppe &&
            requiredBasePartsLc.contains(it.leistung.toLowerCase()) &&
            (it.varianteLabel?.toLowerCase().contains(keyLc) ?? false),
        orElse: () => const _CartItem(
          kategorie: '',
          leistung: '',
          preis: null,
          dauer: null,
          zielgruppe: '',
          selectedAt: 0,
        ),
      );
      if (match.kategorie.isNotEmpty) {
        return key;
      }
    }
    return null;
  }

  double? _bundlePriceForCombo({
    required Offer combo,
    required String zielgruppe,
    String? sizeKey,
  }) {
    final sizeMap = _sizeMapForOffer(combo, zielgruppe);
    if (sizeKey != null && sizeMap.isNotEmpty) {
      final price = _sizePrice(sizeMap, sizeKey);
      if (price != null) return price;
    }
    return combo.priceFor(zielgruppe) ?? _minSizePriceFor(combo, zielgruppe);
  }

  int? _bundleDurationForCombo({
    required Offer combo,
    required String zielgruppe,
    String? sizeKey,
  }) {
    final sizeMap = _sizeMapForOffer(combo, zielgruppe);
    if (sizeKey != null && sizeMap.isNotEmpty) {
      final duration = _sizeDuration(sizeMap, sizeKey);
      if (duration != null) return duration;
    }
    return combo.durationFor(zielgruppe) ?? _minSizeDurationFor(combo, zielgruppe);
  }

  bool _isBetterOfferForDisplay(Offer candidate, Offer existing, String zg) {
    int score(Offer o) {
      int s = 0;
      if (o.priceFor(zg) != null) s += 4;
      if (o.durationFor(zg) != null) s += 2;
      if (_hasSizeOptions(o, zg)) s += 1;
      return s;
    }

    final candidateScore = score(candidate);
    final existingScore = score(existing);
    if (candidateScore != existingScore) {
      return candidateScore > existingScore;
    }

    final candidatePrice = _displayPriceFor(candidate, zg);
    final existingPrice = _displayPriceFor(existing, zg);
    if (candidatePrice != null && existingPrice != null && candidatePrice != existingPrice) {
      return candidatePrice < existingPrice;
    }

    final candidateDuration = _displayDurationFor(candidate, zg);
    final existingDuration = _displayDurationFor(existing, zg);
    if (candidateDuration != null &&
        existingDuration != null &&
        candidateDuration != existingDuration) {
      return candidateDuration < existingDuration;
    }

    return candidate.id.compareTo(existing.id) < 0;
  }
  // === Zielgruppen-Mix verhindern ============================================
  bool _hasItemsFromOtherZielgruppe(String zg) {
    final map = _selectedVN.value;
    if (map.isNotEmpty && map.values.any((it) => it.zielgruppe != zg)) {
      return true;
    }
    final combos = _selectedCombosVN.value;
    if (combos.isNotEmpty && combos.values.any((it) => it.zielgruppe != zg)) {
      return true;
    }
    return false;
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
    final combos = Map<String, _ComboSelection>.from(_selectedCombosVN.value);

    if (!map.containsKey(key)) {
      if (_hasItemsFromOtherZielgruppe(item.zielgruppe)) {
        final other = map.values.isNotEmpty
            ? map.values.first.zielgruppe
            : _selectedCombosVN.value.values.first.zielgruppe;
        _showWrongGroupSnack(other);
        return;
      }
      map[key] = item;
      combos.removeWhere(
            (_, combo) =>
        combo.zielgruppe == item.zielgruppe &&
            combo.bundle.kategorie == item.kategorie &&
            combo.bundle.leistungenLc.contains(item.leistung.toLowerCase()),
      );
    } else {
      map.remove(key);
      _removeDependentSelections(
        selectionMap: map,
        zielgruppe: item.zielgruppe,
        category: item.kategorie,
        removedPartLc: item.leistung.toLowerCase(),
      );
    }

    _selectedVN.value = map;
    _selectedCombosVN.value = combos;
  }

  void _toggleGroupSelection({
    required String category,
    required Offer combo,
    required List<String> partsDisplay,
    required List<String> partsLc,
    required Set<String> requiredBasePartsLc,
    required Map<String, Offer> singleBaseIndex,
  }) {
    final map = Map<String, _CartItem>.from(_selectedVN.value);
    final combos = Map<String, _ComboSelection>.from(_selectedCombosVN.value);
    final zg = _zielgruppe;

    if (_hasItemsFromOtherZielgruppe(zg)) {
      final other = map.values.isNotEmpty
          ? map.values.first.zielgruppe
          : _selectedCombosVN.value.values.first.zielgruppe;
      _showWrongGroupSnack(other);
      return;
    }

    final selectedAll = partsLc.every(
          (lc) => map.containsKey(_keyFor(zielgruppe: zg, category: category, partLc: lc)),
    );

    if (selectedAll) {
      for (final partLc in partsLc) {
        final key = _keyFor(zielgruppe: zg, category: category, partLc: partLc);
        map.remove(key);
        _removeDependentSelections(
          selectionMap: map,
          zielgruppe: zg,
          category: category,
          removedPartLc: partLc,
        );
      }
      _selectedVN.value = map;
      return;
    }

    final selectedPartsLc = map.values
        .where((it) => it.kategorie == category && it.zielgruppe == zg)
        .map((it) => it.leistung.toLowerCase())
        .toSet();

    final remainder = _previewForComboGroup(
      combo: combo,
      category: category,
      zielgruppe: zg,
      requiredBasePartsLc: requiredBasePartsLc,
      selectedPartsLc: selectedPartsLc,
      selectionMap: map,
      singleBaseIndex: singleBaseIndex,
      bundlePriceOverride: _bundlePriceForCombo(
        combo: combo,
        zielgruppe: zg,
        sizeKey: _selectedSizeKeyFromSelection(
          combo: combo,
          category: category,
          zielgruppe: zg,
          requiredBasePartsLc: requiredBasePartsLc,
          selectionMap: map,
        ),
      ),
    );
    if (remainder == null) return;

    final perPartPrice =
        (remainder ?? 0.0) / (partsLc.isEmpty ? 1 : partsLc.length);

    for (int i = 0; i < partsLc.length; i++) {
      final partLc = partsLc[i];
      final partDisplay = partsDisplay[i];
      final key = _keyFor(zielgruppe: zg, category: category, partLc: partLc);
      map[key] = _CartItem(
        kategorie: category,
        leistung: partDisplay,
        preis: perPartPrice,
        dauer: null,
        zielgruppe: zg,
        selectedAt: ++_selectionTicker,
        lockedDisplayPrice: perPartPrice,
      );
    }

    combos.removeWhere(
          (_, comboSel) =>
      comboSel.zielgruppe == zg &&
          comboSel.bundle.kategorie == category &&
          comboSel.bundle.leistungenLc.any(partsLc.contains),
    );

    _selectedVN.value = map;
    _selectedCombosVN.value = combos;
  }

  void _removeDependentSelections({
    required Map<String, _CartItem> selectionMap,
    required String zielgruppe,
    required String category,
    required String removedPartLc,
  }) {
    final pendingRemoved = <String>{removedPartLc};
    bool removedAny = true;

    while (removedAny) {
      removedAny = false;
      final selectedParts = selectionMap.values
          .where((it) => it.zielgruppe == zielgruppe && it.kategorie == category)
          .map((it) => it.leistung.toLowerCase())
          .toSet()
        ..removeAll(pendingRemoved);
      selectionMap.removeWhere((_, item) {
        if (item.zielgruppe != zielgruppe || item.kategorie != category) {
          return false;
        }
        final key = '${item.kategorie}|${item.leistung.toLowerCase()}';
        final reqSets = _comboDependencies[key];
        if (reqSets == null || reqSets.isEmpty) return false;
        final stillValid = reqSets.any((req) => req.every(selectedParts.contains));
        if (stillValid) return false;
        pendingRemoved.add(item.leistung.toLowerCase());
        removedAny = true;
        return true;
      });
    }
  }

  /// Combo-Helper: (de)selektiert alle Einzel-Leistungen der Kombi
  void _toggleCombo({
    required Offer combo,
  }) {
    final zg = _zielgruppe;

    if (_hasItemsFromOtherZielgruppe(zg)) {
      final other = _selectedVN.value.values.isNotEmpty
          ? _selectedVN.value.values.first.zielgruppe
          : _selectedCombosVN.value.values.first.zielgruppe;
      _showWrongGroupSnack(other);
      return;
    }

    final singles = Map<String, _CartItem>.from(_selectedVN.value);
    final combos = Map<String, _ComboSelection>.from(_selectedCombosVN.value);
    final comboKey = _comboSelectionKey(zielgruppe: zg, combo: combo);
    final groupKey = _comboGroupKey(combo);

    if (combos.containsKey(comboKey)) {
      combos.remove(comboKey);
    } else {
      combos.removeWhere(
            (_, comboSel) =>
        comboSel.zielgruppe == zg &&
            comboSel.bundle.kategorie == combo.kategorie &&
            _comboGroupKey(comboSel.bundle) == groupKey,
      );
      for (final partLc in combo.leistungenLc) {
        final key = _keyFor(zielgruppe: zg, category: combo.kategorie, partLc: partLc);
        singles.remove(key);
      }
      final comboPreis = combo.priceFor(zg);
      final comboDauer = combo.durationFor(zg);
      combos[comboKey] = _ComboSelection(
        bundle: combo,
        zielgruppe: zg,
        selectedAt: ++_selectionTicker,
        preis: comboPreis,
        dauer: comboDauer,
      );
    }

    _selectedVN.value = singles;
    _selectedCombosVN.value = combos;
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

  Future<void> _openBookingSummaryPanel({
    required Map<String, _CartItem> singles,
    required Map<String, _ComboSelection> combos,
    required double total,
    required double savings,
  }) async {
    List<_BookingSummaryEntry> entries = [
      ...singles.entries.map(
        (entry) => _BookingSummaryEntry(
          selectionKey: entry.key,
          isCombo: false,
          selectedAt: entry.value.selectedAt,
          title: entry.value.leistung,
          subtitle: [entry.value.kategorie, entry.value.varianteLabel]
              .where((e) => e != null && e.trim().isNotEmpty)
              .join(' • '),
          price: entry.value.preis,
          duration: entry.value.dauer,
        ),
      ),
      ...combos.entries.map(
        (entry) => _BookingSummaryEntry(
          selectionKey: entry.key,
          isCombo: true,
          selectedAt: entry.value.selectedAt,
          title: entry.value.bundle.leistungen.join(' + '),
          subtitle: [
            entry.value.bundle.kategorie,
            entry.value.varianteLabel ??
                _comboMethodLabelForDisplay(entry.value.bundle),
          ].where((e) => e != null && e.trim().isNotEmpty).join(' • '),
          price: entry.value.preis,
          duration: entry.value.dauer,
        ),
      ),
    ]..sort((a, b) => a.selectedAt.compareTo(b.selectedAt));

    double panelTotal = total;
    double panelSavings = savings;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Buchungsübersicht schließen',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, _, __) {
        final media = MediaQuery.of(ctx);
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.white,
            child: SafeArea(
              child: StatefulBuilder(
                builder: (ctx, setSheetState) {
                  return SizedBox(
                    width: media.size.width.clamp(320.0, 420.0),
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text(
                            'Deine Buchungsübersicht',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${entries.length} Leistungen ausgewählt',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) {
                              final entry = entries[i];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: const Color(0xFFF7F8FB),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (entry.subtitle.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                entry.subtitle,
                                                style: const TextStyle(
                                                  color: Colors.black54,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                            ),
                                          if (entry.duration != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                '${entry.duration} Min',
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      entry.price == null
                                          ? '–'
                                          : _formatEuro(entry.price!),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Leistung entfernen',
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        final singlesMap = Map<String, _CartItem>.from(
                                          _selectedVN.value,
                                        );
                                        final combosMap =
                                            Map<String, _ComboSelection>.from(
                                          _selectedCombosVN.value,
                                        );

                                        if (entry.isCombo) {
                                          combosMap.remove(entry.selectionKey);
                                        } else {
                                          final removedItem = singlesMap.remove(
                                            entry.selectionKey,
                                          );
                                          if (removedItem != null) {
                                            _removeDependentSelections(
                                              selectionMap: singlesMap,
                                              zielgruppe: removedItem.zielgruppe,
                                              category: removedItem.kategorie,
                                              removedPartLc:
                                                  removedItem.leistung.toLowerCase(),
                                            );
                                          }
                                        }

                                        _selectedVN.value = singlesMap;
                                        _selectedCombosVN.value = combosMap;

                                        entries = [
                                          ...singlesMap.entries.map(
                                            (e) => _BookingSummaryEntry(
                                              selectionKey: e.key,
                                              isCombo: false,
                                              selectedAt: e.value.selectedAt,
                                              title: e.value.leistung,
                                              subtitle: [
                                                e.value.kategorie,
                                                e.value.varianteLabel,
                                              ]
                                                  .where(
                                                    (x) =>
                                                        x != null &&
                                                        x.trim().isNotEmpty,
                                                  )
                                                  .join(' • '),
                                              price: e.value.preis,
                                              duration: e.value.dauer,
                                            ),
                                          ),
                                          ...combosMap.entries.map(
                                            (e) => _BookingSummaryEntry(
                                              selectionKey: e.key,
                                              isCombo: true,
                                              selectedAt: e.value.selectedAt,
                                              title: e.value.bundle.leistungen
                                                  .join(' + '),
                                              subtitle: [
                                                e.value.bundle.kategorie,
                                                e.value.varianteLabel ??
                                                    _comboMethodLabelForDisplay(
                                                      e.value.bundle,
                                                    ),
                                              ]
                                                  .where(
                                                    (x) =>
                                                        x != null &&
                                                        x.trim().isNotEmpty,
                                                  )
                                                  .join(' • '),
                                              price: e.value.preis,
                                              duration: e.value.dauer,
                                            ),
                                          ),
                                        ]
                                          ..sort(
                                            (a, b) => a.selectedAt.compareTo(
                                              b.selectedAt,
                                            ),
                                          );

                                        panelTotal = entries.fold<double>(
                                          0.0,
                                          (sum, e) => sum + (e.price ?? 0.0),
                                        );
                                        panelSavings = 0.0;

                                        if (entries.isEmpty) {
                                          Navigator.of(ctx).pop();
                                          return;
                                        }

                                        setSheetState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Gesamt',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    _formatEuro(panelTotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              if (panelSavings > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Dein Vorteil',
                                        style: TextStyle(color: Colors.black54),
                                      ),
                                      Text(
                                        '-${_formatEuro(panelSavings)}',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, _, child) {
        final offset = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic))
            .animate(animation);
        return SlideTransition(position: offset, child: child);
      },
    );
  }



  /// Öffnet das Sheet für Methode + Haarlänge + Kombinationen
  Future<void> _openVariantSheet({
    required Offer base,
    required String category,
    required List<Offer> variantOffersForPart,
    List<_ComboRow> combineRows = const <_ComboRow>[],
    String? preselectVarLc,
  }) async {
    final zg = _zielgruppe;
    final partDisplay = base.leistungen.first;
    final partLc = base.leistungenLc.first;

    final basePreis = base.priceFor(zg);
    final headerTitle = '$category – $partDisplay';

    // --- Methoden-Optionen vorbereiten ---
    final options = <_VariantOption>[];
    final byLabel = <String, Offer>{};
    for (final v in variantOffersForPart) {
      final hasZg = _hasZielgruppenData(v, zg);
      if (v.varianten.isEmpty) continue;
      final label = v.varianten.first.trim();
      if (label.isEmpty) continue;
      byLabel[label] = v;
    }
    final sortedLabels = byLabel.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final Map<String, Offer> variantsByLc = {
      for (final label in sortedLabels) label.toLowerCase(): byLabel[label]!,
    };
    final Map<String, String> labelsByLc = {
      for (final label in sortedLabels) label.toLowerCase(): label,
    };
    for (final label in sortedLabels) {
      options.add(_VariantOption(label: label, lc: label.toLowerCase(), offer: byLabel[label]!));
    }

    // NEU: Nur wenn es einen echten Basis-Offer gibt, "Standard" als Option zeigen
    final bool hasRealBase = !base.id.startsWith('synthetic:');
    final bool hasBaseValues = base.priceFor(zg) != null || base.durationFor(zg) != null;
    final bool showStandard = hasRealBase && hasBaseValues;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // Voreinstellung:
        // - mit echter Basis: Standard (null) vorselektiert
        // - sonst (nur Varianten): erste Methode
        String? selectedVarLc = preselectVarLc ??
            (showStandard ? null : (options.isNotEmpty ? options.first.lc : null));
        String? selectedSizeKey;
        final Set<int> selectedComboIdx = <int>{};

        final key = _keyFor(zielgruppe: zg, category: category, partLc: partLc);
        final alreadySelected = _selectedVN.value.containsKey(key);

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16, 12, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (ctx2, setSheetState) {
                final Offer chosenOffer =
                (selectedVarLc == null) ? base : (variantsByLc[selectedVarLc] ?? base);

                final sizeMap = _sizeMapForOffer(chosenOffer, zg);
                final sizeKeys = _sortedSizeKeys(sizeMap.keys.map((e) => e.toString()));
                selectedSizeKey ??= sizeKeys.isNotEmpty ? sizeKeys.first : null;

                double? priceForButton;
                int? durationForButton;
                if (selectedSizeKey != null && sizeMap.isNotEmpty) {
                  priceForButton = _sizePrice(sizeMap, selectedSizeKey!);
                  durationForButton = _sizeDuration(sizeMap, selectedSizeKey!);
                } else {
                  priceForButton = chosenOffer.priceFor(zg);
                  durationForButton = chosenOffer.durationFor(zg);
                }

                // Methodenliste (mit optionaler "Standard"-Zeile oben)
                final List<Widget> methodTiles = [];
                final String groupValue = selectedVarLc ?? 'STANDARD';

                if (showStandard) {
                  // Standard-Zeile (OBEN) – vorselektiert, wenn selectedVarLc == null
                  methodTiles.add(
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: groupValue == 'STANDARD'
                              ? Colors.blueAccent
                              : const Color(0xFFE5E5E5),
                          width: groupValue == 'STANDARD' ? 2 : 1,
                        ),
                      ),
                      child: RadioListTile<String>(
                        value: 'STANDARD',
                        groupValue: groupValue,
                        onChanged: (val) {
                          setSheetState(() {
                            selectedVarLc = null; // zurück auf Basis
                            final newSizeMap = _sizeMapForOffer(base, zg);
                            final keys = _sortedSizeKeys(newSizeMap.keys.map((e) => e.toString()));
                            selectedSizeKey = keys.isNotEmpty ? keys.first : null;
                          });
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        title: const Text('Standard',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: (basePreis != null || base.durationFor(zg) != null)
                            ? Text(
                          '${_preisText(basePreis)}${_dauerText(base.durationFor(zg))}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )
                            : null,
                      ),
                    ),
                  );
                  methodTiles.add(const SizedBox(height: 12));
                }

                for (int i = 0; i < options.length; i++) {
                  final opt = options[i];
                  final o = opt.offer;
                  final preis = o.priceFor(zg);
                  final dauer = o.durationFor(zg);

                  methodTiles.add(
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Radio<String>(
                        value: opt.lc,
                        groupValue: groupValue,
                        onChanged: (val) {
                          setSheetState(() {
                            selectedVarLc = val == 'STANDARD' ? null : val;
                            final newOffer = (selectedVarLc == null) ? base : (variantsByLc[selectedVarLc] ?? base);
                            final newSizeMap = _sizeMapForOffer(newOffer, zg);
                            final keys = _sortedSizeKeys(newSizeMap.keys.map((e) => e.toString()));
                            selectedSizeKey = keys.isNotEmpty ? keys.first : null;
                          });
                        },
                      ),
                      title: Text(opt.label, overflow: TextOverflow.ellipsis),
                      trailing: Text(
                        '${_preisText(preis)}${_dauerText(dauer)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () {
                        setSheetState(() {
                          selectedVarLc = opt.lc;
                          final newOffer = variantsByLc[selectedVarLc] ?? base;
                          final newSizeMap = _sizeMapForOffer(newOffer, zg);
                          final keys = _sortedSizeKeys(newSizeMap.keys.map((e) => e.toString()));
                          selectedSizeKey = keys.isNotEmpty ? keys.first : null;
                        });
                      },
                    ),
                  );
                  if (i != options.length - 1) {
                    methodTiles.add(const Divider(height: 1));
                  }
                }

                return Column(
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
                        priceForButton != null ? _formatEuro(priceForButton!) : '–',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (methodTiles.isNotEmpty) ...[
                      ...methodTiles,
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      const SizedBox(height: 8),
                    ],

                    // ---- Haarlängen / Optionen (kurz/mittel/lang) ----
                    if (sizeKeys.isNotEmpty) ...[
                      const Text(
                        'Haarlänge auswählen',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ...sizeKeys.map((k) {
                        final p = _sizePrice(sizeMap, k);
                        final d = _sizeDuration(sizeMap, k);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Radio<String>(
                            value: k,
                            groupValue: selectedSizeKey,
                            onChanged: (val) => setSheetState(() => selectedSizeKey = val),
                          ),
                          title: Text(k),
                          trailing: Text(
                            '${_preisText(p)}${_dauerText(d)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => setSheetState(() => selectedSizeKey = k),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],

                    // ---- Kombinieren mit (Bundles) ---- (unverändert)
                    if (combineRows.isNotEmpty) ...[
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Kombinieren mit',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (int i = 0; i < combineRows.length; i++) ...[
                        Builder(
                          builder: (_) {
                            final row = combineRows[i];
                            final bundlePrice = _bundlePriceForCombo(
                              combo: row.bundle,
                              zielgruppe: zg,
                              sizeKey: selectedSizeKey,
                            );
                            final bundleDur = _bundleDurationForCombo(
                              combo: row.bundle,
                              zielgruppe: zg,
                              sizeKey: selectedSizeKey,
                            );
                            final label = row.extrasDisplay.join('  &  ');
                            final checked = selectedComboIdx.contains(i);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6.0),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: checked,
                                    onChanged: (val) => setSheetState(() {
                                      if (val == true) {
                                        selectedComboIdx.add(i);
                                      } else {
                                        selectedComboIdx.remove(i);
                                      }
                                    }),
                                  ),
                                  Expanded(
                                    child: Text(
                                      label,
                                      overflow: TextOverflow.fade,
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${_preisText(bundlePrice)}${_dauerText(bundleDur)}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],

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
                            final Offer chosen =
                            selectedVarLc == null ? base : (variantsByLc[selectedVarLc] ?? base);

                            double? finalPrice = priceForButton;
                            int? finalDuration = durationForButton;

                            final map = Map<String, _CartItem>.from(_selectedVN.value);

                            if (_hasItemsFromOtherZielgruppe(zg)) {
                              final other = map.values.isNotEmpty
                                  ? map.values.first.zielgruppe
                                  : _selectedCombosVN.value.values.first.zielgruppe;
                              Navigator.pop(ctx);
                              _showWrongGroupSnack(other);
                              return;
                            }

                            final updatedCombos =
                            Map<String, _ComboSelection>.from(_selectedCombosVN.value)
                              ..removeWhere(
                                    (_, combo) =>
                                combo.zielgruppe == zg &&
                                    combo.bundle.kategorie == category &&
                                    combo.bundle.leistungenLc.contains(base.leistungenLc.first),
                              );

                            _selectedVN.value = {
                              ...map,
                              _keyFor(
                                zielgruppe: zg,
                                category: category,
                                partLc: base.leistungenLc.first,
                              ): _CartItem(
                                kategorie: category,
                                leistung: base.leistungen.first,
                                preis: finalPrice,
                                dauer: finalDuration,
                                zielgruppe: zg,
                                // Hinweis: KEIN "Standard"-Label mehr im Warenkorb
                                varianteLabel: () {
                                  final method =
                                  (selectedVarLc != null) ? labelsByLc[selectedVarLc] : null;
                                  final size = selectedSizeKey;
                                  if (method != null && size != null) return '$method • $size';
                                  if (method != null) return method;
                                  if (size != null) return size;
                                  return null;
                                }(),
                                selectedAt: ++_selectionTicker,
                                lockedDisplayPrice: null,
                              ),
                            };
                            _selectedCombosVN.value = updatedCombos;

                            // ggf. noch Kombi-Extras hinzufügen (unverändert)
                            Navigator.pop(ctx);
                          },
                          child: Row(
                            children: [
                              const Expanded(
                                child: Center(
                                  child: Text(
                                    'Hinzufügen',
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                priceForButton == null ? '' : _formatEuro(priceForButton!),
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
          ),
        );
      },
    );
  }

  Future<void> _openComboMethodSheet({
    required List<Offer> combos,
  }) async {
    if (combos.isEmpty) return;
    final zg = _zielgruppe;
    final category = combos.first.kategorie;
    final comboTitle = combos.first.leistungen.join(' + ');
    final methodOptions = _comboMethodOptionsFor(combos);
    if (methodOptions.isEmpty) return;

    _ComboSelection? selectedCombo;
    final groupKey = _comboGroupKey(combos.first);
    for (final comboSel in _selectedCombosVN.value.values) {
      if (comboSel.zielgruppe == zg &&
          comboSel.bundle.kategorie == category &&
          _comboGroupKey(comboSel.bundle) == groupKey) {
        selectedCombo = comboSel;
        break;
      }
    }

    String? selectedMethodLabel =
    selectedCombo != null ? _comboMethodLabelSingle(selectedCombo.bundle) : null;
    Offer selectedOffer = selectedCombo?.bundle ?? methodOptions.first.offer;
    String? selectedSizeKey;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (selectedMethodLabel == null) {
              selectedMethodLabel = methodOptions.first.label;
              selectedOffer = methodOptions.first.offer;
            }

            final sizeMap = _sizeMapForOffer(selectedOffer, zg);
            final sizeKeys = _sortedSizeKeys(sizeMap.keys.map((e) => e.toString()));
            if (sizeKeys.isEmpty) {
              selectedSizeKey = null;
            } else if (selectedSizeKey == null || !sizeKeys.contains(selectedSizeKey)) {
              selectedSizeKey = sizeKeys.first;
              if (selectedCombo?.bundle.id == selectedOffer.id &&
                  selectedCombo?.varianteLabel != null) {
                final currentLabel = selectedCombo!.varianteLabel!.toLowerCase();
                for (final key in sizeKeys) {
                  if (currentLabel.contains(key.toLowerCase())) {
                    selectedSizeKey = key;
                    break;
                  }
                }
              }
            }

            double? priceForButton;
            int? durationForButton;
            if (selectedSizeKey != null && sizeMap.isNotEmpty) {
              priceForButton = _sizePrice(sizeMap, selectedSizeKey!);
              durationForButton = _sizeDuration(sizeMap, selectedSizeKey!);
            } else {
              priceForButton = selectedOffer.priceFor(zg);
              durationForButton = selectedOffer.durationFor(zg);
            }

            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        comboTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        priceForButton != null ? _formatEuro(priceForButton!) : '–',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (methodOptions.length > 1) ...[
                      const Text(
                        'Methode auswählen',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ...methodOptions.map((option) {
                        final optionPrice = _displayPriceFor(option.offer, zg);
                        final optionDuration = _displayDurationFor(option.offer, zg);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Radio<String>(
                            value: option.label,
                            groupValue: selectedMethodLabel,
                            onChanged: (val) {
                              if (val == null) return;
                              setSheetState(() {
                                selectedMethodLabel = val;
                                selectedOffer = option.offer;
                              });
                            },
                          ),
                          title: Text(option.label),
                          trailing: Text(
                            '${_preisText(optionPrice)}${_dauerText(optionDuration)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () {
                            setSheetState(() {
                              selectedMethodLabel = option.label;
                              selectedOffer = option.offer;
                            });
                          },
                        );
                      }),
                      const SizedBox(height: 12),
                    ],

                    if (sizeKeys.isNotEmpty) ...[
                      const Text(
                        'Haarlänge auswählen',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ...sizeKeys.map((k) {
                        final p = _sizePrice(sizeMap, k);
                        final d = _sizeDuration(sizeMap, k);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Radio<String>(
                            value: k,
                            groupValue: selectedSizeKey,
                            onChanged: (val) => setSheetState(() => selectedSizeKey = val),
                          ),
                          title: Text(k),
                          trailing: Text(
                            '${_preisText(p)}${_dauerText(d)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => setSheetState(() => selectedSizeKey = k),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],

                    if (selectedCombo != null) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            final combosMap =
                            Map<String, _ComboSelection>.from(_selectedCombosVN.value);
                            final key = _comboSelectionKey(
                              zielgruppe: zg,
                              combo: selectedCombo!.bundle,
                            );
                            combosMap.remove(key);
                            _selectedCombosVN.value = combosMap;
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Auswahl entfernen'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

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
                            if (_hasItemsFromOtherZielgruppe(zg)) {
                              final other = _selectedVN.value.values.isNotEmpty
                                  ? _selectedVN.value.values.first.zielgruppe
                                  : _selectedCombosVN.value.values.first.zielgruppe;
                              Navigator.pop(ctx);
                              _showWrongGroupSnack(other);
                              return;
                            }

                            final singles =
                            Map<String, _CartItem>.from(_selectedVN.value);
                            final combosMap =
                            Map<String, _ComboSelection>.from(_selectedCombosVN.value);

                            for (final partLc in selectedOffer.leistungenLc) {
                              final key = _keyFor(
                                zielgruppe: zg,
                                category: selectedOffer.kategorie,
                                partLc: partLc,
                              );
                              singles.remove(key);
                            }

                            combosMap.removeWhere(
                                  (_, comboSel) =>
                              comboSel.zielgruppe == zg &&
                                  comboSel.bundle.kategorie == selectedOffer.kategorie &&
                                  _comboGroupKey(comboSel.bundle) == groupKey,
                            );

                            combosMap[_comboSelectionKey(
                              zielgruppe: zg,
                              combo: selectedOffer,
                            )] = _ComboSelection(
                              bundle: selectedOffer,
                              zielgruppe: zg,
                              selectedAt: ++_selectionTicker,
                              preis: priceForButton,
                              dauer: durationForButton,
                              varianteLabel: _comboVariantLabel(
                                method: selectedMethodLabel,
                                size: selectedSizeKey,
                              ),
                            );

                            _selectedVN.value = singles;
                            _selectedCombosVN.value = combosMap;
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
                              Text(
                                priceForButton == null ? '' : _formatEuro(priceForButton!),
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openComboSizeSheet({
    required Offer combo,
  }) async {
    final zg = _zielgruppe;
    final comboTitle = combo.leistungen.join(' + ');
    final sizeMap = _sizeMapForOffer(combo, zg);
    final sizeKeys = _sortedSizeKeys(sizeMap.keys.map((e) => e.toString()));
    final methodLabels = _comboMethodLabels(combo);
    String? selectedSizeKey = sizeKeys.isNotEmpty ? sizeKeys.first : null;
    String? selectedMethod = methodLabels.isNotEmpty ? methodLabels.first : null;

    final comboKey = _comboSelectionKey(zielgruppe: zg, combo: combo);
    final alreadySelected = _selectedCombosVN.value.containsKey(comboKey);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            double? priceForButton;
            int? durationForButton;
            if (selectedSizeKey != null && sizeMap.isNotEmpty) {
              priceForButton = _sizePrice(sizeMap, selectedSizeKey!);
              durationForButton = _sizeDuration(sizeMap, selectedSizeKey!);
            } else {
              priceForButton = combo.priceFor(zg);
              durationForButton = combo.durationFor(zg);
            }

            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        comboTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        priceForButton != null ? _formatEuro(priceForButton!) : '–',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (methodLabels.isNotEmpty) ...[
                      const Text(
                        'Methode auswählen',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ...methodLabels.map((label) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Radio<String>(
                            value: label,
                            groupValue: selectedMethod,
                            onChanged: (val) => setSheetState(() => selectedMethod = val),
                          ),
                          title: Text(label),
                          trailing: Text(
                            '${_preisText(priceForButton)}${_dauerText(durationForButton)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => setSheetState(() => selectedMethod = label),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],

                    if (sizeKeys.isNotEmpty) ...[
                      const Text(
                        'Haarlänge auswählen',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ...sizeKeys.map((k) {
                        final p = _sizePrice(sizeMap, k);
                        final d = _sizeDuration(sizeMap, k);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Radio<String>(
                            value: k,
                            groupValue: selectedSizeKey,
                            onChanged: (val) => setSheetState(() => selectedSizeKey = val),
                          ),
                          title: Text(k),
                          trailing: Text(
                            '${_preisText(p)}${_dauerText(d)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => setSheetState(() => selectedSizeKey = k),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],

                    if (alreadySelected) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            final combos =
                            Map<String, _ComboSelection>.from(_selectedCombosVN.value);
                            combos.remove(comboKey);
                            _selectedCombosVN.value = combos;
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Auswahl entfernen'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

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
                            if (_hasItemsFromOtherZielgruppe(zg)) {
                              final other = _selectedVN.value.values.isNotEmpty
                                  ? _selectedVN.value.values.first.zielgruppe
                                  : _selectedCombosVN.value.values.first.zielgruppe;
                              Navigator.pop(ctx);
                              _showWrongGroupSnack(other);
                              return;
                            }

                            final singles =
                            Map<String, _CartItem>.from(_selectedVN.value);
                            final combos =
                            Map<String, _ComboSelection>.from(_selectedCombosVN.value);
                            final groupKey = _comboGroupKey(combo);

                            for (final partLc in combo.leistungenLc) {
                              final key = _keyFor(
                                zielgruppe: zg,
                                category: combo.kategorie,
                                partLc: partLc,
                              );
                              singles.remove(key);
                            }

                            combos.removeWhere(
                                  (_, comboSel) =>
                              comboSel.zielgruppe == zg &&
                                  comboSel.bundle.kategorie == combo.kategorie &&
                                  _comboGroupKey(comboSel.bundle) == groupKey,
                            );

                            combos[comboKey] = _ComboSelection(
                              bundle: combo,
                              zielgruppe: zg,
                              selectedAt: ++_selectionTicker,
                              preis: priceForButton,
                              dauer: durationForButton,
                              varianteLabel: _comboVariantLabel(
                                method: selectedMethod,
                                size: selectedSizeKey,
                              ),
                            );

                            _selectedVN.value = singles;
                            _selectedCombosVN.value = combos;
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
                              Text(
                                priceForButton == null ? '' : _formatEuro(priceForButton!),
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
                ),
              ),
            );
          },
        );
      },
    );
  }


// ... (Rest der Datei unverändert)


  @override
  Widget build(BuildContext context) {
    final String dienstleisterId = widget.dienstleister['id'] as String;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: CupertinoSegmentedControl<String>(
          children: _zielgruppenSegments(),
          groupValue: _zielgruppe,
          onValueChanged: (v) => setState(() => _zielgruppe = v),
          borderColor: const Color(0xFF1A1A1A),
          selectedColor: activeColorFor(_zielgruppe),
          unselectedColor: Colors.white,
          pressedColor: const Color(0xFFECECEC),
          padding: EdgeInsets.zero,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8.0),
            alignment: Alignment.center,
            child: Text(
              (widget.dienstleister['name'] as String?) ?? 'Profil',
              style: const TextStyle(
                color: Colors.black,
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

          // Methoden-Offers = Singles mit genau 1 Methode
          final singleVariants = singles.where((o) => o.varianten.length == 1).toList();

          // Bundles
          final bundles = all.where((o) => o.isBundle && o.leistungen.length >= 2).toList();

          // ---------- SYNTHETISCHE BASIS-EINTRÄGE AUS METHODEN ----------
          final Map<String, List<Offer>> variantsByPart = {};
          for (final v in singleVariants) {
            final key = '${v.kategorie}|${v.leistungenLc.first}';
            variantsByPart.putIfAbsent(key, () => <Offer>[]).add(v);
          }

          final List<Offer> syntheticBases = [];
          final Set<String> existingBaseKeys = {
            for (final s in singlesBase) '${s.kategorie}|${s.leistungenLc.first}'
          };

          variantsByPart.forEach((key, list) {
            if (!existingBaseKeys.contains(key) && list.isNotEmpty) {
              final sample = list.first;
              final cat = sample.kategorie;
              final partDisplay = sample.leistungen.first;
              final partLc = sample.leistungenLc.first;

              final Map<String, dynamic> zgMap = {};
              final Set<String> allZgs = {};
              for (final o in list) {
                allZgs.addAll(o.zielgruppen.keys.map((e) => e.toString()));
              }
              for (final zg in allZgs) {
                double? minPrice;
                int? minDur;
                for (final o in list) {
                  final p = o.priceFor(zg) ?? _minSizePriceFor(o, zg);
                  final d = o.durationFor(zg) ?? _minSizeDurationFor(o, zg);
                  if (p != null) {
                    minPrice = (minPrice == null) ? p : (p < minPrice! ? p : minPrice);
                  }
                  if (d != null) {
                    minDur = (minDur == null) ? d : (d < minDur! ? d : minDur);
                  }
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
                  varianten: const [],
                  titleDisplay: '$cat – $partDisplay',
                ),
              );
            }
          });

          // Singles-Basis final (echte + synthetische)
          final singlesBaseFinal = [...singlesBase, ...syntheticBases];

          // Indizes
          final Map<String, Offer> singleBaseIndex = {
            for (final s in singlesBaseFinal) '${s.kategorie}|${s.leistungenLc.first}': s
          };
          final Map<String, Offer> singleVariantIndex = {
            for (final s in singleVariants)
              '${s.kategorie}|${s.leistungenLc.first}|${s.varianten.first.toLowerCase()}': s
          };
          final Map<String, Set<String>> variantsAvailable = {};
          for (final v in singleVariants) {
            final hasZg = _hasZielgruppenData(v, _zielgruppe);
            if (!hasZg) continue; // -> nur dann anzeigen
            final key = '${v.kategorie}|${v.leistungenLc.first}';
            variantsAvailable.putIfAbsent(key, () => <String>{});
            if (v.varianten.isNotEmpty) {
              variantsAvailable[key]!.add(v.varianten.first);
            }
          }

          // ---- Anzeige: Singles & Kombis – Kategorien-Union aufbauen ----
          final Map<String, List<Offer>> singlesByCategory = {};
          for (final s in singlesBaseFinal) {
            final hasZg = _hasZielgruppenData(s, _zielgruppe);
            if (!hasZg) continue;
            singlesByCategory.putIfAbsent(s.kategorie, () => []).add(s);
          }

          final Map<String, List<Offer>> combosByCategory = {};
          for (final b in bundles) {
            final hasZg = _hasZielgruppenData(b, _zielgruppe);
            if (!hasZg) continue;
            combosByCategory.putIfAbsent(b.kategorie, () => []).add(b);
          }

          final Map<String, Set<String>> singlePartsByCategory = {};
          singlesByCategory.forEach((cat, list) {
            singlePartsByCategory[cat] = list.map((o) => o.leistungenLc.first).toSet();
          });

          final Map<String, List<Offer>> derivedSinglesByCategory = {};
          final Map<String, List<Set<String>>> dependentRequirements = {};
          final Map<String, Offer> derivedSinglesIndex = {};
          final Map<String, List<_ComboGroupRow>> comboGroupRowsByCategory = {};

          combosByCategory.forEach((cat, list) {
            final baseParts = singlePartsByCategory[cat] ?? const <String>{};
            for (final combo in list) {
              final baseInCombo = combo.leistungenLc.where(baseParts.contains).toSet();
              if (baseInCombo.isEmpty) continue;

              final missingParts = <String>[];
              final missingDisplay = <String>[];
              for (int i = 0; i < combo.leistungenLc.length; i++) {
                final partLc = combo.leistungenLc[i];
                if (baseParts.contains(partLc)) continue;
                missingParts.add(partLc);
                missingDisplay.add(combo.leistungen[i]);
              }

              if (missingParts.length == 1) {
                final partLc = missingParts.first;
                final key = '$cat|$partLc';
                final requiredParts =
                combo.leistungenLc.where((lc) => lc != partLc).toSet();
                if (requiredParts.isEmpty) continue;

                final partDisplay = missingDisplay.first;
                final synthetic = Offer(
                  id: 'combo-extra:${combo.id}:$partLc',
                  kategorie: cat,
                  leistungen: [partDisplay],
                  leistungenLc: [partLc],
                  isBundle: false,
                  comboKey: combo.comboKey,
                  zielgruppen: combo.zielgruppen,
                  varianten: const [],
                  titleDisplay: '$cat – $partDisplay',
                );

                dependentRequirements.putIfAbsent(key, () => []).add(requiredParts);
                derivedSinglesIndex[key] = synthetic;
                derivedSinglesByCategory.putIfAbsent(cat, () => []).add(synthetic);
              }
            }
          });

          combosByCategory.forEach((cat, list) {
            final baseParts = singlePartsByCategory[cat] ?? const <String>{};
            for (final combo in list) {
              final baseInCombo = combo.leistungenLc.where(baseParts.contains).toSet();
              if (baseInCombo.isEmpty) continue;

              final missingParts = <String>[];
              final missingDisplay = <String>[];
              for (int i = 0; i < combo.leistungenLc.length; i++) {
                final partLc = combo.leistungenLc[i];
                if (baseParts.contains(partLc)) continue;
                missingParts.add(partLc);
                missingDisplay.add(combo.leistungen[i]);
              }

              if (missingParts.length <= 1) continue;

              final hasIndividual =
              missingParts.any((partLc) => derivedSinglesIndex.containsKey('$cat|$partLc'));
              if (hasIndividual) continue;

              for (final partLc in missingParts) {
                final key = '$cat|$partLc';
                dependentRequirements.putIfAbsent(key, () => []).add(baseInCombo);
              }

              comboGroupRowsByCategory.putIfAbsent(cat, () => []).add(
                _ComboGroupRow(
                  bundle: combo,
                  missingDisplay: missingDisplay,
                  missingLc: missingParts,
                  requiredBaseLc: baseInCombo,
                ),
              );
            }
          });

          final Map<String, List<Offer>> combosByCategoryDisplay = {};
          combosByCategory.forEach((cat, list) {
            final parts = singlePartsByCategory[cat] ?? const <String>{};
            for (final combo in list) {
              final hasBasePart = combo.leistungenLc.any(parts.contains);
              if (hasBasePart) continue;
              combosByCategoryDisplay.putIfAbsent(cat, () => []).add(combo);
            }
          });

          final Map<String, List<_ComboOfferGroup>> comboDisplayGroupsByCategory = {};
          combosByCategoryDisplay.forEach((cat, list) {
            final Map<String, List<Offer>> grouped = {};
            for (final combo in list) {
              final key = _comboGroupKey(combo);
              grouped.putIfAbsent(key, () => []).add(combo);
            }
            final groups = <_ComboOfferGroup>[];
            grouped.forEach((key, offers) {
              if (offers.isEmpty) return;
              final title = offers.first.leistungen.join(' + ');
              groups.add(_ComboOfferGroup(title: title, groupKey: key, offers: offers));
            });
            comboDisplayGroupsByCategory[cat] = groups;
          });

          final Map<String, List<Offer>> displaySinglesByCategory = {};
          singlesByCategory.forEach((cat, list) {
            displaySinglesByCategory[cat] = [...list];
          });
          derivedSinglesByCategory.forEach((cat, list) {
            displaySinglesByCategory.putIfAbsent(cat, () => []).addAll(list);
          });

          for (final entry in derivedSinglesIndex.entries) {
            singleBaseIndex.putIfAbsent(entry.key, () => entry.value);
          }

          _comboDependencies = dependentRequirements;
          final kategorien = <String>{
            ...displaySinglesByCategory.keys,
            ...combosByCategoryDisplay.keys,
          }.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          // === Gesamtpreis-Berechnung (naiv vs. optimiert) für die Bottom-Bar ===
          _CartTotals computeTotals(
              Map<String, _CartItem> map,
              Map<String, _ComboSelection> combos,
              ) {
            if (map.isEmpty && combos.isEmpty) {
              return const _CartTotals(naive: 0.0, optimized: 0.0);
            }

            final byGroup = <String, List<_CartItem>>{};
            map.forEach((_, item) {
              final gKey = '${item.kategorie}|${item.zielgruppe}';
              byGroup.putIfAbsent(gKey, () => []).add(item);
            });

            double naive = 0.0;
            double optimized = 0.0;

            byGroup.forEach((groupKey, groupItems) {
              final split = groupKey.split('|');
              final cat = split[0];
              final zg = split.length > 1 ? split[1] : 'Damen';

              final partsLc = groupItems.map((e) => e.leistung.toLowerCase()).toList();

              double _singlePriceAt(int idx) {
                final item = groupItems[idx];
                double? p = item.preis;
                p ??= singleBaseIndex['$cat|${partsLc[idx]}']?.priceFor(zg);
                return p ?? 0.0;
              }

              for (int i = 0; i < partsLc.length; i++) {
                naive += _singlePriceAt(i);
              }

              final catBundles = bundles.where((b) => b.kategorie == cat).toList()
                ..sort((a, b) => b.leistungenLc.length.compareTo(a.leistungenLc.length));

              final used = List<bool>.filled(partsLc.length, false);

              for (final b in catBundles) {
                final needed = b.leistungenLc;
                if (needed.isEmpty) continue;

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
                if (idxs.isEmpty || idxs.length != needed.length) continue;

                final bundlePrice = b.priceFor(zg);
                if (bundlePrice == null) continue;

                final singlesSum = idxs.fold<double>(0.0, (sum, i) => sum + _singlePriceAt(i));
                if (bundlePrice < singlesSum) {
                  for (final i in idxs) used[i] = true;
                  optimized += bundlePrice;
                }
              }

              for (int i = 0; i < partsLc.length; i++) {
                if (!used[i]) optimized += _singlePriceAt(i);
              }
            });

            double combosTotal = 0.0;
            for (final combo in combos.values) {
              combosTotal +=
                  combo.preis ?? combo.bundle.priceFor(combo.zielgruppe) ?? 0.0;
            }

            return _CartTotals(
              naive: naive + combosTotal,
              optimized: optimized + combosTotal,
            );
          }

          // ---------- Abschnitte bauen ----------
          final sections = <SectionData>[];
          for (final kat in kategorien) {
            final items = [...(displaySinglesByCategory[kat] ?? const <Offer>[])];
            final Map<String, Offer> uniqueItems = {};
            for (final offer in items) {
              final partLc = offer.leistungenLc.first;
              final existing = uniqueItems[partLc];
              if (existing == null || _isBetterOfferForDisplay(offer, existing, _zielgruppe)) {
                uniqueItems[partLc] = offer;
              }
            }

            final displayItems = uniqueItems.values.toList()
              ..sort((a, b) =>
                  a.leistungen.first.toLowerCase().compareTo(b.leistungen.first.toLowerCase()));

            final children = <Widget>[];

            for (final offer in displayItems) {
              final partDisplay = offer.leistungen.first;
              final partLc = offer.leistungenLc.first;

              final uiTitle = partDisplay;

              final preis = offer.priceFor(_zielgruppe);
              final dauer = offer.durationFor(_zielgruppe);
              final minPreis = _minSizePriceFor(offer, _zielgruppe);
              final minDauer = _minSizeDurationFor(offer, _zielgruppe);
              final displayPreis = preis ?? minPreis;
              final displayDauer = dauer ?? minDauer;

              final selKey = _keyFor(zielgruppe: _zielgruppe, category: kat, partLc: partLc);

              final dependencyKey = '$kat|$partLc';
              final requiredSets = _comboDependencies[dependencyKey] ?? const <Set<String>>[];
              final isDependent = requiredSets.isNotEmpty;
              final requiredParts = requiredSets.isEmpty
                  ? const <String>{}
                  : (requiredSets.toList()
                ..sort((a, b) => a.length.compareTo(b.length))).first;

              final variantKey = '$kat|$partLc';
              final labelsSet = variantsAvailable[variantKey] ?? {};
              final hasMethodVariants = labelsSet.isNotEmpty;
              final sortedLabels = labelsSet.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

              final variantOffersForPart = <Offer>[];
              for (final label in sortedLabels) {
                final o = singleVariantIndex['$kat|$partLc|${label.toLowerCase()}'];
                if (o != null && _hasZielgruppenData(o, _zielgruppe)) {
                  variantOffersForPart.add(o);
                }
              }
              final hasSizeOptionsFromVariants =
              variantOffersForPart.any((o) => _hasSizeOptions(o, _zielgruppe));
              final hasSizeOptionsBase = _hasSizeOptions(offer, _zielgruppe);
              final variantMinPreis = _minSizePriceForVariants(
                variantOffersForPart,
                _zielgruppe,
              );
              final variantMinDauer = _minSizeDurationForVariants(
                variantOffersForPart,
                _zielgruppe,
              );
              final bool isDerivedSingle = offer.id.startsWith('combo-extra:');

              final effectiveDisplayPreis = displayPreis ?? variantMinPreis;
              final effectiveDisplayDauer = displayDauer ?? variantMinDauer;
              final hasAnySizeOptions = hasSizeOptionsBase || hasSizeOptionsFromVariants;

              if (effectiveDisplayPreis == null &&
                  effectiveDisplayDauer == null &&
                  !hasAnySizeOptions &&
                  !hasMethodVariants) {
                continue;
              }

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
                    child: ValueListenableBuilder<Map<String, _CartItem>>(
                      valueListenable: _selectedVN,
                      builder: (_, map, __) {
                        List<_ComboRow> _buildCombineRowsFor(String category, String partLc) {
                          final combos = combosByCategoryDisplay[category] ?? const <Offer>[];
                          final rows = <_ComboRow>[];
                          for (final c in combos) {
                            if (c.leistungenLc.contains(partLc)) {
                              final extrasDisplay = <String>[];
                              final extrasLc = <String>[];
                              for (int i = 0; i < c.leistungen.length; i++) {
                                final lc2 = c.leistungenLc[i];
                                if (lc2 == partLc) continue;
                                extrasDisplay.add(c.leistungen[i]);
                                extrasLc.add(lc2);
                              }
                              if (extrasLc.isNotEmpty) {
                                rows.add(_ComboRow(
                                  bundle: c,
                                  extrasDisplay: extrasDisplay,
                                  extrasLc: extrasLc,
                                ));
                              }
                            }
                          }
                          return rows;
                        }

                        final selectedItem = map[selKey];
                        final selected = map.containsKey(selKey);

                        final selectedPartsLc = map.values
                            .where((it) => it.kategorie == kat && it.zielgruppe == _zielgruppe)
                            .map((it) => it.leistung.toLowerCase())
                            .toSet();

                        final canAdd = !isDependent ||
                            requiredSets.any((req) => req.every(selectedPartsLc.contains));
                        final canInteract = selected || canAdd;

                        final effectiveDuration =
                            selectedItem?.dauer ?? (canAdd ? effectiveDisplayDauer : null);
                        final effectivePrice = selectedItem?.preis ??
                            ((canAdd && !isDerivedSingle) ? effectiveDisplayPreis : null);

                        Widget buildDurationBadge() {
                          if (effectiveDuration == null) return const SizedBox.shrink();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F4F7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Color(0xFFE5E7EB)),
                            ),
                            child: Text(
                              '$effectiveDuration Min',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF374151),
                              ),
                            ),
                          );
                        }

                        Widget buildPriceText() {
                          double? newPrice;
                          double? preview;

                          if (selected) {
                            final locked = selectedItem?.lockedDisplayPrice;
                            if (locked != null && effectivePrice != null && locked < effectivePrice) {
                              newPrice = locked;
                            }
                          } else {
                            preview = _previewForLastMissingPart(
                              category: kat,
                              zielgruppe: _zielgruppe,
                              partLc: partLc,
                              selectedPartsLc: selectedPartsLc,
                              selectionMap: map,
                              singleBaseIndex: singleBaseIndex,
                              bundles: bundles,
                            );
                            if (preview != null && effectivePrice != null && preview < effectivePrice) {
                              newPrice = preview;
                            }
                          }

                          if (newPrice != null) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _preisText(effectivePrice),
                                  style: const TextStyle(
                                    color: Colors.black45,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.lineThrough,
                                    decorationThickness: 2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _preisText(newPrice),
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            );
                          }

                          if (preview != null && effectivePrice == null) {
                            return Text(
                              _preisText(preview),
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            );
                          }

                          return Text(
                            _preisText(effectivePrice),
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        }

                        String? currentMethodLabel() {
                          return selectedItem?.varianteLabel?.split(' • ').first;
                        }

                        Widget buildVariantRow({
                          required String label,
                          required Offer variantOffer,
                          required bool isLast,
                          bool isStandard = false,
                        }) {
                          final selectedLabel = currentMethodLabel();
                          final selectedThis = isStandard
                              ? (selected &&
                                  (selectedLabel == null ||
                                      selectedLabel.trim().isEmpty ||
                                      selectedLabel.toLowerCase() == 'standard'))
                              : (selected && selectedLabel == label);
                          final variantDuration =
                              selectedThis && selectedItem?.dauer != null
                                  ? selectedItem!.dauer
                                  : (variantOffer.durationFor(_zielgruppe) ??
                                      _minSizeDurationFor(variantOffer, _zielgruppe));
                          final isCompactVariantRow =
                              MediaQuery.of(context).size.width <= 380;

                          final variantBasePrice = variantOffer.priceFor(_zielgruppe) ??
                              _minSizePriceFor(variantOffer, _zielgruppe);
                          final variantEffectivePrice =
                              selectedThis && selectedItem?.preis != null
                                  ? selectedItem!.preis
                                  : variantBasePrice;

                          Widget buildVariantPriceText() {
                            double? newPrice;
                            double? preview;

                            if (selectedThis) {
                              final locked = selectedItem?.lockedDisplayPrice;
                              if (locked != null &&
                                  variantEffectivePrice != null &&
                                  locked < variantEffectivePrice) {
                                newPrice = locked;
                              }
                            } else {
                              preview = _previewForLastMissingPart(
                                category: kat,
                                zielgruppe: _zielgruppe,
                                partLc: partLc,
                                selectedPartsLc: selectedPartsLc,
                                selectionMap: map,
                                singleBaseIndex: singleBaseIndex,
                                bundles: bundles,
                              );
                              if (preview != null &&
                                  variantEffectivePrice != null &&
                                  preview < variantEffectivePrice) {
                                newPrice = preview;
                              }
                            }

                            if (newPrice != null) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _preisText(variantEffectivePrice),
                                    style: const TextStyle(
                                      color: Colors.black45,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      decoration: TextDecoration.lineThrough,
                                      decorationThickness: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _preisText(newPrice),
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              );
                            }

                            if (preview != null && variantEffectivePrice == null) {
                              return Text(
                                _preisText(preview),
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              );
                            }

                            return Text(
                              _preisText(variantEffectivePrice),
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              border: isLast
                                  ? null
                                  : const Border(
                                      bottom: BorderSide(color: Color(0xFFECECEC)),
                                    ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (variantDuration != null && !isCompactVariantRow) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF2F4F7),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                    ),
                                    child: Text(
                                      '$variantDuration Min',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF374151),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                buildVariantPriceText(),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: selectedThis
                                      ? 'Entfernen'
                                      : (!canAdd
                                          ? 'Nur mit vorheriger Auswahl'
                                          : 'Hinzufügen'),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                  onPressed: !canInteract
                                      ? null
                                      : () {
                                          if (selectedThis) {
                                            final existing = selectedItem;
                                            if (existing != null) {
                                              _toggleSelection(selKey, existing);
                                            }
                                            return;
                                          }

                                          final currentMap =
                                              Map<String, _CartItem>.from(
                                            _selectedVN.value,
                                          );
                                          final combosMap =
                                              Map<String, _ComboSelection>.from(
                                            _selectedCombosVN.value,
                                          );

                                          if (_hasItemsFromOtherZielgruppe(
                                            _zielgruppe,
                                          )) {
                                            final other = currentMap.values.isNotEmpty
                                                ? currentMap.values.first.zielgruppe
                                                : _selectedCombosVN
                                                    .value
                                                    .values
                                                    .first
                                                    .zielgruppe;
                                            _showWrongGroupSnack(other);
                                            return;
                                          }

                                          final locked = _lockedPriceForNewSelection(
                                            category: kat,
                                            zielgruppe: _zielgruppe,
                                            newPartLc: partLc,
                                            selectionMap: currentMap,
                                            singleBaseIndex: singleBaseIndex,
                                            bundles: bundles,
                                            newPartSinglePrice: variantBasePrice,
                                          );

                                          currentMap[selKey] = _CartItem(
                                            kategorie: kat,
                                            leistung: partDisplay,
                                            preis: variantBasePrice,
                                            dauer: variantDuration,
                                            zielgruppe: _zielgruppe,
                                            varianteLabel: isStandard ? 'Standard' : label,
                                            selectedAt: ++_selectionTicker,
                                            lockedDisplayPrice: locked,
                                          );

                                          combosMap.removeWhere(
                                            (_, combo) =>
                                                combo.zielgruppe == _zielgruppe &&
                                                combo.bundle.kategorie == kat &&
                                                combo.bundle.leistungenLc.contains(partLc),
                                          );

                                          _selectedVN.value = currentMap;
                                          _selectedCombosVN.value = combosMap;
                                        },
                                  icon: Icon(
                                    selectedThis
                                        ? Icons.check_circle
                                        : Icons.add_circle_outline,
                                  ),
                                  color: selectedThis ? activeColorFor(_zielgruppe) : null,
                                ),
                              ],
                            ),
                          );
                        }

                        if (hasMethodVariants) {
                          final hasBaseStandardOption =
                              !offer.id.startsWith('synthetic:') &&
                              (offer.priceFor(_zielgruppe) != null ||
                                  offer.durationFor(_zielgruppe) != null ||
                                  _hasSizeOptions(offer, _zielgruppe));
                          final groupId = '$kat|$partLc';

                          return ValueListenableBuilder<Set<String>>(
                            valueListenable: _expandedVariantGroupsVN,
                            builder: (_, collapsedGroups, __) {
                              final isExpanded = collapsedGroups.contains(groupId);

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? activeColorFor(_zielgruppe)
                                        : Colors.transparent,
                                    width: 1.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      final next = Set<String>.from(
                                        _expandedVariantGroupsVN.value,
                                      );
                                      if (isExpanded) {
                                        next.remove(groupId);
                                      } else {
                                        next.add(groupId);
                                      }
                                      _expandedVariantGroupsVN.value = next;
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              uiTitle,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Icon(
                                            isExpanded
                                                ? Icons.keyboard_arrow_down
                                                : Icons.chevron_right,
                                            color: Colors.black54,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isExpanded) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      margin: const EdgeInsets.only(left: 10),
                                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF4F4F4),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: const Color(0xFFD8D8D8),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (hasBaseStandardOption)
                                            buildVariantRow(
                                              label: 'Standard',
                                              variantOffer: offer,
                                              isStandard: true,
                                              isLast: sortedLabels.isEmpty,
                                            ),
                                          for (int i = 0;
                                              i < sortedLabels.length;
                                              i++)
                                            Builder(
                                              builder: (_) {
                                                final label = sortedLabels[i];
                                                final o = singleVariantIndex[
                                                    '$kat|$partLc|${label.toLowerCase()}'];
                                                if (o == null) {
                                                  return const SizedBox.shrink();
                                                }
                                                return buildVariantRow(
                                                  label: label,
                                                  variantOffer: o,
                                                  isLast:
                                                      i == sortedLabels.length - 1,
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                            },
                          );
                        }

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? activeColorFor(_zielgruppe)
                                  : Colors.transparent,
                              width: 1.8,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    uiTitle,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (effectiveDuration != null) ...[
                                  buildDurationBadge(),
                                  const SizedBox(width: 4),
                                ],
                                buildPriceText(),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: selected
                                      ? 'Entfernen'
                                      : (!canAdd
                                          ? 'Nur mit vorheriger Auswahl'
                                          : (hasAnySizeOptions
                                              ? 'Methode/Option wählen'
                                              : 'Hinzufügen')),
                                  onPressed: !canInteract
                                      ? null
                                      : () {
                                          if (hasAnySizeOptions) {
                                            if (selected) {
                                              final newMap =
                                                  Map<String, _CartItem>.from(
                                                _selectedVN.value,
                                              );
                                              newMap.remove(selKey);
                                              _selectedVN.value = newMap;
                                            } else {
                                              final variantsForPart = <Offer>[];
                                              for (final label in sortedLabels) {
                                                final o = singleVariantIndex[
                                                    '$kat|$partLc|${label.toLowerCase()}'];
                                                if (o != null &&
                                                    _hasZielgruppenData(
                                                      o,
                                                      _zielgruppe,
                                                    )) {
                                                  variantsForPart.add(o);
                                                }
                                              }
                                              final combineRows =
                                                  _buildCombineRowsFor(kat, partLc);
                                              _openVariantSheet(
                                                base: offer,
                                                category: kat,
                                                variantOffersForPart:
                                                    variantsForPart,
                                                combineRows: combineRows,
                                              );
                                            }
                                          } else {
                                            final currentMap =
                                                Map<String, _CartItem>.from(
                                              _selectedVN.value,
                                            );

                                            if (_hasItemsFromOtherZielgruppe(
                                              _zielgruppe,
                                            )) {
                                              final other =
                                                  currentMap.values.isNotEmpty
                                                      ? currentMap
                                                          .values
                                                          .first
                                                          .zielgruppe
                                                      : _selectedCombosVN
                                                          .value
                                                          .values
                                                          .first
                                                          .zielgruppe;
                                              _showWrongGroupSnack(other);
                                              return;
                                            }

                                            final singlePrice = preis ??
                                                singleBaseIndex[
                                                        '$kat|$partLc']
                                                    ?.priceFor(_zielgruppe);

                                            final locked =
                                                _lockedPriceForNewSelection(
                                              category: kat,
                                              zielgruppe: _zielgruppe,
                                              newPartLc: partLc,
                                              selectionMap: currentMap,
                                              singleBaseIndex: singleBaseIndex,
                                              bundles: bundles,
                                              newPartSinglePrice: singlePrice,
                                            );

                                            _toggleSelection(
                                              selKey,
                                              _CartItem(
                                                kategorie: kat,
                                                leistung: partDisplay,
                                                preis: singlePrice,
                                                dauer: dauer,
                                                zielgruppe: _zielgruppe,
                                                selectedAt: ++_selectionTicker,
                                                lockedDisplayPrice: locked,
                                              ),
                                            );
                                          }
                                        },
                                  icon: Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.add_circle_outline,
                                  ),
                                  color: selected ? activeColorFor(_zielgruppe) : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      },
                    },
                    ),
                  ),
                ),
              );
            }

            final groupRows = [...(comboGroupRowsByCategory[kat] ?? const <_ComboGroupRow>[])];
            groupRows.sort(
                  (a, b) => a.missingDisplay
                  .join(' + ')
                  .toLowerCase()
                  .compareTo(b.missingDisplay.join(' + ').toLowerCase()),
            );

            for (final group in groupRows) {
              final groupTitle = group.missingDisplay.join(' + ');
              final groupPartsLc = group.missingLc;
              final groupPartsDisplay = group.missingDisplay;
              final groupPrice = group.bundle.priceFor(_zielgruppe);
              final groupMinPrice = _minSizePriceFor(group.bundle, _zielgruppe);
              final hasGroupSizeOptions = _hasSizeOptions(group.bundle, _zielgruppe);
              if (groupPrice == null && groupMinPrice == null && !hasGroupSizeOptions) continue;
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
                          child: Text(
                            groupTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          width: kDurColWidth,
                          child: const SizedBox.shrink(),
                        ),
                        SizedBox(
                          width: kRightColWidth,
                          child: ValueListenableBuilder<Map<String, _CartItem>>(
                            valueListenable: _selectedVN,
                            builder: (_, map, __) {
                              final selectedPartsLc = map.values
                                  .where((it) => it.kategorie == kat && it.zielgruppe == _zielgruppe)
                                  .map((it) => it.leistung.toLowerCase())
                                  .toSet();
                              final selectedAll = groupPartsLc.every(selectedPartsLc.contains);
                              final comboSizeKey = _selectedSizeKeyFromSelection(
                                combo: group.bundle,
                                category: kat,
                                zielgruppe: _zielgruppe,
                                requiredBasePartsLc: group.requiredBaseLc,
                                selectionMap: map,
                              );
                              final previewPrice = selectedAll
                                  ? null
                                  : _previewForComboGroup(
                                combo: group.bundle,
                                category: kat,
                                zielgruppe: _zielgruppe,
                                requiredBasePartsLc: group.requiredBaseLc,
                                selectedPartsLc: selectedPartsLc,
                                selectionMap: map,
                                singleBaseIndex: singleBaseIndex,
                                bundlePriceOverride: _bundlePriceForCombo(
                                  combo: group.bundle,
                                  zielgruppe: _zielgruppe,
                                  sizeKey: comboSizeKey,
                                ),
                              );
                              final canAdd = previewPrice != null;
                              final canInteract = selectedAll || canAdd;

                              double displayPrice;

                              if (selectedAll) {
                                displayPrice = 0.0;
                                for (final partLc in groupPartsLc) {
                                  final key = _keyFor(
                                    zielgruppe: _zielgruppe,
                                    category: kat,
                                    partLc: partLc,
                                  );
                                  final item = map[key];
                                  displayPrice += item?.lockedDisplayPrice ?? item?.preis ?? 0.0;
                                }
                              } else {
                                displayPrice = previewPrice ?? 0.0;
                              }


                              final priceColor =
                              (displayPrice != null && canAdd) ? Colors.green : Colors.black54;

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    _preisText(displayPrice),
                                    style: TextStyle(
                                      color: priceColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: selectedAll
                                        ? 'Entfernen'
                                        : (canAdd ? 'Hinzufügen' : 'Nur mit vorheriger Auswahl'),
                                    onPressed: !canInteract
                                        ? null
                                        : () {
                                      _toggleGroupSelection(
                                        category: kat,
                                        combo: group.bundle,
                                        partsDisplay: groupPartsDisplay,
                                        partsLc: groupPartsLc,
                                        requiredBasePartsLc: group.requiredBaseLc,
                                        singleBaseIndex: singleBaseIndex,
                                      );
                                    },
                                    icon: Icon(
                                      selectedAll ? Icons.check_circle : Icons.add_circle_outline,
                                    ),
                                    color: selectedAll ? activeColorFor(_zielgruppe) : null,
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            final comboGroups = [
              ...(comboDisplayGroupsByCategory[kat] ?? const <_ComboOfferGroup>[])
            ];
            comboGroups.sort(
                  (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            );

            for (final group in comboGroups) {
              final methodOptions = _comboMethodOptionsFor(group.offers);
              if (methodOptions.isEmpty) continue;
              final methodLabels = methodOptions.map((e) => e.label).toList();

              final displayPreis = _minDisplayPriceForCombos(group.offers, _zielgruppe);
              final displayDauer = _minDisplayDurationForCombos(group.offers, _zielgruppe);
              final hasSizeOptionsBase =
              group.offers.any((offer) => _hasSizeOptions(offer, _zielgruppe));

              if (displayPreis == null && displayDauer == null && !hasSizeOptionsBase) continue;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (methodLabels.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ValueListenableBuilder<Map<String, _ComboSelection>>(
                            valueListenable: _selectedCombosVN,
                            builder: (_, map, __) {
                              String? selectedMethodLabel;
                              for (final comboSel in map.values) {
                                if (comboSel.zielgruppe == _zielgruppe &&
                                    comboSel.bundle.kategorie == kat &&
                                    _comboGroupKey(comboSel.bundle) == group.groupKey) {
                                  selectedMethodLabel = _comboMethodLabelSingle(comboSel.bundle);
                                  break;
                                }
                              }
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final label in methodLabels)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: label == selectedMethodLabel
                                                ? const Color(0xFF34C759)
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: label == selectedMethodLabel
                                                  ? const Color(0xFF34C759)
                                                  : const Color(0xFFBDBDBD),
                                            ),
                                          ),
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: label == selectedMethodLabel
                                                  ? Colors.white
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Spacer(),
                            ValueListenableBuilder<Map<String, _ComboSelection>>(
                              valueListenable: _selectedCombosVN,
                              builder: (_, map, __) {
                                _ComboSelection? selectedCombo;
                                for (final comboSel in map.values) {
                                  if (comboSel.zielgruppe == _zielgruppe &&
                                      comboSel.bundle.kategorie == kat &&
                                      _comboGroupKey(comboSel.bundle) == group.groupKey) {
                                    selectedCombo = comboSel;
                                    break;
                                  }
                                }
                                final selected = selectedCombo != null;
                                final effectivePrice = selectedCombo?.preis ?? displayPreis;
                                final effectiveDuration = selectedCombo?.dauer ?? displayDauer;

                                return Row(
                                  children: [
                                    if (effectiveDuration != null) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF2F4F7),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Color(0xFFE5E7EB)),
                                        ),
                                        child: Text(
                                          '$effectiveDuration Min',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF374151),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      _preisText(effectivePrice),
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip:
                                      selected ? 'Auswahl ändern' : 'Kombi hinzufügen',
                                      onPressed: () {
                                        if (selectedCombo != null) {
                                          final combosMap = Map<String, _ComboSelection>.from(
                                            _selectedCombosVN.value,
                                          );
                                          combosMap.remove(
                                            _comboSelectionKey(
                                              zielgruppe: _zielgruppe,
                                              combo: selectedCombo!.bundle,
                                            ),
                                          );
                                          _selectedCombosVN.value = combosMap;
                                          return;
                                        }
                                        _openComboMethodSheet(combos: group.offers);
                                      },
                                      icon: Icon(
                                        selected ? Icons.check_circle : Icons.add_circle_outline,
                                      ),
                                      color: selected ? activeColorFor(_zielgruppe) : null,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
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
                child: AnimatedBuilder(
                  animation: Listenable.merge([_selectedVN, _selectedCombosVN]),
                  builder: (context, _) {
                    final map = _selectedVN.value;
                    final combos = _selectedCombosVN.value;
                    final hasSelection = map.isNotEmpty || combos.isNotEmpty;
                    final totals = (hasSelection)
                        ? computeTotals(map, combos)
                        : const _CartTotals(naive: 0.0, optimized: 0.0);
                    final total = hasSelection ? totals.optimized : 0.0;
                    final savings = hasSelection ? totals.savings : 0.0;
                    final count = map.length + combos.length;

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
                            count: count,
                            total: total,
                            savings: savings,
                            onPressed: () {
                              _openBookingSummaryPanel(
                                singles: map,
                                combos: combos,
                                total: total,
                                savings: savings,
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

class _CartTotals {
  final double naive; // Summe aller Einzelpreise ohne Kombi
  final double optimized; // Beste Summe mit Kombi-Rabatten
  const _CartTotals({required this.naive, required this.optimized});

  double get savings {
    final s = naive - optimized;
    return s > 0 ? s : 0.0;
  }
}


class _BookingSummaryEntry {
  final String selectionKey;
  final bool isCombo;
  final int selectedAt;
  final String title;
  final String subtitle;
  final double? price;
  final int? duration;

  const _BookingSummaryEntry({
    required this.selectionKey,
    required this.isCombo,
    required this.selectedAt,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.duration,
  });
}

/// ---------------------------------------------------------------
/// Bottom-Bar (Warenkorb / CTA)
/// ---------------------------------------------------------------
class _BookingBar extends StatelessWidget {
  final int count;
  final double? total;
  final double savings;
  final VoidCallback onPressed;

  const _BookingBar({
    required this.count,
    required this.total,
    required this.onPressed,
    this.savings = 0.0,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: onPressed,
        child: Row(
          children: [
            // Warenkorb + Badge mit Anzahl
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
                  child:
                  const Icon(Icons.shopping_basket_outlined, size: 22, color: Colors.white),
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
                          fontSize: 11, fontWeight: FontWeight.w800, color: kBrandOrange),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 8),

            // Spare-Badge (nur wenn savings > 0)
            if (savings > 0.0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Spare ${_formatEuro(savings)}',
                  style: const TextStyle(
                      color: kBrandOrange, fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
            ],

            const Expanded(
              child: Center(
                child: Text(
                  'Zur Buchung',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),

            Text(
              total == null ? '' : _formatEuro(total!),
              style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
