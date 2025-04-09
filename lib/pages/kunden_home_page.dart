import 'package:flutter/material.dart';

class KundenHomePage extends StatelessWidget {
  const KundenHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kunden Home'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Willkommen, Kunde!',
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Füge deine Logik für das Buchen von Terminen hier hinzu
              },
              child: const Text('Termin buchen'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Logik für die Anzeige der Favoriten
              },
              child: const Text('Meine Favoriten'),
            ),
          ],
        ),
      ),
    );
  }
}
