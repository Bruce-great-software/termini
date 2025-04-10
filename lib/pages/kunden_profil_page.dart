import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
