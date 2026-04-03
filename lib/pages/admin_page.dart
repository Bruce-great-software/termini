import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;

import 'admin_branchen_page.dart';
import 'admin_leistung_erstellen_page.dart';
import 'alle_dienstleister_page.dart';
import 'admin_partner_requests_page.dart';


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

  List<Widget> get _pages => [
    const AdminDienstleisterFormular(),
    const AdminPartnerRequestsPage(),
    const AdminBranchenPage(),
    AdminLeistungErstellenPage(),
    Center(
      child: ElevatedButton(
        onPressed: _logout,
        child: const Text('Abmelden'),
      ),
    ),
  ];

  List<_AdminNavItem> get _navItems => const [
    _AdminNavItem(
      icon: Icons.business,
      label: 'Dienstleister',
    ),
    _AdminNavItem(
      icon: Icons.handshake_outlined,
      label: 'Partner-Anfragen',
    ),
    _AdminNavItem(
      icon: Icons.category,
      label: 'Branchen',
    ),
    _AdminNavItem(
      icon: Icons.design_services,
      label: 'Leistungen',
    ),
    _AdminNavItem(
      icon: Icons.logout,
      label: 'Logout',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebLayout(context);
    }

    return _buildAppLayout(context);
  }

  Widget _buildAppLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey,
        items: _navItems
            .map(
              (item) => BottomNavigationBarItem(
            icon: Icon(item.icon),
            label: item.label,
          ),
        )
            .toList(),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildWebSidebar(),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Text(
                    _navItems[_selectedIndex].label == 'Logout'
                        ? 'Admin Dashboard'
                        : 'Admin Dashboard · ${_navItems[_selectedIndex].label}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF7F7FA),
                    child: _pages[_selectedIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebSidebar() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: const Text(
              'Termini Admin',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = _selectedIndex == index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isSelected
                        ? Colors.deepOrange.withOpacity(0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _onTabTapped(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              color: isSelected
                                  ? Colors.deepOrange
                                  : Colors.grey.shade700,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.deepOrange
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminNavItem {
  final IconData icon;
  final String label;

  const _AdminNavItem({
    required this.icon,
    required this.label,
  });
}

class AdminDienstleisterFormular extends StatefulWidget {
  const AdminDienstleisterFormular({super.key});

  @override
  State<AdminDienstleisterFormular> createState() =>
      _AdminDienstleisterFormularState();
}

class _AdminDienstleisterFormularState
    extends State<AdminDienstleisterFormular> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _adresseController = TextEditingController();
  final _ortController = TextEditingController();
  final _plzController = TextEditingController();
  final _brancheController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _ortSuchController = TextEditingController();

  final String apiKey = 'AIzaSyAAydUpc7KvbbEGeUDsw4DF8w2BkpL_Rq0';

  Future<List<Map<String, dynamic>>> _getOrtVorschlaege(String input) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&language=de&components=country:de&key=$apiKey';
    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);

    if (response.statusCode == 200 && data['status'] == 'OK') {
      return List<Map<String, dynamic>>.from(data['predictions']);
    } else {
      return [];
    }
  }

  Future<void> _ladeDetailsUndSetzeAdresse(String placeId) async {
    final detailsUrl =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&language=de&key=$apiKey';

    final response = await http.get(Uri.parse(detailsUrl));
    final data = json.decode(response.body);

    if (response.statusCode == 200 &&
        data['status'] == 'OK' &&
        data['result'] != null) {
      final result = data['result'];
      final geometry = result['geometry'];

      final name = result['name'] ?? '';
      final addressComponents =
          result['address_components'] as List<dynamic>? ?? [];

      String street = '';
      String streetNumber = '';
      String plz = '';
      String ort = '';

      for (final component in addressComponents) {
        final types = List<String>.from(component['types']);

        if (types.contains('route')) {
          street = component['long_name'];
        } else if (types.contains('street_number')) {
          streetNumber = component['long_name'];
        } else if (types.contains('postal_code')) {
          plz = component['long_name'];
        } else if (types.contains('locality')) {
          ort = component['long_name'];
        }
      }

      final adresse = '$street $streetNumber'.trim();
      final lat = geometry['location']['lat'];
      final lng = geometry['location']['lng'];

      setState(() {
        _nameController.text = name;
        _adresseController.text = adresse;
        _plzController.text = plz;
        _ortController.text = ort;
        _latitudeController.text = lat.toString();
        _longitudeController.text = lng.toString();
      });
    } else {
      debugPrint('Fehler beim Laden der Details');
    }
  }

  Future<void> _registriereDienstleister() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final adresse = _adresseController.text.trim();
    final ort = _ortController.text.trim();
    final plz = _plzController.text.trim();
    final branche = _brancheController.text.trim();
    final latitude = double.tryParse(_latitudeController.text.trim()) ?? 0.0;
    final longitude = double.tryParse(_longitudeController.text.trim()) ?? 0.0;

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: 'barber123',
      );

      final uid = userCredential.user!.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': name,
        'email': email,
        'adresse': adresse,
        'ort': ort,
        'plz': plz,
        'branche': branche,
        'dienstleisterId': uid,
        'rolle': 'dienstleister',
        'createAt': FieldValue.serverTimestamp(),
        'geo': GeoPoint(latitude, longitude),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dienstleister erfolgreich registriert'),
        ),
      );

      _formKey.currentState!.reset();
      _latitudeController.clear();
      _longitudeController.clear();
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWebWide = kIsWeb && MediaQuery.of(context).size.width >= 900;

    final formContent = Form(
      key: _formKey,
      child: ListView(
        children: [
          TypeAheadField<Map<String, dynamic>>(
            suggestionsCallback: (String pattern) async {
              if (pattern.length < 2) return [];
              return await _getOrtVorschlaege(pattern);
            },
            itemBuilder: (context, suggestion) {
              return ListTile(
                title: Text(suggestion['description']),
              );
            },
            onSelected: (suggestion) async {
              final placeId = suggestion['place_id'];
              _ortSuchController.text = suggestion['description'];
              await _ladeDetailsUndSetzeAdresse(placeId);
            },
            builder: (context, controller, focusNode) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: 'Ort oder PLZ suchen',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
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
            controller: _adresseController,
            decoration: const InputDecoration(labelText: 'Adresse'),
            validator: (value) => value!.isEmpty ? 'Pflichtfeld' : null,
          ),
          TextFormField(
            controller: _ortController,
            decoration: const InputDecoration(labelText: 'Ort'),
            validator: (value) => value!.isEmpty ? 'Pflichtfeld' : null,
          ),
          TextFormField(
            controller: _plzController,
            decoration: const InputDecoration(labelText: 'PLZ'),
            validator: (value) => value!.isEmpty ? 'Pflichtfeld' : null,
          ),
          FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance.collection('branchen').get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;
              final branchenListe = docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data.containsKey('name') ? data['name'] as String : doc.id;
              }).toList();

              branchenListe.sort();

              return DropdownButtonFormField<String>(
                value: _brancheController.text.isNotEmpty &&
                    branchenListe.contains(_brancheController.text)
                    ? _brancheController.text
                    : null,
                items: branchenListe.map((value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _brancheController.text = value!;
                  });
                },
                decoration: const InputDecoration(labelText: 'Branche'),
                validator: (value) => value == null || value.isEmpty
                    ? 'Bitte eine Branche wählen'
                    : null,
              );
            },
          ),
          TextFormField(
            controller: _latitudeController,
            decoration: InputDecoration(
              labelText: 'Latitude',
              filled: _latitudeController.text.isNotEmpty,
              fillColor: _latitudeController.text.isNotEmpty
                  ? Colors.grey[200]
                  : null,
            ),
            style: TextStyle(
              color: _latitudeController.text.isNotEmpty
                  ? Colors.grey[700]
                  : null,
            ),
            keyboardType: TextInputType.number,
            readOnly: _latitudeController.text.isNotEmpty,
            validator: (value) =>
            value!.isEmpty ? 'Latitude erforderlich' : null,
          ),
          TextFormField(
            controller: _longitudeController,
            decoration: InputDecoration(
              labelText: 'Longitude',
              filled: _longitudeController.text.isNotEmpty,
              fillColor: _longitudeController.text.isNotEmpty
                  ? Colors.grey[200]
                  : null,
            ),
            style: TextStyle(
              color: _longitudeController.text.isNotEmpty
                  ? Colors.grey[700]
                  : null,
            ),
            keyboardType: TextInputType.number,
            readOnly: _longitudeController.text.isNotEmpty,
            validator: (value) =>
            value!.isEmpty ? 'Longitude erforderlich' : null,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _registriereDienstleister,
            child: const Text('Dienstleister speichern'),
          ),
        ],
      ),
    );

    if (isWebWide) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 900,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: formContent,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: formContent,
    );
  }
}