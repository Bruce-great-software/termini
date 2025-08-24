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
import 'login_register_page.dart';
import 'kunden_profil_page.dart';

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

  String? _ausgewaehlteLeistung;
  List<String> _gefilterteDienstleisterIds = [];

  // ===================== Angebote-basierte Filter-Helfer =====================

  /// Alle Dienstleister-IDs einer Branche holen (oder null = keine Einschränkung)
  Future<Set<String>?> _dienstleisterIdsFuerBranche(String? branche) async {
    if (branche == null) return null;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('rolle', isEqualTo: 'dienstleister')
        .where('branche', isEqualTo: branche)
        .get();
    return snap.docs.map((d) => d.id).toSet();
  }

  // ---------- Exact-Match Helfer ----------
  String _norm(String s) => s.toLowerCase().trim();

  Set<String> _extractLeistungsSet(Map<String, dynamic> angebot) {
    // 1) bevorzugt aus Feld 'leistungen'
    final arr = angebot['leistungen'];
    if (arr is List) {
      return arr
          .whereType<String>()
          .map(_norm)
          .where((s) => s.isNotEmpty)
          .toSet();
    }
    // 2) Fallback: aus 'titel' wie "Haare – Schneiden, Stylen, Waschen"
    final raw = (angebot['titel'] as String?) ?? '';
    final rightSide = raw.contains('–') ? raw.split('–').last : raw;
    return rightSide
        .split(RegExp(r'[,\|/\+]+')) // Komma, |, /, +
        .map(_norm)
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  bool _angebotMatchtExakt({
    required Map<String, dynamic> angebot,
    required String kategorie,
    required List<String> selectedLeistungen,
  }) {
    final cat = (angebot['kategorie'] as String?)?.trim();
    if (cat == null || cat != kategorie) return false;

    final sel = selectedLeistungen.map(_norm).toSet();
    final off = _extractLeistungsSet(angebot);

    // exakt gleiche Menge & gleiche Inhalte
    return off.length == sel.length && off.containsAll(sel);
  }

  /// Wendet die aktuell ausgewählten Leistungen (ausgewaehlteLeistungen) auf `angebote` an
  /// und schreibt die passenden Dienstleister-IDs in `_gefilterteDienstleisterIds`.
  /// NEU: Nur exakte Kombis; mehrere Kategorien werden per Schnittmenge (AND) verknüpft.
  Future<void> _applyOfferFiltersFromSelections({String? branche}) async {
    if (ausgewaehlteLeistungen.isEmpty) {
      setState(() => _gefilterteDienstleisterIds = []);
      return;
    }

    final branchIds = await _dienstleisterIdsFuerBranche(branche);
    final idsProKategorie = <Set<String>>[];

    for (final entry in ausgewaehlteLeistungen.entries) {
      final kategorie = entry.key;
      final sel = entry.value;
      if (sel.isEmpty) continue;

      final idsDieserKategorie = <String>{};

      // arrayContainsAny <= 10
      for (var i = 0; i < sel.length; i += 10) {
        final end = math.min(i + 10, sel.length);
        final chunk = sel.sublist(i, end);

        final qSnap = await FirebaseFirestore.instance
            .collection('angebote')
            .where('kategorie', isEqualTo: kategorie)
            .where('leistungen', arrayContainsAny: chunk)
            .get();

        for (final d in qSnap.docs) {
          final data = d.data();
          final id = (data['dienstleisterId'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          if (branchIds != null && !branchIds.contains(id)) continue;

          // EXAKT vergleichen
          if (_angebotMatchtExakt(
            angebot: data,
            kategorie: kategorie,
            selectedLeistungen: sel,
          )) {
            idsDieserKategorie.add(id);
          }
        }
      }

      idsProKategorie.add(idsDieserKategorie);
    }

    // Schnittmenge aller Kategorien
    Set<String> finalIds;
    if (idsProKategorie.isEmpty) {
      finalIds = <String>{};
    } else {
      finalIds = idsProKategorie.reduce((a, b) => a.intersection(b));
    }

    setState(() {
      _gefilterteDienstleisterIds = finalIds.toList();
    });
  }

  /// Nur zählen, wie viele Dienstleister aktuell zu den Selektionen passen
  /// NEU: identische Exact-Match-Logik wie bei `_applyOfferFiltersFromSelections`
  Future<int> _countMatchesBasedOnSelections({String? branche}) async {
    // KEINE Leistungs-Selektion → zeig die aktuell gelisteten Anbieter
    if (ausgewaehlteLeistungen.isEmpty) {
      // Falls bereits per `angebote` gefiltert wurde
      if (_gefilterteDienstleisterIds.isNotEmpty) {
        return _gefilterteDienstleisterIds.length;
      }

      // Sonst alle Dienstleister (ggf. mit aktueller/preview-Branche)
      Query q = FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister');

      if (branche != null && branche.isNotEmpty) {
        q = q.where('branche', isEqualTo: branche);
      } else if (ausgewaehlteBranchen.isNotEmpty) {
        // bereits aktive Branchen-Chips auf der Liste berücksichtigen
        q = q.where('branche', isEqualTo: ausgewaehlteBranchen.first);
      }

      final snap = await q.get();
      return snap.size;
    }

    // MIT Leistungs-Selektion → wie bisher über `angebote` zählen (aber mit Exact-Match)
    final branchIds = await _dienstleisterIdsFuerBranche(branche);
    final idsProKategorie = <Set<String>>[];

    for (final entry in ausgewaehlteLeistungen.entries) {
      final kategorie = entry.key;
      final sel = entry.value;
      if (sel.isEmpty) continue;

      final idsDieserKategorie = <String>{};

      for (var i = 0; i < sel.length; i += 10) {
        final end = math.min(i + 10, sel.length);
        final chunk = sel.sublist(i, end);

        final q = await FirebaseFirestore.instance
            .collection('angebote')
            .where('kategorie', isEqualTo: kategorie)
            .where('leistungen', arrayContainsAny: chunk)
            .get();

        for (final d in q.docs) {
          final data = d.data();
          final id = (data['dienstleisterId'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          if (branchIds != null && !branchIds.contains(id)) continue;

          if (_angebotMatchtExakt(
            angebot: data,
            kategorie: kategorie,
            selectedLeistungen: sel,
          )) {
            idsDieserKategorie.add(id);
          }
        }
      }

      idsProKategorie.add(idsDieserKategorie);
    }

    if (idsProKategorie.isEmpty) return 0;
    final finalIds = idsProKategorie.reduce((a, b) => a.intersection(b));
    return finalIds.length;
  }

  // ========= Kategorien aus 'angebote' laden (optional nach Branche) =========
  Future<List<String>> _ladeLeistungskategorienAusAngeboten(String? branche) async {
    if (branche == null) {
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

    // Mit Branchenfilter -> Dienstleister dieser Branche suchen
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('rolle', isEqualTo: 'dienstleister')
        .where('branche', isEqualTo: branche)
        .get();

    final ids = userSnap.docs.map((d) => d.id).toList();
    if (ids.isEmpty) return [];

    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < ids.length; i += 10) {
      final end = (i + 10 < ids.length) ? i + 10 : ids.length;
      final chunk = ids.sublist(i, end);
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

  // ========= Leistungen einer Kategorie aus 'angebote' (optional Branche) =========
  Future<List<String>> _ladeLeistungenFuerKategorieAusAngeboten(
      String kategorie, String? branche) async {
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

    if (branche == null) {
      final q = await FirebaseFirestore.instance
          .collection('angebote')
          .where('kategorie', isEqualTo: kategorie)
          .get();
      docs = q.docs;
    } else {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .where('branche', isEqualTo: branche)
          .get();
      final ids = userSnap.docs.map((d) => d.id).toList();
      if (ids.isEmpty) return [];

      final tmp = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (var i = 0; i < ids.length; i += 10) {
        final end = (i + 10 < ids.length) ? i + 10 : ids.length;
        final chunk = ids.sublist(i, end);
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

  // ==== Dialog (basiert auf `angebote`) ====
  Future<void> _openLeistungskategorieDialog(String kategorie, {String? branche}) async {
    final leistungen = await _ladeLeistungenFuerKategorieAusAngeboten(kategorie, branche);

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
                                    ausgewaehlteKategorien = [kategorie];
                                  }
                                });
                                // Wichtig: Anwendung/Filter erst im großen "Anwenden"-Button
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

  /// =============== NEU: Passende Angebote pro Dienstleister ===============
  /// NEU: Nur exakte Kombis werden an das Tile geliefert.
  Future<List<Map<String, dynamic>>> _ladePassendeAngeboteFuerDienstleister(
      String dienstleisterId) async {
    if (ausgewaehlteLeistungen.isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    final seen = <String>{}; // docIds zum Deduplizieren

    for (final entry in ausgewaehlteLeistungen.entries) {
      final kategorie = entry.key;
      final sel = entry.value;
      if (sel.isEmpty) continue;

      for (var i = 0; i < sel.length; i += 10) {
        final end = math.min(i + 10, sel.length);
        final chunk = sel.sublist(i, end);

        final q = await FirebaseFirestore.instance
            .collection('angebote')
            .where('dienstleisterId', isEqualTo: dienstleisterId)
            .where('kategorie', isEqualTo: kategorie)
            .where('leistungen', arrayContainsAny: chunk)
            .get();

        for (final d in q.docs) {
          if (seen.contains(d.id)) continue;
          final data = d.data();

          // EXAKT prüfen
          if (!_angebotMatchtExakt(
            angebot: data,
            kategorie: kategorie,
            selectedLeistungen: sel,
          )) {
            continue;
          }

          seen.add(d.id);

          dynamic preis = data['preis'];
          dynamic dauer = data['dauer'];
          final zielgruppen = data['zielgruppen'];
          if ((preis == null || dauer == null) && zielgruppen is Map) {
            if (zielgruppen.isNotEmpty) {
              final first = zielgruppen.values.first;
              if (first is Map) {
                preis ??= first['preis'];
                dauer ??= first['dauer'];
              }
            }
          }

          results.add({
            'docId': d.id,
            'titel': (data['titel'] as String?) ?? '${data['kategorie']}',
            'kategorie': data['kategorie'],
            'preis': preis,
            'dauer': dauer,
          });
        }
      }
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
      onExitApp: () =>
          SystemChannels.platform.invokeMethod('SystemNavigator.pop'),
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

  // Z.B. oberhalb von _showBranchenFilterSheet()
  int get _filterBadgeCount {
    int n = 0;
    if (ausgewaehlteBranchen.isNotEmpty) n += 1; // 1 Punkt für Branchenwahl
    n += ausgewaehlteLeistungen.values.fold<int>(
      0,
          (sum, list) => sum + list.length,
    ); // Summe aller ausgewählten Leistungen
    return n;
  }

  // ---------- Bottom Sheet für Branchen-Filter (FULLSCREEN + Floating Apply) ----------
  Future<void> _showBranchenFilterSheet() async {
    String? tempSelected =
    ausgewaehlteBranchen.isNotEmpty ? ausgewaehlteBranchen.first : null;

    int previewCount =
    await _countMatchesBasedOnSelections(branche: tempSelected);

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
                  branche: tempSelected);
              setModalState(() => previewCount = c);
            }

            return SizedBox(
              height: MediaQuery.of(context).size.height,
              child: Stack(
                children: [
                  // Scrollbarer Inhalt
                  ListView(
                    padding: const EdgeInsets.fromLTRB(
                        16, 16, 16, 120), // Platz für Floating-Button
                    children: [
                      // Header
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
                              });
                              await _recalc();
                            },
                            child: const Text('Zurücksetzen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Branchen
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
                              final selected = tempSelected == b;
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
                                    tempSelected = selected ? null : b;
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
                        future:
                        _ladeLeistungskategorienAusAngeboten(tempSelected),
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
                              (ausgewaehlteLeistungen[name] ??
                                  const <String>[]);

                              return ListTile(
                                dense: true,
                                title: Text(name),
                                // AUSGEWÄHLTE LEISTUNGEN UNTER DER KATEGORIE
                                subtitle: (selectedList.isNotEmpty)
                                    ? Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: selectedList.map((s) {
                                      return InputChip(
                                        label: Text(s),
                                        selected: true,
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
                                          // Leistung aus der Kategorie entfernen
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
                                          // Trefferzahl im Anwenden-Button neu berechnen
                                          await _countMatchesBasedOnSelections(
                                              branche: tempSelected)
                                              .then((c) =>
                                              setModalState(() =>
                                              previewCount = c));
                                        },
                                      );
                                    }).toList(),
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
                                      branche: tempSelected);
                                  await _recalc(); // nach Rückkehr Treffer neu zählen
                                  setModalState(() {}); // UI aktualisieren (Chips)
                                },
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),

                  // Schwebender "Anwenden – n Treffer"-Button
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: ElevatedButton(
                        onPressed: () async {
                          // Filter jetzt anwenden
                          await _applyOfferFiltersFromSelections(
                              branche: tempSelected);
                          setState(() {
                            ausgewaehlteBranchen
                              ..clear()
                              ..addAll(tempSelected != null ? [tempSelected!] : []);
                          });
                          _ladeZielgruppenUndKategorien();
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
                          style:
                          const TextStyle(fontWeight: FontWeight.w600),
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
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('branchen')
                        .where('aktiv', isEqualTo: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }

                      final branchen =
                      snapshot.data!.docs.map((doc) {
                        final data =
                        doc.data() as Map<String, dynamic>;
                        return data.containsKey('name')
                            ? data['name'] as String
                            : doc.id;
                      }).toList()
                        ..sort();

                      return _buildChipReihe(
                        branchen,
                        ausgewaehlteBranchen,
                            (branche) {
                          setState(() {
                            ausgewaehlteBranchen = [branche];
                            _ladeZielgruppenUndKategorien();
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(child: dienstleisterListeView()),
          ],
        );
      case 1:
        return const Center(child: Text('Favoriten kommen bald!'));
      case 2:
        return const Center(child: Text('Buchungen kommen bald!'));
      case 3:
        final user = FirebaseAuth.instance.currentUser;
        return user == null
            ? const LoginRegisterPage()
            : const KundenProfilPage();
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------- Suchfeld + Filterbutton ----------
  Widget _buildSuchfeldMitFilterButton() {
    return Row(
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
              await _ladeDienstleisterZuLeistung(auswahl);
            },
            fieldViewBuilder:
                (context, controller, focusNode, onEditingComplete) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onEditingComplete: onEditingComplete,
                onChanged: (text) {
                  if (text.trim().isEmpty) {
                    setState(() {
                      _ausgewaehlteLeistung = null;
                      _gefilterteDienstleisterIds = [];
                    });
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Leistung oder Dienstleister suchen',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: controller.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      controller.clear();
                      setState(() {
                        _ausgewaehlteLeistung = null;
                        _gefilterteDienstleisterIds = [];
                      });
                    },
                  )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),

        // >>> Filterbutton mit Badge
        Stack(
          clipBehavior: Clip.none,
          children: [
            OutlinedButton.icon(
              onPressed: _showBranchenFilterSheet,
              icon: const Icon(Icons.filter_list),
              label: const Text('Filter'),
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                backgroundColor: _filterBadgeCount > 0
                    ? Colors.blueAccent.withOpacity(0.08)
                    : null,
                side: BorderSide(
                  color:
                  _filterBadgeCount > 0 ? Colors.blueAccent : Colors.black,
                ),
                foregroundColor:
                _filterBadgeCount > 0 ? Colors.blueAccent : null,
              ),
            ),

            if (_filterBadgeCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
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
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    if (selectedItems.contains(item)) {
                      selectedItems.remove(item);
                    } else {
                      selectedItems.clear(); // nur ein aktiver gleichzeitig
                      selectedItems.add(item);
                    }
                    _ladeZielgruppenUndKategorien();
                  });
                },
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

            // Distanz berechnen
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

            // Wenn per `angebote` gefiltert wurde, passende Angebote laden
            if (_gefilterteDienstleisterIds.isNotEmpty) {
              if (_gefilterteDienstleisterIds.contains(data['id'])) {
                final matched =
                await _ladePassendeAngeboteFuerDienstleister(data['id']);
                data['matchedOffers'] = matched; // wird vom Tile gerendert
                dienstleisterMitLeistungen.add(data);
              }
              return;
            }

            // Kein angebote-Filter aktiv: altes Verhalten mit Subcollection (optional)
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

            dienstleisterMitLeistungen.sort((a, b) =>
                (a['distance'] as double).compareTo(b['distance'] as double));

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
          currentCity != null ? currentCity! : 'Ort wird geladen...',
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
