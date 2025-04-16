import 'package:flutter/material.dart';
import '../pages/leistung_erstellen_page.dart';

class StepDialog extends StatefulWidget {
  const StepDialog({super.key});

  @override
  State<StepDialog> createState() => _StepDialogState();
}

class _StepDialogState extends State<StepDialog> {
  int _step = 0;
  String? zielgruppe;
  String? kategorie;

  final zielgruppen = ['Damen', 'Herren', 'Kinder'];
  final kategorien = ['Haare', 'Bart', 'Gesicht'];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _preisController = TextEditingController();
  final TextEditingController _dauerController = TextEditingController();

  void _weiter() {
    if (_step == 0 && zielgruppe == null) return;
    if (_step == 1 && kategorie == null) return;
    if (_step == 2 && !_formValid()) return;

    if (_step < 2) {
      setState(() => _step++);
    } else {
      Navigator.pop(context); // Dialog schließen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LeistungErstellenPage(
            zielgruppe: zielgruppe!,
            kategorie: kategorie!,
          ),
        ),
      );
    }
  }

  bool _formValid() {
    return _nameController.text.trim().isNotEmpty &&
        _preisController.text.trim().isNotEmpty &&
        _dauerController.text.trim().isNotEmpty;
  }

  void _zurueck() {
    if (_step > 0) setState(() => _step--);
  }

  Widget _buildHeader() {
    List<IconData> icons = [Icons.person, Icons.category, Icons.edit];
    List<String> labels = ['Zielgruppe', 'Kategorie', 'Leistung'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(3, (index) {
        final isActive = _step == index;
        final isDone = _step > index;
        return Column(
          children: [
            CircleAvatar(
              backgroundColor:
              isDone ? Colors.green : isActive ? Colors.deepOrange : Colors.grey[300],
              child: Icon(
                icons[index],
                color: isDone || isActive ? Colors.white : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              labels[index],
              style: TextStyle(
                fontSize: 12,
                color: isDone || isActive ? Colors.black : Colors.grey,
              ),
            )
          ],
        );
      }),
    );
  }

  Widget _buildStepContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _step == 0
          ? _buildAuswahl(zielgruppen, zielgruppe, (value) => setState(() => zielgruppe = value))
          : _step == 1
          ? _buildAuswahl(kategorien, kategorie, (value) => setState(() => kategorie = value))
          : _buildFormular(),
    );
  }

  Widget _buildAuswahl(
      List<String> optionen, String? selected, Function(String) onSelected) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: optionen.map((option) {
        final isSelected = selected == option;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          selectedColor: Colors.deepOrange,
          onSelected: (_) => onSelected(option),
        );
      }).toList(),
    );
  }

  Widget _buildFormular() {
    return Column(
      key: const ValueKey('formular'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Name der Leistung'),
        ),
        TextFormField(
          controller: _preisController,
          decoration: const InputDecoration(labelText: 'Preis in €'),
          keyboardType: TextInputType.number,
        ),
        TextFormField(
          controller: _dauerController,
          decoration: const InputDecoration(labelText: 'Dauer in Minuten'),
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _buildHeader(),
      content: SizedBox(
        width: double.maxFinite,
        child: _buildStepContent(),
      ),
      actions: [
        if (_step > 0)
          TextButton(
            onPressed: _zurueck,
            child: const Text('Zurück'),
          ),
        ElevatedButton(
          onPressed: _weiter,
          child: Text(_step < 2 ? 'Weiter' : 'Loslegen'),
        ),
      ],
    );
  }
}