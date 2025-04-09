import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dienstleister_home_page.dart';
import 'dienstleister_registrierung_page.dart';

class DienstleisterLoginPage extends StatefulWidget {
  const DienstleisterLoginPage({super.key});

  @override
  State<DienstleisterLoginPage> createState() => _DienstleisterLoginPageState();
}

class _DienstleisterLoginPageState extends State<DienstleisterLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _login() async {
    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Weiterleitung zur DienstleisterHomePage
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DienstleisterHomePage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
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
            ElevatedButton(
              onPressed: _login,
              child: const Text('Login'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                // Zur Registrierungsseite weiterleiten
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DienstleisterRegistrierungPage()),
                );
              },
              child: const Text('Noch kein Konto? Jetzt registrieren'),
            ),
          ],
        ),
      ),
    );
  }
}
