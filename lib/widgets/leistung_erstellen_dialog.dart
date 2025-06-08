import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LeistungErstellenDialog extends StatefulWidget {
  const LeistungErstellenDialog({Key? key}) : super(key: key);

  @override
  State<LeistungErstellenDialog> createState() => _LeistungErstellenDialogState();
}

class _LeistungErstellenDialogState extends State<LeistungErstellenDialog> {

  Widget _buildPreisDauerForm(String zielgruppe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        children: [
          TextFormField(
            controller: preisController[zielgruppe],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Preis für $zielgruppe (in €)',
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: dauerController[zielgruppe],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Dauer für $zielgruppe (in Minuten)',
            ),
          ),
        ],
      ),
    );
  }


  final Map<String, TextEditingController> preisController = {
    'Damen': TextEditingController(),
    'Herren': TextEditingController(),
  };

  final Map<String, TextEditingController> dauerController = {
    'Damen': TextEditingController(),
    'Herren': TextEditingController(),
  };


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



  Future<void> _ladeLeistungenZurKategorie(String leistungskategorie) async {
    final snapshot = await FirebaseFirestore.instance.collection('leistungen').get();

    final gefilterteLeistungen = snapshot.docs.where((doc) {
      final data = doc.data();
      final leistungskategorien = List<String>.from(data['leistungskategorien'] ?? []);
      return leistungskategorien.contains(leistungskategorie);
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
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
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
              if (ausgewaehlteLeistungskategorie != null)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('leistungen')
                      .where('leistungskategorien', arrayContains: ausgewaehlteLeistungskategorie)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    final docs = snapshot.data!.docs;
                    return Wrap(
                      spacing: 8,
                      children: docs.map((doc) {
                        final leistung = doc.id;
                        final selected = ausgewaehlteLeistungen.contains(leistung);
                        return FilterChip(
                          label: Text(leistung),
                          selected: selected,
                          onSelected: (bool value) {
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
                    );
                  },
                ),
              const SizedBox(height: 16),
              DefaultTabController(
                length: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Damen'),
                        Tab(text: 'Herren'),
                      ],
                    ),
                    SizedBox(
                      height: 200,
                      child: TabBarView(
                        children: [
                          _buildPreisDauerForm('Damen'),
                          _buildPreisDauerForm('Herren'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
