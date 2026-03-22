import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  int _selectedHomeSidebarIndex = 0;
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
    setState(() {
      _selectedIndex = index;
      if (index != 0) {
        _selectedHomeSidebarIndex = 0;
      }
    });
  }

  void _onHomeSidebarTapped(int index) {
    setState(() {
      _selectedIndex = 0;
      _selectedHomeSidebarIndex = index;
    });
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
      _buildCurrentHomeContent(),
      const Center(child: Text('Kalender kommt bald!')),
      const DienstleisterAngebotePage(showScaffold: false),
      _buildProfilPage(),
    ];
    final sidebarItems = _buildSidebarItems();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopLayout = constraints.maxWidth >= 900;

        return Scaffold(
          appBar: AppBar(
            title: Text(_buildAppBarTitle()),
            centerTitle: true,
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isDesktopLayout)
                _DesktopSidebar(
                  width: _desktopSidebarWidth,
                  items: sidebarItems,
                ),
              Expanded(child: pages[_selectedIndex]),
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

  String _buildAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return _selectedHomeSidebarIndex == 1
            ? 'Mitarbeiter'
            : 'Hallo, ${dienstleisterName ?? '...'}';
      case 1:
        return 'Kalender';
      case 2:
        return 'Leistungen';
      case 3:
        return 'Profil';
      default:
        return '';
    }
  }

  Widget _buildCurrentHomeContent() {
    switch (_selectedHomeSidebarIndex) {
      case 1:
        return _buildMitarbeiterPage();
      case 0:
      default:
        return _buildHomePage();
    }
  }

  List<_SidebarItemData> _buildSidebarItems() {
    switch (_selectedIndex) {
      case 0:
        return [
          _SidebarItemData(
            title: 'Home',
            icon: Icons.home_outlined,
            isSelected: _selectedHomeSidebarIndex == 0,
            onTap: () => _onHomeSidebarTapped(0),
          ),
          _SidebarItemData(
            title: 'Mitarbeiter',
            icon: Icons.groups_2_outlined,
            isSelected: _selectedHomeSidebarIndex == 1,
            onTap: () => _onHomeSidebarTapped(1),
          ),
        ];
      case 1:
        return [
          _SidebarItemData(
            title: 'Kalender',
            icon: Icons.calendar_today_outlined,
            isSelected: true,
            onTap: () => _onTabTapped(1),
          ),
        ];
      case 2:
        return [
          _SidebarItemData(
            title: 'Leistungen',
            icon: Icons.design_services_outlined,
            isSelected: true,
            onTap: () => _onTabTapped(2),
          ),
        ];
      case 3:
        return [
          _SidebarItemData(
            title: 'Profil',
            icon: Icons.person_outline,
            isSelected: true,
            onTap: () => _onTabTapped(3),
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _buildHomePage() {
    return Center(
      child: Text(
        'Willkommen zurück, ${dienstleisterName ?? 'Dienstleister'}!',
        style: const TextStyle(fontSize: 20),
      ),
    );
  }

  Widget _buildMitarbeiterPage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Nicht eingeloggt.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'mitarbeiter')
          .where('dienstleisterId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final mitarbeiterDocs = snapshot.data?.docs ?? const [];

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                children: [
                  Text(
                    'Verwalte dein Team',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  InkWell(
                    borderRadius: BorderRadius.circular(44),
                    onTap: _zeigeMitarbeiterErstellenDialog,
                    child: Container(
                      width: 320,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 34,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(44),
                        border: Border.all(color: Colors.black, width: 4),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.person,
                            size: 132,
                            color: Color(0xFF02152B),
                          ),
                          SizedBox(height: 6),
                          CircleAvatar(
                            radius: 23,
                            backgroundColor: Color(0xFF02152B),
                            child: Icon(
                              Icons.add,
                              size: 34,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 26),
                          Text(
                            'Neuen Mitarbeiter erstellen',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Teammitglieder',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    )
                  else if (snapshot.hasError)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Die Mitarbeiter konnten nicht geladen werden.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    )
                  else if (mitarbeiterDocs.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: SizedBox(
                            width: double.infinity,
                            child: Text(
                              'Noch keine Mitarbeiter vorhanden.',
                            ),
                          ),
                        ),
                      )
                    else
                      Column(
                        children: mitarbeiterDocs.map((doc) {
                          final data = doc.data();
                          final name = (data['name'] as String?)?.trim();
                          final istAktiv = data['aktiv'] == true;
                          final loginAktiviert = data['loginAktiviert'] == true;

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF02152B),
                                child: Text(
                                  (name != null && name.isNotEmpty)
                                      ? name.characters.first.toUpperCase()
                                      : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                name?.isNotEmpty == true ? name! : 'Unbenannt',
                              ),
                              subtitle: Text(
                                istAktiv ? 'Aktiv' : 'Inaktiv',
                              ),
                              trailing: Icon(
                                loginAktiviert
                                    ? Icons.verified_user_outlined
                                    : Icons.person_outline,
                                color: const Color(0xFF02152B),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _zeigeMitarbeiterErstellenDialog() async {
    final nameController = TextEditingController();
    String? fehlertext;
    bool wirdGespeichert = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            Future<void> speichern() async {
              final user = FirebaseAuth.instance.currentUser;
              final name = nameController.text.trim();

              if (name.isEmpty) {
                setDialogState(() {
                  fehlertext = 'Bitte geben Sie einen Namen ein.';
                });
                return;
              }

              if (user == null) {
                setDialogState(() {
                  fehlertext = 'Sie sind nicht eingeloggt.';
                });
                return;
              }

              setDialogState(() {
                fehlertext = null;
                wirdGespeichert = true;
              });

              try {
                await FirebaseFirestore.instance.collection('users').add({
                  'name': name,
                  'role': 'mitarbeiter',
                  'dienstleisterId': user.uid,
                  'createdAt': FieldValue.serverTimestamp(),
                  'aktiv': true,
                  'loginAktiviert': false,
                });

                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('Mitarbeiter „$name“ wurde erstellt.'),
                  ),
                );
              } catch (_) {
                setDialogState(() {
                  fehlertext = 'Der Mitarbeiter konnte nicht erstellt werden.';
                  wirdGespeichert = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('Neuen Mitarbeiter erstellen'),
              content: SizedBox(
                width: 420,
                child: TextField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (fehlertext != null) {
                      setDialogState(() {
                        fehlertext = null;
                      });
                    }
                  },
                  onSubmitted: (_) {
                    if (!wirdGespeichert) {
                      speichern();
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Name des Mitarbeiters',
                    errorText: fehlertext,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: wirdGespeichert
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: wirdGespeichert ? null : speichern,
                  child: wirdGespeichert
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Erstellen'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
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

class _SidebarItemData {
  const _SidebarItemData({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.width,
    required this.items,
  });

  final double width;
  final List<_SidebarItemData> items;

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
          for (var i = 0; i < items.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Material(
                color: items[i].isSelected
                    ? const Color(0xFFF4F4F4)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: items[i].onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          items[i].icon,
                          size: 18,
                          color: items[i].isSelected
                              ? selectedColor
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            items[i].title,
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
            if (i < items.length - 1) ...[
              const SizedBox(height: 4),
              const Divider(height: 1, color: Color(0xFFEFEFEF)),
              const SizedBox(height: 4),
            ],
          ],
        ],
      ),
    );
  }
}