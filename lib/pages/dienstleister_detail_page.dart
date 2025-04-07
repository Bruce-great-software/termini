import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DienstleisterDetailPage extends StatefulWidget {
  final Map<String, dynamic> dienstleister;
  final String selektierteZielgruppe;
  final String selektierteKategorie;

  const DienstleisterDetailPage({
    super.key,
    required this.dienstleister,
    required this.selektierteZielgruppe,
    required this.selektierteKategorie,
  });

  @override
  State<DienstleisterDetailPage> createState() => _DienstleisterDetailPageState();
}

class _DienstleisterDetailPageState extends State<DienstleisterDetailPage> {
  String ausgewaehlteZielgruppe = 'Alle';
  final List<String> zielgruppenChips = ['Alle', 'Herren', 'Damen', 'Kinder'];

  @override
  void initState() {
    super.initState();
    ausgewaehlteZielgruppe = widget.selektierteZielgruppe[0].toUpperCase() + widget.selektierteZielgruppe.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branchen')
          .doc(widget.dienstleister['branche'])
          .collection('dienstleister')
          .doc(widget.dienstleister['id'])
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final Map<String, dynamic> leistungen = data['leistungen'] ?? {};
        final Map<String, Map<String, List<Map<String, dynamic>>>> nachZielgruppen = {};

        leistungen.forEach((zielgruppe, kategorienMap) {
          final kategorien = kategorienMap as Map<String, dynamic>;
          nachZielgruppen[zielgruppe] = {};

          kategorien.forEach((kategorieName, eintraege) {
            if (eintraege is List) {
              nachZielgruppen[zielgruppe]![kategorieName] = [];
              for (var eintrag in eintraege) {
                if (eintrag is Map<String, dynamic>) {
                  nachZielgruppen[zielgruppe]![kategorieName]!.add(eintrag);
                }
              }
            }
          });
        });

        final gefiltert = ausgewaehlteZielgruppe == 'Alle'
            ? nachZielgruppen.entries
            : nachZielgruppen.entries.where((e) => e.key.toLowerCase() == ausgewaehlteZielgruppe.toLowerCase());

        return Scaffold(
          appBar: AppBar(title: Text(data['name'] ?? 'Details')),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // ⬇️ Neues: Logo anzeigen
              if (widget.dienstleister['logoUrl'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        widget.dienstleister['logoUrl'],
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

              // Zielgruppenfilter
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Row(
                  children: zielgruppenChips.map((zielgruppe) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(zielgruppe),
                        selected: ausgewaehlteZielgruppe == zielgruppe,
                        onSelected: (_) {
                          setState(() {
                            ausgewaehlteZielgruppe = zielgruppe;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Leistungsanzeige
              ...gefiltert.map((zielgruppeEintrag) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      width: double.infinity,
                      child: Center(
                        child: Text(
                          zielgruppeEintrag.key[0].toUpperCase() + zielgruppeEintrag.key.substring(1),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    ...zielgruppeEintrag.value.entries.map((kategorieEintrag) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kategorieEintrag.key[0].toUpperCase() + kategorieEintrag.key.substring(1),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            ...kategorieEintrag.value.map((leistung) {
                              final name = leistung['name'] ?? 'Unbenannt';
                              final preis = leistung['preis']?.toString() ?? '–';
                              final dauer = leistung['dauer']?.toString() ?? '–';

                              return Padding(
                                padding: const EdgeInsets.only(left: 12.0, bottom: 10.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Preis: $preis €   •   Dauer: $dauer Min',
                                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      );
                    }).toList(),
                    const Divider(height: 32),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
