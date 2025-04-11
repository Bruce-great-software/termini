import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'alle_dienstleister_page.dart';
import 'dienstleister_main_page.dart';

class LoginRegisterPage extends StatefulWidget {
  const LoginRegisterPage({super.key});

  @override
  State<LoginRegisterPage> createState() => _LoginRegisterPageState();
}

class _LoginRegisterPageState extends State<LoginRegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoginMode = true;
  bool isLoading = false;

  Future<void> _handleAuth() async {
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

        // Kunde wird neu in Firestore eingetragen
        await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).set({
          'email': _emailController.text.trim(),
          'rolle': 'kunde',
          'name': '',
        });
      }

      // Rolle prüfen
      final doc = await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).get();

      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Benutzer existiert nicht in der Nutzersammlung.')),
        );
        setState(() => isLoading = false);
        return;
      }

      final data = doc.data();
      final rolle = data?['rolle'];

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLoginMode ? 'Login' : 'Registrierung')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
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
                : ElevatedButton(
              onPressed: _handleAuth,
              child: Text(isLoginMode ? 'Login' : 'Registrieren'),
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
