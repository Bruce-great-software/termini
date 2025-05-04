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
    ausgewaehlteZielgruppe =
        widget.selektierteZielgruppe[0].toUpperCase() + widget.selektierteZielgruppe.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final dienstleisterId = widget.dienstleister['id'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          widget.dienstleister['name'] ?? 'Profil',
          style: const TextStyle(color: Colors.black),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
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
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(dienstleisterId)
                .collection('leistungen')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final leistungen = snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

              final gefiltert = ausgewaehlteZielgruppe == 'Alle'
                  ? leistungen
                  : leistungen.where((l) => l['zielgruppe']?.toLowerCase() == ausgewaehlteZielgruppe.toLowerCase()).toList();

              final Map<String, List<Map<String, dynamic>>> gruppiert = {};
              for (var eintrag in gefiltert) {
                final kategorie = eintrag['kategorie'] ?? 'Sonstiges';
                gruppiert.putIfAbsent(kategorie, () => []).add(eintrag);
              }

              return Column(
                children: gruppiert.entries.map((eintrag) {
                  return ExpansionTile(
                    title: Text(
                      eintrag.key,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    children: eintrag.value.map((leistung) {
                      final name = leistung['name'] ?? 'Unbenannt';
                      final preis = leistung['preis']?.toString() ?? '–';
                      final dauer = leistung['dauer']?.toString() ?? '–';

                      return ListTile(
                        title: Text(name),
                        subtitle: Text('Preis: $preis €   •   Dauer: $dauer Min'),
                      );
                    }).toList(),
                  );
                }).toList(),
              );

            },
          )
        ],
      ),
    );
  }
}