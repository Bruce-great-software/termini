import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dienstleister_main_page.dart';
import 'login_register_page.dart';
import 'admin_page.dart';
import 'alle_dienstleister_page.dart';

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
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!doc.exists) {
        setState(() => _fehlermeldung = 'Benutzerprofil nicht gefunden.');
        return;
      }

      final data = doc.data()!;
      final rolle = data['rolle'];

      if (rolle == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMainPage()),
        );
      } else if (rolle == 'dienstleister') {
        final branche = data['branche'];
        final dienstleisterId = data['dienstleisterId'];

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
          setState(() => _fehlermeldung = 'Unvollständige Dienstleisterdaten.');
        }
      } else {
        setState(() => _fehlermeldung = 'Unbekannte oder fehlende Rolle im Nutzerprofil.');
      }
    } catch (e) {
      setState(() => _fehlermeldung = 'Login fehlgeschlagen: ${e.toString()}');
    }
  }

  void _logout() async {
    await _auth.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()),
            (route) => false,
      );
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
                child: Text(_fehlermeldung, style: const TextStyle(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}

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
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()),
            (route) => false,
      );
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
