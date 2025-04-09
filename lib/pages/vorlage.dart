import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';


class DienstleisterVorlagePage extends StatelessWidget {
  const DienstleisterVorlagePage({super.key});

  Future<void> erstelleVorlagenDienstleister() async {
    final firestore = FirebaseFirestore.instance;

    await firestore
        .collection('branchen')
        .doc('friseure')
        .collection('dienstleister')
        .add({
      'name': 'Barbershop Gentleman',
      'adresse': 'Enscheder Straße 90 A',
      'ort': 'Gronau',
      'plz': '48599',
      'geo': const GeoPoint(52.2175, 7.0222),
      'zielgruppen': ['herren', 'damen', 'kinder'],
      'leistungen': {
        'herren': {
          'haare': [
            {'name': 'Haarschnitt', 'preis': 20, 'dauer': 30},
            {'name': 'Styling', 'preis': 15, 'dauer': 15},
          ],
        },
        'damen': {
          'haare': [
            {'name': 'Waschen & Foehnen', 'preis': 25, 'dauer': 25},
          ],
        },
        'kinder': {
          'haare': [
            {'name': 'Kinderhaarschnitt', 'preis': 15, 'dauer': 20},
          ],
        },
      },
    });

    debugPrint('✅ Barbershop Gentleman wurde angelegt.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dienstleister-Vorlage')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            await erstelleVorlagenDienstleister();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dienstleister erfolgreich angelegt!')),
            );
          },
          child: const Text('Dienstleister erstellen'),
        ),
      ),
    );
  }
}

// In deiner main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MaterialApp(
    home: DienstleisterVorlagePage(),
  ));
}
