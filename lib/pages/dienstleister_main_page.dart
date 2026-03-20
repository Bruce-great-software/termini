import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/leistung_erstellen_dialog.dart';
import 'alle_dienstleister_page.dart';
import 'dienstleister_angebote_page.dart';
import 'dienstleister_edit_page.dart';

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
  static const double _desktopSidebarWidth = 188;

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
        MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()),
            (route) => false,
      );
    }
  }

  Future<void> _leistungLoeschen(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('leistungen')
        .doc(docId)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomePage(),
      const Center(child: Text('Kalender kommt bald!')),
      const DienstleisterAngebotePage(showScaffold: false),
      _buildProfilPage(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopLayout = constraints.maxWidth >= 900;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selectedIndex == 0
                  ? 'Hallo, ${dienstleisterName ?? '...'}'
                  : _selectedIndex == 1
                  ? 'Kalender'
                  : _selectedIndex == 2
                  ? 'Leistungen'
                  : 'Profil',
            ),
            centerTitle: true,
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isDesktopLayout)
                _DesktopSidebar(
                  width: _desktopSidebarWidth,
                  isLeistungenSelected: _selectedIndex == 2,
                  onTap: () => _onTabTapped(2),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: pages[_selectedIndex]),
                    if (_selectedIndex == 2)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: _CreateLeistungButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const LeistungErstellenDialog(),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _selectedIndex,
            onTap: _onTabTapped,
            selectedItemColor: Colors.deepOrange,
            unselectedItemColor: Colors.grey,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_today),
                label: 'Kalender',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.design_services),
                label: 'Leistungen',
              ),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
            ],
          ),
        );
      },
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

  Widget _buildLeistungenPage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Nicht eingeloggt.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('leistungen')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Noch keine Leistungen vorhanden.'));
        }

        final leistungen = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: leistungen.length,
          itemBuilder: (context, index) {
            final doc = leistungen[index];
            final leistung = doc.data() as Map<String, dynamic>;

            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                title: Text(leistung['name'] ?? 'Unbenannt'),
                subtitle: Text(
                  'Zielgruppe: ${leistung['zielgruppe']}, Dauer: ${leistung['dauer']} Min\nPreis: ${leistung['preis']} €',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _leistungLoeschen(doc.id);
                    }
                    // TODO: Bearbeiten-Dialog bei 'edit'
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Bearbeiten'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Löschen'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfilPage() {
    final user = FirebaseAuth.instance.currentUser;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DienstleisterEditPageEditPage(
                    userId: user?.uid ?? '',
                  ),
                ),
              );
            },
            child: const Text('Persönliche Daten bearbeiten'),
          ),
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

class _CreateLeistungButton extends StatelessWidget {
  const _CreateLeistungButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: const Color(0xFFF1EEF9).withOpacity(0.96),
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD8D2EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 20, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Leistungen erstellen',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.width,
    required this.isLeistungenSelected,
    required this.onTap,
  });

  final double width;
  final bool isLeistungenSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Color(0xFFE6E6E6)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Material(
              color: isLeistungenSelected
                  ? const Color(0xFFF4F4F4)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.home_outlined,
                        size: 18,
                        color: isLeistungenSelected
                            ? selectedColor
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Leistungen',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: Color(0xFFEFEFEF)),
        ],
      ),
    );
  }
}
