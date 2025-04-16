import 'package:flutter/material.dart';

class LeistungErstellenPage extends StatefulWidget {
  final String zielgruppe;
  final String kategorie;

  const LeistungErstellenPage({
    super.key,
    required this.zielgruppe,
    required this.kategorie,
  });

  @override
  State<LeistungErstellenPage> createState() => _LeistungErstellenPageState();
}

class _LeistungErstellenPageState extends State<LeistungErstellenPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _preisController = TextEditingController();
  final TextEditingController _dauerController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _preisController.dispose();
    _dauerController.dispose();
    super.dispose();
  }

  void _speichern() {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text.trim();
      final preis = double.tryParse(_preisController.text.trim());
      final dauer = int.tryParse(_dauerController.text.trim());

      if (preis == null || dauer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte gültige Zahlen eingeben.')),
        );
        return;
      }

      print('✅ Leistung gespeichert:');
      print('Zielgruppe: ${widget.zielgruppe}');
      print('Kategorie: ${widget.kategorie}');
      print('Name: $name');
      print('Preis: $preis');
      print('Dauer: $dauer Min');

      // TODO: Speichern in Firestore
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leistung erstellen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Zielgruppe: ${widget.zielgruppe}'),
              Text('Kategorie: ${widget.kategorie}'),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name der Leistung'),
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte einen Namen eingeben' : null,
              ),
              TextFormField(
                controller: _preisController,
                decoration: const InputDecoration(labelText: 'Preis in €'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte Preis eingeben' : null,
              ),
              TextFormField(
                controller: _dauerController,
                decoration: const InputDecoration(labelText: 'Dauer in Minuten'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                value == null || value.isEmpty ? 'Bitte Dauer eingeben' : null,
              ),
              const SizedBox(height: 30),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _speichern,
                  icon: const Icon(Icons.save),
                  label: const Text('Speichern'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}