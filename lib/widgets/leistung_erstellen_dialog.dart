import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LeistungErstellenDialog extends StatefulWidget {
  const LeistungErstellenDialog({Key? key}) : super(key: key);

  @override
  State<LeistungErstellenDialog> createState() => _LeistungErstellenDialogState();
}

class _LeistungErstellenDialogState extends State<LeistungErstellenDialog> {
  List<String> leistungskategorien = [];
  String? ausgewaehlteLeistungskategorie;
  List<String> leistungen = [];
  List<String> ausgewaehlteLeistungen = [];

  String? aktuelleBranche;

  @override
  void initState() {
    super.initState();
    _ladeBrancheDesDienstleisters();
  }

  Future<void> _ladeBrancheDesDienstleisters() async {
    print('➤ ladeBrancheDesDienstleisters gestartet');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = userDoc.data();
    if (data == null) return;

    final branche = data['branche'];
    print('✅ Geladene Branche: \$branche');
    if (branche == null || branche.isEmpty) return;

    setState(() {
      aktuelleBranche = branche;
    });


  }



  Future<void> _ladeLeistungenZurKategorie(String kategorie) async {
    final snapshot = await FirebaseFirestore.instance.collection('leistungen').get();

    final gefilterteLeistungen = snapshot.docs.where((doc) {
      final data = doc.data();
      final kategorien = List<String>.from(data['kategorien'] ?? []);
      return kategorien.contains(kategorie);
    }).map((doc) {
      final titel = doc.data()['titel'] ?? doc.id;
      return titel.toString();
    }).toList();

    setState(() {
      leistungen = gefilterteLeistungen;
      ausgewaehlteLeistungen.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.orange[50],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Leistungskategorie wählen'),
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
                  if (data.containsKey('branchen')) {
                    final branchen = List<String>.from(data['branchen']);
                    return branchen.map((b) => b.toLowerCase()).contains(aktuelleBranche!.toLowerCase());
                  }
                  return false;
                }).toList();

                if (docs.isEmpty) return const Text("Keine Leistungskategorien verfügbar");

                return Wrap(
                  spacing: 8,
                  children: docs.map((doc) {
                    final titel = doc['titel'] ?? doc.id;
                    return ChoiceChip(
                      label: Text(titel),
                      selected: ausgewaehlteLeistungskategorie == titel,
                      onSelected: (ausgewaehlt) {
                        setState(() {
                          ausgewaehlteLeistungskategorie = ausgewaehlt ? titel : null;
                        });
                        if (ausgewaehlt) {
                          _ladeLeistungenZurKategorie(titel);
                        } else {
                          setState(() {
                            leistungen.clear();
                            ausgewaehlteLeistungen.clear();
                          });
                        }
                      },
                    );
                  }).toList(),
                );
              },
            ),

          const SizedBox(height: 16),
          const Text('Leistungen'),
          const SizedBox(height: 8),
          if (leistungen.isEmpty)
            const Text('Keine Leistungen gefunden')
          else
            Wrap(
              spacing: 8,
              children: leistungen.map((leistung) {
                final selected = ausgewaehlteLeistungen.contains(leistung);
                return FilterChip(
                  label: Text(leistung),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        ausgewaehlteLeistungen.add(leistung);
                      } else {
                        ausgewaehlteLeistungen.remove(leistung);
                      }
                    });
                  },
                );
              }).toList(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            print("Ausgewählte Leistungen: $ausgewaehlteLeistungen");
          },
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
