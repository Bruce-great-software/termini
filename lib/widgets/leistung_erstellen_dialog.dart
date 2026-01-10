import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LeistungErstellenDialog extends StatefulWidget {
  final String? angebotId;
  final Map<String, dynamic>? initialData;

  const LeistungErstellenDialog({
    Key? key,
    this.angebotId,
    this.initialData,
  }) : super(key: key);

  @override
  State<LeistungErstellenDialog> createState() => _LeistungErstellenDialogState();
}

// Token, wenn im Methoden-Sheet bewusst „ohne Methode“ gewählt wurde
const String _noMethodToken = '__OHNE_METHODE__';

// Firestore: Definitionen → Dokument-ID mit Umlaut
const String _defHaarlaengeDocId = 'Haarlänge';

class _LeistungErstellenDialogState extends State<LeistungErstellenDialog>
    with SingleTickerProviderStateMixin {
  int currentStep = 0;

  String? aktuelleBranche;
  String? ausgewaehlteLeistungskategorie;

  List<String> leistungen = [];
  List<String> ausgewaehlteLeistungen = [];

  // Ausgewählte Methode je Leistung (max. 1)
  final Map<String, String> _methodeProLeistung = {};

  // ---------- Zielgruppen ----------
  static const List<String> _zielgruppen = ['Damen', 'Herren', 'Kinder'];

  // Basis Preis/Dauer pro Zielgruppe
  final Map<String, TextEditingController> preisController = {
    'Damen': TextEditingController(),
    'Herren': TextEditingController(),
    'Kinder': TextEditingController(),
  };
  final Map<String, TextEditingController> dauerController = {
    'Damen': TextEditingController(),
    'Herren': TextEditingController(),
    'Kinder': TextEditingController(),
  };

  // ---------- Variablen für „Haarlänge“-Block (Definitionen) ----------
  bool _showHaarlaengeBlock = false; // wird aus definitionen/Haarlänge bestimmt
  List<String> _haarlaengeOptions = const ['kurz', 'mittel', 'lang'];

  // Schalter je Zielgruppe, ob variantenspez. Werte erfasst werden
  final Map<String, bool> _variantenOn = {
    'Damen': false,
    'Herren': false,
    'Kinder': false,
  };

  // Controller: zielgruppe -> option -> ('preis'/'dauer' -> Controller)
  final Map<String, Map<String, Map<String, TextEditingController>>> _varCtrls = {
    'Damen': {},
    'Herren': {},
    'Kinder': {},
  };

  bool _saving = false;
  bool get _isEdit => widget.angebotId != null;

  @override
  void initState() {
    super.initState();
    _initOptionCtrls(_haarlaengeOptions);
    _ladeBrancheDesDienstleisters();
  }

  @override
  void dispose() {
    for (final c in preisController.values) c.dispose();
    for (final c in dauerController.values) c.dispose();
    _disposeAllVarCtrls();
    super.dispose();
  }

  // ---------- Controller-Setup/Dispose für dynamische Optionen ----------
  void _initOptionCtrls(List<String> options) {
    for (final zg in _zielgruppen) {
      final map = _varCtrls[zg]!;
      // Entferne nicht mehr benötigte Optionen
      final toRemove = map.keys.where((k) => !options.contains(k)).toList();
      for (final k in toRemove) {
        map[k]!['preis']?.dispose();
        map[k]!['dauer']?.dispose();
        map.remove(k);
      }
      // Füge fehlende hinzu
      for (final opt in options) {
        map.putIfAbsent(opt, () => {
          'preis': TextEditingController(),
          'dauer': TextEditingController(),
        });
      }
    }
  }

  void _disposeAllVarCtrls() {
    for (final zgMap in _varCtrls.values) {
      for (final optMap in zgMap.values) {
        optMap['preis']?.dispose();
        optMap['dauer']?.dispose();
      }
    }
  }

  // ---------- Daten laden ----------
  Future<void> _ladeBrancheDesDienstleisters() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (data != null && data['branche'] != null) {
      setState(() => aktuelleBranche = data['branche']);
    }

    if (_isEdit && widget.initialData != null) {
      await _prefillFromInitial(widget.initialData!);
    }
  }

  Future<void> _prefillFromInitial(Map<String, dynamic> d) async {
    final kat = (d['kategorie'] as String?)?.trim();
    if (kat != null && kat.isNotEmpty) {
      setState(() => ausgewaehlteLeistungskategorie = kat);
      await _ladeLeistungenZurKategorie(kat);
    }

    // Leistungen
    if (d['leistungenSortiert'] is List) {
      ausgewaehlteLeistungen = List<String>.from(d['leistungenSortiert'] as List);
    } else if (d['leistungen'] is List) {
      ausgewaehlteLeistungen = List<String>.from(d['leistungen'] as List);
    }

    // Methoden pro Leistung (Fallback auf altes variantenProLeistung)
    if (d['methodenProLeistung'] is Map) {
      _methodeProLeistung
        ..clear()
        ..addAll((d['methodenProLeistung'] as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString())));
    } else if (d['variantenProLeistung'] is Map) {
      _methodeProLeistung
        ..clear()
        ..addAll((d['variantenProLeistung'] as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString())));
    }

    // Zielgruppen + evtl. Varianten (kurz/mittel/lang) vorfüllen
    if (d['zielgruppen'] is Map) {
      final zgMap = Map<String, dynamic>.from(d['zielgruppen']);
      for (final name in _zielgruppen) {
        final g = zgMap[name];
        if (g is Map) {
          final p = g['preis'];
          final m = g['dauer'];
          preisController[name]?.text = (p == null) ? '' : '$p';
          dauerController[name]?.text = (m == null) ? '' : '$m';

          if (g['varianten'] is Map) {
            final v = Map<String, dynamic>.from(g['varianten']);
            // dynamische Optionen aus vorhandenem Inhalt ergänzen
            final keys = v.keys.map((e) => e.toString()).toSet();
            final merged = {..._haarlaengeOptions, ...keys}.toList();
            _haarlaengeOptions = merged;
            _initOptionCtrls(_haarlaengeOptions);

            _variantenOn[name] = true;
            for (final opt in v.keys) {
              final item = v[opt];
              if (item is Map) {
                final vp = item['preis'];
                final vd = item['dauer'];
                _varCtrls[name]![opt]!['preis']!.text = (vp == null) ? '' : '$vp';
                _varCtrls[name]![opt]!['dauer']!.text = (vd == null) ? '' : '$vd';
              }
            }
          }
        }
      }
    }

    await _refreshDefinitionVisibility(); // nach Prefill prüfen
    setState(() {});
  }

  Future<void> _ladeLeistungenZurKategorie(String leistungskategorie) async {
    final snapshot = await FirebaseFirestore.instance.collection('leistungen').get();

    final gefilterteLeistungen = snapshot.docs
        .where((doc) {
      final data = doc.data();
      final lsks = List<String>.from(data['leistungskategorien'] ?? []);
      return lsks.contains(leistungskategorie);
    })
        .map((doc) => (doc.data()['titel'] ?? doc.id).toString())
        .toList();

    setState(() {
      leistungen = gefilterteLeistungen;
      if (!_isEdit) {
        ausgewaehlteLeistungen.clear();
        _methodeProLeistung.clear();
      } else {
        _methodeProLeistung.removeWhere((k, _) => !leistungen.contains(k));
      }
    });

    await _refreshDefinitionVisibility();
  }

  // ---------- Definitionen/Haarlänge lesen & Sichtbarkeit bestimmen ----------
  Future<void> _refreshDefinitionVisibility() async {
    // Ohne Kat oder ohne Leistung → ausblenden
    if (ausgewaehlteLeistungskategorie == null || (ausgewaehlteLeistungen.isEmpty)) {
      if (mounted) setState(() => _showHaarlaengeBlock = false);
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('definitionen')
        .doc(_defHaarlaengeDocId)
        .get();

    if (!doc.exists) {
      if (mounted) setState(() => _showHaarlaengeBlock = false);
      return;
    }

    final data = doc.data() as Map<String, dynamic>;
    final active = data['active'] == true;

    final List<String> katArr =
    List<String>.from(data['leistungskategorien'] ?? const []);
    final List<String> leistArr = List<String>.from(data['leistungen'] ?? const []);
    final List<String> branchArr = List<String>.from(data['branchen'] ?? const []);

    final matchKat =
        katArr.isEmpty || katArr.contains(ausgewaehlteLeistungskategorie);
    final matchLeistung =
        leistArr.isEmpty || ausgewaehlteLeistungen.any((l) => leistArr.contains(l));
    final matchBranche = (aktuelleBranche == null) ||
        branchArr.isEmpty ||
        branchArr.any((b) => b.toLowerCase() == aktuelleBranche!.toLowerCase());

    final shouldShow = active && matchKat && matchLeistung && matchBranche;

    // options dynamisch übernehmen (fallback auf kurz/mittel/lang)
    final List<String> opts =
    List<String>.from(data['options'] ?? const ['kurz', 'mittel', 'lang']);

    if (mounted) {
      setState(() {
        _showHaarlaengeBlock = shouldShow;
        _haarlaengeOptions = opts;
        _initOptionCtrls(_haarlaengeOptions);
      });
    }
  }

  // ---------- Methoden laden / Sheet ----------
  Future<List<String>> _ladeMethodenFuerLeistung(String leistungstitel) async {
    final snap =
    await FirebaseFirestore.instance.collection('leistungen').doc(leistungstitel).get();
    if (!snap.exists) return [];
    final data = snap.data() as Map<String, dynamic>;

    if (data['methoden'] is List) return List<String>.from(data['methoden']);
    if (data['varianten'] is List) return List<String>.from(data['varianten']); // Legacy
    return <String>[];
  }

  Future<String?> _zeigeMethodenSheet(
      BuildContext context,
      String leistung,
      List<String> methoden,
      ) async {
    String? selected = _methodeProLeistung[leistung] ?? _noMethodToken;

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Methode wählen – $leistung',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    value: _noMethodToken,
                    groupValue: selected,
                    title: const Text('Ohne Methode'),
                    subtitle: const Text('Standard ohne Zusatz'),
                    onChanged: (val) => setSheet(() => selected = val),
                  ),
                  ...methoden.map((m) => RadioListTile<String>(
                    value: m,
                    groupValue: selected,
                    title: Text(m),
                    onChanged: (val) => setSheet(() => selected = val),
                  )),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, selected),
                        child: const Text('Übernehmen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _toggleLeistung(String leistung) async {
    final already = ausgewaehlteLeistungen.contains(leistung);
    if (already) {
      setState(() {
        ausgewaehlteLeistungen.remove(leistung);
        _methodeProLeistung.remove(leistung);
      });
      await _refreshDefinitionVisibility();
      return;
    }

    final methoden = await _ladeMethodenFuerLeistung(leistung);

    if (methoden.isEmpty) {
      setState(() => ausgewaehlteLeistungen.add(leistung));
      await _refreshDefinitionVisibility();
    } else {
      final result = await _zeigeMethodenSheet(context, leistung, methoden);
      if (result == null) return;

      setState(() {
        if (result == _noMethodToken) {
          _methodeProLeistung.remove(leistung);
        } else {
          _methodeProLeistung[leistung] = result;
        }
        ausgewaehlteLeistungen.add(leistung);
      });
      await _refreshDefinitionVisibility();
    }
  }

  String _anzeigeName(String leistung) {
    final m = _methodeProLeistung[leistung];
    return m == null ? leistung : '$leistung ($m)';
  }

  // ---------- Step 1 ----------
  Widget _buildKategorieStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Leistungskategorie wählen', style: TextStyle(color: Colors.blue)),
        const SizedBox(height: 8),
        if (aktuelleBranche == null)
          const CircularProgressIndicator()
        else
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('leistungskategorien').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (!data.containsKey('branchen')) return false;
                final branchen = List<String>.from(data['branchen']);
                return branchen.map((b) => b.toLowerCase()).contains(aktuelleBranche!.toLowerCase());
              }).toList();

              return Wrap(
                spacing: 8,
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final titel = data['titel'] ?? doc.id;
                  final selected = ausgewaehlteLeistungskategorie == titel;
                  return ChoiceChip(
                    label: Text(titel, style: const TextStyle(color: Colors.white)),
                    selected: selected,
                    selectedColor: Colors.blue,
                    backgroundColor: Colors.blue.shade100,
                    onSelected: (_) async {
                      setState(() => ausgewaehlteLeistungskategorie = titel);
                      await _ladeLeistungenZurKategorie(titel);
                      await _refreshDefinitionVisibility();
                    },
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  // ---------- Step 2 ----------
  Widget _buildLeistungenStep() {
    if (ausgewaehlteLeistungskategorie == null) {
      return const Text('Bitte zuerst eine Leistungskategorie auswählen.',
          style: TextStyle(color: Colors.blue));
    }
    if (leistungen.isEmpty) {
      return const Text('Keine Leistungen gefunden.', style: TextStyle(color: Colors.blue));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...leistungen.map((leistung) {
          final selected = ausgewaehlteLeistungen.contains(leistung);
          final methode = _methodeProLeistung[leistung];

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(leistung, style: const TextStyle(color: Colors.blue)),
            subtitle: (methode == null)
                ? null
                : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                children: [
                  Chip(
                    label: Text(methode),
                    onDeleted: () {
                      setState(() {
                        _methodeProLeistung.remove(leistung);
                        ausgewaehlteLeistungen.remove(leistung);
                      });
                      _refreshDefinitionVisibility();
                    },
                  ),
                ],
              ),
            ),
            trailing: IconButton(
              tooltip: selected ? 'Entfernen' : 'Hinzufügen',
              onPressed: () => _toggleLeistung(leistung),
              icon: Icon(
                selected ? Icons.check_circle : Icons.add_circle_outline,
                color: selected ? Colors.green : Colors.blue,
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Text(
          ausgewaehlteLeistungen.isEmpty
              ? 'Keine Leistung ausgewählt'
              : 'Ausgewählt: ${ausgewaehlteLeistungen.map(_anzeigeName).join(', ')}',
          style: const TextStyle(color: Colors.blueGrey),
        ),
      ],
    );
  }

  // ---------- Step 3 ----------
  Widget _buildPreisDauerForm(String zielgruppe) {
    final variantenAktiv = _variantenOn[zielgruppe] ?? false;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_showHaarlaengeBlock || !variantenAktiv) ...[
      TextFormField(
      controller: preisController[zielgruppe],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Preis',
        suffixText: '€',
        border: OutlineInputBorder(),
      ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: dauerController[zielgruppe],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dauer',
                suffixText: 'Minuten',
                border: OutlineInputBorder(),
              ),


          ),
          ],

          // ▼▼▼ Haarlänge-Block nur anzeigen, wenn Definition greift ▼▼▼
          if (_showHaarlaengeBlock) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Varianten (z. B. kurz/mittel/lang)'),
                const Spacer(),
                Switch(
                  value: variantenAktiv,
                  onChanged: (val) => setState(() => _variantenOn[zielgruppe] = val),
                ),
              ],
            ),
            if (variantenAktiv) ...[
              const SizedBox(height: 8),
              for (final opt in _haarlaengeOptions) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                  child: Text(opt,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _varCtrls[zielgruppe]![opt]!['preis'],
                        keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Preis',
                          suffixText: '€',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _varCtrls[zielgruppe]![opt]!['dauer'],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Dauer',
                          suffixText: 'Minuten',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 6),
              Text(
                'Hinweis: Leere Felder werden ignoriert.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPreisDauerStep() {
    return Column(
      children: [
        const TabBar(
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.blueAccent,
          indicatorColor: Colors.blue,
          tabs: [Tab(text: 'Damen'), Tab(text: 'Herren'), Tab(text: 'Kinder')],
        ),
        SizedBox(
          height: _showHaarlaengeBlock ? 480 : 260,
          child: TabBarView(
            children: [
              _buildPreisDauerForm('Damen'),
              _buildPreisDauerForm('Herren'),
              _buildPreisDauerForm('Kinder'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _saving ? null : _speichereAngebot,
          icon: const Icon(Icons.save),
          label: Text(_isEdit ? 'Aktualisieren' : 'Speichern'),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  // ---------- Speichern ----------
  double? _toDouble(String? s) =>
      (s == null || s.trim().isEmpty) ? null : double.tryParse(s.trim().replaceAll(',', '.'));
  int? _toInt(String? s) => (s == null || s.trim().isEmpty) ? null : int.tryParse(s.trim());
  bool _isEmpty(String? s) => s == null || s.trim().isEmpty;

  Map<String, dynamic>? _buildVariantenMapForZg(String zg) {
    if (!(_variantenOn[zg] ?? false)) return null;

    final Map<String, dynamic> out = {};
    for (final opt in _haarlaengeOptions) {
      final p = _toDouble(_varCtrls[zg]![opt]!['preis']!.text);
      final d = _toInt(_varCtrls[zg]![opt]!['dauer']!.text);
      if (p != null || d != null) {
        out[opt] = {
          if (p != null) 'preis': p,
          if (d != null) 'dauer': d,
        };
      }
    }
    if (out.isEmpty) return null;
    return out;
  }

  /// Welche Felder sollen in Firestore gelöscht werden?
  Map<String, dynamic> _buildDeleteMap() {
    final del = <String, dynamic>{};

    for (final zg in _zielgruppen) {
      final switchOn = _variantenOn[zg] ?? false;

      final preisEmpty = _isEmpty(preisController[zg]?.text);
      final dauerEmpty = _isEmpty(dauerController[zg]?.text);

      if (switchOn) {
        del['zielgruppen.$zg.preis'] = FieldValue.delete();
        del['zielgruppen.$zg.dauer'] = FieldValue.delete();
      } else {
        if (preisEmpty) del['zielgruppen.$zg.preis'] = FieldValue.delete();
        if (dauerEmpty) del['zielgruppen.$zg.dauer'] = FieldValue.delete();
      }

      if (!switchOn) {
        del['zielgruppen.$zg.varianten'] = FieldValue.delete();
      } else {
        bool anyVariantEntered = false;
        for (final opt in _haarlaengeOptions) {
          final vpEmpty = _isEmpty(_varCtrls[zg]![opt]!['preis']!.text);
          final vdEmpty = _isEmpty(_varCtrls[zg]![opt]!['dauer']!.text);
          if (vpEmpty && vdEmpty) {
            del['zielgruppen.$zg.varianten.$opt'] = FieldValue.delete();
          } else {
            anyVariantEntered = true;
          }
        }
        if (!anyVariantEntered) {
          del['zielgruppen.$zg.varianten'] = FieldValue.delete();
        }
      }

      final bool variantsAllEmpty = !switchOn ||
          _haarlaengeOptions.every((opt) =>
          _isEmpty(_varCtrls[zg]![opt]!['preis']!.text) &&
              _isEmpty(_varCtrls[zg]![opt]!['dauer']!.text));

      if (preisEmpty && dauerEmpty && variantsAllEmpty) {
        del['zielgruppen.$zg'] = FieldValue.delete();
      }
    }
    return del;
  }

  Future<void> _speichereAngebot() async {
    if (_saving) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (ausgewaehlteLeistungen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens eine Leistung wählen.')),
      );
      return;
    }

    final Map<String, dynamic> zielgruppenGesamt = {};
    for (final zg in _zielgruppen) {
      final switchOn = _variantenOn[zg] ?? false;
      final preis = switchOn ? null : _toDouble(preisController[zg]?.text);
      final dauer = switchOn ? null : _toInt(dauerController[zg]?.text);
      final varianten = _buildVariantenMapForZg(zg);

      if (preis != null || dauer != null || varianten != null) {
        zielgruppenGesamt[zg] = {
          if (preis != null) 'preis': preis,
          if (dauer != null) 'dauer': dauer,
          if (varianten != null) 'varianten': varianten,
        };
      }
    }

    // Bei Neuerstellung muss mind. eine Zielgruppe Werte haben.
    if (!_isEdit && zielgruppenGesamt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Preis und/oder Dauer angeben.')),
      );
      return;
    }

    setState(() => _saving = true);

    // Leistungen sortieren
    final servicesSorted = [...ausgewaehlteLeistungen]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final servicesWithMethod =
    servicesSorted.map(_anzeigeName).toList(growable: false);

    final comboKey = servicesSorted.map((s) => s.toLowerCase()).join('|');
    final isBundle = servicesSorted.length > 1;

    final titel = '$ausgewaehlteLeistungskategorie – ${servicesWithMethod.join(', ')}';

    // flache Methoden-Liste (nur Werte)
    final List<String> selectedMethods = <String>[];
    for (final l in servicesSorted) {
      final m = _methodeProLeistung[l]?.trim();
      if (m != null && m.isNotEmpty && !selectedMethods.contains(m)) {
        selectedMethods.add(m);
      }
    }

    final Map<String, String> methodenProLeistungGefiltert = {
      for (final l in servicesSorted)
        if ((_methodeProLeistung[l]?.trim().isNotEmpty ?? false))
          l: _methodeProLeistung[l]!.trim(),
    };

    final angebot = {
      'dienstleisterId': uid,
      'titel': titel,
      'kategorie': ausgewaehlteLeistungskategorie,
      'leistungen': servicesSorted,
      'leistungenSortiert': servicesSorted,
      'leistungenMitVarianten': servicesWithMethod, // legacy ok
      'methodenProLeistung': methodenProLeistungGefiltert,
      'comboKey': comboKey,
      'isBundle': isBundle,
      'zielgruppen': zielgruppenGesamt,
      if (selectedMethods.isNotEmpty) 'methoden': selectedMethods,
      // Legacy-Felder (bis Detailansicht umgestellt)
      if (selectedMethods.isNotEmpty) 'varianten': selectedMethods,
      if (methodenProLeistungGefiltert.isNotEmpty)
        'variantenProLeistung': methodenProLeistungGefiltert,
      if (_isEdit) 'aktualisiertAm': Timestamp.now(),
      if (!_isEdit) 'erstelltAm': Timestamp.now(),
    };

    final deletions = _buildDeleteMap();

    try {
      final col = FirebaseFirestore.instance.collection('angebote');
      if (_isEdit) {
        final ref = col.doc(widget.angebotId!);
        // 1) setzen/mergen (neue/aktualisierte Werte)
        await ref.set(angebot, SetOptions(merge: true));
        // 2) leere Felder gezielt löschen
        if (deletions.isNotEmpty) {
          await ref.update(deletions);
        }
      } else {
        // Neuanlage – hier sind deletions i.d.R. leer
        await col.add(angebot);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- Root ----------
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          _isEdit ? 'Leistung bearbeiten' : 'Leistung erstellen',
          style: const TextStyle(color: Colors.blue),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Stepper(
            type: StepperType.horizontal,
            currentStep: currentStep,
            controlsBuilder: (context, _) {
              return Column(
                children: [
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Zurück
                      ElevatedButton.icon(
                        onPressed: currentStep > 0
                            ? () {
                          setState(() {
                            currentStep = (currentStep - 1).clamp(0, 2);
                          });
                        }
                            : null,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Zurück'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.blue,
                          padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Abbrechen
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        label: const Text('Abbrechen'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Weiter
                      ElevatedButton.icon(
                        onPressed: () async {
                          // Beim Wechsel von Step 2 -> 3 frisch prüfen
                          if (currentStep == 1) {
                            if (ausgewaehlteLeistungen.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                  Text('Bitte mindestens eine Leistung wählen.'),
                                ),
                              );
                              return;
                            }
                            await _refreshDefinitionVisibility();
                          }

                          if (currentStep < 2) {
                            setState(() => currentStep += 1);
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Text('Weiter'),
                        label: const Icon(Icons.arrow_forward),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.blue,
                          padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              );
            },
            steps: [
              Step(
                title: const Text('Kategorie', style: TextStyle(color: Colors.blue)),
                content: _buildKategorieStep(),
                isActive: currentStep >= 0,
              ),
              Step(
                title: const Text('Leistungen', style: TextStyle(color: Colors.blue)),
                content: _buildLeistungenStep(),
                isActive: currentStep >= 1,
              ),
              Step(
                title: const Text('Preis & Dauer', style: TextStyle(color: Colors.blue)),
                content: _buildPreisDauerStep(),
                isActive: currentStep >= 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
