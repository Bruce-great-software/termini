import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DienstleisterRegistrierungPage extends StatefulWidget {
  const DienstleisterRegistrierungPage({super.key});

  @override
  State<DienstleisterRegistrierungPage> createState() => _DienstleisterRegistrierungPageState();
}

class _DienstleisterRegistrierungPageState extends State<DienstleisterRegistrierungPage> {
  final _formKey = GlobalKey<FormState>();
  final _firmennameController = TextEditingController();
  final _adresseController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwortController = TextEditingController();
  String? _ausgewaehlteBranche;
  final _branchen = ['Friseur', 'Kosmetiker', 'Massagen'];

  Future<void> _registrieren() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwortController.text.trim(),
      );

      await FirebaseFirestore.instance.collection('nutzer').doc(credential.user!.uid).set({
        'rolle': 'dienstleister',
        'freigeschaltet': false,
        'name': _firmennameController.text.trim(),
        'adresse': _adresseController.text.trim(),
        'branche': _ausgewaehlteBranche,
        'email': _emailController.text.trim(),
        'erstelltAm': Timestamp.now(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registrierung erfolgreich – wird geprüft.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dienstleister registrieren')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _firmennameController,
                  decoration: const InputDecoration(labelText: 'Firmenname'),
                  validator: (value) => value == null || value.isEmpty ? 'Bitte Firmenname eingeben' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adresseController,
                  decoration: const InputDecoration(labelText: 'Adresse'),
                  validator: (value) => value == null || value.isEmpty ? 'Bitte Adresse eingeben' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _ausgewaehlteBranche,
                  decoration: const InputDecoration(labelText: 'Branche'),
                  items: _branchen.map((branche) => DropdownMenuItem(value: branche, child: Text(branche))).toList(),
                  onChanged: (value) => setState(() => _ausgewaehlteBranche = value),
                  validator: (value) => value == null ? 'Bitte Branche auswählen' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                  validator: (value) => value == null || value.isEmpty ? 'Bitte E-Mail eingeben' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwortController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Passwort'),
                  validator: (value) => value == null || value.length < 6 ? 'Mind. 6 Zeichen' : null,
                ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton(
                    onPressed: _registrieren,
                    child: const Text('Registrieren'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
