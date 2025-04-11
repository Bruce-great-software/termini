import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'alle_dienstleister_page.dart';

class KundenProfilPage extends StatelessWidget {
  const KundenProfilPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Mein Profil')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Eingeloggt als:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(user?.email ?? 'Unbekannt'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VornameBearbeitenPage()),
                );
              },
              child: const Text('Persönliche Daten'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()),
                      (route) => false,
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Abmelden'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            ),
          ],
        ),
      ),
    );
  }
}

class VornameBearbeitenPage extends StatefulWidget {
  const VornameBearbeitenPage({super.key});

  @override
  State<VornameBearbeitenPage> createState() => _VornameBearbeitenPageState();
}

class _VornameBearbeitenPageState extends State<VornameBearbeitenPage> {
  final _controller = TextEditingController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _ladeVorname();
  }

  Future<void> _ladeVorname() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      _controller.text = doc.data()?['name'] ?? '';
    }
    setState(() => isLoading = false);
  }

  Future<void> _speichern() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'name': _controller.text.trim(),
      });
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vorname bearbeiten')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vorname'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Dein Vorname',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _speichern,
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}