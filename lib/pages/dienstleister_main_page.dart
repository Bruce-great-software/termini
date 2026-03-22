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
  static const double _desktopMitarbeiterDrawerWidth = 380;

  int _selectedIndex = 0;
  int _selectedHomeSidebarIndex = 0;
  String? dienstleisterName;
  String? _selectedMitarbeiterId;

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

    final isDesktopLayout = MediaQuery.sizeOf(context).width >= 1100;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'mitarbeiter')
          .where('dienstleisterId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final mitarbeiterDocs = snapshot.data?.docs ?? const [];
        _SelectedMitarbeiter? selectedMitarbeiter;

        for (final doc in mitarbeiterDocs) {
          final data = doc.data();
          if (_selectedMitarbeiterId == doc.id) {
            selectedMitarbeiter = _SelectedMitarbeiter(
              docId: doc.id,
              name: (data['name'] as String?)?.trim() ?? '',
              aktiv: data['aktiv'] == true,
            );
          }
        }

        if (_selectedMitarbeiterId != null && selectedMitarbeiter == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedMitarbeiterId = null);
            }
          });
        }

        final listContent = _buildMitarbeiterListContent(
          snapshot: snapshot,
          mitarbeiterDocs: mitarbeiterDocs,
          isDesktopLayout: isDesktopLayout,
        );

        if (!isDesktopLayout) {
          return listContent;
        }

        return _buildMitarbeiterDesktopContent(
          listContent: listContent,
          selection: selectedMitarbeiter,
        );
      },
    );
  }

  Widget _buildMitarbeiterListContent({
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mitarbeiterDocs,
    required bool isDesktopLayout,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Verwalte dein Team',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 20),
              Card(
                color: const Color(0xFFFAFAFA),
                elevation: 1.5,
                shadowColor: Colors.black12,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  mouseCursor: SystemMouseCursors.click,
                  hoverColor: const Color(0xFFF5F5F5),
                  splashColor: const Color(0x1402152B),
                  highlightColor: const Color(0x0F02152B),
                  onTap: _zeigeMitarbeiterErstellenDialog,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF02152B),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Neuen Mitarbeiter erstellen',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Lege einen neuen Mitarbeiter an',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 18,
                          color: Color(0xFF02152B),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Dein Team (${mitarbeiterDocs.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
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
                    child: Text('Noch keine Mitarbeiter vorhanden.'),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: mitarbeiterDocs.asMap().entries.map((entry) {
                      final index = entry.key;
                      final doc = entry.value;
                      final data = doc.data();
                      final name = (data['name'] as String?)?.trim();
                      final istAktiv = data['aktiv'] == true;
                      final isSelected = doc.id == _selectedMitarbeiterId;

                      return Column(
                        children: [
                          Material(
                            color: isSelected
                                ? const Color(0xFFF5F8FF)
                                : Colors.transparent,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              horizontalTitleGap: 16,
                              minLeadingWidth: 0,
                              onTap: isDesktopLayout
                                  ? () => setState(() {
                                        _selectedMitarbeiterId = doc.id;
                                      })
                                  : null,
                              mouseCursor: isDesktopLayout
                                  ? SystemMouseCursors.click
                                  : MouseCursor.defer,
                              hoverColor: const Color(0xFFF5F5F5),
                              leading: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x14000000),
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: const Color(0xFF02152B),
                                  child: Text(
                                    (name != null && name.isNotEmpty)
                                        ? name.characters.first.toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                name?.isNotEmpty == true ? name! : 'Unbenannt',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: istAktiv
                                            ? const Color(0xFF2EAD62)
                                            : Colors.grey,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(istAktiv ? 'Aktiv' : 'Inaktiv'),
                                  ],
                                ),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 20,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          if (index < mitarbeiterDocs.length - 1)
                            const Divider(
                              height: 1,
                              indent: 20,
                              endIndent: 20,
                              color: Color(0xFFEEEEEE),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMitarbeiterDesktopContent({
    required Widget listContent,
    required _SelectedMitarbeiter? selection,
  }) {
    final drawerVisible = selection != null;

    return Row(
      children: [
        Expanded(child: listContent),
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: drawerVisible ? _desktopMitarbeiterDrawerWidth : 0,
          child: drawerVisible
              ? DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Color(0xFFE5E5E5)),
                    ),
                  ),
                  child: _buildMitarbeiterDesktopDrawer(selection!),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildMitarbeiterDesktopDrawer(_SelectedMitarbeiter selection) {
    return Material(
      color: Colors.white,
      elevation: 14,
      child: SafeArea(
        child: _MitarbeiterDetailSidebar(
          key: ValueKey(selection.docId),
          name: selection.name,
          istAktiv: selection.aktiv,
          onClose: () => setState(() => _selectedMitarbeiterId = null),
          onSave: (name, status) => _speichereMitarbeiterAenderungen(
            docId: selection.docId,
            name: name,
            status: status,
          ),
        ),
      ),
    );
  }

  Future<void> _speichereMitarbeiterAenderungen({
    required String docId,
    required String name,
    required String status,
  }) async {
    final bereinigterName = name.trim();
    if (bereinigterName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte geben Sie einen Namen ein.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'name': bereinigterName,
        'aktiv': status == 'aktiv',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Änderungen gespeichert.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Änderungen konnten nicht gespeichert werden.'),
        ),
      );
    }
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

class _SelectedMitarbeiter {
  const _SelectedMitarbeiter({
    required this.docId,
    required this.name,
    required this.aktiv,
  });

  final String docId;
  final String name;
  final bool aktiv;
}

class _MitarbeiterDetailSidebar extends StatefulWidget {
  const _MitarbeiterDetailSidebar({
    super.key,
    required this.name,
    required this.istAktiv,
    required this.onClose,
    required this.onSave,
  });

  final String name;
  final bool istAktiv;
  final VoidCallback onClose;
  final Future<void> Function(String name, String status) onSave;

  @override
  State<_MitarbeiterDetailSidebar> createState() =>
      _MitarbeiterDetailSidebarState();
}

class _MitarbeiterDetailSidebarState extends State<_MitarbeiterDetailSidebar> {
  late final TextEditingController _nameController;
  late String _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _status = widget.istAktiv ? 'aktiv' : 'inaktiv';
  }

  @override
  void didUpdateWidget(covariant _MitarbeiterDetailSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      _nameController.text = widget.name;
    }
    if (oldWidget.istAktiv != widget.istAktiv) {
      _status = widget.istAktiv ? 'aktiv' : 'inaktiv';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mitarbeiter bearbeiten',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.name.isNotEmpty ? widget.name : 'Unbenannt',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Schließen',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MitarbeiterSidebarSection(
                  title: 'Name',
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Name des Mitarbeiters',
                    ),
                  ),
                ),
                _MitarbeiterSidebarSection(
                  title: 'Status',
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    items: const [
                      DropdownMenuItem(value: 'aktiv', child: Text('aktiv')),
                      DropdownMenuItem(value: 'inaktiv', child: Text('inaktiv')),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _status = value);
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      setState(() => _isSaving = true);
                      try {
                        await widget.onSave(_nameController.text, _status);
                      } finally {
                        if (mounted) {
                          setState(() => _isSaving = false);
                        }
                      }
                    },
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Änderungen speichern'),
            ),
          ),
        ),
      ],
    );
  }
}

class _MitarbeiterSidebarSection extends StatelessWidget {
  const _MitarbeiterSidebarSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          child,
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