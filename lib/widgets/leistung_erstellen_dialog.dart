// Neuer Dialog basierend auf admin_branchen_verwaltung-Struktur
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LeistungErstellenDialog extends StatefulWidget {
  const LeistungErstellenDialog({super.key});

  @override
  State<LeistungErstellenDialog> createState() => _LeistungErstellenDialogState();
}

class _LeistungErstellenDialogState extends State<LeistungErstellenDialog> {
  String? zielgruppe;
  String? leistungskategorie;
  String? leistung;

  final TextEditingController _preisController = TextEditingController();
  final TextEditingController _dauerController = TextEditingController();

  Map<String, dynamic> struktur = {}; // komplette Struktur aus Firestore

  @override
  void initState() {
    super.initState();
    _ladeBranchenStruktur();
    _preisController.addListener(_onFormChanged);
    _dauerController.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _preisController.removeListener(_onFormChanged);
    _dauerController.removeListener(_onFormChanged);
    _preisController.dispose();
    _dauerController.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    setState(() {});
  }

  Future<void> _ladeBranchenStruktur() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final branche = userDoc.data()?['branche'];
    if (branche == null) return;

    final branchenDoc = await FirebaseFirestore.instance.collection('branchen').doc(branche.toLowerCase()).get();
    final data = branchenDoc.data();
    if (data != null && data.containsKey('zielgruppen')) {
      setState(() {
        struktur = Map<String, dynamic>.from(data['zielgruppen']);
      });
    }
  }

  List<String> getZielgruppen() => struktur.keys.toList();

  List<String> getLeistungskategorien() {
    if (zielgruppe == null) return [];
    final map = struktur[zielgruppe]?['leistungskategorien'] as Map<String, dynamic>?;
    return map?.keys.toList() ?? [];
  }

  List<String> getLeistungen() {
    if (zielgruppe == null || leistungskategorie == null) return [];
    final list = struktur[zielgruppe]?['leistungskategorien']?[leistungskategorie] as List<dynamic>?;
    return List<String>.from(list ?? []);
  }

  bool _formValid() =>
      zielgruppe != null &&
          leistungskategorie != null &&
          leistung != null &&
          _preisController.text.trim().isNotEmpty &&
          _dauerController.text.trim().isNotEmpty;

  Future<void> _leistungSpeichern() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final preis = double.tryParse(_preisController.text.trim());
    final dauer = int.tryParse(_dauerController.text.trim());

    if (preis == null || dauer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gültige Preis- und Dauerangaben machen.')),
      );
      return;
    }

    final leistungObjekt = {
      'name': "$zielgruppe - $leistung",
      'zielgruppe': zielgruppe,
      'kategorie': leistungskategorie,
      'leistung': leistung,
      'preis': preis,
      'dauer': dauer,
      'createdAt': Timestamp.now(),
    };

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('leistungen')
        .add(leistungObjekt);

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leistung erfolgreich gespeichert.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Leistung erstellen'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              value: zielgruppe,
              hint: const Text('Zielgruppe wählen'),
              isExpanded: true,
              items: getZielgruppen().map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
              onChanged: (val) => setState(() {
                zielgruppe = val;
                leistungskategorie = null;
                leistung = null;
              }),
            ),
            if (zielgruppe != null)
              DropdownButton<String>(
                value: leistungskategorie,
                hint: const Text('Leistungskategorie wählen'),
                isExpanded: true,
                items: getLeistungskategorien().map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                onChanged: (val) => setState(() {
                  leistungskategorie = val;
                  leistung = null;
                }),
              ),
            if (leistungskategorie != null)
              DropdownButton<String>(
                value: leistung,
                hint: const Text('Leistung wählen'),
                isExpanded: true,
                items: getLeistungen().map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (val) => setState(() => leistung = val),
              ),
            if (leistung != null) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _preisController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Preis in €'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dauerController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Dauer in Minuten'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _formValid() ? _leistungSpeichern : null,
                child: const Text('Speichern'),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
