import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/app_snackbar.dart';

class AdminDienstleisterErstellenPage extends StatefulWidget {
  const AdminDienstleisterErstellenPage({super.key});

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
  double? latitude;
  double? longitude;

  Future<void> _createDienstleister() async {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();
      try {
        UserCredential userCredential =
        await _auth.createUserWithEmailAndPassword(
          email: email,
          password: 'defaultPassword123',
        );

        String uid = userCredential.user?.uid ?? '';

        await _firestore.collection('users').doc(uid).set({
          'name': name,
          'email': email,
          'adresse': adresse,
          'plz': plz,
          'ort': ort,
          'branche': branche,
          'dienstleisterId': uid,
          'rolle': 'dienstleister',
          'createAt': FieldValue.serverTimestamp(),
          'geo': GeoPoint(latitude ?? 0.0, longitude ?? 0.0),
        });

        Navigator.pop(context);
        showAppSnackBar(context,
          const SnackBar(content: Text('Dienstleister erfolgreich erstellt!')),
        );
      } on FirebaseAuthException catch (e) {
        showAppSnackBar(context,
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
          child: ListView(
            children: <Widget>[
              TextFormField(
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte einen Namen eingeben' : null,
                onSaved: (value) => name = value!,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte eine E-Mail-Adresse eingeben' : null,
                onSaved: (value) => email = value!,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Adresse'),
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte eine Adresse eingeben' : null,
                onSaved: (value) => adresse = value!,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Ort'),
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte einen Ort eingeben' : null,
                onSaved: (value) => ort = value!,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'PLZ'),
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte eine PLZ eingeben' : null,
                onSaved: (value) => plz = value!,
              ),

              // 👇 Geokoordinaten direkt unter PLZ eingefügt
              TextFormField(
                decoration: const InputDecoration(labelText: 'Latitude'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte Latitude eingeben' : null,
                onSaved: (value) =>
                latitude = double.tryParse(value ?? '') ?? 0.0,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Longitude'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte Longitude eingeben' : null,
                onSaved: (value) =>
                longitude = double.tryParse(value ?? '') ?? 0.0,
              ),

              // 👇 Branche kommt danach
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
