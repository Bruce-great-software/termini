import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DienstleisterEditPageEditPage extends StatefulWidget {
  final String userId;

  const DienstleisterEditPageEditPage({super.key, required this.userId});

  @override
  _PersonalDataEditPageState createState() => _PersonalDataEditPageState();
}

class _PersonalDataEditPageState extends State<DienstleisterEditPageEditPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _adresseController = TextEditingController();
  final _ortController = TextEditingController();
  final _plzController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    final data = doc.data();

    if (data != null) {
      _nameController.text = data['name'];
      _emailController.text = data['email'];
      _adresseController.text = data['adresse'];
      _ortController.text = data['ort'];
      _plzController.text = data['plz'];
    }
  }

  Future<void> _saveData() async {
    final updatedData = {
      'name': _nameController.text,
      'email': _emailController.text,
      'adresse': _adresseController.text,
      'ort': _ortController.text,
      'plz': _plzController.text,
    };

    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update(updatedData);
    Navigator.pop(context); // Nach dem Speichern zurück
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daten bearbeiten')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _adresseController,
              decoration: const InputDecoration(labelText: 'Adresse'),
            ),
            TextField(
              controller: _ortController,
              decoration: const InputDecoration(labelText: 'Ort'),
            ),
            TextField(
              controller: _plzController,
              decoration: const InputDecoration(labelText: 'PLZ'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveData,
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}
