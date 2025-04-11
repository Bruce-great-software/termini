import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_register_page.dart';
import 'alle_dienstleister_page.dart';

class DienstleisterMainPage extends StatefulWidget {
  final String branche;
  final String dienstleisterId;

  const DienstleisterMainPage({
    super.key,
    required this.branche,
    required this.dienstleisterId,
  });

  @override
  State<DienstleisterMainPage> createState() => _DienstleisterMainPageState();
}

class _DienstleisterMainPageState extends State<DienstleisterMainPage> {
  int _selectedIndex = 0;
  String? dienstleisterName;

  @override
  void initState() {
    super.initState();
    _ladeDienstleisterName();
  }

  Future<void> _ladeDienstleisterName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = snapshot.data();
      final name = data?['name'];
      print('📦 Name aus users geladen: $name');

      setState(() {
        dienstleisterName = name ?? 'Unbekannt';
      });
    } catch (e) {
      print('❌ Fehler beim Laden des Namens aus users: $e');
      setState(() {
        dienstleisterName = 'Fehler';
      });
    }
  }

  void _onTabTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()), // ← Hier liegt der Unterschied!
            (route) => false,
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomePage(),
      const Center(child: Text('Kalender kommt bald!')),
      Center(child: ElevatedButton(onPressed: () {}, child: Text('Leistungen erstellen'))),
      _buildProfilPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0
            ? 'Hallo, ${dienstleisterName ?? '...'}'
            : _selectedIndex == 1
            ? 'Kalender'
            : 'Profil'),
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // <--- Das sorgt für alle Labels!
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Kalender'),
          BottomNavigationBarItem(icon: Icon(Icons.design_services), label: 'Leistungen'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],

      ),
    );
  }

  Widget _buildHomePage() {
    return Center(
      child: Text(
        'Willkommen zurück, ${dienstleisterName ?? 'Dienstleister'}!',
        style: const TextStyle(fontSize: 20),
      ),
    );
  }

  Widget _buildProfilPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Eingeloggt als: ${FirebaseAuth.instance.currentUser?.email ?? 'Unbekannt'}'),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _logout,
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
  }
}
