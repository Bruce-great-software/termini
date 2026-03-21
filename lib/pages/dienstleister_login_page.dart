import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dienstleister_main_page.dart';
import 'login_register_page.dart';
import 'admin_page.dart';


class DienstleisterLoginPage extends StatefulWidget {
  const DienstleisterLoginPage({super.key});

  @override
  State<DienstleisterLoginPage> createState() => _DienstleisterLoginPageState();
}

class _DienstleisterLoginPageState extends State<DienstleisterLoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _fehlermeldung = '';

  Future<void> _login() async {
    setState(() => _fehlermeldung = '');

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final uid = credential.user!.uid;

      // Firestore-Daten mehrfach versuchen zu laden
      DocumentSnapshot<Map<String, dynamic>>? doc;
      int versuche = 0;
      while (versuche < 3) {
        doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && doc.data() != null) break;
        versuche++;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (doc == null || !doc.exists || doc.data() == null) {
        setState(() => _fehlermeldung = 'Benutzerprofil nicht gefunden oder nicht verfügbar.');
        return;
      }

      final data = doc.data()!;



      final rolle = data['rolle']?.toString().toLowerCase();

      if (rolle == null || rolle.isEmpty) {
        setState(() => _fehlermeldung = 'Rolle fehlt im Nutzerprofil.');
        return;
      }

      if (rolle == 'admin') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminMainPage()),
          );
        });
      } else if (rolle == 'dienstleister' || rolle == 'mitarbeiter') {
        final branche = data['branche'];
        final dienstleisterId = data['dienstleisterId'] ?? uid;

        if (branche != null && dienstleisterId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DienstleisterMainPage(
                  branche: branche,
                  dienstleisterId: dienstleisterId,
                ),
              ),
            );
          });
        } else {
          setState(() => _fehlermeldung = 'Unvollständige Dienstleisterdaten.');
        }
      } else {
        setState(() => _fehlermeldung = 'Unbekannte oder ungültige Rolle im Nutzerprofil.');
      }
    } catch (e) {
      setState(() => _fehlermeldung = 'Login fehlgeschlagen: ${e.toString()}');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dienstleister Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginRegisterPage()),
                );
              },
              child: const Text('Noch kein Konto? Jetzt registrieren'),
            ),
            const SizedBox(height: 12),
            if (_fehlermeldung.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.brown[200],
                child: Text(
                  _fehlermeldung,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
