import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LeistungErstellenDialog extends StatefulWidget {
  const LeistungErstellenDialog({Key? key}) : super(key: key);

  @override
  State<LeistungErstellenDialog> createState() => _LeistungErstellenDialogState();
}

class _LeistungErstellenDialogState extends State<LeistungErstellenDialog> with SingleTickerProviderStateMixin {
  int currentStep = 0;

  bool individuellePreise = false;
  String? aktuelleBranche;
  String? ausgewaehlteLeistungskategorie;
  List<String> leistungskategorien = [];
  List<String> leistungen = [];
  List<String> ausgewaehlteLeistungen = [];

  final TextEditingController standardPreisController = TextEditingController();
  final TextEditingController standardDauerController = TextEditingController();

  final Map<String, TextEditingController> preisController = {
    'Damen': TextEditingController(),
    'Herren': TextEditingController(),
    'Kinder': TextEditingController(),
  };

  final Map<String, TextEditingController> dauerController = {
    'Damen': TextEditingController(),
    'Herren': TextEditingController(),
    'Kinder': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _ladeBrancheDesDienstleisters();
  }

  Future<void> _ladeBrancheDesDienstleisters() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snapshot = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (data != null && data['branche'] != null) {
      setState(() {
        aktuelleBranche = data['branche'];
      });
    }
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

  Widget _buildKategorieStep() {
    return Column(
      children: [
        const Text('Leistungskategorie wählen', style: TextStyle(color: Colors.blue)),
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

              return Wrap(
                spacing: 8,
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final titel = data['titel'] ?? doc.id;
                  return ChoiceChip(
                    label: Text(titel, style: const TextStyle(color: Colors.white)),
                    selected: ausgewaehlteLeistungskategorie == titel,
                    selectedColor: Colors.blue,
                    backgroundColor: Colors.blue.shade100,
                    onSelected: (_) {
                      setState(() {
                        ausgewaehlteLeistungskategorie = titel;
                      });
                      _ladeLeistungenZurKategorie(titel);
                    },
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLeistungenStep() {
    if (ausgewaehlteLeistungskategorie == null) {
      return const Text('Bitte zuerst eine Leistungskategorie auswählen.', style: TextStyle(color: Colors.blue));
    }

    if (leistungen.isEmpty) {
      return const Text('Keine Leistungen gefunden.', style: TextStyle(color: Colors.blue));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: leistungen.map((leistung) {
        final selected = ausgewaehlteLeistungen.contains(leistung);
        return CheckboxListTile(
          title: Text(leistung, style: const TextStyle(color: Colors.blue)),
          value: selected,
          activeColor: Colors.blue,
          checkColor: Colors.white,
          onChanged: (value) {
            setState(() {
              if (value == true) {
                ausgewaehlteLeistungen.add(leistung);
              } else {
                ausgewaehlteLeistungen.remove(leistung);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildPreisDauerForm(String zielgruppe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        children: [
          TextFormField(
            controller: preisController[zielgruppe],
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Preis',
              suffixText: '€',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: dauerController[zielgruppe],
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Dauer',
              suffixText: 'Minuten',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreisDauerStep() {
    return Column(
      children: [
        const TabBar(
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.blueAccent,
          indicatorColor: Colors.blue,
          tabs: [
            Tab(text: 'Damen'),
            Tab(text: 'Herren'),
            Tab(text: 'Kinder'),
          ],
        ),
        SizedBox(
          height: 200,
          child: TabBarView(
            children: [
              _buildPreisDauerForm('Damen'),
              _buildPreisDauerForm('Herren'),
              _buildPreisDauerForm('Kinder'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _speichereAngebot,
          icon: const Icon(Icons.save),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Future<void> _speichereAngebot() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final titel = '$ausgewaehlteLeistungskategorie – ${ausgewaehlteLeistungen.join(', ')}';
    final Map<String, dynamic> zielgruppen = {};

    for (final ziel in ['Damen', 'Herren', 'Kinder']) {
      final preis = preisController[ziel]?.text;
      final dauer = dauerController[ziel]?.text;
      if (preis != null && preis.isNotEmpty && dauer != null && dauer.isNotEmpty) {
        zielgruppen[ziel] = {
          'preis': double.tryParse(preis) ?? 0,
          'dauer': int.tryParse(dauer) ?? 0,
        };
      }
    }

    final angebot = {
      'dienstleisterId': uid,
      'titel': titel,
      'kategorie': ausgewaehlteLeistungskategorie,
      'leistungen': ausgewaehlteLeistungen,
      'zielgruppen': zielgruppen,
      'erstelltAm': Timestamp.now(),
    };

    await FirebaseFirestore.instance.collection('angebote').add(angebot);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Leistung erstellen', style: TextStyle(color: Colors.blue)),
        content: SizedBox(
          width: double.maxFinite,
          child: Stepper(
            type: StepperType.horizontal,
            currentStep: currentStep,
            controlsBuilder: (context, _) {
              return Column(
                children: [
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: currentStep > 0
                            ? () {
                          setState(() {
                            currentStep = (currentStep - 1).clamp(0, 2);
                          });
                        }
                            : null,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Zurück'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (currentStep < 2) {
                            setState(() {
                              currentStep += 1;
                            });
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Text('Weiter'),
                        label: const Icon(Icons.arrow_forward),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              );
            },
            steps: [
              Step(
                title: const Text('Kategorie', style: TextStyle(color: Colors.blue)),
                content: _buildKategorieStep(),
                isActive: currentStep >= 0,
              ),
              Step(
                title: const Text('Leistungen', style: TextStyle(color: Colors.blue)),
                content: _buildLeistungenStep(),
                isActive: currentStep >= 1,
              ),
              Step(
                title: const Text('Preis & Dauer', style: TextStyle(color: Colors.blue)),
                content: _buildPreisDauerStep(),
                isActive: currentStep >= 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
