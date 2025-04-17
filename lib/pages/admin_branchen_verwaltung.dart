import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminBranchenVerwaltungPage extends StatefulWidget {
  final String brancheId;

  const AdminBranchenVerwaltungPage({super.key, required this.brancheId});

  @override
  State<AdminBranchenVerwaltungPage> createState() => _AdminBranchenVerwaltungPageState();
}

class _AdminBranchenVerwaltungPageState extends State<AdminBranchenVerwaltungPage> {
  List<String> zielgruppen = [];
  List<String> kategorien = [];
  final TextEditingController _zielgruppenController = TextEditingController();
  final TextEditingController _kategorienController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ladeBranchenDaten();
  }

  Future<void> _ladeBranchenDaten() async {
    final doc = await FirebaseFirestore.instance
        .collection('branchen')
        .doc(widget.brancheId)
        .get();

    final data = doc.data();
    if (data != null) {
      setState(() {
        zielgruppen = List<String>.from(data['zielgruppe'] ?? []);
        kategorien = List<String>.from(data['kategorien'] ?? []);
      });
    }
  }

  Future<void> _zielgruppeHinzufuegen(String neueZielgruppe) async {
    if (neueZielgruppe.trim().isEmpty || zielgruppen.contains(neueZielgruppe)) return;

    final updated = List<String>.from(zielgruppen)..add(neueZielgruppe.trim());
    await FirebaseFirestore.instance
        .collection('branchen')
        .doc(widget.brancheId)
        .update({'zielgruppe': updated});

    _zielgruppenController.clear();
    _ladeBranchenDaten();
  }

  Future<void> _zielgruppeEntfernen(String zielgruppe) async {
    final updated = List<String>.from(zielgruppen)..remove(zielgruppe);
    await FirebaseFirestore.instance
        .collection('branchen')
        .doc(widget.brancheId)
        .update({'zielgruppe': updated});

    _ladeBranchenDaten();
  }

  Future<void> _kategorieHinzufuegen(String neueKategorie) async {
    if (neueKategorie.trim().isEmpty || kategorien.contains(neueKategorie)) return;

    final updated = List<String>.from(kategorien)..add(neueKategorie.trim());
    await FirebaseFirestore.instance
        .collection('branchen')
        .doc(widget.brancheId)
        .update({'kategorien': updated});

    _kategorienController.clear();
    _ladeBranchenDaten();
  }

  Future<void> _kategorieEntfernen(String kategorie) async {
    final updated = List<String>.from(kategorien)..remove(kategorie);
    await FirebaseFirestore.instance
        .collection('branchen')
        .doc(widget.brancheId)
        .update({'kategorien': updated});

    _ladeBranchenDaten();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Branchenverwaltung')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Zielgruppen verwalten:'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: zielgruppen.map((z) {
                return Chip(
                  label: Text(z),
                  onDeleted: () => _zielgruppeEntfernen(z),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _zielgruppenController,
                    decoration: const InputDecoration(hintText: 'z. B. Senioren'),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _zielgruppeHinzufuegen(_zielgruppenController.text),
                  child: const Text('Hinzufügen'),
                ),
              ],
            ),
            const Divider(height: 40),
            const Text('Kategorien verwalten:'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: kategorien.map((k) {
                return Chip(
                  label: Text(k),
                  onDeleted: () => _kategorieEntfernen(k),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _kategorienController,
                    decoration: const InputDecoration(hintText: 'z. B. Haare'),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _kategorieHinzufuegen(_kategorienController.text),
                  child: const Text('Hinzufügen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
