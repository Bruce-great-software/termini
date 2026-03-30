// dienstleister_detail_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/cupertino.dart';
import 'login_register_page.dart';
import 'package:termini/widgets/angebote_view.dart';

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
  final double? originalPrice;
  final List<String>? selectedPartsDisplay;
  final List<String>? selectedPartsLcOverride;

  const _ComboSelection({
    required this.bundle,
    required this.zielgruppe,
    required this.selectedAt,
    this.preis,
    this.dauer,
    this.varianteLabel,
    this.originalPrice,
    this.selectedPartsDisplay,
    this.selectedPartsLcOverride,
  });

  List<String> get selectedPartsLc => selectedPartsLcOverride ?? bundle.leistungenLc;
  List<String> get selectedTitles => selectedPartsDisplay ?? bundle.leistungen;
}

class _SelectedComboContribution {
  final Set<String> partsLc;
  final double price;

  const _SelectedComboContribution({
    required this.partsLc,
    required this.price,
  });
}

Set<String> _selectedPartsForContext({
  required String zielgruppe,
  required String category,
  required Map<String, _CartItem> selectionMap,
  required Map<String, _ComboSelection> combosMap,
}) {
  final selectedParts = <String>{};

  for (final item in selectionMap.values) {
    if (item.zielgruppe != zielgruppe || item.kategorie != category) continue;
    selectedParts.add(item.leistung.toLowerCase());
  }

  for (final combo in combosMap.values) {
    if (combo.zielgruppe != zielgruppe || combo.bundle.kategorie != category) continue;
    selectedParts.addAll(combo.selectedPartsLc);
  }

  return selectedParts;
}

List<_SelectedComboContribution> _selectedComboContributionsForContext({
  required String zielgruppe,
  required String category,
  required Map<String, _ComboSelection> combosMap,
}) {
  final contributions = <_SelectedComboContribution>[];

  for (final combo in combosMap.values) {
    if (combo.zielgruppe != zielgruppe || combo.bundle.kategorie != category) continue;
    final price = combo.preis ?? combo.bundle.priceFor(zielgruppe);
    if (price == null) continue;
    contributions.add(
      _SelectedComboContribution(
        partsLc: combo.selectedPartsLc.toSet(),
        price: price,
      ),
    );
  }

  contributions.sort((a, b) => b.partsLc.length.compareTo(a.partsLc.length));
  return contributions;
}

double? _comboAwareRemainderForBundle({
  required Offer bundle,
  required String zielgruppe,
  required String newPartLc,
  required Map<String, _CartItem> selectionMap,
  required Map<String, _ComboSelection> combosMap,
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
  required double? newPartSinglePrice,
  double? bundlePriceOverride,
}) {
  final bundlePrice = bundlePriceOverride ?? bundle.priceFor(zielgruppe);
  if (bundlePrice == null) return null;

  final otherParts = bundle.leistungenLc.where((lc) => lc != newPartLc).toSet();
  if (otherParts.isEmpty) return null;

  final selectedParts = _selectedPartsForContext(
    zielgruppe: zielgruppe,
    category: bundle.kategorie,
    selectionMap: selectionMap,
    combosMap: combosMap,
  );
  if (!otherParts.every(selectedParts.contains)) return null;

  var remainingParts = Set<String>.from(otherParts);
  var contribution = 0.0;

  for (final combo in _selectedComboContributionsForContext(
    zielgruppe: zielgruppe,
    category: bundle.kategorie,
    combosMap: combosMap,
  )) {
    if (combo.partsLc.contains(newPartLc)) continue;
    if (!combo.partsLc.every(otherParts.contains)) continue;
    if (!combo.partsLc.every(remainingParts.contains)) continue;

    remainingParts.removeAll(combo.partsLc);
    contribution += combo.price;
  }

  for (final partLc in otherParts) {
    if (!remainingParts.contains(partLc)) continue;
    contribution += _contributionPriceOfPart(
      category: bundle.kategorie,
      zielgruppe: zielgruppe,
      partLc: partLc,
      selectionMap: selectionMap,
      combosMap: combosMap,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
    );
    remainingParts.remove(partLc);
  }

  if (remainingParts.isNotEmpty) return null;

  final remainder = (bundlePrice - contribution).clamp(0.0, double.infinity);
  if (newPartSinglePrice == null || remainder < newPartSinglePrice) {
    return remainder;
  }
  return null;
}


// Singlepreis eines Parts bestimmen (Variantenpreis > Basis > 0)
double _singlePriceOfPart({
  required String category,
  required String zielgruppe,
  required String partLc,
  required Map<String, _CartItem> selectionMap,
  required Map<String, Offer> singleBaseIndex,
}) {
  final selectedKey = _keyFor(
    zielgruppe: zielgruppe,
    category: category,
    partLc: partLc,
  );
  final selectedItem = selectionMap[selectedKey];
  if (selectedItem != null && selectedItem.preis != null) {
    return selectedItem.preis!;
  }

  final p = singleBaseIndex['$category|$partLc']?.priceFor(zielgruppe);
  return p ?? 0.0;
}

double _contributionPriceOfPart({
  required String category,
  required String zielgruppe,
  required String partLc,
  required Map<String, _CartItem> selectionMap,
  Map<String, _ComboSelection> combosMap = const {},
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
}) {
  final key = _keyFor(zielgruppe: zielgruppe, category: category, partLc: partLc);
  final selected = selectionMap[key];
  if (selected != null) {
    final locked = _validatedLockedDisplayPrice(
      item: selected,
      selectionMap: selectionMap,
      combosMap: combosMap,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
    );
    if (locked != null) return locked;
    if (selected.preis != null) return selected.preis!;
  }

  return _singlePriceOfPart(
    category: category,
    zielgruppe: zielgruppe,
    partLc: partLc,
    selectionMap: selectionMap,
    singleBaseIndex: singleBaseIndex,
  );
}

// Restbetrag (locked price) für neues Item, wenn dadurch Bundle greift
double? _lockedPriceForNewSelection({
  required String category,
  required String zielgruppe,
  required String newPartLc,
  required Map<String, _CartItem> selectionMap,
  Map<String, _ComboSelection> combosMap = const {},
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
  required double? newPartSinglePrice,
}) {
  if (newPartSinglePrice == null) return null;

  double? bestRemainder;

  for (final b in bundles) {
    if (b.kategorie != category) continue;
    if (!b.leistungenLc.contains(newPartLc)) continue;

    final remainder = _comboAwareRemainderForBundle(
      bundle: b,
      zielgruppe: zielgruppe,
      newPartLc: newPartLc,
      selectionMap: selectionMap,
      combosMap: combosMap,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
      newPartSinglePrice: newPartSinglePrice,
    );
    if (remainder != null && (bestRemainder == null || remainder < bestRemainder!)) {
      bestRemainder = remainder;
    }
  }

  if (bestRemainder != null && bestRemainder! < newPartSinglePrice) {
    return bestRemainder;
  }
  return null;
}

double? _currentDiscountedSingleDisplayPrice({
  required String category,
  required String zielgruppe,
  required String partLc,
  required Map<String, _CartItem> selectionMap,
  Map<String, _ComboSelection> combosMap = const {},
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
}) {
  final key = _keyFor(zielgruppe: zielgruppe, category: category, partLc: partLc);
  final selected = selectionMap[key];
  if (selected == null || selected.preis == null) return null;

  final otherSelections = Map<String, _CartItem>.from(selectionMap)..remove(key);
  return _lockedPriceForNewSelection(
    category: category,
    zielgruppe: zielgruppe,
    newPartLc: partLc,
    selectionMap: otherSelections,
    combosMap: combosMap,
    singleBaseIndex: singleBaseIndex,
    bundles: bundles,
    newPartSinglePrice: selected.preis,
  );
}

double? _validatedLockedDisplayPrice({
  required _CartItem item,
  required Map<String, _CartItem> selectionMap,
  Map<String, _ComboSelection> combosMap = const {},
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
}) {
  final locked = item.lockedDisplayPrice;
  if (locked == null || item.preis == null || locked >= item.preis!) return null;

  const tolerance = 0.001;
  final partLc = item.leistung.toLowerCase();

  for (final b in bundles) {
    if (b.kategorie != item.kategorie) continue;
    if (!b.leistungenLc.contains(partLc)) continue;

    final bundlePrice = b.priceFor(item.zielgruppe);
    if (bundlePrice == null) continue;

    final expectedRemainder = _comboAwareRemainderForBundle(
      bundle: b,
      zielgruppe: item.zielgruppe,
      newPartLc: partLc,
      selectionMap: selectionMap,
      combosMap: combosMap,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
      newPartSinglePrice: item.preis,
      bundlePriceOverride: bundlePrice,
    );
    if (expectedRemainder == null) continue;
    final isMatchingLocked = (expectedRemainder - locked).abs() <= tolerance;
    if (isMatchingLocked && expectedRemainder < item.preis!) {
      return locked;
    }
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
  Map<String, _ComboSelection> combosMap = const {},
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
}) {
  double? best;

  for (final b in bundles) {
    if (b.kategorie != category) continue;
    if (!b.leistungenLc.contains(partLc)) continue;

    final remainder = _comboAwareRemainderForBundle(
      bundle: b,
      zielgruppe: zielgruppe,
      newPartLc: partLc,
      selectionMap: selectionMap,
      combosMap: combosMap,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
      newPartSinglePrice: singleBaseIndex['$category|$partLc']?.priceFor(zielgruppe),
    );
    if (remainder != null && (best == null || remainder < best!)) {
      best = remainder;
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
  Map<String, _ComboSelection> combosMap = const {},
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
  double? bundlePriceOverride,
}) {
  if (!requiredBasePartsLc.every(selectedPartsLc.contains)) return null;

  final bundlePrice = bundlePriceOverride ?? combo.priceFor(zielgruppe);
  if (bundlePrice == null) return null;

  double baseContribution = 0.0;
  for (final baseLc in requiredBasePartsLc) {
    baseContribution += _contributionPriceOfPart(
      category: category,
      zielgruppe: zielgruppe,
      partLc: baseLc,
      selectionMap: selectionMap,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
    );
  }

  return (bundlePrice - baseContribution).clamp(0.0, double.infinity);
}

double? _previewForStandaloneComboOffer({
  required Offer combo,
  required String category,
  required String zielgruppe,
  required Set<String> selectedPartsLc,
  required Map<String, _CartItem> selectionMap,
  Map<String, _ComboSelection> combosMap = const {},
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
  double? comboPriceOverride,
}) {
  final comboPrice = comboPriceOverride ?? combo.priceFor(zielgruppe);
  double? best;

  for (final bundle in bundles) {
    if (bundle.kategorie != category) continue;
    if (bundle.id == combo.id) continue;
    if (!combo.leistungenLc.every(bundle.leistungenLc.contains)) continue;

    final additionalParts = bundle.leistungenLc
        .where((partLc) => !combo.leistungenLc.contains(partLc))
        .toSet();
    if (additionalParts.isEmpty) continue;
    if (!additionalParts.every(selectedPartsLc.contains)) continue;

    final bundlePrice = bundle.priceFor(zielgruppe);
    if (bundlePrice == null) continue;

    double baseContribution = 0.0;
    for (final partLc in additionalParts) {
      baseContribution += _contributionPriceOfPart(
        category: category,
        zielgruppe: zielgruppe,
        partLc: partLc,
        selectionMap: selectionMap,
        combosMap: combosMap,
        singleBaseIndex: singleBaseIndex,
        bundles: bundles,
      );
    }

    final remainder = (bundlePrice - baseContribution).clamp(0.0, double.infinity);
    if (comboPrice == null || remainder < comboPrice) {
      best = best == null || remainder < best ? remainder : best;
    }
  }

  return best;
}

double? _previewForStandaloneComboOffers({
  required List<Offer> offers,
  required String category,
  required String zielgruppe,
  required Set<String> selectedPartsLc,
  required Map<String, _CartItem> selectionMap,
  Map<String, _ComboSelection> combosMap = const {},
  required Map<String, Offer> singleBaseIndex,
  required List<Offer> bundles,
}) {
  double? best;

  for (final offer in offers) {
    final preview = _previewForStandaloneComboOffer(
      combo: offer,
      category: category,
      zielgruppe: zielgruppe,
      selectedPartsLc: selectedPartsLc,
      selectionMap: selectionMap,
      combosMap: combosMap,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
      comboPriceOverride: offer.priceFor(zielgruppe),
    );
    if (preview == null) continue;
    best = best == null || preview < best ? preview : best;
  }

  return best;
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

class _BookingMitarbeiterOption {
  final String? id;
  final String label;

  const _BookingMitarbeiterOption({
    required this.id,
    required this.label,
  });
}

class _BookingSlotOption {
  final String time;
  final String mitarbeiterId;
  final String mitarbeiterName;

  const _BookingSlotOption({
    required this.time,
    required this.mitarbeiterId,
    required this.mitarbeiterName,
  });
}

class _BookingTimeAvailability {
  final List<String> times;
  final String? message;
  final Map<String, _BookingSlotOption> slotAssignments;

  const _BookingTimeAvailability({
    required this.times,
    this.message,
    this.slotAssignments = const <String, _BookingSlotOption>{},
  });
}

enum _BookingLoginState { loginInitial, loginForm, loginSuccess }

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
              const double sectionTopSpacing = 10;

              return Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: sectionTopSpacing),
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

                        return Positioned(
                          top: sectionTopSpacing,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
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

class _BildNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _BildNavButton({
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x73000000),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            color: onTap == null ? Colors.white54 : Colors.white,
            size: 22,
          ),
        ),
      ),
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
  final VoidCallback? onNavigateToTermine;

  const DienstleisterDetailPage({
    super.key,
    required this.dienstleister,
    required this.selektierteZielgruppe,
    required this.selektierteKategorie,
    this.onNavigateToTermine,
  });

  @override
  State<DienstleisterDetailPage> createState() => _DienstleisterDetailPageState();
}

class _DienstleisterDetailPageState extends State<DienstleisterDetailPage> {
  String _zielgruppe = 'Damen';
  final PageController _bilderPageController = PageController();
  int _aktuellerBildIndex = 0;

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
  String? _selectedMitarbeiterId;
  String _selectedMitarbeiterLabel = 'Beliebiger Mitarbeiter';
  late DateTime _selectedBookingDate;
  String? _selectedBookingTime;
  _BookingSlotOption? _selectedBookingSlotOption;
  late List<String> _availableBookingTimes;
  Map<String, _BookingSlotOption> _bookingSlotAssignments = const {};
  String? _bookingTimesHint;
  _BookingLoginState _bookingLoginState = _BookingLoginState.loginInitial;
  final TextEditingController _bookingLoginEmailController =
  TextEditingController();
  final TextEditingController _bookingLoginPasswordController =
  TextEditingController();
  bool _isBookingLoginLoading = false;
  bool _bookingLoginObscurePassword = true;
  String _bookingLoginName = '';
  String _bookingLoginEmail = '';
  String _bookingLoginPhone = '';
  bool _isBookingLoginSyncInProgress = false;
  String? _bookingLoginSyncedUid;

  @override
  void initState() {
    super.initState();
    _selectedBookingDate = _dateOnly(DateTime.now());
    _availableBookingTimes = const <String>[];
    _bookingTimesHint = null;
    _ladeZielgruppeAusProfil();
  }

  @override
  void dispose() {
    _bilderPageController.dispose();
    _selectedVN.dispose();
    _selectedCombosVN.dispose();
    _expandedVariantGroupsVN.dispose();
    _bookingLoginEmailController.dispose();
    _bookingLoginPasswordController.dispose();
    super.dispose();
  }

  void _zurBildSeite(int index) {
    if (!_bilderPageController.hasClients) return;
    _bilderPageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  String? _mapGeschlechtZuZielgruppe(String? geschlechtRaw) {
    final geschlecht = geschlechtRaw?.trim().toLowerCase();
    if (geschlecht == 'frau') return 'Damen';
    if (geschlecht == 'herr') return 'Herren';
    return null;
  }

  Future<void> _ladeZielgruppeAusProfil() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final zielgruppe = _mapGeschlechtZuZielgruppe(data?['geschlecht'] as String?);

      if (!mounted || zielgruppe == null || _zielgruppe == zielgruppe) {
        return;
      }

      setState(() {
        _zielgruppe = zielgruppe;
      });
    } catch (_) {
      // Profil-Zielgruppe ist optional; bei Fehler bleibt die bestehende Auswahl aktiv.
    }
  }

  Map<String, Widget> _zielgruppenSegments() {
    TextStyle label(String value) => TextStyle(
      fontWeight: FontWeight.w600,
      color: _zielgruppe == value ? Colors.white : Colors.black,
    );
    const EdgeInsets pad = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
    return {
      'Damen': Padding(padding: pad, child: Text('Damen', style: label('Damen'))),
      'Herren': Padding(padding: pad, child: Text('Herren', style: label('Herren'))),
      'Kinder': Padding(padding: pad, child: Text('Kinder', style: label('Kinder'))),
    };
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
    return '';
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
    Offer? fallbackOffer;
    for (final combo in offers) {
      final label = _comboMethodLabelSingle(combo);
      if (label.trim().isEmpty) {
        if (fallbackOffer == null || _isBetterOfferForDisplay(combo, fallbackOffer, _zielgruppe)) {
          fallbackOffer = combo;
        }
        continue;
      }
      final existing = byLabel[label];
      if (existing == null || _isBetterOfferForDisplay(combo, existing, _zielgruppe)) {
        byLabel[label] = combo;
      }
    }
    if (byLabel.isEmpty && fallbackOffer != null) {
      return [_ComboMethodOption(label: '', offer: fallbackOffer)];
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

  Offer? _bestStandaloneComboForParts({
    required String category,
    required String zielgruppe,
    required List<String> partLcs,
    required List<Offer> bundles,
  }) {
    final selectedParts = partLcs.toSet();

    return bundles.where((offer) {
      if (offer.kategorie != category) return false;
      if (!_hasZielgruppenData(offer, zielgruppe)) return false;
      if (offer.leistungenLc.length != partLcs.length) return false;
      final offerParts = offer.leistungenLc.toSet();
      return offerParts.containsAll(selectedParts) &&
          selectedParts.containsAll(offerParts);
    }).fold<Offer?>(null, (best, offer) {
      if (best == null) return offer;
      final bestPrice = _bundlePriceForCombo(
        combo: best,
        zielgruppe: zielgruppe,
      );
      final offerPrice = _bundlePriceForCombo(
        combo: offer,
        zielgruppe: zielgruppe,
      );
      if (offerPrice == null) return best;
      if (bestPrice == null || offerPrice < bestPrice) return offer;
      return best;
    });
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

  void _clearInvalidLockedPrices({
    required Map<String, _CartItem> selectionMap,
    required Map<String, Offer> singleBaseIndex,
    required List<Offer> bundles,
  }) {
    final keys = selectionMap.keys.toList();
    for (final key in keys) {
      final item = selectionMap[key];
      if (item == null || item.lockedDisplayPrice == null) continue;

      final validatedLocked = _validatedLockedDisplayPrice(
        item: item,
        selectionMap: selectionMap,
        singleBaseIndex: singleBaseIndex,
        bundles: bundles,
      );

      selectionMap[key] = _CartItem(
        kategorie: item.kategorie,
        leistung: item.leistung,
        preis: item.preis,
        dauer: item.dauer,
        zielgruppe: item.zielgruppe,
        varianteLabel: item.varianteLabel,
        selectedAt: item.selectedAt,
        lockedDisplayPrice: validatedLocked,
      );
    }
  }

  void _toggleSelection(
      String key,
      _CartItem item, {
        required Map<String, Offer> singleBaseIndex,
        required List<Offer> bundles,
      }) {
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
            combo.selectedPartsLc.contains(item.leistung.toLowerCase()),
      );
    } else {
      map.remove(key);
      _removeDependentSelections(
        selectionMap: map,
        zielgruppe: item.zielgruppe,
        category: item.kategorie,
        removedPartLc: item.leistung.toLowerCase(),
      );
      _removeDependentComboSelections(
        combosMap: combos,
        zielgruppe: item.zielgruppe,
        category: item.kategorie,
        removedPartLc: item.leistung.toLowerCase(),
        bundles: bundles,
      );
    }

    _clearInvalidLockedPrices(
      selectionMap: map,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
    );
    _refreshComboSelections(
      selectionMap: map,
      combosMap: combos,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
    );

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
    required List<Offer> bundles,
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
          (lc) => combos.values.any(
            (comboSel) =>
        comboSel.zielgruppe == zg &&
            comboSel.bundle.kategorie == category &&
            comboSel.selectedPartsLc.length == partsLc.length &&
            comboSel.selectedPartsLc.contains(lc) &&
            partsLc.every(comboSel.selectedPartsLc.contains),
      ),
    );

    if (selectedAll) {
      combos.removeWhere(
            (_, comboSel) =>
        comboSel.zielgruppe == zg &&
            comboSel.bundle.kategorie == category &&
            comboSel.selectedPartsLc.length == partsLc.length &&
            partsLc.every(comboSel.selectedPartsLc.contains),
      );
      _selectedVN.value = map;
      _selectedCombosVN.value = combos;
      return;
    }

    final selectedPartsLc = _selectedPartsForContext(
      zielgruppe: zg,
      category: category,
      selectionMap: map,
      combosMap: combos,
    );

    final bundleOriginalPrice = _bundlePriceForCombo(
      combo: combo,
      zielgruppe: zg,
      sizeKey: _selectedSizeKeyFromSelection(
        combo: combo,
        category: category,
        zielgruppe: zg,
        requiredBasePartsLc: requiredBasePartsLc,
        selectionMap: map,
      ),
    );
    final remainder = _previewForComboGroup(
      combo: combo,
      category: category,
      zielgruppe: zg,
      requiredBasePartsLc: requiredBasePartsLc,
      selectedPartsLc: selectedPartsLc,
      selectionMap: map,
      combosMap: combos,
      singleBaseIndex: singleBaseIndex,
      bundles: bundles,
      bundlePriceOverride: bundleOriginalPrice,
    );
    if (remainder == null) return;

    combos.removeWhere(
          (_, comboSel) =>
      comboSel.zielgruppe == zg &&
          comboSel.bundle.kategorie == category &&
          comboSel.selectedPartsLc.any(partsLc.contains),
    );

    combos[_comboSelectionKey(zielgruppe: zg, combo: combo)] = _ComboSelection(
      bundle: combo,
      zielgruppe: zg,
      selectedAt: ++_selectionTicker,
      preis: remainder,
      dauer: null,
      originalPrice:
      bundleOriginalPrice != null && remainder < bundleOriginalPrice
          ? bundleOriginalPrice
          : null,
      selectedPartsDisplay: partsDisplay,
      selectedPartsLcOverride: partsLc,
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


  void _refreshComboSelections({
    required Map<String, _CartItem> selectionMap,
    required Map<String, _ComboSelection> combosMap,
    required Map<String, Offer> singleBaseIndex,
    required List<Offer> bundles,
  }) {
    final entries = combosMap.entries.toList();

    for (final entry in entries) {
      final selection = entry.value;
      if (selection.selectedPartsLc.length != selection.bundle.leistungenLc.length) {
        continue;
      }

      final standaloneCombo = _bestStandaloneComboForParts(
        category: selection.bundle.kategorie,
        zielgruppe: selection.zielgruppe,
        partLcs: selection.selectedPartsLc,
        bundles: bundles,
      );
      final targetCombo = standaloneCombo ?? selection.bundle;
      final standalonePrice = _bundlePriceForCombo(
        combo: targetCombo,
        zielgruppe: selection.zielgruppe,
      );
      if (standalonePrice == null) continue;

      final selectedParts = _selectedPartsForContext(
        zielgruppe: selection.zielgruppe,
        category: selection.bundle.kategorie,
        selectionMap: selectionMap,
        combosMap: combosMap,
      );
      final previewPrice = _previewForStandaloneComboOffer(
        combo: targetCombo,
        category: selection.bundle.kategorie,
        zielgruppe: selection.zielgruppe,
        selectedPartsLc: selectedParts,
        selectionMap: selectionMap,
        combosMap: combosMap,
        singleBaseIndex: singleBaseIndex,
        bundles: bundles,
        comboPriceOverride: standalonePrice,
      );
      final effectivePrice =
      previewPrice != null && previewPrice < standalonePrice
          ? previewPrice
          : standalonePrice;

      final newKey = _comboSelectionKey(
        zielgruppe: selection.zielgruppe,
        combo: targetCombo,
      );
      if (newKey != entry.key) {
        combosMap.remove(entry.key);
      }
      combosMap[newKey] = _ComboSelection(
        bundle: targetCombo,
        zielgruppe: selection.zielgruppe,
        selectedAt: selection.selectedAt,
        preis: effectivePrice,
        dauer: selection.dauer ??
            _bundleDurationForCombo(
              combo: targetCombo,
              zielgruppe: selection.zielgruppe,
            ),
        varianteLabel: selection.varianteLabel ??
            _comboVariantLabel(method: _comboMethodLabelSingle(targetCombo)),
        originalPrice: effectivePrice < standalonePrice ? standalonePrice : null,
        selectedPartsDisplay: selection.selectedTitles,
        selectedPartsLcOverride: selection.selectedPartsLc,
      );
    }
  }

  void _removeDependentComboSelections({
    required Map<String, _ComboSelection> combosMap,
    required String zielgruppe,
    required String category,
    required String removedPartLc,
    required List<Offer> bundles,
  }) {
    final entries = combosMap.entries.toList();

    for (final entry in entries) {
      final comboSel = entry.value;
      final isDependentPartialCombo =
          comboSel.zielgruppe == zielgruppe &&
              comboSel.bundle.kategorie == category &&
              comboSel.selectedPartsLc.length != comboSel.bundle.leistungenLc.length &&
              !comboSel.selectedPartsLc.contains(removedPartLc) &&
              comboSel.bundle.leistungenLc.contains(removedPartLc);
      if (!isDependentPartialCombo) continue;

      combosMap.remove(entry.key);

      final standaloneCombo = _bestStandaloneComboForParts(
        category: category,
        zielgruppe: zielgruppe,
        partLcs: comboSel.selectedPartsLc,
        bundles: bundles,
      );
      if (standaloneCombo == null) {
        continue;
      }

      final standalonePrice = _bundlePriceForCombo(
        combo: standaloneCombo,
        zielgruppe: zielgruppe,
      );
      if (standalonePrice == null) {
        continue;
      }

      combosMap[_comboSelectionKey(
        zielgruppe: zielgruppe,
        combo: standaloneCombo,
      )] = _ComboSelection(
        bundle: standaloneCombo,
        zielgruppe: zielgruppe,
        selectedAt: comboSel.selectedAt,
        preis: standalonePrice,
        dauer: comboSel.dauer ??
            _bundleDurationForCombo(
              combo: standaloneCombo,
              zielgruppe: zielgruppe,
            ),
        varianteLabel: comboSel.varianteLabel ??
            _comboVariantLabel(method: _comboMethodLabelSingle(standaloneCombo)),
        originalPrice: null,
        selectedPartsDisplay: comboSel.selectedTitles,
        selectedPartsLcOverride: comboSel.selectedPartsLc,
      );
    }
  }

  /// Combo-Helper: (de)selektiert alle Einzel-Leistungen der Kombi
  void _toggleCombo({
    required Offer combo,
    double? priceOverride,
    int? durationOverride,
    String? varianteLabel,
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
      final comboPreis = priceOverride ?? combo.priceFor(zg);
      final comboOriginal = _bundlePriceForCombo(combo: combo, zielgruppe: zg);
      final comboDauer = durationOverride ?? combo.durationFor(zg);
      combos[comboKey] = _ComboSelection(
        bundle: combo,
        zielgruppe: zg,
        selectedAt: ++_selectionTicker,
        preis: comboPreis,
        dauer: comboDauer,
        varianteLabel: varianteLabel,
        originalPrice:
        comboOriginal != null && comboPreis != null && comboPreis < comboOriginal
            ? comboOriginal
            : null,
      );
    }

    _selectedVN.value = singles;
    _selectedCombosVN.value = combos;
  }

  String _formatEuro(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return '$s €';
  }

  int _selectedServiceCount({
    required Map<String, _CartItem> singles,
    required Map<String, _ComboSelection> combos,
  }) {
    return singles.length +
        combos.values.fold<int>(
          0,
              (sum, combo) => sum + combo.selectedPartsLc.length,
        );
  }

  String _preisText(double? p) {
    if (p == null) return '–';
    final s = p.toStringAsFixed(2).replaceAll('.', ',');
    return 'ab $s €';
  }

  String _dauerText(int? d) => d == null ? '' : ' • ${d.toString()} Min';

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<Map<String, dynamic>?> _loadDienstleisterOeffnungszeiten() async {
    final dienstleisterId = widget.dienstleister['id'] as String?;
    if (dienstleisterId == null || dienstleisterId.trim().isEmpty) {
      return null;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(dienstleisterId)
          .get();

      final data = snapshot.data();
      final rawOeffnungszeiten = data?['oeffnungszeiten'];
      if (rawOeffnungszeiten is! Map) {
        return null;
      }

      return Map<String, dynamic>.from(rawOeffnungszeiten);
    } catch (_) {
      return null;
    }
  }

  String _weekdayKeyFromDate(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'montag';
      case DateTime.tuesday:
        return 'dienstag';
      case DateTime.wednesday:
        return 'mittwoch';
      case DateTime.thursday:
        return 'donnerstag';
      case DateTime.friday:
        return 'freitag';
      case DateTime.saturday:
        return 'samstag';
      case DateTime.sunday:
        return 'sonntag';
      default:
        return '';
    }
  }

  int? _parseHourMinute(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final parts = trimmed.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return hour * 60 + minute;
  }

  String _formatHourMinute(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minute = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  int _selectedDurationMinutes({
    required Map<String, _CartItem> singles,
    required Map<String, _ComboSelection> combos,
  }) {
    var totalMinutes = 0;

    for (final item in singles.values) {
      totalMinutes += item.dauer ?? 0;
    }
    for (final combo in combos.values) {
      totalMinutes += combo.dauer ?? 0;
    }

    return totalMinutes;
  }

  _BookingTimeAvailability _buildAvailabilityFromOpeningHours({
    required Map<String, dynamic>? oeffnungszeiten,
    required DateTime selectedDate,
    required int totalDurationMinutes,
  }) {
    if (oeffnungszeiten == null || oeffnungszeiten.isEmpty) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'Für diesen Tag sind keine Öffnungszeiten hinterlegt.',
      );
    }

    final weekdayKey = _weekdayKeyFromDate(selectedDate);
    final rawDay = oeffnungszeiten[weekdayKey];
    if (rawDay is! Map) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'Für diesen Tag sind keine Öffnungszeiten hinterlegt.',
      );
    }

    final day = Map<String, dynamic>.from(rawDay);
    final isActive = day['aktiv'] == true;
    final fromMinutes = _parseHourMinute(day['von'] as String?);
    final untilMinutes = _parseHourMinute(day['bis'] as String?);

    if (!isActive) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'An diesem Tag ist geschlossen.',
      );
    }

    if (fromMinutes == null ||
        untilMinutes == null ||
        untilMinutes <= fromMinutes) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'Für diesen Tag sind keine Öffnungszeiten hinterlegt.',
      );
    }

    final duration = totalDurationMinutes < 0 ? 0 : totalDurationMinutes;
    final latestStart = untilMinutes - duration;
    if (latestStart < fromMinutes) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'Für die gewählte Auswahl sind an diesem Tag keine Zeiten verfügbar.',
      );
    }

    final slots = <String>[];
    for (var minutes = fromMinutes; minutes <= latestStart; minutes += 30) {
      slots.add(_formatHourMinute(minutes));
    }

    if (slots.isEmpty) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'Für die gewählte Auswahl sind an diesem Tag keine Zeiten verfügbar.',
      );
    }

    return _BookingTimeAvailability(times: slots);
  }

  Future<_BookingTimeAvailability> _buildAvailabilityFromMitarbeiter({
    required String mitarbeiterId,
    required DateTime selectedDate,
    required int totalDurationMinutes,
  }) async {
    final trimmedMitarbeiterId = mitarbeiterId.trim();
    if (trimmedMitarbeiterId.isEmpty) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'Dieser Mitarbeiter ist an diesem Tag nicht verfügbar.',
      );
    }

    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(trimmedMitarbeiterId)
          .get();
      final userData = userSnapshot.data();
      final rawArbeitszeiten = userData?['arbeitszeiten'];
      if (rawArbeitszeiten is! Map) {
        return const _BookingTimeAvailability(
          times: <String>[],
          message: 'Dieser Mitarbeiter ist an diesem Tag nicht verfügbar.',
        );
      }

      final arbeitszeiten = Map<String, dynamic>.from(rawArbeitszeiten);
      final weekdayKey = _weekdayKeyFromDate(selectedDate);
      final rawDay = arbeitszeiten[weekdayKey];
      if (rawDay is! Map) {
        return const _BookingTimeAvailability(
          times: <String>[],
          message: 'Dieser Mitarbeiter ist an diesem Tag nicht verfügbar.',
        );
      }

      final day = Map<String, dynamic>.from(rawDay);
      final isActive = day['aktiv'] == true;
      final fromMinutes = _parseHourMinute(day['von'] as String?);
      final untilMinutes = _parseHourMinute(day['bis'] as String?);

      if (!isActive) {
        return const _BookingTimeAvailability(
          times: <String>[],
          message: 'Dieser Mitarbeiter ist an diesem Tag nicht verfügbar.',
        );
      }

      if (fromMinutes == null ||
          untilMinutes == null ||
          untilMinutes <= fromMinutes) {
        return const _BookingTimeAvailability(
          times: <String>[],
          message: 'Dieser Mitarbeiter ist an diesem Tag nicht verfügbar.',
        );
      }

      final duration = totalDurationMinutes < 0 ? 0 : totalDurationMinutes;
      final latestStart = untilMinutes - duration;
      if (latestStart < fromMinutes) {
        return const _BookingTimeAvailability(
          times: <String>[],
          message: 'Keine freien Termine verfügbar.',
        );
      }

      final existingAppointmentsSnapshot = await FirebaseFirestore.instance
          .collection('termine')
          .where('mitarbeiterId', isEqualTo: trimmedMitarbeiterId)
          .where('datum', isEqualTo: _bookingDateIso(selectedDate))
          .get();

      final existingAppointments = existingAppointmentsSnapshot.docs
          .map((doc) => doc.data())
          .where((data) {
        final status = (data['status'] as String?)?.trim().toLowerCase();
        return status != 'abgesagt';
      }).map((data) {
        final startAt = _timestampOrDateTime(data['startAt']);
        final endAt = _timestampOrDateTime(data['endAt']);
        if (startAt == null || endAt == null) return null;
        return DateTimeRange(start: startAt, end: endAt);
      }).whereType<DateTimeRange>()
          .where((range) => range.end.isAfter(range.start))
          .toList();

      final slots = <String>[];
      for (var minutes = fromMinutes; minutes <= latestStart; minutes += 30) {
        final slotStart = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
        ).add(Duration(minutes: minutes));
        final slotEnd = slotStart.add(Duration(minutes: duration));
        final hasCollision = existingAppointments.any(
              (appointment) =>
          slotStart.isBefore(appointment.end) &&
              slotEnd.isAfter(appointment.start),
        );
        if (!hasCollision) {
          slots.add(_formatHourMinute(minutes));
        }
      }

      if (slots.isEmpty) {
        return const _BookingTimeAvailability(
          times: <String>[],
          message: 'Keine freien Termine verfügbar.',
        );
      }

      return _BookingTimeAvailability(times: slots);
    } catch (_) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'Keine freien Termine verfügbar.',
      );
    }
  }

  Future<_BookingTimeAvailability> _buildAvailabilityForAnyMitarbeiter({
    required DateTime selectedDate,
    required int totalDurationMinutes,
  }) async {
    final dienstleisterId = (widget.dienstleister['id'] as String? ?? '').trim();
    if (dienstleisterId.isEmpty) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'Keine freien Termine verfügbar.',
      );
    }

    try {
      final mitarbeiterSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('dienstleisterId', isEqualTo: dienstleisterId)
          .where('aktiv', isEqualTo: true)
          .get();

      final mitarbeiterDocs = mitarbeiterSnapshot.docs
          .where((doc) => _isActiveEmployee(doc.data()))
          .toList()
        ..sort((a, b) {
          final nameA = (a.data()['name'] as String? ?? '').trim().toLowerCase();
          final nameB = (b.data()['name'] as String? ?? '').trim().toLowerCase();
          return nameA.compareTo(nameB);
        });

      if (mitarbeiterDocs.isEmpty) {
        return const _BookingTimeAvailability(
          times: <String>[],
          message: 'Keine freien Termine verfügbar.',
        );
      }

      final slotAssignments = <String, _BookingSlotOption>{};
      for (final mitarbeiterDoc in mitarbeiterDocs) {
        final data = mitarbeiterDoc.data();
        final name = (data['name'] as String?)?.trim().isNotEmpty == true
            ? (data['name'] as String).trim()
            : 'Unbenannt';
        final availability = await _buildAvailabilityFromMitarbeiter(
          mitarbeiterId: mitarbeiterDoc.id,
          selectedDate: selectedDate,
          totalDurationMinutes: totalDurationMinutes,
        );

        for (final time in availability.times) {
          slotAssignments.putIfAbsent(
            time,
            () => _BookingSlotOption(
              time: time,
              mitarbeiterId: mitarbeiterDoc.id,
              mitarbeiterName: name,
            ),
          );
        }
      }

      final mergedTimes = slotAssignments.keys.toList()
        ..sort((a, b) {
          final minuteA = _parseHourMinute(a) ?? 0;
          final minuteB = _parseHourMinute(b) ?? 0;
          return minuteA.compareTo(minuteB);
        });

      if (mergedTimes.isEmpty) {
        return const _BookingTimeAvailability(
          times: <String>[],
          message: 'Keine freien Termine verfügbar.',
        );
      }

      return _BookingTimeAvailability(
        times: mergedTimes,
        slotAssignments: slotAssignments,
      );
    } catch (_) {
      return const _BookingTimeAvailability(
        times: <String>[],
        message: 'Keine freien Termine verfügbar.',
      );
    }
  }

  Future<void> _reloadBookingTimes({
    required Map<String, dynamic>? oeffnungszeiten,
    required int totalDurationMinutes,
  }) async {
    _BookingTimeAvailability availability;
    var slotAssignments = <String, _BookingSlotOption>{};
    if (_selectedMitarbeiterId != null &&
        _selectedMitarbeiterId!.trim().isNotEmpty) {
      availability = await _buildAvailabilityFromMitarbeiter(
        mitarbeiterId: _selectedMitarbeiterId!,
        selectedDate: _selectedBookingDate,
        totalDurationMinutes: totalDurationMinutes,
      );
      for (final time in availability.times) {
        slotAssignments[time] = _BookingSlotOption(
          time: time,
          mitarbeiterId: _selectedMitarbeiterId!.trim(),
          mitarbeiterName: _selectedMitarbeiterLabel.trim(),
        );
      }
    } else {
      availability = await _buildAvailabilityForAnyMitarbeiter(
        selectedDate: _selectedBookingDate,
        totalDurationMinutes: totalDurationMinutes,
      );
      slotAssignments = Map<String, _BookingSlotOption>.from(
        availability.slotAssignments,
      );
    }

    if (!mounted) return;
    setState(() {
      _selectedBookingTime = null;
      _selectedBookingSlotOption = null;
      _availableBookingTimes = List<String>.from(availability.times);
      _bookingSlotAssignments = slotAssignments;
      _bookingTimesHint = availability.message;
    });
  }

  String _formatBookingDate(DateTime date) {
    const weekdays = <String>[
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ];
    const months = <String>[
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];

    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    return '$weekday, ${date.day}. $month';
  }

  String _formatBookingDateWithYear(DateTime date) {
    return '${_formatBookingDate(date)} ${date.year}';
  }

  Future<void> _selectBookingDate({
    required BuildContext context,
    required Map<String, dynamic>? oeffnungszeiten,
    required int totalDurationMinutes,
  }) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedBookingDate,
      firstDate: _dateOnly(DateTime.now()),
      lastDate: _dateOnly(DateTime.now().add(const Duration(days: 365))),
    );

    if (!mounted || pickedDate == null) return;

    setState(() {
      _selectedBookingDate = _dateOnly(pickedDate);
    });
    await _reloadBookingTimes(
      oeffnungszeiten: oeffnungszeiten,
      totalDurationMinutes: totalDurationMinutes,
    );
  }

  Widget _buildDateTimeSection({
    required BuildContext context,
    required StateSetter setSheetState,
    required Map<String, dynamic>? oeffnungszeiten,
    required int totalDurationMinutes,
  }) {
    final hasSelectedDateTime = _selectedBookingTime != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          '2. Datum und Uhrzeit auswählen',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        if (!hasSelectedDateTime) ...[
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await _selectBookingDate(
                context: context,
                oeffnungszeiten: oeffnungszeiten,
                totalDurationMinutes: totalDurationMinutes,
              );
              if (context.mounted) {
                setSheetState(() {});
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDADDE5)),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatBookingDate(_selectedBookingDate),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _availableBookingTimes.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.15,
            ),
            itemBuilder: (context, index) {
              final time = _availableBookingTimes[index];
              final isSelected = _selectedBookingTime == time;

              return Material(
                color: isSelected ? Colors.black : const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selectedBookingTime = time;
                      _selectedBookingSlotOption = _bookingSlotAssignments[time];
                    });
                    setSheetState(() {});
                  },
                  child: Center(
                    child: Text(
                      time,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (_availableBookingTimes.isEmpty && _bookingTimesHint != null) ...[
            const SizedBox(height: 8),
            Text(
              _bookingTimesHint!,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFE4E7EC)),
                bottom: BorderSide(color: Color(0xFFE4E7EC)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatBookingDateWithYear(_selectedBookingDate),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF344054),
                        ),
                      ),
                      Text(
                        'um $_selectedBookingTime',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedBookingTime = null;
                    });
                    setSheetState(() {});
                  },
                  child: const Text(
                    'Bearbeiten',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8B84F6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoginSection(
      BuildContext context, {
        required StateSetter setSheetState,
      }) {
    _ensureBookingLoginStateFromCurrentUser(setSheetState: setSheetState);

    final state = _bookingLoginState;
    void updateLoginSectionState(VoidCallback updater) {
      setState(updater);
      setSheetState(() {});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const Divider(height: 1, color: Color(0xFFE4E7EC)),
        const SizedBox(height: 18),
        const Text(
          '3. Login',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF7269EA),
          ),
        ),
        const SizedBox(height: 18),
        if (state == _BookingLoginState.loginInitial) ...[
          const Text(
            'Neu bei Termini?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1D2939),
            ),
          ),
          const SizedBox(height: 12),
          _buildCreateAccountButton(context),
          const SizedBox(height: 16),
          _buildLoginOrDivider(),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              updateLoginSectionState(() {
                _bookingLoginState = _BookingLoginState.loginForm;
              });
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: const Color(0xFF181A1F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Einloggen',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ] else if (state == _BookingLoginState.loginForm) ...[
          const Text(
            'E-Mail *',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D2939),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bookingLoginEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'E-Mail'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Passwort *',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D2939),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bookingLoginPasswordController,
            obscureText: _bookingLoginObscurePassword,
            decoration: InputDecoration(
              hintText: 'Passwort',
              suffixIcon: IconButton(
                onPressed: () {
                  updateLoginSectionState(() {
                    _bookingLoginObscurePassword = !_bookingLoginObscurePassword;
                  });
                },
                icon: Icon(
                  _bookingLoginObscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwort vergessen ist noch nicht verfügbar.')),
                );
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: const Color(0xFF262D34),
              ),
              child: const Text(
                'Passwort vergessen?',
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _isBookingLoginLoading
                ? null
                : () => _handleBookingLogin(setSheetState: setSheetState),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: const Color(0xFF181A1F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isBookingLoginLoading
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Text(
              'Einloggen',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildLoginOrDivider(),
          const SizedBox(height: 16),
          _buildCreateAccountButton(context),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFE4E7EC)),
                bottom: BorderSide(color: Color(0xFFE4E7EC)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _bookingLoginName.isEmpty ? 'Kunde' : _bookingLoginName,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1D2939),
                        ),
                      ),
                      if (_bookingLoginEmail.isNotEmpty)
                        Text(
                          _bookingLoginEmail,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF667085),
                          ),
                        ),
                      if (_bookingLoginPhone.isNotEmpty)
                        Text(
                          _bookingLoginPhone,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF667085),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _handleBookingLogout(
                    setSheetState: setSheetState,
                  ),
                  child: const Text(
                    'Ausloggen',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8B84F6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoginOrDivider() {
    return Row(
      children: const [
        Expanded(child: Divider(color: Color(0xFFDDE1E8), thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ODER',
            style: TextStyle(
              color: Color(0xFF7B8190),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFFDDE1E8), thickness: 1)),
      ],
    );
  }

  Widget _buildCreateAccountButton(BuildContext context) {
    return OutlinedButton(
      onPressed: () => _openLoginScreen(context),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        side: const BorderSide(color: Color(0xFFBFC5D2)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Text(
        'Ein Konto erstellen',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF3A3F46),
        ),
      ),
    );
  }

  Future<void> _openLoginScreen(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginRegisterPage()),
    );
  }

  Future<void> _handleBookingLogin({
    required StateSetter setSheetState,
  }) async {
    final email = _bookingLoginEmailController.text.trim();
    final password = _bookingLoginPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte E-Mail und Passwort eingeben.')),
      );
      return;
    }

    setState(() {
      _isBookingLoginLoading = true;
    });
    setSheetState(() {});

    try {
      final authResult = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = authResult.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = userDoc.data();
      final name = (data?['name'] as String?)?.trim() ?? '';
      final profileEmail = (data?['email'] as String?)?.trim() ?? user.email ?? '';
      final phoneNumber = (data?['phoneNumber'] as String?)?.trim() ?? user.phoneNumber ?? '';

      if (!mounted) {
        return;
      }

      setState(() {
        _bookingLoginName = name;
        _bookingLoginEmail = profileEmail;
        _bookingLoginPhone = phoneNumber;
        _bookingLoginState = _BookingLoginState.loginSuccess;
        _bookingLoginSyncedUid = user.uid;
      });
      setSheetState(() {});
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.message ?? 'Login fehlgeschlagen.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login fehlgeschlagen.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBookingLoginLoading = false;
        });
        setSheetState(() {});
      }
    }
  }

  Future<void> _handleBookingLogout({
    required StateSetter setSheetState,
  }) async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) {
      return;
    }

    setState(() {
      _bookingLoginState = _BookingLoginState.loginInitial;
      _bookingLoginName = '';
      _bookingLoginEmail = '';
      _bookingLoginPhone = '';
      _bookingLoginEmailController.clear();
      _bookingLoginPasswordController.clear();
      _bookingLoginObscurePassword = true;
      _isBookingLoginLoading = false;
      _bookingLoginSyncedUid = null;
    });
    setSheetState(() {});
  }

  void _ensureBookingLoginStateFromCurrentUser({
    required StateSetter setSheetState,
  }) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      if (_bookingLoginState == _BookingLoginState.loginSuccess) {
        setState(() {
          _bookingLoginState = _BookingLoginState.loginInitial;
          _bookingLoginName = '';
          _bookingLoginEmail = '';
          _bookingLoginPhone = '';
          _bookingLoginSyncedUid = null;
        });
        setSheetState(() {});
      }
      return;
    }

    if (_isBookingLoginSyncInProgress) {
      return;
    }

    if (_bookingLoginState == _BookingLoginState.loginSuccess &&
        _bookingLoginSyncedUid == currentUser.uid) {
      return;
    }

    _isBookingLoginSyncInProgress = true;

    FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get()
        .then((snapshot) {
      if (!mounted) {
        return;
      }

      final data = snapshot.data();
      final email = (data?['email'] as String?)?.trim().isNotEmpty == true
          ? (data?['email'] as String).trim()
          : (currentUser.email ?? '').trim();
      final name = (data?['name'] as String?)?.trim().isNotEmpty == true
          ? (data?['name'] as String).trim()
          : (email.isNotEmpty ? email : 'Kunde');
      final phone = (data?['phoneNumber'] as String?)?.trim().isNotEmpty == true
          ? (data?['phoneNumber'] as String).trim()
          : (currentUser.phoneNumber ?? '').trim();

      setState(() {
        _bookingLoginName = name;
        _bookingLoginEmail = email;
        _bookingLoginPhone = phone;
        _bookingLoginState = _BookingLoginState.loginSuccess;
        _bookingLoginSyncedUid = currentUser.uid;
      });
      setSheetState(() {});
    }).catchError((_) {
      if (!mounted) {
        return;
      }

      final fallbackEmail = (currentUser.email ?? '').trim();
      final fallbackName = fallbackEmail.isNotEmpty ? fallbackEmail : 'Kunde';
      final fallbackPhone = (currentUser.phoneNumber ?? '').trim();

      setState(() {
        _bookingLoginName = fallbackName;
        _bookingLoginEmail = fallbackEmail;
        _bookingLoginPhone = fallbackPhone;
        _bookingLoginState = _BookingLoginState.loginSuccess;
        _bookingLoginSyncedUid = currentUser.uid;
      });
      setSheetState(() {});
    }).whenComplete(() {
      _isBookingLoginSyncInProgress = false;
    });
  }

  bool _canShowBookingConfirmButton({
    required Map<String, _CartItem> singles,
    required Map<String, _ComboSelection> combos,
  }) {
    final hasServices = singles.isNotEmpty || combos.isNotEmpty;
    final hasDateTime = _selectedBookingTime != null;
    final hasLoggedInUser = _bookingLoginState == _BookingLoginState.loginSuccess;
    return hasServices && hasDateTime && hasLoggedInUser;
  }

  DateTime? _buildBookingStartAt({
    required DateTime date,
    required String time,
  }) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time.trim());
    if (match == null) {
      return null;
    }

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Future<bool> _hasBookingCollision({
    required String mitarbeiterId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final dayStart = DateTime(startAt.year, startAt.month, startAt.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final snapshot = await FirebaseFirestore.instance
        .collection('termine')
        .where('mitarbeiterId', isEqualTo: mitarbeiterId)
        .where('startAt', isLessThan: Timestamp.fromDate(dayEnd))
        .where('endAt', isGreaterThan: Timestamp.fromDate(dayStart))
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final existingStart = _bookingDateTimeFromDynamic(data['startAt']);
      final existingEnd = _bookingDateTimeFromDynamic(data['endAt']);
      if (existingStart == null || existingEnd == null) {
        continue;
      }
      final overlaps = existingStart.isBefore(endAt) && existingEnd.isAfter(startAt);
      if (overlaps) {
        return true;
      }
    }

    return false;
  }

  DateTime? _bookingDateTimeFromDynamic(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String _bookingDateIso(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  bool _isActiveEmployee(Map<String, dynamic> data) {
    final rolle = (data['rolle'] as String?)?.trim().toLowerCase();
    return rolle == 'mitarbeiter' ;
  }

  Widget _buildMitarbeiterAvatar({
    required String name,
    String? profileImageUrl,
  }) {
    final trimmedName = name.trim();
    final trimmedUrl = profileImageUrl?.trim();

    if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFFE5E7EB),
        backgroundImage: NetworkImage(trimmedUrl),
      );
    }

    final initial = trimmedName.isNotEmpty
        ? trimmedName.characters.first.toUpperCase()
        : '?';

    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.black,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _openMitarbeiterSelectionSheet({
    required BuildContext context,
    required Map<String, dynamic>? oeffnungszeiten,
    required int totalDurationMinutes,
  }) async {
    final dienstleisterId = widget.dienstleister['id'] as String;

    final selectedOption = await showModalBottomSheet<_BookingMitarbeiterOption>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('dienstleisterId', isEqualTo: dienstleisterId)
                .where('aktiv', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              final mitarbeiterDocs = (snapshot.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  .where((doc) => _isActiveEmployee(doc.data()))
                  .toList()
                ..sort((a, b) {
                  final nameA = (a.data()['name'] as String? ?? '').trim();
                  final nameB = (b.data()['name'] as String? ?? '').trim();
                  return nameA.toLowerCase().compareTo(nameB.toLowerCase());
                });

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Mitarbeiter/in auswählen',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Beliebiger Mitarbeiter'),
                            trailing: Radio<String?>(
                              value: null,
                              groupValue: _selectedMitarbeiterId,
                              onChanged: (_) {
                                Navigator.of(sheetContext).pop(
                                  const _BookingMitarbeiterOption(
                                    id: null,
                                    label: 'Beliebiger Mitarbeiter',
                                  ),
                                );
                              },
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop(
                                const _BookingMitarbeiterOption(
                                  id: null,
                                  label: 'Beliebiger Mitarbeiter',
                                ),
                              );
                            },
                          ),
                          if (snapshot.connectionState == ConnectionState.waiting)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            ...mitarbeiterDocs.map((doc) {
                              final data = doc.data();
                              final name =
                              (data['name'] as String?)?.trim().isNotEmpty == true
                                  ? (data['name'] as String).trim()
                                  : 'Unbenannt';
                              final imageUrl =
                              (data['profileImageUrl'] as String?)?.trim();

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: _buildMitarbeiterAvatar(
                                  name: name,
                                  profileImageUrl: imageUrl,
                                ),
                                title: Text(name),
                                trailing: Radio<String?>(
                                  value: doc.id,
                                  groupValue: _selectedMitarbeiterId,
                                  onChanged: (_) {
                                    Navigator.of(sheetContext).pop(
                                      _BookingMitarbeiterOption(
                                        id: doc.id,
                                        label: name,
                                      ),
                                    );
                                  },
                                ),
                                onTap: () {
                                  Navigator.of(sheetContext).pop(
                                    _BookingMitarbeiterOption(
                                      id: doc.id,
                                      label: name,
                                    ),
                                  );
                                },
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (!mounted || selectedOption == null) return;

    setState(() {
      _selectedMitarbeiterId = selectedOption.id;
      _selectedMitarbeiterLabel = selectedOption.label;
    });
    await _reloadBookingTimes(
      oeffnungszeiten: oeffnungszeiten,
      totalDurationMinutes: totalDurationMinutes,
    );
  }

  Future<void> _openBookingSummaryPanel({
    required Map<String, _CartItem> singles,
    required Map<String, _ComboSelection> combos,
    required Map<String, Offer> singleBaseIndex,
    required List<Offer> bundles,
    required _CartTotals Function(
        Map<String, _CartItem> singles,
        Map<String, _ComboSelection> combos,
        ) computeTotals,
    required double total,
    required double savings,
  }) async {
    var panelSingles = Map<String, _CartItem>.from(singles);
    var panelCombos = Map<String, _ComboSelection>.from(combos);

    _BookingSummaryEntry _singleEntry(String key, _CartItem item) {
      final partLc = item.leistung.toLowerCase();
      final lockedDiscount = _validatedLockedDisplayPrice(
        item: item,
        selectionMap: panelSingles,
        combosMap: panelCombos,
        singleBaseIndex: singleBaseIndex,
        bundles: bundles,
      );
      final dynamicDiscount = _currentDiscountedSingleDisplayPrice(
        category: item.kategorie,
        zielgruppe: item.zielgruppe,
        partLc: partLc,
        selectionMap: panelSingles,
        combosMap: panelCombos,
        singleBaseIndex: singleBaseIndex,
        bundles: bundles,
      );
      final effectiveDiscount = lockedDiscount ?? dynamicDiscount;
      final hasDiscount =
          effectiveDiscount != null &&
              item.preis != null &&
              effectiveDiscount < item.preis!;

      return _BookingSummaryEntry(
        selectionKey: key,
        isCombo: false,
        selectedAt: item.selectedAt,
        categoryLabel: item.kategorie,
        title: item.leistung,
        subtitle: [item.varianteLabel]
            .where((e) => e != null && e.trim().isNotEmpty)
            .join(' • '),
        price: hasDiscount ? effectiveDiscount : item.preis,
        originalPrice: hasDiscount ? item.preis : null,
        duration: item.dauer,
      );
    }

    _BookingSummaryEntry _comboEntry(String key, _ComboSelection selection) {
      final comboPrice = selection.preis;
      final comboOriginal = selection.originalPrice ??
          selection.selectedPartsLc.fold<double>(
            0.0,
                (sum, partLc) =>
            sum +
                _singlePriceOfPart(
                  category: selection.bundle.kategorie,
                  zielgruppe: selection.zielgruppe,
                  partLc: partLc,
                  selectionMap: panelSingles,
                  singleBaseIndex: singleBaseIndex,
                ),
          );
      final hasDiscount =
          comboPrice != null && comboOriginal > 0 && comboOriginal > comboPrice;

      return _BookingSummaryEntry(
        selectionKey: key,
        isCombo: true,
        selectedAt: selection.selectedAt,
        categoryLabel: selection.bundle.kategorie,
        title: selection.selectedTitles.join(' + '),
        subtitle: [
          selection.varianteLabel ??
              _comboMethodLabelForDisplay(selection.bundle),
        ].where((e) => e != null && e.trim().isNotEmpty).join(' • '),
        price: comboPrice,
        originalPrice: hasDiscount ? comboOriginal : null,
        duration: selection.dauer,
      );
    }

    String _displayNameForPart({
      required String category,
      required String partLc,
      String? fallback,
    }) {
      final offer = singleBaseIndex['$category|$partLc'];
      if (offer != null && offer.leistungen.isNotEmpty) {
        return offer.leistungen.first;
      }
      if (fallback != null && fallback.trim().isNotEmpty) {
        return fallback;
      }
      if (partLc.isEmpty) return partLc;
      return partLc[0].toUpperCase() + partLc.substring(1);
    }

    List<_BookingSummarySuggestion> _buildSuggestions() {
      final selectedPartsByContext = <String, Set<String>>{};

      for (final item in panelSingles.values) {
        final contextKey = '${item.zielgruppe}|${item.kategorie}';
        selectedPartsByContext.putIfAbsent(contextKey, () => <String>{})
            .add(item.leistung.toLowerCase());
      }

      for (final combo in panelCombos.values) {
        final contextKey = '${combo.zielgruppe}|${combo.bundle.kategorie}';
        selectedPartsByContext.putIfAbsent(contextKey, () => <String>{})
            .addAll(combo.selectedPartsLc);
      }

      final suggestionsByKey = <String, _BookingSummarySuggestion>{};

      bool shouldReplaceSuggestion(
          _BookingSummarySuggestion current,
          _BookingSummarySuggestion next,
          ) {
        final currentPrice = current.price;
        final nextPrice = next.price;

        if (currentPrice == null) return nextPrice != null;
        if (nextPrice == null) return false;
        if (nextPrice < currentPrice) return true;
        if (nextPrice > currentPrice) return false;

        final currentSavings =
        current.originalPrice != null ? current.originalPrice! - currentPrice : 0.0;
        final nextSavings =
        next.originalPrice != null ? next.originalPrice! - nextPrice : 0.0;
        if (nextSavings > currentSavings) return true;
        if (nextSavings < currentSavings) return false;

        if (current.originalPrice == null && next.originalPrice != null) {
          return true;
        }

        return false;
      }

      void storeSuggestion(String key, _BookingSummarySuggestion suggestion) {
        final current = suggestionsByKey[key];
        if (current == null || shouldReplaceSuggestion(current, suggestion)) {
          suggestionsByKey[key] = suggestion;
        }
      }

      for (final bundle in bundles) {
        for (final context in selectedPartsByContext.entries) {
          final ctx = context.key.split('|');
          if (ctx.length != 2) continue;
          final zielgruppe = ctx[0];
          final category = ctx[1];
          if (bundle.kategorie != category) continue;
          if (!_hasZielgruppenData(bundle, zielgruppe)) continue;

          final selectedParts = context.value;
          final hasSelectedBundlePart =
          bundle.leistungenLc.any(selectedParts.contains);
          if (!hasSelectedBundlePart) continue;

          final bundleBaseParts = bundle.leistungenLc
              .where((partLc) => singleBaseIndex.containsKey('$category|$partLc'))
              .toSet();
          final missingPartIndexes = <int>[
            for (int i = 0; i < bundle.leistungenLc.length; i++)
              if (!selectedParts.contains(bundle.leistungenLc[i])) i,
          ];

          final canSuggestAsGroupedCombo =
              missingPartIndexes.length > 1 &&
                  bundleBaseParts.isNotEmpty &&
                  bundleBaseParts.every(selectedParts.contains);

          if (canSuggestAsGroupedCombo) {
            final missingPartLcs = [
              for (final index in missingPartIndexes) bundle.leistungenLc[index],
            ];
            final missingDisplayNames = [
              for (final index in missingPartIndexes) bundle.leistungen[index],
            ];
            final suggestionKey =
                '$zielgruppe|$category|combo|${missingPartLcs.join("+")}';
            final comboPrice = _previewForComboGroup(
              combo: bundle,
              category: category,
              zielgruppe: zielgruppe,
              requiredBasePartsLc: bundleBaseParts,
              selectedPartsLc: selectedParts,
              selectionMap: panelSingles,
              combosMap: panelCombos,
              singleBaseIndex: singleBaseIndex,
              bundles: bundles,
            );
            if (comboPrice == null) continue;

            final missingPartsSet = missingPartLcs.toSet();
            final matchingStandaloneCombo = bundles.where((offer) {
              if (offer.kategorie != category) return false;
              if (!_hasZielgruppenData(offer, zielgruppe)) return false;
              if (offer.leistungenLc.length != missingPartLcs.length) return false;
              return offer.leistungenLc.toSet().containsAll(missingPartsSet) &&
                  missingPartsSet.containsAll(offer.leistungenLc);
            }).fold<Offer?>(null, (best, offer) {
              if (best == null) return offer;
              final bestPrice = _bundlePriceForCombo(
                combo: best,
                zielgruppe: zielgruppe,
              );
              final offerPrice = _bundlePriceForCombo(
                combo: offer,
                zielgruppe: zielgruppe,
              );
              if (offerPrice == null) return best;
              if (bestPrice == null || offerPrice < bestPrice) return offer;
              return best;
            });

            double comboOriginal =
            matchingStandaloneCombo != null
                ? (_bundlePriceForCombo(
              combo: matchingStandaloneCombo,
              zielgruppe: zielgruppe,
            ) ??
                0.0)
                : 0.0;
            if (comboOriginal <= 0) {
              for (final partLc in missingPartLcs) {
                comboOriginal += _singlePriceOfPart(
                  category: category,
                  zielgruppe: zielgruppe,
                  partLc: partLc,
                  selectionMap: panelSingles,
                  singleBaseIndex: singleBaseIndex,
                );
              }
            }
            final hasDiscount = comboOriginal > 0 && comboPrice < comboOriginal;

            storeSuggestion(
              suggestionKey,
              _BookingSummarySuggestion(
                contextKey: suggestionKey,
                zielgruppe: zielgruppe,
                category: category,
                title: missingDisplayNames.join(' + '),
                displayNames: missingDisplayNames,
                partLcs: missingPartLcs,
                price: comboPrice,
                originalPrice: hasDiscount ? comboOriginal : null,
                duration: null,
                bundle: bundle,
              ),
            );
            continue;
          }

          for (int i = 0; i < bundle.leistungenLc.length; i++) {
            final partLc = bundle.leistungenLc[i];
            if (selectedParts.contains(partLc)) continue;

            final suggestionKey = '$zielgruppe|$category|$partLc';
            final baseOffer = singleBaseIndex['$category|$partLc'];
            final basePrice = baseOffer?.priceFor(zielgruppe);
            final duration = baseOffer?.durationFor(zielgruppe);
            final preview = _previewForLastMissingPart(
              category: category,
              zielgruppe: zielgruppe,
              partLc: partLc,
              selectedPartsLc: selectedParts,
              selectionMap: panelSingles,
              combosMap: panelCombos,
              singleBaseIndex: singleBaseIndex,
              bundles: bundles,
            );
            final hasDiscount =
                preview != null && basePrice != null && preview < basePrice;
            final suggestionPrice = hasDiscount
                ? preview
                : (basePrice ?? preview);
            final displayName = _displayNameForPart(
              category: category,
              partLc: partLc,
              fallback: i < bundle.leistungen.length ? bundle.leistungen[i] : null,
            );

            storeSuggestion(
              suggestionKey,
              _BookingSummarySuggestion(
                contextKey: suggestionKey,
                zielgruppe: zielgruppe,
                category: category,
                title: category.trim().isEmpty
                    ? displayName
                    : '$category - $displayName',
                displayNames: [displayName],
                partLcs: [partLc],
                price: suggestionPrice,
                originalPrice: hasDiscount ? basePrice : null,
                duration: duration,
              ),
            );
          }
        }
      }

      final result = suggestionsByKey.values.toList()
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return result;
    }

    List<_BookingSummarySuggestion> suggestions = _buildSuggestions();

    List<_BookingSummaryEntry> entries = [
      ...panelSingles.entries.map((entry) => _singleEntry(entry.key, entry.value)),
      ...panelCombos.entries.map((entry) => _comboEntry(entry.key, entry.value)),
    ]..sort((a, b) => a.selectedAt.compareTo(b.selectedAt));

    double panelTotal = total;
    double panelSavings = savings;
    bool isBookingSubmitting = false;
    bool bookingSuccess = false;
    Map<String, String> bookingSuccessSummary = {};
    final oeffnungszeiten = await _loadDienstleisterOeffnungszeiten();

    if (mounted) {
      await _reloadBookingTimes(
        oeffnungszeiten: oeffnungszeiten,
        totalDurationMinutes: _selectedDurationMinutes(
          singles: panelSingles,
          combos: panelCombos,
        ),
      );
    }

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
                            '${_selectedServiceCount(singles: panelSingles, combos: panelCombos)} '
                                'Leistungen ausgewählt',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: bookingSuccess
                              ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              const Text(
                                'Termin erfolgreich gebucht',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF101828),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F8FB),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE4E7EC),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      bookingSuccessSummary['datum'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'um ${bookingSuccessSummary['zeit'] ?? ''}',
                                      style: const TextStyle(
                                        color: Color(0xFF667085),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'bei ${bookingSuccessSummary['mitarbeiter'] ?? ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      bookingSuccessSummary['dienstleister'] ?? '',
                                      style: const TextStyle(
                                        color: Color(0xFF475467),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      bookingSuccessSummary['titel'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      bookingSuccessSummary['preis'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF181A1F),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                              : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              const Text(
                                '1. Ausgewählte Leistungen',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              for (var i = 0; i < entries.length; i++) ...[
                                if (i > 0)
                                  const SizedBox(height: 12),
                                Builder(
                                  builder: (_) {
                                    final entry = entries[i];
                                    final categoryLabel = entry.categoryLabel?.trim();
                                    final showCategoryHeader =
                                        categoryLabel != null &&
                                            categoryLabel.isNotEmpty &&
                                            (i == 0 ||
                                                entries[i - 1].categoryLabel?.trim() !=
                                                    categoryLabel);
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (showCategoryHeader)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            color: Colors.black,
                                            child: Text(
                                              categoryLabel,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        if (showCategoryHeader)
                                          const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            color: const Color(0xFFF7F8FB),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                        padding:
                                                        const EdgeInsets.only(
                                                          top: 2,
                                                        ),
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
                                                        padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
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
                                              Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                                children: [
                                                  if (entry.originalPrice != null)
                                                    Text(
                                                      _formatEuro(
                                                        entry.originalPrice!,
                                                      ),
                                                      style: const TextStyle(
                                                        color: Colors.black45,
                                                        fontSize: 12.5,
                                                        fontWeight:
                                                        FontWeight.w500,
                                                        decoration:
                                                        TextDecoration
                                                            .lineThrough,
                                                        decorationThickness: 2,
                                                      ),
                                                    ),
                                                  Text(
                                                    entry.price == null
                                                        ? '–'
                                                        : _formatEuro(entry.price!),
                                                    style: TextStyle(
                                                      fontWeight:
                                                      FontWeight.w700,
                                                      color: entry.originalPrice !=
                                                          null
                                                          ? Colors.green
                                                          : null,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              IconButton(
                                                tooltip: 'Leistung entfernen',
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 20,
                                                ),
                                                onPressed: () async {
                                                  final singlesMap =
                                                  Map<String, _CartItem>.from(
                                                    _selectedVN.value,
                                                  );
                                                  final combosMap = Map<
                                                      String,
                                                      _ComboSelection>.from(
                                                    _selectedCombosVN.value,
                                                  );

                                                  if (entry.isCombo) {
                                                    combosMap.remove(
                                                      entry.selectionKey,
                                                    );
                                                  } else {
                                                    final removedItem =
                                                    singlesMap.remove(
                                                      entry.selectionKey,
                                                    );
                                                    if (removedItem != null) {
                                                      _removeDependentSelections(
                                                        selectionMap: singlesMap,
                                                        zielgruppe:
                                                        removedItem.zielgruppe,
                                                        category:
                                                        removedItem.kategorie,
                                                        removedPartLc: removedItem
                                                            .leistung
                                                            .toLowerCase(),
                                                      );
                                                      _removeDependentComboSelections(
                                                        combosMap: combosMap,
                                                        zielgruppe:
                                                        removedItem.zielgruppe,
                                                        category:
                                                        removedItem.kategorie,
                                                        removedPartLc:
                                                        removedItem.leistung
                                                            .toLowerCase(),
                                                        bundles: bundles,
                                                      );
                                                    }
                                                  }

                                                  _clearInvalidLockedPrices(
                                                    selectionMap: singlesMap,
                                                    singleBaseIndex:
                                                    singleBaseIndex,
                                                    bundles: bundles,
                                                  );
                                                  _refreshComboSelections(
                                                    selectionMap: singlesMap,
                                                    combosMap: combosMap,
                                                    singleBaseIndex:
                                                    singleBaseIndex,
                                                    bundles: bundles,
                                                  );

                                                  _selectedVN.value = singlesMap;
                                                  _selectedCombosVN.value =
                                                      combosMap;
                                                  panelSingles = singlesMap;
                                                  panelCombos = combosMap;

                                                  entries = [
                                                    ...panelSingles.entries.map(
                                                          (e) => _singleEntry(
                                                        e.key,
                                                        e.value,
                                                      ),
                                                    ),
                                                    ...panelCombos.entries.map(
                                                          (e) => _comboEntry(
                                                        e.key,
                                                        e.value,
                                                      ),
                                                    ),
                                                  ]
                                                    ..sort(
                                                          (a, b) => a.selectedAt
                                                          .compareTo(
                                                        b.selectedAt,
                                                      ),
                                                    );
                                                  suggestions =
                                                      _buildSuggestions();

                                                  final totals = computeTotals(
                                                    singlesMap,
                                                    combosMap,
                                                  );
                                                  panelTotal = totals.optimized;
                                                  panelSavings = totals.savings;
                                                  await _reloadBookingTimes(
                                                    oeffnungszeiten: oeffnungszeiten,
                                                    totalDurationMinutes:
                                                    _selectedDurationMinutes(
                                                      singles: singlesMap,
                                                      combos: combosMap,
                                                    ),
                                                  );

                                                  if (entries.isEmpty) {
                                                    Navigator.of(ctx).pop();
                                                    return;
                                                  }

                                                  setSheetState(() {});
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                              const SizedBox(height: 16),
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  await _openMitarbeiterSelectionSheet(
                                    context: ctx,
                                    oeffnungszeiten: oeffnungszeiten,
                                    totalDurationMinutes: _selectedDurationMinutes(
                                      singles: panelSingles,
                                      combos: panelCombos,
                                    ),
                                  );
                                  if (ctx.mounted) {
                                    setSheetState(() {});
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFDADDE5),
                                    ),
                                    color: Colors.white,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _selectedMitarbeiterLabel,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      const Icon(Icons.keyboard_arrow_down),
                                    ],
                                  ),
                                ),
                              ),
                              _buildDateTimeSection(
                                context: ctx,
                                setSheetState: setSheetState,
                                oeffnungszeiten: oeffnungszeiten,
                                totalDurationMinutes: _selectedDurationMinutes(
                                  singles: panelSingles,
                                  combos: panelCombos,
                                ),
                              ),
                              if (_selectedBookingTime != null)
                                _buildLoginSection(
                                  ctx,
                                  setSheetState: setSheetState,
                                ),
                              if (suggestions.isNotEmpty) ...[
                                if (entries.isNotEmpty)
                                  const SizedBox(height: 20),
                                const Text(
                                  'Passend kombinierbar',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                for (var i = 0; i < suggestions.length; i++) ...[
                                  if (i > 0)
                                    const SizedBox(height: 10),
                                  Builder(
                                    builder: (_) {
                                      final suggestion = suggestions[i];
                                      return Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                          BorderRadius.circular(12),
                                          color: const Color(0xFFF7F8FB),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    suggestion.title,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                      FontWeight.w700,
                                                    ),
                                                  ),
                                                  if (suggestion.duration != null)
                                                    Padding(
                                                      padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                      child: Text(
                                                        '${suggestion.duration} Min',
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                              children: [
                                                if (suggestion.originalPrice !=
                                                    null)
                                                  Text(
                                                    _formatEuro(
                                                      suggestion.originalPrice!,
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.black45,
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                      FontWeight.w500,
                                                      decoration:
                                                      TextDecoration
                                                          .lineThrough,
                                                      decorationThickness: 2,
                                                    ),
                                                  ),
                                                Text(
                                                  suggestion.price == null
                                                      ? '–'
                                                      : _formatEuro(
                                                    suggestion.price!,
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: suggestion
                                                        .originalPrice !=
                                                        null
                                                        ? Colors.green
                                                        : null,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            IconButton(
                                              tooltip: 'Leistung hinzufügen',
                                              icon: const Icon(
                                                Icons.add_circle_outline,
                                                size: 20,
                                              ),
                                              onPressed: suggestion.price == null
                                                  ? null
                                                  : () {
                                                if (_hasItemsFromOtherZielgruppe(
                                                  suggestion.zielgruppe,
                                                )) {
                                                  final other = _selectedVN
                                                      .value
                                                      .values
                                                      .isNotEmpty
                                                      ? _selectedVN
                                                      .value
                                                      .values
                                                      .first
                                                      .zielgruppe
                                                      : _selectedCombosVN
                                                      .value
                                                      .values
                                                      .first
                                                      .zielgruppe;
                                                  _showWrongGroupSnack(
                                                    other,
                                                  );
                                                  return;
                                                }

                                                final singlesMap = Map<String,
                                                    _CartItem>.from(
                                                  _selectedVN.value,
                                                );
                                                final combosMap = Map<String,
                                                    _ComboSelection>.from(
                                                  _selectedCombosVN.value,
                                                );

                                                if (suggestion.isComboSuggestion) {
                                                  final bundle = suggestion.bundle;
                                                  if (bundle == null) return;
                                                  Offer targetBundle = bundle;
                                                  for (final candidate in bundles) {
                                                    if (candidate.kategorie !=
                                                        suggestion.category ||
                                                        !_hasZielgruppenData(
                                                          candidate,
                                                          suggestion.zielgruppe,
                                                        ) ||
                                                        candidate.leistungenLc.length !=
                                                            suggestion.partLcs.length) {
                                                      continue;
                                                    }
                                                    if (!suggestion.partLcs.every(
                                                      candidate.leistungenLc.contains,
                                                    )) {
                                                      continue;
                                                    }
                                                    targetBundle = candidate;
                                                    break;
                                                  }

                                                  combosMap.removeWhere(
                                                        (_, comboSel) =>
                                                    comboSel.zielgruppe ==
                                                        suggestion.zielgruppe &&
                                                        comboSel.bundle.kategorie ==
                                                            suggestion.category &&
                                                        comboSel.selectedPartsLc.any(
                                                          suggestion.partLcs.contains,
                                                        ),
                                                  );

                                                  combosMap[_comboSelectionKey(
                                                    zielgruppe:
                                                    suggestion.zielgruppe,
                                                    combo: targetBundle,
                                                  )] = _ComboSelection(
                                                    bundle: targetBundle,
                                                    zielgruppe:
                                                    suggestion.zielgruppe,
                                                    selectedAt:
                                                    ++_selectionTicker,
                                                    preis: suggestion.price,
                                                    dauer: suggestion.duration,
                                                    originalPrice:
                                                    suggestion.originalPrice,
                                                    selectedPartsDisplay:
                                                    suggestion.displayNames,
                                                    selectedPartsLcOverride:
                                                    suggestion.partLcs,
                                                  );

                                                  _selectedVN.value =
                                                      singlesMap;
                                                  _selectedCombosVN.value =
                                                      combosMap;
                                                  panelSingles = singlesMap;
                                                  panelCombos = combosMap;

                                                  entries = [
                                                    ...panelSingles.entries.map(
                                                          (e) => _singleEntry(
                                                        e.key,
                                                        e.value,
                                                      ),
                                                    ),
                                                    ...panelCombos.entries.map(
                                                          (e) => _comboEntry(
                                                        e.key,
                                                        e.value,
                                                      ),
                                                    ),
                                                  ]
                                                    ..sort(
                                                          (a, b) => a.selectedAt
                                                          .compareTo(
                                                        b.selectedAt,
                                                      ),
                                                    );
                                                  suggestions =
                                                      _buildSuggestions();

                                                  final totals = computeTotals(
                                                    singlesMap,
                                                    combosMap,
                                                  );
                                                  panelTotal =
                                                      totals.optimized;
                                                  panelSavings =
                                                      totals.savings;

                                                  setSheetState(() {});
                                                  return;
                                                }

                                                final selectionKey =
                                                _keyFor(
                                                  zielgruppe:
                                                  suggestion.zielgruppe,
                                                  category:
                                                  suggestion.category,
                                                  partLc: suggestion.partLc,
                                                );
                                                if (singlesMap
                                                    .containsKey(
                                                  selectionKey,
                                                )) {
                                                  return;
                                                }

                                                final baseOffer =
                                                singleBaseIndex[
                                                '${suggestion.category}|${suggestion.partLc}'];
                                                final singlePrice =
                                                baseOffer?.priceFor(
                                                  suggestion.zielgruppe,
                                                );
                                                final singleDuration =
                                                baseOffer?.durationFor(
                                                  suggestion.zielgruppe,
                                                );

                                                final basePriceForSelection =
                                                    singlePrice ??
                                                        suggestion.price;
                                                final durationForSelection =
                                                    suggestion.duration ??
                                                        singleDuration;

                                                final computedLocked =
                                                _lockedPriceForNewSelection(
                                                  category:
                                                  suggestion.category,
                                                  zielgruppe:
                                                  suggestion.zielgruppe,
                                                  newPartLc:
                                                  suggestion.partLc,
                                                  selectionMap:
                                                  singlesMap,
                                                  singleBaseIndex:
                                                  singleBaseIndex,
                                                  bundles: bundles,
                                                  newPartSinglePrice:
                                                  basePriceForSelection,
                                                );
                                                final locked =
                                                (suggestion.originalPrice !=
                                                    null &&
                                                    suggestion.price !=
                                                        null &&
                                                    basePriceForSelection !=
                                                        null &&
                                                    suggestion.price! <
                                                        basePriceForSelection)
                                                    ? suggestion.price
                                                    : computedLocked;

                                                singlesMap[selectionKey] =
                                                    _CartItem(
                                                      kategorie:
                                                      suggestion.category,
                                                      leistung: suggestion
                                                          .displayName,
                                                      preis:
                                                      basePriceForSelection,
                                                      dauer:
                                                      durationForSelection,
                                                      zielgruppe: suggestion
                                                          .zielgruppe,
                                                      selectedAt:
                                                      ++_selectionTicker,
                                                      lockedDisplayPrice: locked,
                                                    );

                                                combosMap.removeWhere(
                                                      (_, combo) =>
                                                  combo.zielgruppe ==
                                                      suggestion
                                                          .zielgruppe &&
                                                      combo.bundle.kategorie ==
                                                          suggestion
                                                              .category &&
                                                      combo.selectedPartsLc
                                                          .contains(
                                                        suggestion.partLc,
                                                      ),
                                                );

                                                _clearInvalidLockedPrices(
                                                  selectionMap: singlesMap,
                                                  singleBaseIndex:
                                                  singleBaseIndex,
                                                  bundles: bundles,
                                                );

                                                _selectedVN.value =
                                                    singlesMap;
                                                _selectedCombosVN.value =
                                                    combosMap;
                                                panelSingles = singlesMap;
                                                panelCombos = combosMap;

                                                entries = [
                                                  ...panelSingles.entries.map(
                                                        (e) => _singleEntry(
                                                      e.key,
                                                      e.value,
                                                    ),
                                                  ),
                                                  ...panelCombos.entries.map(
                                                        (e) => _comboEntry(
                                                      e.key,
                                                      e.value,
                                                    ),
                                                  ),
                                                ]
                                                  ..sort(
                                                        (a, b) => a.selectedAt
                                                        .compareTo(
                                                      b.selectedAt,
                                                    ),
                                                  );
                                                suggestions =
                                                    _buildSuggestions();

                                                final totals = computeTotals(
                                                  singlesMap,
                                                  combosMap,
                                                );
                                                panelTotal =
                                                    totals.optimized;
                                                panelSavings =
                                                    totals.savings;

                                                setSheetState(() {});
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            children: [
                              if (bookingSuccess)
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      widget.onNavigateToTermine?.call();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(54),
                                      backgroundColor: const Color(0xFF181A1F),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'Zu meinen Terminen',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                )
                              else ...[
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
                                if (_canShowBookingConfirmButton(
                                  singles: panelSingles,
                                  combos: panelCombos,
                                )) ...[
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: isBookingSubmitting
                                          ? null
                                          : () async {
                                        if (entries.isEmpty) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                              content: Text('Bitte wählen Sie mindestens eine Leistung.'),
                                            ),
                                          );
                                          return;
                                        }

                                        final selectedTime = _selectedBookingTime;
                                        if (selectedTime == null ||
                                            selectedTime.trim().isEmpty) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                              content: Text('Bitte wählen Sie eine Uhrzeit aus.'),
                                            ),
                                          );
                                          return;
                                        }

                                        final currentUser = FirebaseAuth.instance.currentUser;
                                        if (currentUser == null ||
                                            _bookingLoginState != _BookingLoginState.loginSuccess) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                              content: Text('Bitte loggen Sie sich ein.'),
                                            ),
                                          );
                                          return;
                                        }

                                        String mitarbeiterId =
                                            _selectedMitarbeiterId?.trim() ?? '';
                                        String mitarbeiterName =
                                            _selectedMitarbeiterLabel.trim();
                                        if (mitarbeiterId.isEmpty) {
                                          final selectedSlotOption =
                                              _selectedBookingSlotOption?.time ==
                                                      selectedTime.trim()
                                                  ? _selectedBookingSlotOption
                                                  : _bookingSlotAssignments[
                                                      selectedTime.trim()];
                                          if (selectedSlotOption != null) {
                                            mitarbeiterId =
                                                selectedSlotOption.mitarbeiterId;
                                            mitarbeiterName =
                                                selectedSlotOption.mitarbeiterName;
                                          }
                                        }

                                        if (mitarbeiterId.isEmpty) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Dieser Termin ist leider nicht mehr verfügbar. Bitte wählen Sie eine andere Uhrzeit.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        final startAt = _buildBookingStartAt(
                                          date: _selectedBookingDate,
                                          time: selectedTime,
                                        );
                                        final durationMinutes =
                                        _selectedDurationMinutes(
                                          singles: panelSingles,
                                          combos: panelCombos,
                                        );

                                        if (startAt == null || durationMinutes <= 0) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                              content: Text('Terminzeit konnte nicht ermittelt werden.'),
                                            ),
                                          );
                                          return;
                                        }

                                        final endAt = startAt.add(
                                          Duration(minutes: durationMinutes),
                                        );
                                        final kundeId = currentUser.uid.trim();
                                        if (kundeId.isEmpty) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                              content: Text('Kundendaten konnten nicht ermittelt werden.'),
                                            ),
                                          );
                                          return;
                                        }

                                        setSheetState(() {
                                          isBookingSubmitting = true;
                                        });

                                        try {
                                          final hasCollision =
                                          await _hasBookingCollision(
                                            mitarbeiterId: mitarbeiterId,
                                            startAt: startAt,
                                            endAt: endAt,
                                          );

                                          if (hasCollision) {
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(ctx).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Dieser Termin ist leider nicht mehr verfügbar. Bitte wählen Sie eine andere Uhrzeit.',
                                                  ),
                                                ),
                                              );
                                            }
                                            return;
                                          }

                                          final dienstleisterId =
                                          (widget.dienstleister['id'] as String? ?? '')
                                              .trim();
                                          if (dienstleisterId.isEmpty) {
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              const SnackBar(
                                                content: Text('Dienstleister konnte nicht ermittelt werden.'),
                                              ),
                                            );
                                            return;
                                          }

                                          final dienstleisterName =
                                          (widget.dienstleister['name']
                                          as String? ??
                                              widget
                                                  .dienstleister['titel']
                                              as String? ??
                                              '')
                                              .trim();
                                          final kundeName =
                                          _bookingLoginName.trim().isNotEmpty
                                              ? _bookingLoginName.trim()
                                              : (_bookingLoginEmail.trim().isNotEmpty
                                              ? _bookingLoginEmail.trim()
                                              : 'Kunde');
                                          final kundeEmail =
                                          _bookingLoginEmail.trim();
                                          final kundePhone =
                                          _bookingLoginPhone.trim();
                                          final titel = entries
                                              .map((entry) => entry.title)
                                              .where((title) => title.trim().isNotEmpty)
                                              .join(' • ');
                                          final leistungen = entries
                                              .map((entry) => entry.title)
                                              .where((title) => title.trim().isNotEmpty)
                                              .toList(growable: false);
                                          final leistungsPositionen = entries
                                              .map((entry) => <String, dynamic>{
                                            'category': (entry.categoryLabel ?? '').trim(),
                                            'title': entry.title.trim(),
                                            'subtitle': entry.subtitle.trim(),
                                            'price': entry.price,
                                            'originalPrice': entry.originalPrice,
                                            'duration': entry.duration,
                                          })
                                              .toList(growable: false);
                                          final now = Timestamp.now();

                                          await FirebaseFirestore.instance
                                              .collection('termine')
                                              .add({
                                            'dienstleisterId': dienstleisterId,
                                            'dienstleisterName': dienstleisterName,
                                            'mitarbeiterId': mitarbeiterId,
                                            'mitarbeiterName': mitarbeiterName,
                                            'kundeId': kundeId,
                                            'kundeName': kundeName,
                                            'kundeEmail': kundeEmail,
                                            'kundePhone': kundePhone,
                                            'titel': titel,
                                            'leistungen': leistungen,
                                            'leistungsPositionen': leistungsPositionen,
                                            'datum': _bookingDateIso(
                                              _selectedBookingDate,
                                            ),
                                            'startZeit': selectedTime,
                                            'endZeit': _formatHourMinute(
                                              (endAt.hour * 60) + endAt.minute,
                                            ),
                                            'startAt': Timestamp.fromDate(
                                              startAt,
                                            ),
                                            'endAt': Timestamp.fromDate(endAt),
                                            'preisGesamt': panelTotal,
                                            'dauerGesamt': durationMinutes,
                                            'status': 'bestaetigt',
                                            'quelle': 'kunde',
                                            'createdAt': now,
                                            'updatedAt': now,
                                          });

                                          if (!ctx.mounted) {
                                            return;
                                          }

                                          setSheetState(() {
                                            bookingSuccess = true;
                                            bookingSuccessSummary = {
                                              'datum':
                                              _formatBookingDateWithYear(
                                                _selectedBookingDate,
                                              ),
                                              'zeit': selectedTime,
                                              'mitarbeiter': mitarbeiterName,
                                              'dienstleister':
                                              dienstleisterName,
                                              'titel': titel,
                                              'preis': _formatEuro(
                                                panelTotal,
                                              ),
                                            };
                                          });
                                        } on FirebaseException catch (error) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  error.message ??
                                                      'Buchung konnte nicht gespeichert werden.',
                                                ),
                                              ),
                                            );
                                          }
                                        } catch (_) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              const SnackBar(
                                                content: Text('Buchung konnte nicht gespeichert werden.'),
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (ctx.mounted) {
                                            setSheetState(() {
                                              isBookingSubmitting = false;
                                            });
                                          }
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(54),
                                        backgroundColor: const Color(0xFF181A1F),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: isBookingSubmitting
                                          ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                          : const Text(
                                        'Bestätigen',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
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
                                    combo.selectedPartsLc.contains(base.leistungenLc.first),
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
    required Map<String, Offer> singleBaseIndex,
    required List<Offer> bundles,
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
            final selectedPartsLc = _selectedVN.value.values
                .where((it) => it.kategorie == category && it.zielgruppe == zg)
                .map((it) => it.leistung.toLowerCase())
                .toSet();
            final previewPriceForButton = _previewForStandaloneComboOffer(
              combo: selectedOffer,
              category: category,
              zielgruppe: zg,
              selectedPartsLc: selectedPartsLc,
              selectionMap: _selectedVN.value,
              singleBaseIndex: singleBaseIndex,
              bundles: bundles,
              comboPriceOverride: priceForButton,
            );
            final effectivePriceForButton = previewPriceForButton ?? priceForButton;

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
                        effectivePriceForButton != null
                            ? _formatEuro(effectivePriceForButton!)
                            : '–',
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
                        final optionPreviewPrice = _previewForStandaloneComboOffer(
                          combo: option.offer,
                          category: category,
                          zielgruppe: zg,
                          selectedPartsLc: selectedPartsLc,
                          selectionMap: _selectedVN.value,
                          singleBaseIndex: singleBaseIndex,
                          bundles: bundles,
                          comboPriceOverride: optionPrice,
                        );
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
                            '${_preisText(optionPreviewPrice ?? optionPrice)}${_dauerText(optionDuration)}',
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
                        final previewPrice = _previewForStandaloneComboOffer(
                          combo: selectedOffer,
                          category: category,
                          zielgruppe: zg,
                          selectedPartsLc: selectedPartsLc,
                          selectionMap: _selectedVN.value,
                          singleBaseIndex: singleBaseIndex,
                          bundles: bundles,
                          comboPriceOverride: p,
                        );
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Radio<String>(
                            value: k,
                            groupValue: selectedSizeKey,
                            onChanged: (val) => setSheetState(() => selectedSizeKey = val),
                          ),
                          title: Text(k),
                          trailing: Text(
                            '${_preisText(previewPrice ?? p)}${_dauerText(d)}',
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
                              preis: effectivePriceForButton,
                              dauer: durationForButton,
                              originalPrice:
                              priceForButton != null &&
                                  effectivePriceForButton != null &&
                                  effectivePriceForButton < priceForButton
                                  ? priceForButton
                                  : null,
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
                                effectivePriceForButton == null
                                    ? ''
                                    : _formatEuro(effectivePriceForButton!),
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
                              originalPrice: null,
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
    final String logoUrl = (widget.dienstleister['logoUrl'] ?? '').toString().trim();

    final bilderStream = FirebaseFirestore.instance
        .collection('users')
        .doc(dienstleisterId)
        .collection('bilder')
        .orderBy('createdAt', descending: true)
        .snapshots();

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
          selectedColor: Colors.black,
          unselectedColor: Colors.white,
          pressedColor: const Color(0xFFECECEC),
          padding: EdgeInsets.zero,
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 190,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: bilderStream,
              builder: (context, snapshot) {
                final bildUrls = <String>[];
                if (logoUrl.isNotEmpty) {
                  bildUrls.add(logoUrl);
                }
                if (snapshot.hasData) {
                  for (final doc in snapshot.data!.docs) {
                    final url = (doc.data()['url'] ?? '').toString().trim();
                    if (url.isEmpty) continue;
                    if (url == logoUrl) continue;
                    bildUrls.add(url);
                  }
                }

                if (bildUrls.isEmpty) {
                  return Container(color: const Color(0xFFF2F2F2));
                }

                final pageCount = bildUrls.length;
                if (_aktuellerBildIndex >= pageCount) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _aktuellerBildIndex = 0);
                    _zurBildSeite(0);
                  });
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _bilderPageController,
                      itemCount: pageCount,
                      onPageChanged: (index) {
                        if (!mounted) return;
                        setState(() => _aktuellerBildIndex = index);
                      },
                      itemBuilder: (context, index) {
                        return Image.network(
                          bildUrls[index],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(color: const Color(0xFFF2F2F2)),
                        );
                      },
                    ),
                    if (pageCount > 1)
                      Positioned(
                        left: 10,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _BildNavButton(
                            icon: Icons.chevron_left,
                            onTap: _aktuellerBildIndex > 0
                                ? () => _zurBildSeite(_aktuellerBildIndex - 1)
                                : null,
                          ),
                        ),
                      ),
                    if (pageCount > 1)
                      Positioned(
                        right: 10,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _BildNavButton(
                            icon: Icons.chevron_right,
                            onTap: _aktuellerBildIndex < pageCount - 1
                                ? () => _zurBildSeite(_aktuellerBildIndex + 1)
                                : null,
                          ),
                        ),
                      ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x99000000),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${(_aktuellerBildIndex + 1).clamp(1, pageCount)}/$pageCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: AngeboteView(
              angeboteStream: FirebaseFirestore.instance
                  .collection('angebote')
                  .where('dienstleisterId', isEqualTo: dienstleisterId)
                  .snapshots(),
              builder: (context, docs) {
                // ---- Docs in Modelle umwandeln, Singles/Bundles trennen ----
                final all = docs.map((d) => Offer.fromDoc(d)).toList();

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

                    final hasStandaloneComboForMissingParts = list.any((otherCombo) {
                      if (identical(otherCombo, combo)) return false;
                      final otherHasBasePart =
                      otherCombo.leistungenLc.any(baseParts.contains);
                      if (otherHasBasePart) return false;
                      if (otherCombo.leistungenLc.length != missingParts.length) {
                        return false;
                      }
                      return missingParts.every(otherCombo.leistungenLc.contains);
                    });
                    if (hasStandaloneComboForMissingParts) continue;

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

                    double _singleOptimizedPriceAt(int idx) {
                      final basePrice = _singlePriceAt(idx);
                      final discounted = _currentDiscountedSingleDisplayPrice(
                        category: cat,
                        zielgruppe: zg,
                        partLc: partsLc[idx],
                        selectionMap: map,
                        combosMap: combos,
                        singleBaseIndex: singleBaseIndex,
                        bundles: bundles,
                      );
                      if (discounted != null && discounted < basePrice) {
                        return discounted;
                      }
                      return basePrice;
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
                      if (!used[i]) optimized += _singleOptimizedPriceAt(i);
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

                              final combosMap = _selectedCombosVN.value;
                              final selectedPartsLc = _selectedPartsForContext(
                                zielgruppe: _zielgruppe,
                                category: kat,
                                selectionMap: map,
                                combosMap: combosMap,
                              );

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
                                  final lockedDiscount = selectedItem == null
                                      ? null
                                      : _validatedLockedDisplayPrice(
                                    item: selectedItem,
                                    selectionMap: map,
                                    combosMap: combosMap,
                                    singleBaseIndex: singleBaseIndex,
                                    bundles: bundles,
                                  );
                                  final dynamicDiscount = selectedItem == null
                                      ? null
                                      : _currentDiscountedSingleDisplayPrice(
                                    category: kat,
                                    zielgruppe: _zielgruppe,
                                    partLc: partLc,
                                    selectionMap: map,
                                    combosMap: combosMap,
                                    singleBaseIndex: singleBaseIndex,
                                    bundles: bundles,
                                  );
                                  final effectiveDiscount = lockedDiscount ?? dynamicDiscount;
                                  if (effectiveDiscount != null &&
                                      effectivePrice != null &&
                                      effectiveDiscount < effectivePrice) {
                                    newPrice = effectiveDiscount;
                                  }
                                } else {
                                  preview = _previewForLastMissingPart(
                                    category: kat,
                                    zielgruppe: _zielgruppe,
                                    partLc: partLc,
                                    selectedPartsLc: selectedPartsLc,
                                    selectionMap: map,
                                    combosMap: combosMap,
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
                                    final lockedDiscount = selectedItem == null
                                        ? null
                                        : _validatedLockedDisplayPrice(
                                      item: selectedItem,
                                      selectionMap: map,
                                      combosMap: combosMap,
                                      singleBaseIndex: singleBaseIndex,
                                      bundles: bundles,
                                    );
                                    final dynamicDiscount = selectedItem == null
                                        ? null
                                        : _currentDiscountedSingleDisplayPrice(
                                      category: kat,
                                      zielgruppe: _zielgruppe,
                                      partLc: partLc,
                                      selectionMap: map,
                                      combosMap: combosMap,
                                      singleBaseIndex: singleBaseIndex,
                                      bundles: bundles,
                                    );
                                    final effectiveDiscount = lockedDiscount ?? dynamicDiscount;
                                    if (effectiveDiscount != null &&
                                        variantEffectivePrice != null &&
                                        effectiveDiscount < variantEffectivePrice) {
                                      newPrice = effectiveDiscount;
                                    }
                                  } else {
                                    preview = _previewForLastMissingPart(
                                      category: kat,
                                      zielgruppe: _zielgruppe,
                                      partLc: partLc,
                                      selectedPartsLc: selectedPartsLc,
                                      selectionMap: map,
                                      combosMap: combosMap,
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
                                              _toggleSelection(
                                                selKey,
                                                existing,
                                                singleBaseIndex: singleBaseIndex,
                                                bundles: bundles,
                                              );
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
                                            combosMap: combosMap,
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
                                                combo.selectedPartsLc.contains(partLc),
                                          );

                                          _selectedVN.value = currentMap;
                                          _selectedCombosVN.value = combosMap;
                                        },
                                        icon: Icon(
                                          selectedThis
                                              ? Icons.check_circle
                                              : Icons.add_circle_outline,
                                        ),
                                        color: selectedThis ? Colors.blueAccent : null,
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

                                    return Column(
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
                                    );
                                  },
                                );
                              }

                              return Column(
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
                                            final previewPrice =
                                            _previewForLastMissingPart(
                                              category: kat,
                                              zielgruppe: _zielgruppe,
                                              partLc: partLc,
                                              selectedPartsLc: selectedPartsLc,
                                              selectionMap: currentMap,
                                              combosMap: _selectedCombosVN.value,
                                              singleBaseIndex: singleBaseIndex,
                                              bundles: bundles,
                                            );
                                            final priceForSelection = isDerivedSingle
                                                ? (previewPrice ?? singlePrice)
                                                : (singlePrice ?? previewPrice);

                                            final locked =
                                            _lockedPriceForNewSelection(
                                              category: kat,
                                              zielgruppe: _zielgruppe,
                                              newPartLc: partLc,
                                              selectionMap: currentMap,
                                              combosMap: _selectedCombosVN.value,
                                              singleBaseIndex: singleBaseIndex,
                                              bundles: bundles,
                                              newPartSinglePrice: priceForSelection,
                                            );

                                            _toggleSelection(
                                              selKey,
                                              _CartItem(
                                                kategorie: kat,
                                                leistung: partDisplay,
                                                preis: priceForSelection,
                                                dauer: effectiveDuration,
                                                zielgruppe: _zielgruppe,
                                                selectedAt: ++_selectionTicker,
                                                lockedDisplayPrice: locked,
                                              ),
                                              singleBaseIndex: singleBaseIndex,
                                              bundles: bundles,
                                            );
                                          }
                                        },
                                        icon: Icon(
                                          selected
                                              ? Icons.check_circle
                                              : Icons.add_circle_outline,
                                        ),
                                        color: selected ? Colors.blueAccent : null,
                                      ),
                                    ],
                                  ),
                                ],
                              );
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
                                child: AnimatedBuilder(
                                  animation: Listenable.merge([_selectedVN, _selectedCombosVN]),
                                  builder: (_, __) {
                                    final map = _selectedVN.value;
                                    final combos = _selectedCombosVN.value;
                                    final selectedPartsLc = map.values
                                        .where((it) => it.kategorie == kat && it.zielgruppe == _zielgruppe)
                                        .map((it) => it.leistung.toLowerCase())
                                        .toSet();
                                    _ComboSelection? selectedGroupCombo;
                                    for (final comboSel in combos.values) {
                                      if (comboSel.zielgruppe != _zielgruppe ||
                                          comboSel.bundle.kategorie != kat ||
                                          comboSel.selectedPartsLc.length != groupPartsLc.length) {
                                        continue;
                                      }
                                      if (groupPartsLc.every(comboSel.selectedPartsLc.contains)) {
                                        selectedGroupCombo = comboSel;
                                        break;
                                      }
                                    }
                                    final selectedAll = selectedGroupCombo != null;
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
                                      bundles: bundles,
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
                                      displayPrice = selectedGroupCombo?.preis ?? 0.0;
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
                                              bundles: bundles,
                                            );
                                          },
                                          icon: Icon(
                                            selectedAll ? Icons.check_circle : Icons.add_circle_outline,
                                          ),
                                          color: selectedAll ? Colors.blueAccent : null,
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
                    final methodLabels = methodOptions
                        .map((e) => e.label)
                        .where((label) => label.trim().isNotEmpty)
                        .toList();

                    final displayPreis = _minDisplayPriceForCombos(group.offers, _zielgruppe);
                    final displayDauer = _minDisplayDurationForCombos(group.offers, _zielgruppe);
                    final hasSizeOptionsBase =
                    group.offers.any((offer) => _hasSizeOptions(offer, _zielgruppe));
                    final canSelectDirectly =
                        methodOptions.length == 1 &&
                            methodLabels.isEmpty &&
                            !hasSizeOptionsBase;

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
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      group.title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  AnimatedBuilder(
                                    animation: Listenable.merge([_selectedVN, _selectedCombosVN]),
                                    builder: (_, __) {
                                      final map = _selectedCombosVN.value;
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
                                      final selectedPartsLc = _selectedPartsForContext(
                                        zielgruppe: _zielgruppe,
                                        category: kat,
                                        selectionMap: _selectedVN.value,
                                        combosMap: _selectedCombosVN.value,
                                      );
                                      final previewPrice = selected
                                          ? null
                                          : _previewForStandaloneComboOffers(
                                        offers: group.offers,
                                        category: kat,
                                        zielgruppe: _zielgruppe,
                                        selectedPartsLc: selectedPartsLc,
                                        selectionMap: _selectedVN.value,
                                        combosMap: _selectedCombosVN.value,
                                        singleBaseIndex: singleBaseIndex,
                                        bundles: bundles,
                                      );
                                      final effectivePrice =
                                          selectedCombo?.preis ?? previewPrice ?? displayPreis;
                                      final effectiveDuration = selectedCombo?.dauer ?? displayDauer;

                                      final hasDiscountedComboPrice =
                                          displayPreis != null &&
                                              effectivePrice != null &&
                                              effectivePrice < displayPreis;

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
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              if (hasDiscountedComboPrice)
                                                Text(
                                                  _preisText(displayPreis),
                                                  style: const TextStyle(
                                                    color: Colors.black45,
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w500,
                                                    decoration: TextDecoration.lineThrough,
                                                    decorationThickness: 2,
                                                  ),
                                                ),
                                              Text(
                                                _preisText(effectivePrice),
                                                style: TextStyle(
                                                  color: hasDiscountedComboPrice
                                                      ? Colors.green
                                                      : Colors.black54,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            tooltip:
                                            selected ? 'Auswahl ändern' : 'Kombi hinzufügen',
                                            onPressed: () {
                                              if (canSelectDirectly) {
                                                _toggleCombo(
                                                  combo: selectedCombo?.bundle ?? group.offers.first,
                                                  priceOverride: effectivePrice,
                                                  durationOverride: effectiveDuration,
                                                );
                                                return;
                                              }
                                              _openComboMethodSheet(
                                                combos: group.offers,
                                                singleBaseIndex: singleBaseIndex,
                                                bundles: bundles,
                                              );
                                            },
                                            icon: Icon(
                                              selected ? Icons.check_circle : Icons.add_circle_outline,
                                            ),
                                            color: selected ? Colors.blueAccent : null,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
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
                          final count = _selectedServiceCount(
                            singles: map,
                            combos: combos,
                          );

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
                                      singleBaseIndex: singleBaseIndex,
                                      bundles: bundles,
                                      computeTotals: computeTotals,
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
          ),
        ],
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
  final String? categoryLabel;
  final String title;
  final String subtitle;
  final double? price;
  final double? originalPrice;
  final int? duration;

  const _BookingSummaryEntry({
    required this.selectionKey,
    required this.isCombo,
    required this.selectedAt,
    this.categoryLabel,
    required this.title,
    required this.subtitle,
    required this.price,
    this.originalPrice,
    required this.duration,
  });
}

class _BookingSummarySuggestion {
  final String contextKey;
  final String zielgruppe;
  final String category;
  final String title;
  final List<String> displayNames;
  final List<String> partLcs;
  final double? price;
  final double? originalPrice;
  final int? duration;
  final Offer? bundle;

  const _BookingSummarySuggestion({
    required this.contextKey,
    required this.zielgruppe,
    required this.category,
    required this.title,
    required this.displayNames,
    required this.partLcs,
    required this.price,
    this.originalPrice,
    this.duration,
    this.bundle,
  });

  bool get isComboSuggestion => bundle != null && partLcs.length > 1;
  String get displayName => displayNames.join(' + ');
  String get partLc => partLcs.first;
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
