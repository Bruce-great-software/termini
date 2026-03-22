import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/app_snackbar.dart';

class AdminLeistungErstellenPage extends StatefulWidget {
  const AdminLeistungErstellenPage({super.key});

  @override
  State<AdminLeistungErstellenPage> createState() =>
      _AdminLeistungErstellenPageState();
}

class _AdminLeistungErstellenPageState
    extends State<AdminLeistungErstellenPage> {
  final TextEditingController _leistungsController = TextEditingController();
  final TextEditingController _kategorieController = TextEditingController();
  final TextEditingController _methodenController = TextEditingController();

  List<String> _leistungen = [];
  List<String> _leistungskategorien = [];
  List<String> _branchen = [];
  List<String> _methoden = [];

  List<String> _ausgewaehlteLeistungen = [];
  List<String> _ausgewaehlteLeistungskategorien = [];
  List<String> _ausgewaehlteBranchen = [];
  List<String> _ausgewaehlteMethoden = [];

  // >>> Neue Ebene: Staffelungen
  static const String _attrHaarlaengeId = 'Haarlänge'; // Doc-ID in "definitionen"
  bool _haarlaengeAktiv = false; // Checkbox-Status in der UI
  // <<<

  @override
  void initState() {
    super.initState();
    _ladeDaten();
  }

  Future<void> _ladeDaten() async {
    final leistungenSnapshot =
    await FirebaseFirestore.instance.collection('leistungen').get();
    final kategorienSnapshot =
    await FirebaseFirestore.instance.collection('leistungskategorien').get();
    final branchenSnapshot =
    await FirebaseFirestore.instance.collection('branchen').get();
    final methodenSnapshot =
    await FirebaseFirestore.instance.collection('methoden').get();

    setState(() {
      _leistungen = leistungenSnapshot.docs.map((doc) => doc.id).toList();
      _leistungskategorien =
          kategorienSnapshot.docs.map((doc) => doc.id).toList();
      _branchen = branchenSnapshot.docs.map((doc) => doc.id).toList();
      _methoden = methodenSnapshot.docs.map((doc) => doc.id).toList();
    });
  }

  Future<void> _leistungHinzufuegen(String titel) async {
    final name = titel.trim();
    if (name.isEmpty) return;

    final docRef =
    FirebaseFirestore.instance.collection('leistungen').doc(name);
    await docRef.set({
      'titel': name,
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() => _leistungen.add(name));
    _leistungsController.clear();
  }

  Future<void> _kategorieHinzufuegen(String titel) async {
    final name = titel.trim();
    if (name.isEmpty) return;

    final aktuelleBranchen = List<String>.from(_ausgewaehlteBranchen);
    final docRef = FirebaseFirestore.instance
        .collection('leistungskategorien')
        .doc(name);
    await docRef.set({
      'titel': name,
      'created_at': FieldValue.serverTimestamp(),
      'branchen': aktuelleBranchen,
    }, SetOptions(merge: true));

    setState(() => _leistungskategorien.add(name));
    _kategorieController.clear();
  }

  Future<void> _methodeHinzufuegen(String titel) async {
    final name = titel.trim();
    if (name.isEmpty) return;

    final docRef =
    FirebaseFirestore.instance.collection('methoden').doc(name);
    await docRef.set({
      'titel': name,
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() => _methoden.add(name));
    _methodenController.clear();
  }

  /// Definition-Dokument `definitionen/Haarlaenge` sicherstellen (+ Defaults).
  Future<void> _ensureDefinitionHaarlaengeExists() async {
    final defRef =
    FirebaseFirestore.instance.collection('definitionen').doc(_attrHaarlaengeId);
    final snap = await defRef.get();
    if (!snap.exists) {
      await defRef.set({
        'id': _attrHaarlaengeId,
        'titel': 'Haarlänge',
        'options': const ['kurz', 'mittel', 'lang'],
        'created_at': FieldValue.serverTimestamp(),
        'active': true,
      }, SetOptions(merge: true));
    }
  }

  /// Speichert alle Relationen:
  /// - leistungen/{L}: branchen[], leistungskategorien[], methoden[] (flach)
  /// - leistungskategorien/{K}: branchen[], leistungen[], methoden[], definitionen[]
  /// - methoden/{M}: leistungen[], leistungskategorien[], branchen[]
  /// - definitionen/Haarlaenge: leistungen[], leistungskategorien[], branchen[]
  ///
  /// Zusätzlich: Staffelung "Haarlaenge" pro Kategorie-zu-Leistung-Zuordnung:
  ///   leistungen/{L}.definitionen.<Kategorie>  (Array)
  Future<void> _zuordnungSpeichern() async {
    if (_ausgewaehlteLeistungen.isEmpty ||
        _ausgewaehlteLeistungskategorien.isEmpty) {
      showAppSnackBar(context,
        const SnackBar(
          content: Text(
              'Bitte mindestens eine Leistung *und* eine Leistungskategorie wählen.'),
        ),
      );
      return;
    }

    // Falls aktiv, Definition-Dokument anlegen (mit Optionen)
    if (_haarlaengeAktiv) {
      await _ensureDefinitionHaarlaengeExists();
    }

    final batch = FirebaseFirestore.instance.batch();
    final hasMethoden = _ausgewaehlteMethoden.isNotEmpty;

    // ---- Leistungen aktualisieren ----
    for (final leistung in _ausgewaehlteLeistungen) {
      final refLeistung =
      FirebaseFirestore.instance.collection('leistungen').doc(leistung);

      final baseData = <String, dynamic>{
        'titel': leistung,
        'leistungskategorien':
        FieldValue.arrayUnion(_ausgewaehlteLeistungskategorien),
        'branchen': FieldValue.arrayUnion(_ausgewaehlteBranchen),
        if (hasMethoden) 'methoden': FieldValue.arrayUnion(_ausgewaehlteMethoden),
        'updated_at': FieldValue.serverTimestamp(),
      };
      batch.set(refLeistung, baseData, SetOptions(merge: true));

      // Staffelung "Haarlaenge" je gewählter Kategorie setzen/entfernen
      for (final kat in _ausgewaehlteLeistungskategorien) {
        final fieldPath = 'definitionen.$kat';
        final payload = _haarlaengeAktiv
            ? {fieldPath: FieldValue.arrayUnion([_attrHaarlaengeId])}
            : {fieldPath: FieldValue.arrayRemove([_attrHaarlaengeId])};
        batch.set(refLeistung, payload, SetOptions(merge: true));
      }

      // Aufräumen alter Felder (Legacy)
      batch.update(refLeistung, {
        'varianten': FieldValue.delete(),
        'variantenByKategorie': FieldValue.delete(),
      });
    }

    // ---- Kategorien aktualisieren (bidirektional) ----
    for (final kat in _ausgewaehlteLeistungskategorien) {
      final refKat = FirebaseFirestore.instance
          .collection('leistungskategorien')
          .doc(kat);

      final katData = <String, dynamic>{
        'branchen': FieldValue.arrayUnion(_ausgewaehlteBranchen),
        'leistungen': FieldValue.arrayUnion(_ausgewaehlteLeistungen),
        if (hasMethoden) 'methoden': FieldValue.arrayUnion(_ausgewaehlteMethoden),
        // NEU: Definitionen-Array in der Kategorie pflegen
        'definitionen': _haarlaengeAktiv
            ? FieldValue.arrayUnion([_attrHaarlaengeId])
            : FieldValue.arrayRemove([_attrHaarlaengeId]),
        'updated_at': FieldValue.serverTimestamp(),
      };
      batch.set(refKat, katData, SetOptions(merge: true));

      // altes Flag & Feld entfernen
      batch.update(refKat, {
        'varianten': FieldValue.delete(),
        'variantenAktiv': FieldValue.delete(),
      });
    }

    // ---- Methoden ebenfalls mit Meta-Relationen versorgen ----
    if (hasMethoden) {
      for (final m in _ausgewaehlteMethoden) {
        final refMeth =
        FirebaseFirestore.instance.collection('methoden').doc(m);
        batch.set(
          refMeth,
          {
            'leistungen': FieldValue.arrayUnion(_ausgewaehlteLeistungen),
            'leistungskategorien':
            FieldValue.arrayUnion(_ausgewaehlteLeistungskategorien),
            'branchen': FieldValue.arrayUnion(_ausgewaehlteBranchen),
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }

    // ---- Definitionen/Haarlaenge mit Meta-Relationen versorgen (falls aktiv) ----
    if (_haarlaengeAktiv) {
      final refDef = FirebaseFirestore.instance
          .collection('definitionen')
          .doc(_attrHaarlaengeId);

      batch.set(
        refDef,
        {
          'leistungen': FieldValue.arrayUnion(_ausgewaehlteLeistungen),
          'leistungskategorien':
          FieldValue.arrayUnion(_ausgewaehlteLeistungskategorien),
          'branchen': FieldValue.arrayUnion(_ausgewaehlteBranchen),
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    // Nach dem Speichern Status neu laden (zur Sicherheit)
    await _syncHaarlaengeFromDB();

    showAppSnackBar(context,
      const SnackBar(content: Text('Zuordnung erfolgreich gespeichert')),
    );
  }

  Widget _baueChips(
      List<String> items,
      List<String> ausgewaehlt,
      void Function(String) onChanged,
      ) {
    items.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final istAusgewaehlt = ausgewaehlt.contains(item);
        return FilterChip(
          label: Text(item),
          selected: istAusgewaehlt,
          onSelected: (_) async {
            setState(() {
              if (istAusgewaehlt) {
                ausgewaehlt.remove(item);
              } else {
                ausgewaehlt.add(item);
              }
            });
            onChanged(item);
            // Auswahl geändert -> Haarlänge-Status aus Firestore nachziehen
            await _syncHaarlaengeFromDB();
          },
        );
      }).toList(),
    );
  }

  // >>> Neue UI-Sektion: Staffelungen
  Widget _buildStaffelungenSection() {
    final disabled = _ausgewaehlteLeistungskategorien.isEmpty ||
        _ausgewaehlteLeistungen.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text("Staffelungen"),
        const SizedBox(height: 8),
        AbsorbPointer(
          absorbing: disabled,
          child: Opacity(
            opacity: disabled ? 0.5 : 1,
            child: CheckboxListTile(
              title: const Text('Haarlänge (kurz/mittel/lang)'),
              value: _haarlaengeAktiv,
              onChanged: (v) => setState(() => _haarlaengeAktiv = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              subtitle: const Text(
                'Aktivieren, wenn diese Leistung je nach Haarlänge gestaffelt wird.',
              ),
            ),
          ),
        ),
      ],
    );
  }
  // <<<

  /// Prüft anhand der aktuellen Auswahl (Kategorien × Leistungen),
  /// ob überall die Definition "Haarlaenge" gesetzt ist.
  /// Ergebnis: Checkbox an, wenn *alle* ausgewählten Kombinationen sie tragen.
  Future<void> _syncHaarlaengeFromDB() async {
    if (_ausgewaehlteLeistungskategorien.isEmpty ||
        _ausgewaehlteLeistungen.isEmpty) {
      setState(() => _haarlaengeAktiv = false);
      return;
    }

    bool allHave = true;

    for (final l in _ausgewaehlteLeistungen) {
      final snap =
      await FirebaseFirestore.instance.collection('leistungen').doc(l).get();
      final defs = (snap.data()?['definitionen'] as Map<String, dynamic>?) ?? {};

      for (final k in _ausgewaehlteLeistungskategorien) {
        final list = (defs[k] as List?)?.cast<String>() ?? const [];
        if (!list.contains(_attrHaarlaengeId)) {
          allHave = false;
        }
      }
    }

    if (mounted) {
      setState(() => _haarlaengeAktiv = allHave);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Admin Dashboard"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Erstellen"),
              Tab(text: "Verwaltung"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _erstellenTab(),
            _verwaltungTab(),
          ],
        ),
      ),
    );
  }

  Widget _erstellenTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1) Branchen
          const Text("Branchen zuordnen"),
          const SizedBox(height: 8),
          _baueChips(
            _branchen.map((b) => b[0].toUpperCase() + b.substring(1)).toList(),
            _ausgewaehlteBranchen,
                (_) {},
          ),

          const SizedBox(height: 24),

          // 2) Leistungskategorien
          const Text("Leistungskategorie hinzufügen"),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kategorieController,
                  decoration: const InputDecoration(hintText: "z. B. Haare"),
                ),
              ),
              IconButton(
                onPressed: () =>
                    _kategorieHinzufuegen(_kategorieController.text),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _baueChips(
            _leistungskategorien,
            _ausgewaehlteLeistungskategorien,
                (_) {},
          ),

          const SizedBox(height: 24),

          // 3) Leistungen
          const Text("Leistung hinzufügen"),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _leistungsController,
                  decoration:
                  const InputDecoration(hintText: "z. B. Schneiden"),
                ),
              ),
              IconButton(
                onPressed: () => _leistungHinzufuegen(_leistungsController.text),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _baueChips(
            _leistungen,
            _ausgewaehlteLeistungen,
                (_) {},
          ),

          // >>> Neue Ebene zwischen Leistung & Methoden
          _buildStaffelungenSection(),
          // <<<

          const SizedBox(height: 24),

          // 4) Methoden
          const Text("Methoden hinzufügen"),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _methodenController,
                  decoration: const InputDecoration(
                      hintText: "z. B. Faden / Zupfen / Klassisch"),
                ),
              ),
              IconButton(
                onPressed: () => _methodeHinzufuegen(_methodenController.text),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _baueChips(_methoden, _ausgewaehlteMethoden, (_) {}),

          const SizedBox(height: 24),
          Center(
            child: ElevatedButton(
              onPressed: _zuordnungSpeichern,
              child: const Text("Zuordnung speichern"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verwaltungTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                    child: Text("Leistungskategorie",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 100,
                    child: Text("Zielgruppen",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 100,
                    child: Text("Methoden",
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('leistungskategorien')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final name = doc.id;

                    final bool methodenAktiv =
                        (data['methodenAktiv'] as bool?) ??
                            (data['variantenAktiv'] as bool?) ??
                            false;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(name)),
                          SizedBox(
                            width: 100,
                            child: Switch(
                              value:
                              (data['zielgruppenAktiv'] as bool?) ?? false,
                              onChanged: (value) {
                                FirebaseFirestore.instance
                                    .collection('leistungskategorien')
                                    .doc(name)
                                    .update({'zielgruppenAktiv': value});
                              },
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Switch(
                              value: methodenAktiv,
                              onChanged: (value) {
                                FirebaseFirestore.instance
                                    .collection('leistungskategorien')
                                    .doc(name)
                                    .set({
                                  'methodenAktiv': value,
                                }, SetOptions(merge: true)).then((_) {
                                  FirebaseFirestore.instance
                                      .collection('leistungskategorien')
                                      .doc(name)
                                      .update({
                                    'variantenAktiv': FieldValue.delete()
                                  });
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
