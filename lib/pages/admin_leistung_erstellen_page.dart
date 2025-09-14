import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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

  /// Speichert alle Relationen:
  /// - leistungen/{L}: branchen[], leistungskategorien[], methoden[] (flach)
  /// - leistungskategorien/{K}: branchen[], leistungen[], methoden[]
  /// - methoden/{M}: leistungen[], leistungskategorien[], branchen[]
  /// (alte Felder 'varianten' / 'variantenAktiv' werden bereinigt)
  Future<void> _zuordnungSpeichern() async {
    if (_ausgewaehlteLeistungen.isEmpty ||
        _ausgewaehlteLeistungskategorien.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Bitte mindestens eine Leistung *und* eine Leistungskategorie wählen.'),
        ),
      );
      return;
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
      };
      batch.set(refLeistung, baseData, SetOptions(merge: true));

      // Aufräumen alter Felder
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

      batch.set(
        refKat,
        {
          'branchen': FieldValue.arrayUnion(_ausgewaehlteBranchen),
          'leistungen': FieldValue.arrayUnion(_ausgewaehlteLeistungen),
          if (hasMethoden) 'methoden': FieldValue.arrayUnion(_ausgewaehlteMethoden),
        },
        SetOptions(merge: true),
      );

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
          },
          SetOptions(merge: true),
        );
      }
    }

    await batch.commit();

    ScaffoldMessenger.of(context).showSnackBar(
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
          onSelected: (_) {
            setState(() {
              if (istAusgewaehlt) {
                ausgewaehlt.remove(item);
              } else {
                ausgewaehlt.add(item);
              }
            });
            onChanged(item);
          },
        );
      }).toList(),
    );
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
              _leistungskategorien, _ausgewaehlteLeistungskategorien, (_) {}),

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
                onPressed: () =>
                    _leistungHinzufuegen(_leistungsController.text),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _baueChips(_leistungen, _ausgewaehlteLeistungen, (_) {}),

          const SizedBox(height: 24),

          // 4) Methoden (früher: Varianten)
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

                    // Fallback: altes Flag variantenAktiv noch unterstützen
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
                              value: (data['zielgruppenAktiv'] as bool?) ?? false,
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
                                  // altes Flag entfernen
                                  FirebaseFirestore.instance
                                      .collection('leistungskategorien')
                                      .doc(name)
                                      .update({'variantenAktiv': FieldValue.delete()});
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
