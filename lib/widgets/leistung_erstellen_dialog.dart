import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LeistungErstellenDialog extends StatefulWidget {
  const LeistungErstellenDialog({Key? key}) : super(key: key);

  @override
  State<LeistungErstellenDialog> createState() =>
      _LeistungErstellenDialogState();
}

class _LeistungErstellenDialogState extends State<LeistungErstellenDialog>
    with SingleTickerProviderStateMixin {
  int currentStep = 0;

  String? aktuelleBranche;
  String? ausgewaehlteLeistungskategorie;

  List<String> leistungen = [];
  List<String> ausgewaehlteLeistungen = [];

  // Step 3 – Preis & Dauer pro Zielgruppe (einheitlich)
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

  static const List<String> _zielgruppen = ['Damen', 'Herren', 'Kinder'];

  @override
  void initState() {
    super.initState();
    _ladeBrancheDesDienstleisters();
  }

  @override
  void dispose() {
    for (final c in preisController.values) c.dispose();
    for (final c in dauerController.values) c.dispose();
    super.dispose();
  }

  Future<void> _ladeBrancheDesDienstleisters() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snapshot =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (data != null && data['branche'] != null) {
      setState(() => aktuelleBranche = data['branche']);
    }
  }

  Future<void> _ladeLeistungenZurKategorie(String leistungskategorie) async {
    final snapshot =
    await FirebaseFirestore.instance.collection('leistungen').get();

    final gefilterteLeistungen = snapshot.docs.where((doc) {
      final data = doc.data();
      final lsks = List<String>.from(data['leistungskategorien'] ?? []);
      return lsks.contains(leistungskategorie);
    }).map((doc) {
      final titel = doc.data()['titel'] ?? doc.id;
      return titel.toString();
    }).toList();

    setState(() {
      leistungen = gefilterteLeistungen;
      ausgewaehlteLeistungen.clear();
    });
  }

  // ---------- Step 1: Kategorie ----------
  Widget _buildKategorieStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Leistungskategorie wählen',
            style: TextStyle(color: Colors.blue)),
        const SizedBox(height: 8),
        if (aktuelleBranche == null)
          const CircularProgressIndicator()
        else
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('leistungskategorien')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (!data.containsKey('branchen')) return false;
                final branchen = List<String>.from(data['branchen']);
                return branchen
                    .map((b) => b.toLowerCase())
                    .contains(aktuelleBranche!.toLowerCase());
              }).toList();

              return Wrap(
                spacing: 8,
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final titel = data['titel'] ?? doc.id;
                  final selected = ausgewaehlteLeistungskategorie == titel;
                  return ChoiceChip(
                    label:
                    Text(titel, style: const TextStyle(color: Colors.white)),
                    selected: selected,
                    selectedColor: Colors.blue,
                    backgroundColor: Colors.blue.shade100,
                    onSelected: (_) {
                      setState(() => ausgewaehlteLeistungskategorie = titel);
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

  // ---------- Step 2: Nur Auswahl der Leistungen (KEINE Auflistung darunter) ----------
  Widget _buildLeistungenStep() {
    if (ausgewaehlteLeistungskategorie == null) {
      return const Text(
        'Bitte zuerst eine Leistungskategorie auswählen.',
        style: TextStyle(color: Colors.blue),
      );
    }
    if (leistungen.isEmpty) {
      return const Text(
        'Keine Leistungen gefunden.',
        style: TextStyle(color: Colors.blue),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...leistungen.map((leistung) {
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
        }),
        const SizedBox(height: 8),
        Text(
          ausgewaehlteLeistungen.isEmpty
              ? 'Keine Leistung ausgewählt'
              : 'Ausgewählt: ${ausgewaehlteLeistungen.join(', ')}',
          style: const TextStyle(color: Colors.blueGrey),
        ),
      ],
    );
  }

  // ---------- Step 3: Preis & Dauer je Zielgruppe ----------
  Widget _buildPreisDauerForm(String zielgruppe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        children: [
          TextFormField(
            controller: preisController[zielgruppe],
            keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
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
          height: 220,
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
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  // ---------- Speichern ----------
  Future<void> _speichereAngebot() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Zielgruppen-Preise/Dauern einsammeln (einheitlicher Block)
    final Map<String, dynamic> zielgruppenGesamt = {};
    for (final zg in _zielgruppen) {
      final preis = preisController[zg]?.text.trim();
      final dauer = dauerController[zg]?.text.trim();
      if ((preis ?? '').isNotEmpty || (dauer ?? '').isNotEmpty) {
        zielgruppenGesamt[zg] = {
          if ((preis ?? '').isNotEmpty) 'preis': double.tryParse(preis!) ?? 0,
          if ((dauer ?? '').isNotEmpty) 'dauer': int.tryParse(dauer!) ?? 0,
        };
      }
    }

    final titel =
        '$ausgewaehlteLeistungskategorie – ${ausgewaehlteLeistungen.join(', ')}';

    final angebot = {
      'dienstleisterId': uid,
      'titel': titel,
      'kategorie': ausgewaehlteLeistungskategorie,
      'leistungen': ausgewaehlteLeistungen,
      'zielgruppen': zielgruppenGesamt, // nur Gesamt (kein Listing darunter)
      'erstelltAm': Timestamp.now(),
    };

    await FirebaseFirestore.instance.collection('angebote').add(angebot);
    if (mounted) Navigator.of(context).pop();
  }

  // ---------- Root ----------
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Leistung erstellen',
            style: TextStyle(color: Colors.blue)),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (currentStep < 2) {
                            setState(() => currentStep += 1);
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Text('Weiter'),
                        label: const Icon(Icons.arrow_forward),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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
                title:
                const Text('Kategorie', style: TextStyle(color: Colors.blue)),
                content: _buildKategorieStep(),
                isActive: currentStep >= 0,
              ),
              Step(
                title:
                const Text('Leistungen', style: TextStyle(color: Colors.blue)),
                content: _buildLeistungenStep(),
                isActive: currentStep >= 1,
              ),
              Step(
                title: const Text('Preis & Dauer',
                    style: TextStyle(color: Colors.blue)),
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
