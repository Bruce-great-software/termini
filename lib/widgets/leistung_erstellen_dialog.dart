// Speichern-Button wird aktiviert nach Eingabe aller Felder inkl. Dauer
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
  String? kategorie;
  List<String> ausgewaehlteOptionen = [];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _preisController = TextEditingController();
  final TextEditingController _dauerController = TextEditingController();

  List<String> zielgruppen = [];
  List<String> kategorien = [];
  List<String> optionen = ['Schneiden', 'Waschen', 'Föhnen', 'Stylen'];

  @override
  void initState() {
    super.initState();
    _ladeZielgruppenUndKategorien();
  }

  Future<void> _ladeZielgruppenUndKategorien() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final branche = userDoc.data()?['branche'];
    if (branche == null) return;

    final doc = await FirebaseFirestore.instance.collection('branchen').doc(branche.toString().toLowerCase()).get();
    final data = doc.data();
    if (data != null) {
      setState(() {
        zielgruppen = List<String>.from(data['zielgruppe'] ?? []);
        kategorien = List<String>.from(data['kategorien'] ?? []);
      });
    }
  }

  bool _formValid() {
    return _nameController.text.trim().isNotEmpty &&
        _preisController.text.trim().isNotEmpty &&
        _dauerController.text.trim().isNotEmpty;
  }

  void _updateLeistungsName() {
    if (zielgruppe != null && ausgewaehlteOptionen.isNotEmpty) {
      final name = "$zielgruppe - ${ausgewaehlteOptionen.join(', ')}";
      _nameController.text = name;
    }
  }

  Future<void> _leistungSpeichern() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final preis = double.tryParse(_preisController.text.trim());
    final dauer = int.tryParse(_dauerController.text.trim());

    if (preis == null || dauer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gültige Zahlen eingeben.')),
      );
      return;
    }

    final leistung = {
      'name': _nameController.text.trim(),
      'zielgruppe': zielgruppe,
      'kategorie': kategorie,
      'optionen': ausgewaehlteOptionen,
      'preis': preis,
      'dauer': dauer,
      'createdAt': Timestamp.now(),
    };

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('leistungen')
        .add(leistung);

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leistung erfolgreich gespeichert.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color chipSelectedColor = Colors.deepOrange;
    final Color chipTextColor = Colors.white;

    return AlertDialog(
      backgroundColor: Colors.white,
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Zielgruppe', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: zielgruppen.map((z) {
                  return ChoiceChip(
                    label: Text(z, style: TextStyle(color: zielgruppe == z ? chipTextColor : null)),
                    selected: zielgruppe == z,
                    onSelected: (_) => setState(() {
                      zielgruppe = z;
                      kategorie = null;
                      ausgewaehlteOptionen.clear();
                      _nameController.clear();
                      _preisController.clear();
                      _dauerController.clear();
                      _updateLeistungsName();
                    }),
                    selectedColor: chipSelectedColor,
                  );
                }).toList(),
              ),
              if (zielgruppe != null) ...[
                const SizedBox(height: 20),
                const Text('Kategorie', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: kategorien.map((k) {
                    return ChoiceChip(
                      label: Text(k, style: TextStyle(color: kategorie == k ? chipTextColor : null)),
                      selected: kategorie == k,
                      onSelected: (_) => setState(() {
                        kategorie = k;
                      }),
                      selectedColor: chipSelectedColor,
                    );
                  }).toList(),
                ),
              ],
              if (zielgruppe != null && kategorie != null) ...[
                const SizedBox(height: 20),
                const Text('Inklusive Optionen:'),
                Wrap(
                  spacing: 10,
                  children: optionen.map((opt) {
                    final selected = ausgewaehlteOptionen.contains(opt);
                    return FilterChip(
                      label: Text(opt, style: TextStyle(color: selected ? chipTextColor : null)),
                      selected: selected,
                      selectedColor: chipSelectedColor,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            ausgewaehlteOptionen.add(opt);
                          } else {
                            ausgewaehlteOptionen.remove(opt);
                          }
                          _updateLeistungsName();
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
              if (zielgruppe != null && kategorie != null && ausgewaehlteOptionen.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Leistung', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Name der Leistung'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _preisController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Preis in €'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _dauerController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dauer in Minuten'),
                  onChanged: (_) => setState(() {}),
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
      ),
    );
  }
}