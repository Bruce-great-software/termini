import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DienstleisterHomePage extends StatefulWidget {
  const DienstleisterHomePage({super.key});

  @override
  State<DienstleisterHomePage> createState() => _DienstleisterHomePageState();
}

class _DienstleisterHomePageState extends State<DienstleisterHomePage> {
  Map<String, dynamic>? dienstleisterDaten;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _ladeDienstleisterDaten();
  }

  Future<void> _ladeDienstleisterDaten() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = userDoc.data();

      if (data != null && data['rolle'] == 'dienstleister') {
        final branche = data['branche'];
        final dienstleisterId = data['dienstleisterId'];

        final dsDoc = await FirebaseFirestore.instance
            .collection('branchen')
            .doc(branche)
            .collection('dienstleister')
            .doc(dienstleisterId)
            .get();

        if (dsDoc.exists) {
          setState(() {
            dienstleisterDaten = dsDoc.data();
            isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dienstleister Übersicht')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : dienstleisterDaten == null
          ? const Center(child: Text('Keine Daten gefunden.'))
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Willkommen, ${dienstleisterDaten!['name'] ?? 'Unbekannt'}!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text('Adresse: ${dienstleisterDaten!['adresse'] ?? '-'}'),
            Text('PLZ: ${dienstleisterDaten!['plz'] ?? '-'}'),
            Text('Ort: ${dienstleisterDaten!['ort'] ?? '-'}'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Platz für zukünftige Navigation (Leistungen, Öffnungszeiten etc.)
              },
              child: const Text('Leistungen verwalten'),
            ),
          ],
        ),
      ),
    );
  }
}
