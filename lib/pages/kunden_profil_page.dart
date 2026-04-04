import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'alle_dienstleister_page.dart';

class KundenProfilPage extends StatelessWidget {
  const KundenProfilPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const KontaktdatenBearbeitenPage();
  }
}

class KontaktdatenBearbeitenPage extends StatefulWidget {
  const KontaktdatenBearbeitenPage({super.key});

  @override
  State<KontaktdatenBearbeitenPage> createState() => _KontaktdatenBearbeitenPageState();
}

class _KontaktdatenBearbeitenPageState extends State<KontaktdatenBearbeitenPage> {
  final _vornameController = TextEditingController();
  final _nachnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonController = TextEditingController();

  String _initialVorname = '';
  String _initialNachname = '';
  String _initialEmail = '';
  String _initialTelefon = '';
  String _initialGeschlecht = 'herr';
  String _selectedGeschlecht = 'herr';

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _ladeKontaktdaten();
  }

  @override
  void dispose() {
    _vornameController.dispose();
    _nachnameController.dispose();
    _emailController.dispose();
    _telefonController.dispose();
    super.dispose();
  }

  Future<void> _ladeKontaktdaten() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data() ?? <String, dynamic>{};

    final name = (data['name'] as String?)?.trim() ?? '';
    final splitName = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    final fallbackVorname = splitName.isNotEmpty ? splitName.first : '';
    final fallbackNachname = splitName.length > 1 ? splitName.sublist(1).join(' ') : '';

    _initialVorname = (data['vorname'] as String?)?.trim().isNotEmpty == true
        ? (data['vorname'] as String).trim()
        : fallbackVorname;
    _initialNachname = (data['nachname'] as String?)?.trim().isNotEmpty == true
        ? (data['nachname'] as String).trim()
        : fallbackNachname;
    _initialEmail = (data['email'] as String?)?.trim().isNotEmpty == true
        ? (data['email'] as String).trim()
        : (user.email ?? '');
    _initialTelefon = _formatPhoneForDisplay(_readFirstNonEmptyString([
      data['phoneNumber'],
      data['phone'],
      data['telefon'],
      data['handynummer'],
    ]));
    final geschlechtRaw = (data['geschlecht'] as String?)?.trim().toLowerCase();
    _initialGeschlecht = geschlechtRaw == 'frau' ? 'frau' : 'herr';
    _selectedGeschlecht = _initialGeschlecht;

    _vornameController.text = _initialVorname;
    _nachnameController.text = _initialNachname;
    _emailController.text = _initialEmail;
    _telefonController.text = _initialTelefon;

    setState(() => _isLoading = false);
  }

  String _readFirstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  String _formatPhoneForDisplay(String value) {
    final normalized = value.replaceAll(' ', '').trim();
    if (normalized.startsWith('+49') && normalized.length > 3) {
      return '0${normalized.substring(3)}';
    }
    if (normalized.startsWith('49') && normalized.length > 2) {
      return '0${normalized.substring(2)}';
    }
    return normalized;
  }

  String _formatPhoneForStorage(String value) {
    final normalized = value.replaceAll(' ', '').trim();
    if (normalized.isEmpty) return '';
    if (normalized.startsWith('+')) return normalized;
    if (normalized.startsWith('00') && normalized.length > 2) {
      return '+${normalized.substring(2)}';
    }
    if (normalized.startsWith('0') && normalized.length > 1) {
      return '+49${normalized.substring(1)}';
    }
    if (normalized.startsWith('49') && normalized.length > 2) {
      return '+$normalized';
    }
    return normalized;
  }

  bool get _hasChanges {
    return _vornameController.text.trim() != _initialVorname ||
        _nachnameController.text.trim() != _initialNachname ||
        _emailController.text.trim() != _initialEmail ||
        _telefonController.text.trim() != _initialTelefon ||
        _selectedGeschlecht != _initialGeschlecht;
  }

  Future<void> _speichern() async {
    if (!_hasChanges || _isSaving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    final vorname = _vornameController.text.trim();
    final nachname = _nachnameController.text.trim();
    final email = _emailController.text.trim();
    final telefon = _telefonController.text.trim();
    final telefonStorage = _formatPhoneForStorage(telefon);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'vorname': vorname,
      'nachname': nachname,
      'name': '$vorname $nachname'.trim(),
      'email': email,
      'phoneNumber': telefonStorage,
      'telefon': telefonStorage,
      'handynummer': telefonStorage,
      'geschlecht': _selectedGeschlecht,
    }, SetOptions(merge: true));

    _initialVorname = vorname;
    _initialNachname = nachname;
    _initialEmail = email;
    _initialTelefon = telefon;
    _initialGeschlecht = _selectedGeschlecht;

    if (!mounted) return;
    setState(() => _isSaving = false);
  }

  void _abbrechen() {
    if (!_hasChanges || _isSaving) return;

    _vornameController.text = _initialVorname;
    _nachnameController.text = _initialNachname;
    _emailController.text = _initialEmail;
    _telefonController.text = _initialTelefon;
    _selectedGeschlecht = _initialGeschlecht;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_isLoading && !_isSaving && _hasChanges;

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Kontaktdaten')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
        color: const Color(0xFFF2F2F5),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Anrede', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Container(
                width: 220,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: _selectedGeschlecht,
                  thumbColor: const Color(0xFF404040),
                  padding: const EdgeInsets.all(2),
                  children: const {
                    'herr': Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Herr',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    'frau': Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Frau',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedGeschlecht = value);
                  },
                ),
              ),
              const SizedBox(height: 14),
              _KontaktTextField(label: 'Vorname *', controller: _vornameController, onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              _KontaktTextField(label: 'Nachname *', controller: _nachnameController, onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              _KontaktTextField(
                label: 'E-Mail *',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Text('Handynummer *', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD3D6DE)),
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🇩🇪'),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _telefonController,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSubmit ? _speichern : null,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: _isSaving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Speichern'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSubmit ? _abbrechen : null,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('Abbrechen'),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!context.mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()),
                          (route) => false,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: Colors.redAccent),
                    foregroundColor: Colors.redAccent,
                  ),
                  child: const Text('Ausloggen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KontaktTextField extends StatelessWidget {
  const _KontaktTextField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.keyboardType,
    this.prefix,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final Widget? prefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            prefixIcon: prefix == null
                ? null
                : Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Center(child: prefix),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
        ),
      ],
    );
  }
}
