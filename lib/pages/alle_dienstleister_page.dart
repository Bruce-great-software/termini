import 'dart:math' as math; // für Chunking bei arrayContainsAny (<=10)
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';

import '../services/location_service.dart';
import '../widgets/dienstleister_tile.dart';
import 'dienstleister_detail_page.dart';
import 'kunden_favoriten_page.dart';
import 'login_register_page.dart';
import 'kunden_profil_page.dart';

import 'package:flutter/cupertino.dart';

/// Sortierreihenfolge für Preise / Distanz
enum SortOrder { none, priceAsc, priceDesc, distanceAsc }

class AlleDienstleisterPage extends StatefulWidget {
  const AlleDienstleisterPage({super.key});

  @override
  State<AlleDienstleisterPage> createState() => _AlleDienstleisterPageState();
}

class _AlleDienstleisterPageState extends State<AlleDienstleisterPage>
    with WidgetsBindingObserver {
  final TextEditingController _suchfeldController = TextEditingController();

  void _onSuchbegriffChanged(String wert) {
    if (kDebugMode) print("Suchbegriff: $wert");
  }

  // Helper, um Tastatur/Fokus sicher zu schließen
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _resetAllFiltersAndSearch([TextEditingController? c]) {
    c?.clear();
    _dismissKeyboard();

    setState(() {
      _ausgewaehlteLeistung = null;
      _gefilterteDienstleisterIds = [];
      _sortOrder = SortOrder.none;

      ausgewaehlteBranchen.clear();
      ausgewaehlteZielgruppen.clear();
      ausgewaehlteKategorien.clear();
      ausgewaehlteLeistungen.clear();
    });

    _ladeZielgruppenUndKategorien();
  }

  String? _ausgewaehlteLeistung;
  List<String> _gefilterteDienstleisterIds = [];

  /// Sortierreihenfolge (im Filter-Sheet & Sortier-Chip auswählbar)
  SortOrder _sortOrder = SortOrder.none;

  /// fixe Zielgruppen-Liste für den „Für wen?“-Block
  final List<String> _zielgruppenFix = const ['Damen', 'Herren', 'Kinder'];

  // ===================== Angebote-basierte Filter-Helfer =====================

  /// Mehrere Branchen → Menge an Dienstleister-IDs (ODER-Verknüpfung)
  Future<Set<String>?> _dienstleisterIdsFuerBranchen(List<String>? branchen) async {
    if (branchen == null || branchen.isEmpty) return null;
    final ids = <String>{};

    // Firestore whereIn max 10
    for (var i = 0; i < branchen.length; i += 10) {
      final end = math.min(i + 10, branchen.length);
      final chunk = branchen.sublist(i, end);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .where('branche', whereIn: chunk)
          .get();
      ids.addAll(snap.docs.map((d) => d.id));
    }
    return ids;
  }

  Future<void> _applyOfferFiltersFromSelections({List<String>? branchen}) async {
    if (ausgewaehlteLeistungen.isEmpty) {
      setState(() => _gefilterteDienstleisterIds = []);
      return;
    }

    final branchIds = await _dienstleisterIdsFuerBranchen(branchen);
    final resultIds = <String>{};

    for (final entry in ausgewaehlteLeistungen.entries) {
      final kategorie = entry.key;
      final leistungen = entry.value;
      if (leistungen.isEmpty) continue;

      for (var i = 0; i < leistungen.length; i += 10) {
        final end = math.min(i + 10, leistungen.length);
        final chunk = leistungen.sublist(i, end);

        final qSnap = await FirebaseFirestore.instance
            .collection('angebote')
            .where('kategorie', isEqualTo: kategorie)
            .where('leistungen', arrayContainsAny: chunk)
            .get();

        for (final d in qSnap.docs) {
          final id = (d.data()['dienstleisterId'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          if (branchIds != null && !branchIds.contains(id)) continue;
          resultIds.add(id);
        }
      }
    }

    setState(() {
      _gefilterteDienstleisterIds = resultIds.toList();
    });
  }

  Future<int> _countMatchesBasedOnSelections({List<String>? branchen}) async {
    if (ausgewaehlteLeistungen.isEmpty) {
      if (_gefilterteDienstleisterIds.isNotEmpty) {
        return _gefilterteDienstleisterIds.length;
      }

      // Wenn Branchen vorgegeben → Anzahl der DL in diesen Branchen
      final sel = branchen ?? (ausgewaehlteBranchen.isNotEmpty ? ausgewaehlteBranchen : null);
      if (sel != null && sel.isNotEmpty) {
        final ids = await _dienstleisterIdsFuerBranchen(sel);
        return ids?.length ?? 0;
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .get();
      return snap.size;
    }

    final branchIds = await _dienstleisterIdsFuerBranchen(branchen ?? ausgewaehlteBranchen);
    final ids = <String>{};

    for (final entry in ausgewaehlteLeistungen.entries) {
      final kategorie = entry.key;
      final leistungen = entry.value;
      if (leistungen.isEmpty) continue;

      for (var i = 0; i < leistungen.length; i += 10) {
        final end = math.min(i + 10, leistungen.length);
        final chunk = leistungen.sublist(i, end);

        final q = await FirebaseFirestore.instance
            .collection('angebote')
            .where('kategorie', isEqualTo: kategorie)
            .where('leistungen', arrayContainsAny: chunk)
            .get();

        for (final d in q.docs) {
          final id = (d.data()['dienstleisterId'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          if (branchIds != null && !branchIds.contains(id)) continue;
          ids.add(id);
        }
      }
    }

    return ids.length;
  }

  Future<List<String>> _ladeLeistungskategorienAusAngeboten(List<String>? branchen) async {
    // Ohne Branchen: alle Kategorien
    if (branchen == null || branchen.isEmpty) {
      final snap = await FirebaseFirestore.instance.collection('angebote').get();
      final cats = snap.docs
          .map((d) => (d.data()['kategorie'] as String?)?.trim())
          .where((s) => s != null && s!.isNotEmpty)
          .map((s) => s!)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return cats;
    }

    final ids = await _dienstleisterIdsFuerBranchen(branchen) ?? <String>{};
    if (ids.isEmpty) return [];

    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final idList = ids.toList();

    for (var i = 0; i < idList.length; i += 10) {
      final end = math.min(i + 10, idList.length);
      final chunk = idList.sublist(i, end);
      final aSnap = await FirebaseFirestore.instance
          .collection('angebote')
          .where('dienstleisterId', whereIn: chunk)
          .get();
      allDocs.addAll(aSnap.docs);
    }

    final cats = allDocs
        .map((d) => (d.data()['kategorie'] as String?)?.trim())
        .where((s) => s != null && s!.isNotEmpty)
        .map((s) => s!)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return cats;
  }

  Future<List<String>> _ladeLeistungenFuerKategorieAusAngeboten(
      String kategorie, List<String>? branchen) async {
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

    if (branchen == null || branchen.isEmpty) {
      final q = await FirebaseFirestore.instance
          .collection('angebote')
          .where('kategorie', isEqualTo: kategorie)
          .get();
      docs = q.docs;
    } else {
      final ids = await _dienstleisterIdsFuerBranchen(branchen) ?? <String>{};
      if (ids.isEmpty) return [];
      final tmp = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final idList = ids.toList();

      for (var i = 0; i < idList.length; i += 10) {
        final end = math.min(i + 10, idList.length);
        final chunk = idList.sublist(i, end);
        final aSnap = await FirebaseFirestore.instance
            .collection('angebote')
            .where('kategorie', isEqualTo: kategorie)
            .where('dienstleisterId', whereIn: chunk)
            .get();
        tmp.addAll(aSnap.docs);
      }
      docs = tmp;
    }

    final set = <String>{};
    for (final d in docs) {
      final data = d.data();
      final arr = data['leistungen'];
      if (arr is List) {
        for (final e in arr) {
          final s = (e as String?)?.trim();
          if (s != null && s.isNotEmpty) set.add(s);
        }
      } else {
        final titel = (data['titel'] as String?)?.trim();
        if (titel != null && titel.contains('–')) {
          final part = titel.split('–').last.trim();
          if (part.isNotEmpty) set.add(part);
        }
      }
    }

    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<void> _openLeistungskategorieDialog(String kategorie, {List<String>? branchen}) async {
    final leistungen = await _ladeLeistungenFuerKategorieAusAngeboten(kategorie, branchen);

    final initial = Set<String>.from(ausgewaehlteLeistungen[kategorie] ?? []);
    final tempSelected = Set<String>.from(initial);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: StatefulBuilder(
            builder: (context, setLocal) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, left: 20, right: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          kategorie,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: leistungen.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final name = leistungen[i];
                          final checked = tempSelected.contains(name);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) {
                              setLocal(() {
                                if (v == true) {
                                  tempSelected.add(name);
                                } else {
                                  tempSelected.remove(name);
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.trailing,
                            title: Text(name),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Abbrechen'),
                            ),
                          ),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                setState(() {
                                  if (tempSelected.isEmpty) {
                                    ausgewaehlteLeistungen.remove(kategorie);
                                    ausgewaehlteKategorien.removeWhere((e) => e == kategorie);
                                  } else {
                                    ausgewaehlteLeistungen[kategorie] = tempSelected.toList();
                                    if (!ausgewaehlteKategorien.contains(kategorie)) {
                                      ausgewaehlteKategorien.add(kategorie);
                                    }
                                  }
                                });
                                Navigator.of(context).pop();
                              },
                              child: const Text('OK'),
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
        );
      },
    );

    setState(() {}); // Oberfläche aktualisieren
  }

  Future<List<String>> _ladeLeistungsVorschlaege(String eingabe) async {
    if (eingabe.trim().isEmpty) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('angebote')
        .limit(50)
        .get();

    return snapshot.docs
        .map((doc) => doc['titel'].toString())
        .where((titel) => titel.toLowerCase().contains(eingabe.toLowerCase()))
        .toSet()
        .toList();
  }

  Future<void> _ladeDienstleisterZuLeistung(String titel) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('angebote')
        .where('titel', isEqualTo: titel)
        .get();

    final ids =
    snapshot.docs.map((doc) => doc['dienstleisterId'].toString()).toList();

    setState(() {
      _gefilterteDienstleisterIds = ids;
    });
  }

  Future<void> _applySelectionFromTitle(String titel) async {
    final parts = titel.split(RegExp(r'\s*[–—-]\s*'));
    String? kategorie;
    String? leistung;

    if (parts.length >= 2) {
      kategorie = parts.first.trim();
      leistung = parts.sublist(1).join(' – ').trim();
    }

    if (kategorie == null || kategorie.isEmpty || leistung == null || leistung.isEmpty) {
      await _ladeDienstleisterZuLeistung(titel);
      return;
    }

    setState(() {
      ausgewaehlteLeistungen.clear();
      ausgewaehlteKategorien.clear();
      ausgewaehlteLeistungen[kategorie!] = [leistung!];
      ausgewaehlteKategorien = [kategorie!];
    });

    final List<String>? aktuelleBranchen =
    ausgewaehlteBranchen.isNotEmpty ? List<String>.from(ausgewaehlteBranchen) : null;
    await _applyOfferFiltersFromSelections(branchen: aktuelleBranchen);
  }

  // ---- Preis-Helper ---------------------------------------------------------
  double? _preisToDouble(dynamic p) {
    if (p == null) return null;
    if (p is num) return p.toDouble();
    if (p is String) {
      final cleaned = p.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
      if (cleaned.isEmpty) return null;
      try {
        return double.parse(cleaned);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  double? _lowestPriceInOffers(List<Map<String, dynamic>>? offers) {
    if (offers == null || offers.isEmpty) return null;
    double? minP;
    for (final o in offers) {
      final p = _preisToDouble(o['preis']);
      if (p == null) continue;
      if (minP == null || p < minP) minP = p;
    }
    return minP;
  }

  // ---------- Farben für Zielgruppen ----------
  static const String _zgDamen = 'Damen';
  static const String _zgHerren = 'Herren';
  static const String _zgKinder = 'Kinder';

  Color _colorForZielgruppe(String? zg) {
    switch (zg) {
      case _zgDamen:
        return const Color(0xFFE91E63); // Pink
      case _zgKinder:
        return const Color(0xFFFFC107); // Gelb (Amber)
      case _zgHerren:
      default:
        return Colors.blueAccent; // Blau
    }
  }

  Future<List<Map<String, dynamic>>> _ladePassendeAngeboteFuerDienstleister(
      String dienstleisterId,
      ) async {
    if (ausgewaehlteLeistungen.isEmpty) return [];

    final selectedGroups = List<String>.from(ausgewaehlteZielgruppen);
    final results = <Map<String, dynamic>>[];
    final seenPair = <String>{};

    for (final entry in ausgewaehlteLeistungen.entries) {
      final kategorie = entry.key;
      final leistungen = entry.value;
      if (leistungen.isEmpty) continue;

      for (var i = 0; i < leistungen.length; i += 10) {
        final end = math.min(i + 10, leistungen.length);
        final chunk = leistungen.sublist(i, end);

        final q = await FirebaseFirestore.instance
            .collection('angebote')
            .where('dienstleisterId', isEqualTo: dienstleisterId)
            .where('kategorie', isEqualTo: kategorie)
            .where('leistungen', arrayContainsAny: chunk)
            .get();

        for (final d in q.docs) {
          final data = d.data();
          final titel = (data['titel'] as String?) ?? '${data['kategorie']}';
          final zgMap = (data['zielgruppen'] is Map)
              ? Map<String, dynamic>.from(data['zielgruppen'])
              : null;

          if (selectedGroups.isNotEmpty) {
            for (final g in selectedGroups) {
              final grp = zgMap?[g];
              if (grp is Map) {
                final key = '${d.id}|$g';
                if (seenPair.add(key)) {
                  results.add({
                    'docId': d.id,
                    'titel': titel,
                    'kategorie': data['kategorie'],
                    'preis': grp['preis'],
                    'dauer': grp['dauer'],
                    'zielgruppe': g,
                    'chipColor': _colorForZielgruppe(g),
                  });
                }
              }
            }
            continue;
          }

          if (zgMap != null && zgMap.isNotEmpty) {
            for (final entry in zgMap.entries) {
              final g = entry.key.toString();
              final grp = entry.value;
              if (grp is! Map) continue;
              final key = '${d.id}|$g';
              if (seenPair.add(key)) {
                results.add({
                  'docId': d.id,
                  'titel': titel,
                  'kategorie': data['kategorie'],
                  'preis': grp['preis'],
                  'dauer': grp['dauer'],
                  'zielgruppe': g,
                  'chipColor': _colorForZielgruppe(g),
                });
              }
            }
          } else {
            final key = '${d.id}|_global';
            if (seenPair.add(key)) {
              results.add({
                'docId': d.id,
                'titel': titel,
                'kategorie': data['kategorie'],
                'preis': data['preis'],
                'dauer': data['dauer'],
                'zielgruppe': null,
                'chipColor': _colorForZielgruppe('Herren'),
              });
            }
          }
        }
      }
    }

    if (_sortOrder == SortOrder.priceAsc || _sortOrder == SortOrder.priceDesc) {
      double? _toDouble(dynamic p) {
        if (p == null) return null;
        if (p is num) return p.toDouble();
        if (p is String) {
          final cleaned =
          p.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
          if (cleaned.isEmpty) return null;
          return double.tryParse(cleaned);
        }
        return null;
      }

      results.sort((a, b) {
        final ap = _toDouble(a['preis']);
        final bp = _toDouble(b['preis']);
        if (ap == null && bp == null) return 0;
        if (ap == null) return 1;
        if (bp == null) return -1;
        return _sortOrder == SortOrder.priceAsc ? ap.compareTo(bp) : bp.compareTo(ap);
      });
    }

    return results;
  }

  String? currentCity;
  Position? userPosition;
  bool isLoading = true;
  int _selectedIndex = 0;

  List<String> verfuegbareBranchen = [];
  List<String> ausgewaehlteBranchen = [];

  List<String> verfuegbareZielgruppen = [];
  List<String> ausgewaehlteZielgruppen = [];

  List<String> verfuegbareKategorien = [];
  List<String> ausgewaehlteKategorien = [];

  Map<String, List<String>> kategorieZuLeistungen = {};
  Map<String, List<String>> ausgewaehlteLeistungen = {};
  String? offeneKategorie;

  bool filterChipOffen = false;
  Map<String, dynamic>? geoeffneterDienstleister;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initLocation();
    }
  }

  Future<void> _ermittleOrtAusKoordinaten() async {
    if (userPosition == null) return;

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        userPosition!.latitude,
        userPosition!.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark ort = placemarks.first;
        setState(() {
          currentCity = ort.locality ??
              ort.subAdministrativeArea ??
              ort.administrativeArea ??
              'Unbekannt';
        });
      }
    } catch (e) {
      if (kDebugMode) print("Fehler beim Reverse Geocoding: $e");
    }
  }

  Future<void> _initLocation() async {
    setState(() => isLoading = true);
    userPosition = await LocationService.initLocation(
      context: context,
      onExitApp: () => SystemChannels.platform.invokeMethod('SystemNavigator.pop'),
      onOpenAppSettings: () => AppSettings.openAppSettings(),
    );
    await _ermittleOrtAusKoordinaten();
    setState(() => isLoading = false);
  }

  Future<void> _ladeZielgruppenUndKategorien() async {
    if (ausgewaehlteBranchen.isEmpty) {
      setState(() {
        verfuegbareZielgruppen = [];
        verfuegbareKategorien = [];
        kategorieZuLeistungen = {};
      });
      return;
    }

    // Beibehaltung des bisherigen Verhaltens (erste Branche),
    // um möglichst wenig in die übrige Logik einzugreifen.
    final doc = await FirebaseFirestore.instance
        .collection('branchen')
        .doc(ausgewaehlteBranchen.first)
        .get();
    final data = doc.data();
    if (data == null || !data.containsKey('zielgruppen')) return;

    final zielgruppenMap = Map<String, dynamic>.from(data['zielgruppen']);
    final zielgruppen = zielgruppenMap.keys.toList();

    setState(() {
      verfuegbareZielgruppen = zielgruppen;
      verfuegbareKategorien = [];
      kategorieZuLeistungen = {};
      ausgewaehlteZielgruppen = [];
      ausgewaehlteKategorien = [];
      ausgewaehlteLeistungen = {};
    });
  }

  // Badge zählt: Branche + Zielgruppen + Anzahl Leistungen + Sortierung
  int get _filterBadgeCount {
    int n = 0;
    if (ausgewaehlteBranchen.isNotEmpty) n += 1;
    n += ausgewaehlteZielgruppen.length;
    n += ausgewaehlteLeistungen.values.fold<int>(
      0,
          (sum, list) => sum + list.length,
    );
    if (_sortOrder != SortOrder.none) n += 1;
    return n;
  }

  // ---------- Quick-Sheet für Branchen (Multi-Select) ----------
  Future<void> _showBranchenQuickSheet() async {
    _dismissKeyboard();

    final tempSelected = <String>{}..addAll(ausgewaehlteBranchen);

    int previewCount =
    await _countMatchesBasedOnSelections(branchen: tempSelected.toList());

    final snap = await FirebaseFirestore.instance
        .collection('branchen')
        .where('aktiv', isEqualTo: true)
        .get();

    final branchen = snap.docs
        .map((d) => ((d.data()['name'] as String?) ?? d.id).trim())
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> _recalc() async {
              final c = await _countMatchesBasedOnSelections(
                  branchen: tempSelected.toList());
              setLocal(() => previewCount = c);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Branche wählen',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: branchen.length,
                        itemBuilder: (_, i) {
                          final b = branchen[i];
                          final checked = tempSelected.contains(b);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) async {
                              setLocal(() {
                                if (v == true) {
                                  tempSelected.add(b);
                                } else {
                                  tempSelected.remove(b);
                                }
                              });
                              await _recalc();
                            },
                            controlAffinity: ListTileControlAffinity.trailing,
                            title: Text(b[0].toUpperCase() + b.substring(1)),
                            dense: true,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            ausgewaehlteBranchen
                              ..clear()
                              ..addAll(tempSelected);
                          });

                          await _applyOfferFiltersFromSelections(
                              branchen: tempSelected.toList());
                          _ladeZielgruppenUndKategorien();

                          if (mounted) Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          'Anwenden – $previewCount Treffer',
                          style: const TextStyle(fontWeight: FontWeight.w600),
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

  // ---------- LEISTUNGEN-SHEET (für den „Leistungen“-Chip) ----------
  Future<void> _showLeistungenSheet() async {
    _dismissKeyboard();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Leistungen',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                ausgewaehlteKategorien.clear();
                                ausgewaehlteLeistungen.clear();
                              });
                              setModal(() {});
                            },
                            child: const Text('Zurücksetzen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      FutureBuilder<List<String>>(
                        future: _ladeLeistungskategorienAusAngeboten(
                            ausgewaehlteBranchen),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                  'Fehler beim Laden der Kategorien aus Angeboten'),
                            );
                          }

                          final items = snapshot.data ?? [];
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child:
                              Text('Keine Leistungskategorien vorhanden.'),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final name = items[i];
                              final selectedList =
                              (ausgewaehlteLeistungen[name] ??
                                  const <String>[]);

                              return ListTile(
                                dense: true,
                                title: Text(name),
                                subtitle: (selectedList.isNotEmpty)
                                    ? Padding(
                                  padding:
                                  const EdgeInsets.only(top: 6),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: selectedList.map((s) {
                                        return Padding(
                                          padding:
                                          const EdgeInsets.only(
                                              right: 6),
                                          child: InputChip(
                                            label: Text(s),
                                            selected: true,
                                            showCheckmark: false,
                                            selectedColor: Colors
                                                .blueAccent
                                                .withOpacity(.12),
                                            labelStyle:
                                            const TextStyle(
                                                color: Colors
                                                    .blueAccent),
                                            shape: const StadiumBorder(
                                              side: BorderSide(
                                                  color: Colors
                                                      .blueAccent),
                                            ),
                                            deleteIcon: const Icon(
                                                Icons.close,
                                                size: 18,
                                                color: Colors
                                                    .blueAccent),
                                            onDeleted: () {
                                              setState(() {
                                                ausgewaehlteLeistungen[
                                                name]!
                                                    .remove(s);
                                                if (ausgewaehlteLeistungen[
                                                name]!
                                                    .isEmpty) {
                                                  ausgewaehlteLeistungen
                                                      .remove(name);
                                                  ausgewaehlteKategorien
                                                      .removeWhere(
                                                          (e) =>
                                                      e == name);
                                                }
                                              });
                                              setModal(() {});
                                            },
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                )
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selectedList.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                          BorderRadius.circular(12),
                                          color: Colors.orange.shade100,
                                        ),
                                        child: Text(
                                          '${selectedList.length}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () async {
                                  await _openLeistungskategorieDialog(name,
                                      branchen: ausgewaehlteBranchen);
                                  setModal(() {});
                                },
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),

                  // Anwenden
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: ElevatedButton(
                        onPressed: () async {
                          await _applyOfferFiltersFromSelections(
                              branchen: ausgewaehlteBranchen);
                          if (mounted) Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Anwenden'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------- Sortier-Sheet (für Sortieren-Chip) ----------
  Future<void> _showSortSheet() async {
    SortOrder temp = _sortOrder;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Sortieren',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        TextButton(
                          onPressed: () => setLocal(() => temp = SortOrder.none),
                          child: const Text('Zurücksetzen'),
                        ),
                      ],
                    ),
                    RadioListTile<SortOrder>(
                      value: SortOrder.priceAsc,
                      groupValue: temp,
                      onChanged: (v) => setLocal(() => temp = v!),
                      title: const Text('Niedrigster Preis'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                    RadioListTile<SortOrder>(
                      value: SortOrder.priceDesc,
                      groupValue: temp,
                      onChanged: (v) => setLocal(() => temp = v!),
                      title: const Text('Höchster Preis'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                    RadioListTile<SortOrder>(
                      value: SortOrder.distanceAsc,
                      groupValue: temp,
                      onChanged: (v) => setLocal(() => temp = v!),
                      title: const Text('In meiner Nähe'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _sortOrder = temp);
                          Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Anwenden'),
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

  // ---------- Vollständiges Filter-Sheet ----------
  Future<void> _showBranchenFilterSheet() async {
    // Multi-Select als temporäre Menge
    final Set<String> tempBranchen = {...ausgewaehlteBranchen};

    SortOrder tempSortOrder = _sortOrder;
    final List<String> tempZielgruppen = List<String>.from(ausgewaehlteZielgruppen);

    int previewCount =
    await _countMatchesBasedOnSelections(branchen: tempBranchen.toList());

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // FULLSCREEN
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> _recalc() async {
              final c = await _countMatchesBasedOnSelections(
                  branchen: tempBranchen.toList());
              setModalState(() => previewCount = c);
            }

            return SizedBox(
              height: MediaQuery.of(context).size.height,
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Filter',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          TextButton(
                            onPressed: () async {
                              setState(() {
                                ausgewaehlteBranchen.clear();
                                ausgewaehlteKategorien.clear();
                                ausgewaehlteLeistungen.clear();
                                ausgewaehlteZielgruppen.clear();
                                _sortOrder = SortOrder.none;
                              });
                              setModalState(() {
                                tempBranchen.clear();
                                tempZielgruppen.clear();
                                tempSortOrder = SortOrder.none;
                              });
                              _dismissKeyboard();
                              await _recalc();
                            },
                            child: const Text('Zurücksetzen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Für wen?
                      Text(
                        'Für wen?',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _zielgruppenFix.map((zg) {
                          final selected = tempZielgruppen.contains(zg);
                          return FilterChip(
                            label: Text(
                              zg,
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.black,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            selected: selected,
                            onSelected: (_) {
                              setModalState(() {
                                if (selected) {
                                  tempZielgruppen.remove(zg);
                                } else {
                                  tempZielgruppen.add(zg);
                                }
                              });
                            },
                            selectedColor: Colors.blueAccent,
                            backgroundColor: Colors.white,
                            checkmarkColor: Colors.white,
                            shape: const StadiumBorder(
                              side: BorderSide(color: Colors.black),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 20),

                      // Branchen (Multi-Select)
                      Text(
                        'Branchen',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('branchen')
                            .where('aktiv', isEqualTo: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final branchen = snapshot.data!.docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return (data['name'] as String?) ?? doc.id;
                          }).toList()
                            ..sort((a, b) =>
                                a.toLowerCase().compareTo(b.toLowerCase()));

                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: branchen.map((b) {
                              final selected = tempBranchen.contains(b);
                              return FilterChip(
                                label: Text(
                                  b[0].toUpperCase() + b.substring(1),
                                  style: TextStyle(
                                    color: selected ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                selected: selected,
                                onSelected: (_) async {
                                  setModalState(() {
                                    if (selected) {
                                      tempBranchen.remove(b);
                                    } else {
                                      tempBranchen.add(b);
                                    }
                                  });
                                  await _recalc();
                                },
                                selectedColor: Colors.blueAccent,
                                backgroundColor: Colors.white,
                                checkmarkColor: Colors.white,
                                shape: const StadiumBorder(
                                  side: BorderSide(color: Colors.black),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // Leistungen
                      Text(
                        'Leistungen',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),

                      FutureBuilder<List<String>>(
                        future: _ladeLeistungskategorienAusAngeboten(
                            tempBranchen.toList()),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('Fehler beim Laden der Kategorien aus Angeboten'),
                            );
                          }

                          final items = snapshot.data ?? [];
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('Keine Leistungskategorien vorhanden.'),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final name = items[i];
                              final selectedList =
                              (ausgewaehlteLeistungen[name] ?? const <String>[]);

                              return ListTile(
                                dense: true,
                                title: Text(name),
                                subtitle: (selectedList.isNotEmpty)
                                    ? Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: selectedList.map((s) {
                                        return Padding(
                                          padding:
                                          const EdgeInsets.only(right: 6),
                                          child: InputChip(
                                            label: Text(s),
                                            selected: true,
                                            showCheckmark: false,
                                            selectedColor: Colors.blueAccent
                                                .withOpacity(.12),
                                            labelStyle: const TextStyle(
                                                color: Colors.blueAccent),
                                            shape: const StadiumBorder(
                                              side: BorderSide(
                                                  color: Colors.blueAccent),
                                            ),
                                            deleteIcon: const Icon(Icons.close,
                                                size: 18,
                                                color: Colors.blueAccent),
                                            onDeleted: () async {
                                              setState(() {
                                                ausgewaehlteLeistungen[name]!
                                                    .remove(s);
                                                if (ausgewaehlteLeistungen[name]!
                                                    .isEmpty) {
                                                  ausgewaehlteLeistungen
                                                      .remove(name);
                                                  ausgewaehlteKategorien
                                                      .removeWhere(
                                                          (e) => e == name);
                                                }
                                              });
                                              await _countMatchesBasedOnSelections(
                                                  branchen:
                                                  tempBranchen.toList())
                                                  .then((c) => setModalState(
                                                      () => previewCount = c));
                                            },
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                )
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selectedList.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          color: Colors.orange.shade100,
                                        ),
                                        child: Text(
                                          '${selectedList.length}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () async {
                                  await _openLeistungskategorieDialog(name,
                                      branchen: tempBranchen.toList());
                                  await _recalc();
                                  setModalState(() {});
                                },
                              );
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // Sortieren (neue Bezeichnungen + Distanz)
                      Text(
                        'Sortieren',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      RadioListTile<SortOrder>(
                        value: SortOrder.priceAsc,
                        groupValue: tempSortOrder,
                        onChanged: (v) => setModalState(() => tempSortOrder = v!),
                        title: const Text('Niedrigster Preis'),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                      RadioListTile<SortOrder>(
                        value: SortOrder.priceDesc,
                        groupValue: tempSortOrder,
                        onChanged: (v) => setModalState(() => tempSortOrder = v!),
                        title: const Text('Höchster Preis'),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                      RadioListTile<SortOrder>(
                        value: SortOrder.distanceAsc,
                        groupValue: tempSortOrder,
                        onChanged: (v) => setModalState(() => tempSortOrder = v!),
                        title: const Text('In meiner Nähe'),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                    ],
                  ),

                  // Schwebender Button
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            _sortOrder = tempSortOrder;
                            ausgewaehlteZielgruppen =
                            List<String>.from(tempZielgruppen);
                          });

                          await _applyOfferFiltersFromSelections(
                              branchen: tempBranchen.toList());
                          setState(() {
                            ausgewaehlteBranchen
                              ..clear()
                              ..addAll(tempBranchen);
                          });
                          _ladeZielgruppenUndKategorien();

                          _dismissKeyboard();
                          if (mounted) Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const StadiumBorder(),
                          elevation: 4,
                        ),
                        child: Text(
                          '$previewCount Treffer',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------------

  Widget _buildBodyByIndex(int index) {
    switch (index) {
      case 0:
        return geoeffneterDienstleister != null
            ? DienstleisterDetailPage(
          dienstleister: geoeffneterDienstleister!,
          selektierteZielgruppe: 'alle',
          selektierteKategorie: 'alle',
        )
            : Column(
          children: [
            Padding(
              padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSuchfeldMitFilterButton(),
                ],
              ),
            ),
            Expanded(child: dienstleisterListeView()),
          ],
        );
      case 1:
        return const KundenFavoritenPage();
      case 2:
        return const Center(child: Text('Buchungen kommen bald!'));
      case 3:
        final user = FirebaseAuth.instance.currentUser;
        return user == null ? const LoginRegisterPage() : const KundenProfilPage();
      default:
        return const SizedBox.shrink();
    }
  }


// ---------- Inline-Chips unter dem Suchfeld ----------
  Widget _buildInlineFilterChips() {
    final bool branchenAktiv = ausgewaehlteBranchen.isNotEmpty;
    final String branchenText =
        'Branchen${branchenAktiv ? '(${ausgewaehlteBranchen.length})' : ''}';

    final int leistungenCount =
    ausgewaehlteLeistungen.values.fold<int>(0, (s, l) => s + l.length);
    final bool leistungenAktiv = leistungenCount > 0;
    final String leistungenText =
        'Leistungen${leistungenAktiv ? '($leistungenCount)' : ''}';

    final bool sortAktiv = _sortOrder != SortOrder.none;

    final List<Widget> chips = [];

    // Branchen
    chips.add(
      InputChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                branchenText,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: branchenAktiv ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!branchenAktiv) ...[
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Colors.black54),
            ],
          ],
        ),
        selected: branchenAktiv,
        onSelected: (_) => _showBranchenQuickSheet(),
        onDeleted: branchenAktiv
            ? () async {
          setState(() {
            ausgewaehlteBranchen.clear();
          });
          await _applyOfferFiltersFromSelections(branchen: null);
          _ladeZielgruppenUndKategorien();
        }
            : null,
        deleteIcon: Icon(Icons.close,
            size: 18, color: branchenAktiv ? Colors.white : Colors.black54),
        selectedColor: Colors.blueAccent,
        backgroundColor: Colors.white,
        shape: const StadiumBorder(side: BorderSide(color: Colors.black)),
      ),
    );

    // Leistungen (öffnet das Leistungen-Sheet)
    chips.add(
      InputChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                leistungenText,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: leistungenAktiv ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!leistungenAktiv) ...[
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Colors.black54),
            ],
          ],
        ),
        selected: leistungenAktiv,
        onSelected: (_) => _showLeistungenSheet(),
        onDeleted: leistungenAktiv
            ? () async {
          setState(() {
            ausgewaehlteKategorien.clear();
            ausgewaehlteLeistungen.clear();
          });
          await _applyOfferFiltersFromSelections(
              branchen: ausgewaehlteBranchen);
        }
            : null,
        deleteIcon: Icon(Icons.close,
            size: 18, color: leistungenAktiv ? Colors.white : Colors.black54),
        selectedColor: Colors.blueAccent,
        backgroundColor: Colors.white,
        shape: const StadiumBorder(side: BorderSide(color: Colors.black)),
      ),
    );

    // Sortieren
    chips.add(
      InputChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sortieren', style: TextStyle(fontWeight: FontWeight.w600)),
            if (!sortAktiv) ...[
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Colors.black54),
            ],
          ],
        ),
        selected: sortAktiv,
        onSelected: (_) => _showSortSheet(),
        onDeleted:
        sortAktiv ? () => setState(() => _sortOrder = SortOrder.none) : null,
        deleteIcon: Icon(Icons.close,
            size: 18, color: sortAktiv ? Colors.white : Colors.black54),
        selectedColor: Colors.blueAccent,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(color: sortAktiv ? Colors.white : Colors.black),
        shape: const StadiumBorder(side: BorderSide(color: Colors.black)),
      ),
    );

    // >>> HIER WIEDER DRIN: Kategorie-Chips (z. B. „Augenbrauen“) <<<
    for (final kategorie in ausgewaehlteKategorien) {
      final bool aktiv =
      (ausgewaehlteLeistungen[kategorie]?.isNotEmpty ?? false);

      chips.add(
        InputChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  kategorie,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: aktiv ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!aktiv) ...[
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: Colors.black54),
              ],
            ],
          ),
          selected: aktiv,
          onSelected: (_) async {
            await _openLeistungskategorieDialog(kategorie,
                branchen: ausgewaehlteBranchen);
            await _applyOfferFiltersFromSelections(
                branchen: ausgewaehlteBranchen);
            setState(() {});
          },
          onDeleted: aktiv
              ? () async {
            setState(() {
              ausgewaehlteLeistungen.remove(kategorie);
              ausgewaehlteKategorien.removeWhere((e) => e == kategorie);
            });
            await _applyOfferFiltersFromSelections(
                branchen: ausgewaehlteBranchen);
          }
              : null,
          deleteIcon: Icon(Icons.close,
              size: 18, color: aktiv ? Colors.white : Colors.black54),
          selectedColor: Colors.blueAccent,
          backgroundColor: Colors.white,
          shape: const StadiumBorder(side: BorderSide(color: Colors.black)),
        ),
      );
    }

    // HORIZONTALE, SCROLLBARE EIN-ZEILIGE REIHE
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            chips[i],
            if (i != chips.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ---------- Suchfeld + Filterbutton ----------
  Widget _buildSuchfeldMitFilterButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) async {
                  if (textEditingValue.text == '') {
                    return const Iterable<String>.empty();
                  }
                  final vorschlaege =
                  await _ladeLeistungsVorschlaege(textEditingValue.text);
                  return vorschlaege;
                },
                onSelected: (String auswahl) async {
                  setState(() {
                    _ausgewaehlteLeistung = auswahl;
                  });
                  await _applySelectionFromTitle(auswahl);
                  _dismissKeyboard();
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    onChanged: (text) {
                      if (text.trim().isEmpty) {
                        _resetAllFiltersAndSearch(controller);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Leistung oder Dienstleister suchen',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            _resetAllFiltersAndSearch(controller),
                      )
                          : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),

            // Filterbutton mit Badge (nur Icon)
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Filter',
                  iconSize: 26,
                  color: _filterBadgeCount > 0 ? Colors.blueAccent : null,
                  icon: const Icon(CupertinoIcons.slider_horizontal_3),
                  onPressed: () async {
                    _dismissKeyboard();
                    await _showBranchenFilterSheet();
                  },
                ),
                if (_filterBadgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        _filterBadgeCount > 99 ? '99+' : '$_filterBadgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Inline-Filterchip-Reihe: Branchen, Leistungen, Sortieren
        _buildInlineFilterChips(),
      ],
    );
  }

  // ----------------------------------------------------------

  Widget _buildChipReihe(
      List<String> items, List<String> selectedItems, Function(String) onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((item) {
            final selected = selectedItems.contains(item);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                label: Text(
                  item[0].toUpperCase() + item.substring(1),
                ),
                selected: selected,
                onSelected: (_) => onTap(item),
                selectedColor: const Color(0xFFF7931E),
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                shape: const StadiumBorder(
                  side: BorderSide(color: Colors.black),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterChip() {
    return GestureDetector(
      onTap: () => setState(() => filterChipOffen = !filterChipOffen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: [
            Icon(Icons.filter_list, size: 20),
            SizedBox(width: 4),
            Text('Filter'),
          ],
        ),
      ),
    );
  }

  Widget dienstleisterListeView() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<Map<String, dynamic>> dienstleisterMitLeistungen = [];
        final docs = snapshot.data!.docs;

        return FutureBuilder(
          future: Future.wait(docs.map((doc) async {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            data['logoUrl'] = (data['logoUrl'] ?? '').toString();

            if (data['geo'] != null) {
              final geo = data['geo'] as GeoPoint;
              final distanceInMeters = Geolocator.distanceBetween(
                userPosition!.latitude,
                userPosition!.longitude,
                geo.latitude,
                geo.longitude,
              );
              data['distance'] = distanceInMeters / 1000;
            } else {
              data['distance'] = double.infinity;
            }

            if (_gefilterteDienstleisterIds.isNotEmpty) {
              if (_gefilterteDienstleisterIds.contains(data['id'])) {
                final matched =
                await _ladePassendeAngeboteFuerDienstleister(data['id']);
                if (matched.isNotEmpty) {
                  data['matchedOffers'] = matched;
                  dienstleisterMitLeistungen.add(data);
                }
              }
              return;
            }

            final leistungenSnap = await FirebaseFirestore.instance
                .collection('users')
                .doc(doc.id)
                .collection('leistungen')
                .get();

            final leistungen =
            leistungenSnap.docs.map((l) => l.data()).toList();
            data['leistungen'] = leistungen;

            final branche = data['branche']?.toString();
            final zielgruppen =
            leistungen.map((l) => l['zielgruppe']?.toString()).toSet();
            final kategorien =
            leistungen.map((l) => l['kategorie']?.toString()).toSet();

            final branchePasst = ausgewaehlteBranchen.isEmpty ||
                ausgewaehlteBranchen.contains(branche);
            final zielgruppePasst = ausgewaehlteZielgruppen.isEmpty ||
                zielgruppen.any(ausgewaehlteZielgruppen.contains);
            final kategoriePasst = ausgewaehlteKategorien.isEmpty ||
                kategorien.any(ausgewaehlteKategorien.contains);

            bool leistungPasst = true;
            if (ausgewaehlteLeistungen.isNotEmpty) {
              final ausgewaehlteKombination =
              ausgewaehlteLeistungen.values.expand((e) => e).toList();
              final ausgewaehlteSet = ausgewaehlteKombination.toSet();

              leistungPasst = leistungen.any((leistungDoc) {
                final leistungsliste =
                    (leistungDoc['leistung'] as List?)?.cast<String>() ?? [];
                final leistungSet = leistungsliste.toSet();
                return leistungSet.containsAll(ausgewaehlteSet) &&
                    leistungSet.length == ausgewaehlteSet.length;
              });
            }

            if (branchePasst &&
                zielgruppePasst &&
                kategoriePasst &&
                leistungPasst) {
              dienstleisterMitLeistungen.add(data);
            }
          })),
          builder: (context, AsyncSnapshot<List<void>> snapshot2) {
            if (snapshot2.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Sortierung anwenden
            if (_sortOrder == SortOrder.priceAsc ||
                _sortOrder == SortOrder.priceDesc) {
              if (_gefilterteDienstleisterIds.isNotEmpty) {
                dienstleisterMitLeistungen.sort((a, b) {
                  final ap = _lowestPriceInOffers(
                      (a['matchedOffers'] as List<Map<String, dynamic>>?));
                  final bp = _lowestPriceInOffers(
                      (b['matchedOffers'] as List<Map<String, dynamic>>?));
                  int cmp;
                  if (ap == null && bp == null) {
                    cmp = 0;
                  } else if (ap == null) {
                    cmp = 1;
                  } else if (bp == null) {
                    cmp = -1;
                  } else {
                    cmp = _sortOrder == SortOrder.priceAsc
                        ? ap.compareTo(bp)
                        : bp.compareTo(ap);
                  }
                  if (cmp == 0) {
                    cmp = (a['distance'] as double)
                        .compareTo(b['distance'] as double);
                  }
                  return cmp;
                });
              } else {
                // keine Preisinfos → Distanz
                dienstleisterMitLeistungen.sort((a, b) =>
                    (a['distance'] as double).compareTo(b['distance'] as double));
              }
            } else if (_sortOrder == SortOrder.distanceAsc) {
              dienstleisterMitLeistungen.sort((a, b) =>
                  (a['distance'] as double).compareTo(b['distance'] as double));
            } else {
              // Default: Distanz
              dienstleisterMitLeistungen.sort((a, b) =>
                  (a['distance'] as double).compareTo(b['distance'] as double));
            }

            return ListView.builder(
              itemCount: dienstleisterMitLeistungen.length,
              itemBuilder: (context, index) {
                final data = dienstleisterMitLeistungen[index];
                return DienstleisterTile(
                  data: data,
                  matchedOffers:
                  (data['matchedOffers'] as List<Map<String, dynamic>>?),
                  onTap: () {
                    setState(() {
                      geoeffneterDienstleister = data;
                    });
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || userPosition == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        centerTitle: true,
        title: Text(
          geoeffneterDienstleister != null
              ? ''
              : (currentCity != null ? currentCity! : 'Ort wird geladen...'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        leading: geoeffneterDienstleister != null
            ? IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              geoeffneterDienstleister = null;
            });
          },
        )
            : null,
      ),
      body: _buildBodyByIndex(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            geoeffneterDienstleister = null;
            _selectedIndex = index;
          });
        },
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        backgroundColor: Colors.white,
        elevation: 8,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Suchen'),
          BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border), label: 'Favoriten'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: 'Termine'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }
}