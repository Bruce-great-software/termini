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
  final TextEditingController _variantenController = TextEditingController();

  List<String> _leistungen = [];
  List<String> _leistungskategorien = [];
  List<String> _branchen = [];
  List<String> _varianten = [];

  List<String> _ausgewaehlteLeistungen = [];
  List<String> _ausgewaehlteLeistungskategorien = [];
  List<String> _ausgewaehlteBranchen = [];
  List<String> _ausgewaehlteVarianten = [];

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
    final variantenSnapshot =
    await FirebaseFirestore.instance.collection('varianten').get();

    setState(() {
      _leistungen = leistungenSnapshot.docs.map((doc) => doc.id).toList();
      _leistungskategorien =
          kategorienSnapshot.docs.map((doc) => doc.id).toList();
      _branchen = branchenSnapshot.docs.map((doc) => doc.id).toList();
      _varianten = variantenSnapshot.docs.map((doc) => doc.id).toList();
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
    final docRef =
    FirebaseFirestore.instance.collection('leistungskategorien').doc(name);
    await docRef.set({
      'titel': name,
      'created_at': FieldValue.serverTimestamp(),
      'branchen': aktuelleBranchen,
    }, SetOptions(merge: true));

    setState(() => _leistungskategorien.add(name));
    _kategorieController.clear();
  }

  Future<void> _varianteHinzufuegen(String titel) async {
    final name = titel.trim();
    if (name.isEmpty) return;

    final docRef =
    FirebaseFirestore.instance.collection('varianten').doc(name);
    await docRef.set({
      'titel': name,
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() => _varianten.add(name));
    _variantenController.clear();
  }

  /// Speichert alle Relationen:
  /// - leistungen/{L}: branchen[], leistungskategorien[], varianten[] (flach)
  /// - leistungen/{L}: variantenByKategorie.{Kategorie}[] (kategorie-spezifisch)
  /// - leistungskategorien/{K}: branchen[], leistungen[], varianten[]
  /// - varianten/{V}: leistungen[], leistungskategorien[], branchen[]
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
    final hasVarianten = _ausgewaehlteVarianten.isNotEmpty;

    // ---- Leistungen aktualisieren ----
    for (final leistung in _ausgewaehlteLeistungen) {
      final refLeistung =
      FirebaseFirestore.instance.collection('leistungen').doc(leistung);

      // Grunddaten + flache Variantenrelation
      final baseData = <String, dynamic>{
        'titel': leistung,
        'leistungskategorien':
        FieldValue.arrayUnion(_ausgewaehlteLeistungskategorien),
        'branchen': FieldValue.arrayUnion(_ausgewaehlteBranchen),
        if (hasVarianten) 'varianten': FieldValue.arrayUnion(_ausgewaehlteVarianten),
      };
      batch.set(refLeistung, baseData, SetOptions(merge: true));

      // Kategorie-spezifische Varianten
      if (hasVarianten) {
        final Map<String, dynamic> nested = {};
        for (final kat in _ausgewaehlteLeistungskategorien) {
          nested['variantenByKategorie.$kat'] =
              FieldValue.arrayUnion(_ausgewaehlteVarianten);
        }
        batch.set(refLeistung, nested, SetOptions(merge: true));
      }
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
          if (hasVarianten) 'varianten': FieldValue.arrayUnion(_ausgewaehlteVarianten),
        },
        SetOptions(merge: true),
      );
    }

    // ---- Varianten ebenfalls mit Meta-Relationen versorgen ----
    if (hasVarianten) {
      for (final v in _ausgewaehlteVarianten) {
        final refVar =
        FirebaseFirestore.instance.collection('varianten').doc(v);
        batch.set(
          refVar,
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

          // 4) Varianten
          const Text("Varianten hinzufügen"),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _variantenController,
                  decoration: const InputDecoration(
                      hintText: "z. B. Faden / Zupfen / Klassisch"),
                ),
              ),
              IconButton(
                onPressed: () =>
                    _varianteHinzufuegen(_variantenController.text),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _baueChips(_varianten, _ausgewaehlteVarianten, (_) {}),

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
                    child: Text("Varianten",
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
                    final zielgruppenAktiv = data['zielgruppenAktiv'] ?? false;
                    final variantenAktiv = data['variantenAktiv'] ?? false;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(name)),
                          SizedBox(
                            width: 100,
                            child: Switch(
                              value: zielgruppenAktiv,
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
                              value: variantenAktiv,
                              onChanged: (value) {
                                FirebaseFirestore.instance
                                    .collection('leistungskategorien')
                                    .doc(name)
                                    .update({'variantenAktiv': value});
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
