import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PartnerWerdenPage extends StatefulWidget {
  const PartnerWerdenPage({super.key});

  @override
  State<PartnerWerdenPage> createState() => _PartnerWerdenPageState();
}

class _PartnerWerdenPageState extends State<PartnerWerdenPage> {
  // Geschäft
  final TextEditingController geschaeftController = TextEditingController();
  final TextEditingController strasseController = TextEditingController();
  final TextEditingController hausnummerController = TextEditingController();
  final TextEditingController plzController = TextEditingController();
  final TextEditingController stadtController = TextEditingController();

  // Eigentümer
  final TextEditingController vornameController = TextEditingController();
  final TextEditingController nachnameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController telefonController = TextEditingController();
  final TextEditingController passwortController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String? branche;
  bool _isSubmitting = false;
  bool _isSubmittedSuccessfully = false;

  final List<String> branchenListe = [
    "Friseur",
    "Barbershop",
    "Kosmetikstudio",
    "Nagelstudio",
    "Massage",
  ];

  @override
  void dispose() {
    geschaeftController.dispose();
    strasseController.dispose();
    hausnummerController.dispose();
    plzController.dispose();
    stadtController.dispose();
    vornameController.dispose();
    nachnameController.dispose();
    emailController.dispose();
    telefonController.dispose();
    passwortController.dispose();
    super.dispose();
  }

  Future<void> _submitPartnerRequest() async {
    if (_isSubmitting) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    if (branche == null || branche!.trim().isEmpty) {
      _showError("Bitte wähle eine Branche aus.");
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwortController.text.trim(),
      );

      final uid = credential.user!.uid;

      await FirebaseFirestore.instance
          .collection('partner_requests')
          .doc(uid)
          .set({
        'uid': uid,
        'status': 'pending',
        'rolle': 'dienstleister',
        'createdAt': FieldValue.serverTimestamp(),
        'geschaeftsname': geschaeftController.text.trim(),
        'strassenname': strasseController.text.trim(),
        'hausnummer': hausnummerController.text.trim(),
        'adresse':
        '${strasseController.text.trim()} ${hausnummerController.text.trim()}'
            .trim(),
        'plz': plzController.text.trim(),
        'stadt': stadtController.text.trim(),
        'branche': branche,
        'vorname': vornameController.text.trim(),
        'nachname': nachnameController.text.trim(),
        'email': emailController.text.trim(),
        'telefon': telefonController.text.trim(),
        'approvedAt': null,
        'approvedBy': null,
      });

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      setState(() {
        _isSubmittedSuccessfully = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Antrag erfolgreich gesendet")),
      );
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Fehler bei der Registrierung");
    } catch (e) {
      _showError("Unbekannter Fehler");
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    geschaeftController.clear();
    strasseController.clear();
    hausnummerController.clear();
    plzController.clear();
    stadtController.clear();
    vornameController.clear();
    nachnameController.clear();
    emailController.clear();
    telefonController.clear();
    passwortController.clear();

    setState(() {
      branche = null;
      _isSubmittedSuccessfully = false;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Partner werden"),
        elevation: 0,
      ),
      body: isWide
          ? Row(
        children: [
          Expanded(child: _buildLeftSide()),
          Expanded(
            child: SingleChildScrollView(
              child: _isSubmittedSuccessfully
                  ? _buildSuccessView()
                  : _buildForm(),
            ),
          ),
        ],
      )
          : SingleChildScrollView(
        child: Column(
          children: [
            _buildLeftSide(),
            _isSubmittedSuccessfully
                ? _buildSuccessView()
                : _buildForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftSide() {
    return Container(
      padding: const EdgeInsets.all(40),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SizedBox(height: 40),
          Text(
            "Gewinne neue Kunden\nmit TERMINI",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          Text(
            "• Online Termine verwalten\n"
                "• Mehr Sichtbarkeit in deiner Region\n"
                "• Weniger Telefonstress\n"
                "• Modernes Buchungssystem",
            style: TextStyle(fontSize: 16, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Jetzt Partner werden",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),

            const Text("Geschäftsinformationen"),
            const SizedBox(height: 15),

            _buildInput(
              "Name des Geschäfts",
              geschaeftController,
              validator: (value) =>
              value == null || value.trim().isEmpty
                  ? 'Bitte den Namen des Geschäfts eingeben'
                  : null,
            ),
            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: _buildInput(
                    "Straßenname",
                    strasseController,
                    validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Bitte die Straße eingeben'
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInput(
                    "Hausnummer",
                    hausnummerController,
                    validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Bitte die Hausnummer eingeben'
                        : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: _buildInput(
                    "PLZ",
                    plzController,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Bitte die PLZ eingeben'
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInput(
                    "Stadt",
                    stadtController,
                    validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Bitte die Stadt eingeben'
                        : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              value: branche,
              hint: const Text("Branche wählen"),
              items: branchenListe
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: _isSubmitting
                  ? null
                  : (value) => setState(() => branche = value),
              validator: (value) =>
              value == null || value.trim().isEmpty
                  ? 'Bitte eine Branche wählen'
                  : null,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 30),

            const Text("Eigentümerinformationen"),
            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: _buildInput(
                    "Vorname",
                    vornameController,
                    validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Bitte den Vornamen eingeben'
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildInput(
                    "Nachname",
                    nachnameController,
                    validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Bitte den Nachnamen eingeben'
                        : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            _buildInput(
              "E-Mail",
              emailController,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Bitte eine E-Mail eingeben';
                }
                if (!value.contains('@')) {
                  return 'Bitte eine gültige E-Mail eingeben';
                }
                return null;
              },
            ),
            const SizedBox(height: 15),

            _buildInput(
              "Telefonnummer",
              telefonController,
              keyboardType: TextInputType.phone,
              validator: (value) =>
              value == null || value.trim().isEmpty
                  ? 'Bitte eine Telefonnummer eingeben'
                  : null,
            ),
            const SizedBox(height: 15),

            _buildInput(
              "Passwort",
              passwortController,
              isPassword: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Bitte ein Passwort eingeben';
                }
                if (value.trim().length < 6) {
                  return 'Das Passwort muss mindestens 6 Zeichen lang sein';
                }
                return null;
              },
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitPartnerRequest,
                child: _isSubmitting
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text("Jetzt Partner werden"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withOpacity(0.18)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 56,
              ),
              const SizedBox(height: 20),
              const Text(
                'Antrag erfolgreich eingereicht',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Danke für deine Registrierung als Partner bei TERMINI.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Wie geht es jetzt weiter?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '• Wir prüfen deine Angaben im Admin-Bereich.\n'
                    '• Nach der Freigabe kannst du dich als Dienstleister einloggen.\n'
                    '• Bei Rückfragen melden wir uns unter deiner angegebenen E-Mail-Adresse.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Zur Startseite'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _resetForm,
                    child: const Text('Weiteren Antrag stellen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(
      String hint,
      TextEditingController controller, {
        bool isPassword = false,
        String? Function(String?)? validator,
        TextInputType? keyboardType,
      }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      validator: validator,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}