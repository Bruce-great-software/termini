import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminDienstleisterErstellenPage extends StatefulWidget {
  const AdminDienstleisterErstellenPage({Key? key}) : super(key: key);

  @override
  _AdminDienstleisterErstellenPageState createState() =>
      _AdminDienstleisterErstellenPageState();
}

class _AdminDienstleisterErstellenPageState
    extends State<AdminDienstleisterErstellenPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String name = '';
  String email = '';
  String adresse = '';
  String plz = '';
  String ort = '';
  String branche = 'friseure';

  Future<void> _createDienstleister() async {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        // Nutzer in Firebase Authentication anlegen
        UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: 'defaultPassword123', // Ein Standardpasswort für den Dienstleister
        );

        // UID des Nutzers aus Authentication
        String uid = userCredential.user?.uid ?? '';

        // Daten in der Firestore-Sammlung 'users' speichern
        await _firestore.collection('users').doc(uid).set({
          'name': name,
          'email': email,
          'adresse': adresse,
          'plz': plz,
          'ort': ort,
          'branche': branche,
          'dienstleisterId': uid, // UID als Dienstleister-ID
          'rolle': 'dienstleister',
          'createAt': FieldValue.serverTimestamp(),
        });

        // Erfolgreiche Erstellung, zur Admin-Seite zurückkehren
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dienstleister erfolgreich erstellt!')),
        );
      } on FirebaseAuthException catch (e) {
        // Fehler beim Erstellen des Nutzers
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dienstleister erstellen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextFormField(
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bitte einen Namen eingeben';
                  }
                  return null;
                },
                onSaved: (value) => name = value!,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bitte eine E-Mail-Adresse eingeben';
                  }
                  return null;
                },
                onSaved: (value) => email = value!,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Adresse'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bitte eine Adresse eingeben';
                  }
                  return null;
                },
                onSaved: (value) => adresse = value!,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'PLZ'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bitte eine PLZ eingeben';
                  }
                  return null;
                },
                onSaved: (value) => plz = value!,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Ort'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bitte einen Ort eingeben';
                  }
                  return null;
                },
                onSaved: (value) => ort = value!,
              ),
              DropdownButtonFormField<String>(
                value: branche,
                items: <String>['friseure', 'kosmetiker', 'massagen']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    branche = value!;
                  });
                },
                decoration: const InputDecoration(labelText: 'Branche'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _createDienstleister,
                child: const Text('Dienstleister speichern'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
