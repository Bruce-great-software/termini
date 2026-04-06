import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CreateAppointmentPage extends StatefulWidget {
  final String contactId;
  final String contactName;

  const CreateAppointmentPage({
    super.key,
    required this.contactId,
    required this.contactName,
  });

  @override
  State<CreateAppointmentPage> createState() => _CreateAppointmentPageState();
}

class _CreateAppointmentPageState extends State<CreateAppointmentPage> {
  final TextEditingController _titleController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    try {
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate ?? now,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: DateTime(now.year + 5),
      );

      if (picked != null) {
        setState(() {
          _selectedDate = picked;
        });
      }
    } catch (_) {
      _showMessage('Datumsauswahl konnte nicht geöffnet werden.');
    }
  }

  Future<void> _pickTime() async {
    try {
      final picked = await showTimePicker(
        context: context,
        initialTime: _selectedTime ?? TimeOfDay.now(),
      );

      if (picked != null) {
        setState(() {
          _selectedTime = picked;
        });
      }
    } catch (_) {
      _showMessage('Uhrzeitauswahl konnte nicht geöffnet werden.');
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      _showMessage('Bitte gib einen Titel ein.');
      return;
    }

    if (_selectedDate == null) {
      _showMessage('Bitte wähle ein Datum aus.');
      return;
    }

    if (_selectedTime == null) {
      _showMessage('Bitte wähle eine Uhrzeit aus.');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    final appointmentDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    setState(() {
      _isSubmitting = true;
    });

    try {
      await FirebaseFirestore.instance.collection('appointments').add({
        'createdBy': currentUser.uid,
        'contactId': widget.contactId,
        'contactName': widget.contactName,
        'participants': [currentUser.uid, widget.contactId],
        'title': title,
        'appointmentAt': Timestamp.fromDate(appointmentDateTime),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      _showMessage('Terminanfrage konnte nicht gespeichert werden.');
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formattedDate() {
    if (_selectedDate == null) return 'Datum auswählen';
    return DateFormat('dd.MM.yyyy', 'de_DE').format(_selectedDate!);
  }

  String _formattedTime() {
    if (_selectedTime == null) return 'Uhrzeit auswählen';
    final hour = _selectedTime!.hour.toString().padLeft(2, '0');
    final minute = _selectedTime!.minute.toString().padLeft(2, '0');
    return '$hour:$minute Uhr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Termin vorschlagen'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Neuer Termin mit ${widget.contactName}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Für die erste Version erfassen wir nur Titel, Datum und Uhrzeit.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Titel',
                hintText: 'z. B. Treffen oder Termin',
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(16),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Datum',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(_formattedDate()),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(16),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Uhrzeit',
                  suffixIcon: Icon(Icons.access_time_outlined),
                ),
                child: Text(_formattedTime()),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _isSubmitting ? 'Wird gesendet...' : 'Terminanfrage senden',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
