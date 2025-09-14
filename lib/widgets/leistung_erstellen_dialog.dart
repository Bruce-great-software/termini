import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LeistungErstellenDialog extends StatefulWidget {
  final String? angebotId;
  final Map<String, dynamic>? initialData;

  const LeistungErstellenDialog({
    Key? key,
    this.angebotId,
    this.initialData,
  }) : super(key: key);

  @override
  State<LeistungErstellenDialog> createState() =>
      _LeistungErstellenDialogState();
}

// Spezielles Token aus dem Sheet, wenn bewusst "ohne Methode" gewählt wird
const String _noMethodToken = '__OHNE_METHODE__';

class _LeistungErstellenDialogState extends State<LeistungErstellenDialog>
    with SingleTickerProviderStateMixin {
  int currentStep = 0;

  String? aktuelleBranche;
  String? ausgewaehlteLeistungskategorie;

  List<String> leistungen = [];
  List<String> ausgewaehlteLeistungen = [];

  /// Ausgewählte Methode je Leistung (max. 1)
  final Map<String, String> _methodeProLeistung = {};

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

  bool _saving = false;

  bool get _isEdit => widget.angebotId != null;

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

    if (_isEdit && widget.initialData != null) {
      await _prefillFromInitial(widget.initialData!);
    }
  }

  Future<void> _prefillFromInitial(Map<String, dynamic> d) async {
    final kat = (d['kategorie'] as String?)?.trim();
    if (kat != null && kat.isNotEmpty) {
      setState(() => ausgewaehlteLeistungskategorie = kat);
      await _ladeLeistungenZurKategorie(kat);
    }

    // Leistungen
    if (d['leistungenSortiert'] is List) {
      ausgewaehlteLeistungen =
      List<String>.from(d['leistungenSortiert'] as List);
    } else if (d['leistungen'] is List) {
      ausgewaehlteLeistungen = List<String>.from(d['leistungen'] as List);
    }

    // Methoden pro Leistung (Fallback auf altes variantenProLeistung)
    if (d['methodenProLeistung'] is Map) {
      _methodeProLeistung
        ..clear()
        ..addAll((d['methodenProLeistung'] as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString())));
    } else if (d['variantenProLeistung'] is Map) {
      _methodeProLeistung
        ..clear()
        ..addAll((d['variantenProLeistung'] as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString())));
    }

    // Zielgruppen vorfüllen
    if (d['zielgruppen'] is Map) {
      final zg = Map<String, dynamic>.from(d['zielgruppen']);
      for (final name in _zielgruppen) {
        final g = zg[name];
        if (g is Map) {
          final p = g['preis'];
          final m = g['dauer'];
          preisController[name]?.text = (p == null) ? '' : '$p';
          dauerController[name]?.text = (m == null) ? '' : '$m';
        }
      }
    }
    setState(() {});
  }

  Future<void> _ladeLeistungenZurKategorie(String leistungskategorie) async {
    final snapshot =
    await FirebaseFirestore.instance.collection('leistungen').get();

    final gefilterteLeistungen = snapshot.docs
        .where((doc) {
      final data = doc.data();
      final lsks = List<String>.from(data['leistungskategorien'] ?? []);
      return lsks.contains(leistungskategorie);
    })
        .map((doc) => (doc.data()['titel'] ?? doc.id).toString())
        .toList();

    setState(() {
      leistungen = gefilterteLeistungen;
      if (!_isEdit) {
        ausgewaehlteLeistungen.clear();
        _methodeProLeistung.clear();
      } else {
        // bei Prefill alte Methoden entfernen, die nicht mehr zur Liste gehören
        _methodeProLeistung.removeWhere((k, _) => !leistungen.contains(k));
      }
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
                    onSelected: (_) async {
                      setState(() => ausgewaehlteLeistungskategorie = titel);
                      await _ladeLeistungenZurKategorie(titel);
                    },
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  // ---------- Methoden laden / Sheet ----------

  /// Lädt **Methoden** einer Leistung aus `leistungen/{titel}.methoden`
  /// (fällt zurück auf altes Feld `varianten`, falls vorhanden).
  Future<List<String>> _ladeMethodenFuerLeistung(String leistungstitel) async {
    final snap = await FirebaseFirestore.instance
        .collection('leistungen')
        .doc(leistungstitel)
        .get();

    if (!snap.exists) return [];
    final data = snap.data() as Map<String, dynamic>;

    if (data['methoden'] is List) {
      return List<String>.from(data['methoden']);
    }
    if (data['varianten'] is List) {
      // Rückwärtskompatibel lesen
      return List<String>.from(data['varianten']);
    }
    return <String>[];
  }

  Future<String?> _zeigeMethodenSheet(
      BuildContext context,
      String leistung,
      List<String> methoden,
      ) async {
    String? selected = _methodeProLeistung[leistung];
    // Wenn noch keine Methode gesetzt ist, default auf "ohne Methode"
    selected ??= _noMethodToken;

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Methode wählen – $leistung',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    // Neu: "Ohne Methode"
                    RadioListTile<String>(
                      value: _noMethodToken,
                      groupValue: selected,
                      title: const Text('Ohne Methode'),
                      subtitle: const Text('Standard ohne Zusatz'),
                      onChanged: (val) => setSheet(() => selected = val),
                    ),
                    // vorhandene Methoden
                    ...methoden.map((m) => RadioListTile<String>(
                      value: m,
                      groupValue: selected,
                      title: Text(m),
                      onChanged: (val) => setSheet(() => selected = val),
                    )),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Abbrechen'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          // durch das Default oben ist 'selected' nie null
                          onPressed: () => Navigator.pop(ctx, selected),
                          child: const Text('Übernehmen'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Auswahl-Logik ausschließlich über das Plus-/Häkchen-Icon
  Future<void> _toggleLeistung(String leistung) async {
    final already = ausgewaehlteLeistungen.contains(leistung);
    if (already) {
      // Abwählen: Leistung und ggf. Methode entfernen
      setState(() {
        ausgewaehlteLeistungen.remove(leistung);
        _methodeProLeistung.remove(leistung);
      });
      return;
    }

    // Prüfen, ob Methoden existieren
    final methoden = await _ladeMethodenFuerLeistung(leistung);

    if (methoden.isEmpty) {
      // Direkte Auswahl ohne Methoden
      setState(() => ausgewaehlteLeistungen.add(leistung));
    } else {
      final result = await _zeigeMethodenSheet(context, leistung, methoden);
      if (result == null) return; // Abgebrochen

      setState(() {
        if (result == _noMethodToken) {
          // explizit ohne Methode
          _methodeProLeistung.remove(leistung);
        } else {
          _methodeProLeistung[leistung] = result;
        }
        ausgewaehlteLeistungen.add(leistung);
      });
    }
  }

  String _anzeigeName(String leistung) {
    final m = _methodeProLeistung[leistung];
    return m == null ? leistung : '$leistung ($m)';
  }

  // ---------- Step 2: Leistungen ----------
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
          final methode = _methodeProLeistung[leistung];

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(leistung, style: const TextStyle(color: Colors.blue)),
            // ▼▼▼ Chip der gewählten Methode mit "x" ▼▼▼
            subtitle: (methode == null)
                ? null
                : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                children: [
                  Chip(
                    label: Text(methode),
                    onDeleted: () {
                      setState(() {
                        // Methode entfernen …
                        _methodeProLeistung.remove(leistung);
                        // … und Leistung wieder auf Standard zurücksetzen
                        ausgewaehlteLeistungen.remove(leistung);
                      });
                    },
                  ),
                ],
              ),
            ),

            // Auswahl nur über das Icon (kein onTap)
            trailing: IconButton(
              tooltip: selected ? 'Entfernen' : 'Hinzufügen',
              onPressed: () => _toggleLeistung(leistung),
              icon: Icon(
                selected ? Icons.check_circle : Icons.add_circle_outline,
                color: selected ? Colors.green : Colors.blue,
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Text(
          ausgewaehlteLeistungen.isEmpty
              ? 'Keine Leistung ausgewählt'
              : 'Ausgewählt: ${ausgewaehlteLeistungen.map(_anzeigeName).join(', ')}',
          style: const TextStyle(color: Colors.blueGrey),
        ),
      ],
    );
  }

  // ---------- Step 3 ----------
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
          onPressed: _saving ? null : _speichereAngebot,
          icon: const Icon(Icons.save),
          label: Text(_isEdit ? 'Aktualisieren' : 'Speichern'),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.green,
            padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Speichern ----------
  Future<void> _speichereAngebot() async {
    if (_saving) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (ausgewaehlteLeistungen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens eine Leistung wählen.')),
      );
      return;
    }

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

    if (zielgruppenGesamt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Preis und/oder Dauer für eine Zielgruppe angeben.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    // Leistungen sortieren
    final servicesSorted = [...ausgewaehlteLeistungen]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final servicesWithMethod =
    servicesSorted.map(_anzeigeName).toList(growable: false);

    final comboKey = servicesSorted.map((s) => s.toLowerCase()).join('|');
    final isBundle = servicesSorted.length > 1;

    final titel =
        '$ausgewaehlteLeistungskategorie – ${servicesWithMethod.join(', ')}';

    // flache Methoden-Liste (nur Werte), Reihenfolge gemäß servicesSorted,
    // ohne Duplikate und ohne leere Einträge
    final List<String> selectedMethods = <String>[];
    for (final l in servicesSorted) {
      final m = _methodeProLeistung[l]?.trim();
      if (m != null && m.isNotEmpty && !selectedMethods.contains(m)) {
        selectedMethods.add(m);
      }
    }

    // (optional, sauber): nur die Methoden der tatsächlich ausgewählten Leistungen speichern
    final Map<String, String> methodenProLeistungGefiltert = {
      for (final l in servicesSorted)
        if ((_methodeProLeistung[l]?.trim().isNotEmpty ?? false))
          l: _methodeProLeistung[l]!.trim(),
    };

    final angebot = {
      'dienstleisterId': uid,
      'titel': titel,
      'kategorie': ausgewaehlteLeistungskategorie,
      'leistungen': servicesSorted,
      'leistungenSortiert': servicesSorted,
      'leistungenMitVarianten': servicesWithMethod, // (Legacy-Feldname ok)
      'methodenProLeistung': methodenProLeistungGefiltert,
      'comboKey': comboKey,
      'isBundle': isBundle,
      'zielgruppen': zielgruppenGesamt,
      if (selectedMethods.isNotEmpty) 'methoden': selectedMethods,
      // --- Übergangsphase: Legacy-Felder mitschreiben, bis die Detailseite umgestellt ist ---
      if (selectedMethods.isNotEmpty) 'varianten': selectedMethods,
      if (methodenProLeistungGefiltert.isNotEmpty)
        'variantenProLeistung': methodenProLeistungGefiltert,
      // ---------------------------------------------------------------------------------------
      if (_isEdit) 'aktualisiertAm': Timestamp.now(),
      if (!_isEdit) 'erstelltAm': Timestamp.now(),
    };

    try {
      final col = FirebaseFirestore.instance.collection('angebote');
      if (_isEdit) {
        await col.doc(widget.angebotId!).set(angebot, SetOptions(merge: true));
      } else {
        await col.add(angebot);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- Root ----------
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          _isEdit ? 'Leistung bearbeiten' : 'Leistung erstellen',
          style: const TextStyle(color: Colors.blue),
        ),
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
                      // Links: Zurück
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(width: 20),

                      // MITTE: Abbrechen
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () {
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Abbrechen'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(width: 20),

                      // Rechts: Weiter
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
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                title: const Text('Leistungen',
                    style: TextStyle(color: Colors.blue)),
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
