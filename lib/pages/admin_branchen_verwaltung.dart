import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminBranchenVerwaltungPage extends StatefulWidget {
  final String branchenId;
  const AdminBranchenVerwaltungPage({super.key, required this.branchenId});

  @override
  State<AdminBranchenVerwaltungPage> createState() => _AdminBranchenVerwaltungPageState();
}

class _AdminBranchenVerwaltungPageState extends State<AdminBranchenVerwaltungPage> {
  Map<String, dynamic> struktur = {}; // komplette Zielgruppenstruktur
  String? ausgewaehlteZielgruppe;
  String? ausgewaehlteKategorie;
  final TextEditingController zielgruppenController = TextEditingController();
  final TextEditingController kategorienController = TextEditingController();
  final TextEditingController leistungController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ladeStruktur();
  }

  Future<void> _ladeStruktur() async {
    final doc = await FirebaseFirestore.instance.collection('branchen').doc(widget.branchenId).get();
    final data = doc.data();
    if (data != null && data.containsKey('zielgruppen')) {
      setState(() {
        struktur = Map<String, dynamic>.from(data['zielgruppen'] ?? {});
      });
    }
  }

  Future<void> _speichereStruktur() async {
    await FirebaseFirestore.instance.collection('branchen').doc(widget.branchenId).set({'zielgruppen': struktur});
    _ladeStruktur();
  }

  void _zielgruppeHinzufuegen(String name) {
    if (name.trim().isEmpty || struktur.containsKey(name)) return;
    struktur[name] = {'leistungskategorien': {}};
    zielgruppenController.clear();
    _speichereStruktur();
  }

  void _zielgruppeEntfernen(String name) {
    struktur.remove(name);
    if (ausgewaehlteZielgruppe == name) ausgewaehlteZielgruppe = null;
    _speichereStruktur();
  }

  void _leistungskategorieHinzufuegen(String name) {
    if (ausgewaehlteZielgruppe == null) return;
    final kategorieMap = struktur[ausgewaehlteZielgruppe]!['leistungskategorien'] as Map;
    if (name.trim().isEmpty || kategorieMap.containsKey(name)) return;
    kategorieMap[name] = [];
    kategorienController.clear();
    _speichereStruktur();
  }

  void _leistungskategorieEntfernen(String name) {
    if (ausgewaehlteZielgruppe == null) return;
    struktur[ausgewaehlteZielgruppe]!['leistungskategorien'].remove(name);
    if (ausgewaehlteKategorie == name) ausgewaehlteKategorie = null;
    _speichereStruktur();
  }

  void _leistungHinzufuegen(String name) {
    if (ausgewaehlteZielgruppe == null || ausgewaehlteKategorie == null) return;
    final liste = struktur[ausgewaehlteZielgruppe]!['leistungskategorien'][ausgewaehlteKategorie] as List;
    if (name.trim().isEmpty || liste.contains(name)) return;
    liste.add(name);
    leistungController.clear();
    _speichereStruktur();
  }

  void _leistungEntfernen(String name) {
    final liste = struktur[ausgewaehlteZielgruppe]!['leistungskategorien'][ausgewaehlteKategorie] as List;
    liste.remove(name);
    _speichereStruktur();
  }

  @override
  Widget build(BuildContext context) {
    final zielgruppen = struktur.keys.toList();
    final leistungskategorien = ausgewaehlteZielgruppe != null
        ? (struktur[ausgewaehlteZielgruppe]!['leistungskategorien'] as Map).keys.toList()
        : [];
    final leistungen = (ausgewaehlteZielgruppe != null && ausgewaehlteKategorie != null)
        ? List<String>.from(struktur[ausgewaehlteZielgruppe]!['leistungskategorien'][ausgewaehlteKategorie])
        : [];

    return Scaffold(
      appBar: AppBar(title: const Text('Branchenstruktur verwalten')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Zielgruppen verwalten:'),
            Wrap(
              spacing: 8,
              children: zielgruppen.map((z) => InputChip(
                label: Text(z),
                selected: z == ausgewaehlteZielgruppe,
                onSelected: (_) => setState(() => ausgewaehlteZielgruppe = z),
                onDeleted: () => _zielgruppeEntfernen(z),
              )).toList(),
            ),
            Row(
              children: [
                Expanded(child: TextField(controller: zielgruppenController, decoration: const InputDecoration(hintText: 'z. B. Herren'))),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: () => _zielgruppeHinzufuegen(zielgruppenController.text), child: const Text('Hinzufügen')),
              ],
            ),

            const Divider(height: 40),
            const Text('Leistungskategorien verwalten:'),
            Wrap(
              spacing: 8,
              children: struktur.values
                  .expand((zg) => (zg['leistungskategorien'] as Map).keys)
                  .toSet()
                  .map((k) => Chip(label: Text(k)))
                  .toList(),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: kategorienController,
                    decoration: const InputDecoration(
                      hintText: 'z. B. Bart',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    if (ausgewaehlteZielgruppe != null) {
                      _leistungskategorieHinzufuegen(kategorienController.text);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bitte zuerst eine Zielgruppe auswählen.')),
                      );
                    }
                  },
                  child: const Text('Hinzufügen'),
                ),
              ],
            ),

            const Divider(height: 40),
            if (ausgewaehlteZielgruppe != null) ...[
              Text(
                'Leistungskategorien für "$ausgewaehlteZielgruppe" verwalten:',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Wrap(
                spacing: 8,
                children: leistungskategorien.map((k) => InputChip(
                  label: Text(k),
                  selected: k == ausgewaehlteKategorie,
                  onSelected: (_) => setState(() => ausgewaehlteKategorie = k),
                  onDeleted: () => _leistungskategorieEntfernen(k),
                )).toList(),
              ),
            ],

            const Divider(height: 40),
            if (ausgewaehlteKategorie != null) ...[
              Text(
                'Leistungen für "$ausgewaehlteKategorie" verwalten:',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Wrap(
                spacing: 8,
                children: leistungen.map((l) => Chip(
                  label: Text(l),
                  onDeleted: () => _leistungEntfernen(l),
                )).toList(),
              ),
              Row(
                children: [
                  Expanded(child: TextField(
                    controller: leistungController,
                    decoration: const InputDecoration(
                      labelText: 'Leistung hinzufügen',
                      hintText: 'z. B. Rasur',
                      border: OutlineInputBorder(),
                    ),
                  )),
                  const SizedBox(width: 10),
                  ElevatedButton(onPressed: () => _leistungHinzufuegen(leistungController.text), child: const Text('Hinzufügen')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
