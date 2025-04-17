import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminChipsVerwaltenPage extends StatefulWidget {
  final String branchenName;
  const AdminChipsVerwaltenPage({super.key, required this.branchenName});

  @override
  State<AdminChipsVerwaltenPage> createState() => _AdminChipsVerwaltenPageState();
}

class _AdminChipsVerwaltenPageState extends State<AdminChipsVerwaltenPage> {
  late DocumentReference brancheRef;

  @override
  void initState() {
    super.initState();
    brancheRef = FirebaseFirestore.instance
        .collection('users_config')
        .doc('branchen')
        .collection('alle')
        .doc(widget.branchenName)
        .collection('chips')
        .doc('meta');
  }

  Future<List<String>> _ladeListe(String feld) async {
    final doc = await brancheRef.get();
    final data = doc.data() as Map<String, dynamic>?;
    return List<String>.from(data?[feld] ?? []);
  }

  Future<void> _hinzufuegen(String feld, String wert) async {
    await brancheRef.set({feld: FieldValue.arrayUnion([wert])}, SetOptions(merge: true));
    setState(() {});
  }

  Future<void> _loeschen(String feld, String wert) async {
    await brancheRef.update({feld: FieldValue.arrayRemove([wert])});
    setState(() {});
  }

  Future<void> _chipDialog(String feld, String titel) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$titel hinzufügen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _hinzufuegen(feld, name);
                Navigator.pop(context);
              }
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }

  Widget _chipVerwaltung(String titel, String feld) {
    return FutureBuilder<List<String>>(
      future: _ladeListe(feld),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final werte = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(titel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _chipDialog(feld, titel),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: werte.map((wert) {
                return Chip(
                  label: Text(wert),
                  deleteIcon: const Icon(Icons.close),
                  onDeleted: () => _loeschen(feld, wert),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.branchenName} verwalten')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _chipVerwaltung('Zielgruppen', 'zielgruppen'),
            _chipVerwaltung('Kategorien', 'kategorien'),
            _chipVerwaltung('Optionen', 'optionen'),
          ],
        ),
      ),
    );
  }
}