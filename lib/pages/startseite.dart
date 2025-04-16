import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dienstleister_home_page.dart';
import 'dienstleister_login_page.dart';  // Beispiel für Login


class Startseite extends StatefulWidget {
  const Startseite({super.key});

  @override
  State<Startseite> createState() => _StartseiteState();
}

class _StartseiteState extends State<Startseite> {
  int _selectedIndex = 0;

  // Für die Auswahl von Home und Profil (Login/Registrierung)
  final List<Widget> _pages = [
    const DienstleisterHomePage(),  // Home-Seite
    const DienstleisterLoginPage()  // Profil-Seite (Login/Registrierung)
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _checkUserLoginStatus() async {
    final user = FirebaseAuth.instance.currentUser;

    // Falls der Benutzer nicht eingeloggt ist, zur Login-Seite navigieren
    if (user == null && _selectedIndex == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DienstleisterLoginPage()),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _checkUserLoginStatus(); // Prüfen, ob der Benutzer eingeloggt ist
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Startseite'),
      ),
      body: _pages[_selectedIndex],  // Die gewählte Seite anzeigen
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
