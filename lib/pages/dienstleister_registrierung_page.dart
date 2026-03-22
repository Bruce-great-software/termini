import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dienstleister_home_page.dart';
import '../utils/app_snackbar.dart';

class DienstleisterRegistrierungPage extends StatefulWidget {
  const DienstleisterRegistrierungPage({super.key});

  @override
  State<DienstleisterRegistrierungPage> createState() => _DienstleisterRegistrierungPageState();
}

class _DienstleisterRegistrierungPageState extends State<DienstleisterRegistrierungPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _register() async {
    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Weiterleitung zur DienstleisterHomePage
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DienstleisterHomePage()),
      );
    } catch (e) {
      showAppSnackBar(context,SnackBar(content: Text('Fehler: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrierung')),
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
              onPressed: _register,
              child: const Text('Registrieren'),
            ),
          ],
        ),
      ),
    );
  }
}
