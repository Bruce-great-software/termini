import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'alle_dienstleister_page.dart';

class AdminMainPage extends StatefulWidget {
  const AdminMainPage({super.key});

  @override
  State<AdminMainPage> createState() => _AdminMainPageState();
}

class _AdminMainPageState extends State<AdminMainPage> {
  int _selectedIndex = 0;

  void _onTabTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()),
        );
      });

    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const AdminDienstleisterFormular(),
      Center(
        child: ElevatedButton(
          onPressed: _logout,
          child: const Text('Abmelden'),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Admin Dashboard")),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.business), label: 'Dienstleister'),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'Logout'),
        ],
      ),
    );
  }
}

class AdminDienstleisterFormular extends StatefulWidget {
  const AdminDienstleisterFormular({super.key});

  @override
  State<AdminDienstleisterFormular> createState() => _AdminDienstleisterFormularState();
}

class _AdminDienstleisterFormularState extends State<AdminDienstleisterFormular> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _brancheController = TextEditingController();
  final _dienstleisterIdController = TextEditingController();

  Future<void> _registriereDienstleister() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final branche = _brancheController.text.trim();
    final dienstleisterId = _dienstleisterIdController.text.trim();

    try {
      await FirebaseFirestore.instance.collection('users').add({
        'name': name,
        'email': email,
        'branche': branche,
        'dienstleisterId': dienstleisterId,
        'rolle': 'dienstleister',
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dienstleister erfolgreich registriert')),
      );
      _formKey.currentState!.reset();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => value!.isEmpty ? 'Pflichtfeld' : null,
            ),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) => value!.isEmpty ? 'Pflichtfeld' : null,
            ),
            TextFormField(
              controller: _brancheController,
              decoration: const InputDecoration(labelText: 'Branche'),
              validator: (value) => value!.isEmpty ? 'Pflichtfeld' : null,
            ),
            TextFormField(
              controller: _dienstleisterIdController,
              decoration: const InputDecoration(labelText: 'Dienstleister-ID'),
              validator: (value) => value!.isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _registriereDienstleister,
              child: const Text('Dienstleister speichern'),
            ),
          ],
        ),
      ),
    );
  }
}
