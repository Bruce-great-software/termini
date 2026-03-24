import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'alle_dienstleister_page.dart';
import 'dienstleister_main_page.dart';
import 'admin_page.dart';

class LoginRegisterPage extends StatefulWidget {
  const LoginRegisterPage({super.key});

  @override
  State<LoginRegisterPage> createState() => _LoginRegisterPageState();
}

class _LoginRegisterPageState extends State<LoginRegisterPage> {
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoginMode = true;
  bool isLoading = false;

  Future<void> _handleAuth() async {
    if (!isLoginMode && _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gib eine Handynummer ein.')),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      UserCredential credential;
      final auth = FirebaseAuth.instance;

      if (isLoginMode) {
        credential = await auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        credential = await auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Neuer Kunde wird in Firestore gespeichert
        await FirebaseFirestore.instance
            .collection('users')
            .doc(credential.user!.uid)
            .set({
          'email': _emailController.text.trim(),
          'rolle': 'kunde',
          'name': '',
        });
      }

      // Rolle prüfen
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .get();

      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Benutzer existiert nicht in der Nutzersammlung.')),
        );
        setState(() => isLoading = false);
        return;
      }

      final data = doc.data();
      final rolle = data?['rolle']?.toString().toLowerCase();

      if (rolle == 'kunde') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()),
        );
      } else if (rolle == 'dienstleister') {
        final branche = data?['branche'];
        final dienstleisterId = data?['dienstleisterId'];

        if (branche != null && dienstleisterId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DienstleisterMainPage(
                branche: branche,
                dienstleisterId: dienstleisterId,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Daten für Dienstleister unvollständig.')),
          );
        }
      } else if (rolle == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMainPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unbekannte oder fehlende Rolle im Nutzerprofil.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: ${e.toString()}')),
      );
    }
    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLoginMode ? 'Login' : 'Registrierung')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isLoginMode) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Handynummer *',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF344054),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    height: 56,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD0D5DD)),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🇩🇪', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 8),
                        Text(
                          '+49',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF101828),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: 'Handynummer',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'E-Mail'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Passwort'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleAuth,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: isLoginMode
                      ? null
                      : const Color(0xFF1F1F1F),
                  foregroundColor: isLoginMode ? null : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: isLoginMode ? null : 0,
                ),
                child: Text(
                  isLoginMode ? 'Login' : 'Ein Konto erstellen',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() => isLoginMode = !isLoginMode);
              },
              child: Text(isLoginMode
                  ? 'Noch kein Konto? Jetzt registrieren'
                  : 'Bereits registriert? Jetzt einloggen'),
            ),
          ],
        ),
      ),
    );
  }
}