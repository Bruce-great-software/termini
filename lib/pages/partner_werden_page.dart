import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/alle_dienstleister_web_shell.dart';

class PartnerWerdenPage extends StatefulWidget {
  final VoidCallback? onHeaderPartnerWerdenPressed;
  final VoidCallback? onHeaderMeinKontoPressed;

  const PartnerWerdenPage({
    super.key,
    this.onHeaderPartnerWerdenPressed,
    this.onHeaderMeinKontoPressed,
  });

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
  bool _obscurePassword = true;

  final List<String> branchenListe = [
    "Friseur",
    "Barbershop",
    "Kosmetikstudio",
    "Nagelstudio",
    "Massage",
  ];

  static const Color _bgColor = Color(0xFFF7F3EE);
  static const Color _cardColor = Colors.white;
  static const Color _primaryColor = Color(0xFF111111);
  static const Color _accentColor = Color(0xFFD6C3AE);
  static const Color _softBorder = Color(0xFFE7DED3);
  static const Color _textPrimary = Color(0xFF1B1B1B);
  static const Color _textSecondary = Color(0xFF6E675F);

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
      final credential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
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
    } catch (_) {
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
      _obscurePassword = true;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1100;
    final isTablet = width >= 700 && width < 1100;

    final content = SafeArea(
      top: !kIsWeb,
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 32 : 18,
            vertical: isWide ? 28 : 18,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: isWide
                ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 11,
                  child: _buildLeftHero(isWide: true),
                ),
                const SizedBox(width: 28),
                Expanded(
                  flex: 10,
                  child: _isSubmittedSuccessfully
                      ? _buildSuccessView(isWideCard: true)
                      : _buildFormCard(isWideCard: true),
                ),
              ],
            )
                : Column(
              children: [
                _buildLeftHero(isWide: false),
                const SizedBox(height: 20),
                _isSubmittedSuccessfully
                    ? _buildSuccessView(isWideCard: isTablet)
                    : _buildFormCard(isWideCard: isTablet),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: kIsWeb
          ? null
          : AppBar(
        title: const Text(
          "Partner werden",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFFF4EEF7),
        foregroundColor: _textPrimary,
      ),
      body: kIsWeb
          ? Column(
        children: [
          TerminiWebHeader(
            opacity: 1,
            onPartnerWerdenPressed: widget.onHeaderPartnerWerdenPressed ??
                    () {},
            onMeinKontoPressed: widget.onHeaderMeinKontoPressed ??
                    () {
                  Navigator.of(context).maybePop();
                },
          ),
          Expanded(child: content),
        ],
      )
          : content,
    );
  }

  Widget _buildLeftHero({required bool isWide}) {
    return Container(
      padding: EdgeInsets.all(isWide ? 36 : 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF5EEE6),
            Color(0xFFECE1D4),
          ],
        ),
        border: Border.all(color: _softBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.78),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white),
            ),
            child: const Text(
              "Kostenlos starten • Manuelle Freischaltung",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
          SizedBox(height: isWide ? 32 : 24),
          Text(
            "Gewinne neue Kunden\nmit TERMINI",
            style: TextStyle(
              fontSize: isWide ? 46 : 34,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: const Text(
              "Mehr Sichtbarkeit, weniger Telefonaufwand und ein moderner Online-Auftritt für dein Geschäft. Mit TERMINI kannst du Anfragen digital verwalten und neue Kunden in deiner Region erreichen.",
              style: TextStyle(
                fontSize: 17,
                height: 1.7,
                color: _textSecondary,
              ),
            ),
          ),
          SizedBox(height: isWide ? 30 : 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: const [
              _InfoBadge(label: "Friseure"),
              _InfoBadge(label: "Barbershops"),
              _InfoBadge(label: "Kosmetikstudios"),
              _InfoBadge(label: "Nagelstudios"),
            ],
          ),
          SizedBox(height: isWide ? 34 : 28),
          _buildBenefitCard(
            icon: Icons.calendar_month_outlined,
            title: "Online-Termine rund um die Uhr",
            subtitle:
            "Deine Kunden können jederzeit Anfragen stellen, auch außerhalb deiner Öffnungszeiten.",
          ),
          const SizedBox(height: 14),
          _buildBenefitCard(
            icon: Icons.phone_in_talk_outlined,
            title: "Weniger Telefonstress im Alltag",
            subtitle:
            "Anfragen landen strukturiert im System, statt zwischen Kundengesprächen verloren zu gehen.",
          ),
          const SizedBox(height: 14),
          _buildBenefitCard(
            icon: Icons.location_on_outlined,
            title: "Mehr lokale Sichtbarkeit",
            subtitle:
            "Werde besser gefunden und präsentiere dein Geschäft professionell in deiner Region.",
          ),
          const SizedBox(height: 14),
          _buildBenefitCard(
            icon: Icons.verified_user_outlined,
            title: "Schneller und sicherer Start",
            subtitle:
            "Deine Anfrage wird geprüft. Nach der Freigabe kannst du dein Dienstleister-Konto nutzen.",
          ),
          SizedBox(height: isWide ? 28 : 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.86),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Warum Partner werden?",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "TERMINI richtet sich an moderne Dienstleister, die online sichtbar sein und ihre Terminverwaltung zeitgemäß aufbauen möchten.",
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.65,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.84),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFF5EFE7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: _textPrimary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.6,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard({required bool isWideCard}) {
    return Container(
      padding: EdgeInsets.all(isWideCard ? 32 : 22),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _softBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 34,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Jetzt Partner werden",
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Erstelle deine Anfrage in unter 2 Minuten. Wir prüfen deine Angaben und schalten dein Profil anschließend frei.",
              style: TextStyle(
                fontSize: 15.5,
                height: 1.65,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 26),
            _buildSectionTitle("Geschäftsinformationen"),
            const SizedBox(height: 16),
            _buildInput(
              "Name des Geschäfts",
              geschaeftController,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Bitte den Namen des Geschäfts eingeben'
                  : null,
            ),
            const SizedBox(height: 16),
            _buildResponsiveTwoColumn(
              left: _buildInput(
                "Straßenname",
                strasseController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bitte die Straße eingeben'
                    : null,
              ),
              right: _buildInput(
                "Hausnummer",
                hausnummerController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bitte die Hausnummer eingeben'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            _buildResponsiveTwoColumn(
              left: _buildInput(
                "PLZ",
                plzController,
                keyboardType: TextInputType.number,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bitte die PLZ eingeben'
                    : null,
              ),
              right: _buildInput(
                "Stadt",
                stadtController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bitte die Stadt eingeben'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: branche,
              hint: const Text("Branche wählen"),
              items: branchenListe
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: _isSubmitting
                  ? null
                  : (value) => setState(() => branche = value),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Bitte eine Branche wählen'
                  : null,
              decoration: _inputDecoration("Branche wählen"),
              borderRadius: BorderRadius.circular(18),
              dropdownColor: Colors.white,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            const SizedBox(height: 28),
            _buildSectionTitle("Ansprechpartner"),
            const SizedBox(height: 16),
            _buildResponsiveTwoColumn(
              left: _buildInput(
                "Vorname",
                vornameController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bitte den Vornamen eingeben'
                    : null,
              ),
              right: _buildInput(
                "Nachname",
                nachnameController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bitte den Nachnamen eingeben'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            _buildInput(
              "Telefonnummer",
              telefonController,
              keyboardType: TextInputType.phone,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Bitte eine Telefonnummer eingeben'
                  : null,
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5F1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _softBorder),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 20, color: _textSecondary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Deine Anfrage ist kostenlos. Nach dem Absenden prüfen wir deine Angaben manuell.",
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitPartnerRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  disabledBackgroundColor: _primaryColor.withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Text(
                  "Anfrage absenden",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView({required bool isWideCard}) {
    return Container(
      padding: EdgeInsets.all(isWideCard ? 34 : 24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _softBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 34,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.10),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
              size: 42,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Antrag erfolgreich eingereicht',
            style: TextStyle(
              fontSize: 30,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Danke für deine Registrierung als Partner bei TERMINI. Wir haben deine Anfrage erhalten.',
            style: TextStyle(
              fontSize: 15.5,
              height: 1.65,
              color: _textSecondary,
            ),
          ),
          const SizedBox(height: 26),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F5F1),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _softBorder),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wie geht es jetzt weiter?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                SizedBox(height: 14),
                _StepItem(
                  text: 'Wir prüfen deine Angaben im Admin-Bereich.',
                ),
                SizedBox(height: 10),
                _StepItem(
                  text:
                  'Nach der Freigabe kannst du dich als Dienstleister einloggen.',
                ),
                SizedBox(height: 10),
                _StepItem(
                  text:
                  'Bei Rückfragen melden wir uns unter deiner angegebenen E-Mail-Adresse.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Zur Startseite',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              SizedBox(
                height: 54,
                child: OutlinedButton(
                  onPressed: _resetForm,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textPrimary,
                    side: const BorderSide(color: _softBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Weiteren Antrag stellen',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveTwoColumn({
    required Widget left,
    required Widget right,
  }) {
    final width = MediaQuery.of(context).size.width;
    final stacked = width < 760;

    if (stacked) {
      return Column(
        children: [
          left,
          const SizedBox(height: 16),
          right,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: _textPrimary,
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
      obscureText: isPassword ? _obscurePassword : false,
      validator: validator,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 15.5,
        color: _textPrimary,
      ),
      decoration: _inputDecoration(hint).copyWith(
        suffixIcon: isPassword
            ? IconButton(
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: _textSecondary,
          ),
        )
            : null,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: _textSecondary,
        fontSize: 15,
      ),
      filled: true,
      fillColor: const Color(0xFFFFFDFC),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _softBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _softBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFFC9AB87),
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Colors.redAccent,
          width: 1.2,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Colors.redAccent,
          width: 1.4,
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String label;

  const _InfoBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: _PartnerWerdenPageState._textPrimary,
        ),
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final String text;

  const _StepItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFEFE7DD),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Icon(
            Icons.check,
            size: 15,
            color: _PartnerWerdenPageState._textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.6,
              color: _PartnerWerdenPageState._textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}