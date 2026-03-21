import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

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
  String? _kontoname;
  String? _dienstleisterName;
  String? _rolle;

  @override
  void initState() {
    super.initState();
    _ladeNamen();
  }

  Future<void> _ladeNamen() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final nutzerSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final nutzerDaten = nutzerSnapshot.data() ?? <String, dynamic>{};

      final aktuellerName = (nutzerDaten['name'] as String?)?.trim();
      final aktuelleRolle = (nutzerDaten['rolle'] as String?)?.trim().toLowerCase();
      final aktuellerDienstleisterName =
          (nutzerDaten['dienstleisterName'] as String?)?.trim();

      String? dienstleisterName = aktuellerDienstleisterName;
      if (widget.dienstleisterId.isNotEmpty &&
          widget.dienstleisterId != user.uid &&
          dienstleisterName == null) {
        final dienstleisterSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.dienstleisterId)
            .get();
        dienstleisterName =
            (dienstleisterSnapshot.data()?['name'] as String?)?.trim();
      }

      if (!mounted) return;
      setState(() {
        _kontoname = aktuellerName?.isNotEmpty == true ? aktuellerName : 'Unbekannt';
        _rolle = aktuelleRolle;
        _dienstleisterName = dienstleisterName?.isNotEmpty == true
            ? dienstleisterName
            : _kontoname;
      });
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der Namen aus users: $e');
      if (!mounted) return;
      setState(() {
        _kontoname = 'Fehler';
        _dienstleisterName = 'Fehler';
        _rolle = null;
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
        return 'Hallo, ${_kontoname ?? '...'}';
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
        'Willkommen zurück, ${_kontoname ?? 'Dienstleister'}!',
        style: const TextStyle(fontSize: 20),
      ),
    );
  }

  Widget _buildMitarbeiterPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'mitarbeiter')
          .where('dienstleisterId', isEqualTo: widget.dienstleisterId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Fehler beim Laden der Mitarbeiter: ${snapshot.error}'),
          );
        }

        final mitarbeiter = [...snapshot.data?.docs ?? []]
          ..sort((a, b) {
            final nameA = (a.data()['name'] as String? ?? '').toLowerCase();
            final nameB = (b.data()['name'] as String? ?? '').toLowerCase();
            return nameA.compareTo(nameB);
          });

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxContentWidth = constraints.maxWidth > 1200
                ? 1120.0
                : constraints.maxWidth - 32;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Mitarbeiterbereich für ${_dienstleisterName ?? 'Dienstleister'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 40),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 28,
                        runSpacing: 28,
                        children: [
                          ...mitarbeiter.map((doc) => _MitarbeiterCard(
                                name: (doc.data()['name'] as String?)?.trim().isNotEmpty == true
                                    ? (doc.data()['name'] as String).trim()
                                    : 'Unbekannt',
                                email: (doc.data()['email'] as String?)?.trim(),
                              )),
                          if (_rolle == 'dienstleister')
                            _CreateMitarbeiterCard(
                              onTap: _showCreateMitarbeiterDialog,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateMitarbeiterDialog() async {
    if (_rolle != 'dienstleister') return;

    final result = await showDialog<_MitarbeiterCreationResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateMitarbeiterDialog(
        dienstleisterId: widget.dienstleisterId,
        defaultBranche: widget.branche,
      ),
    );

    if (result == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Mitarbeiter ${result.name} erstellt. Login: ${result.email} | Passwort: ${result.password}',
        ),
        duration: const Duration(seconds: 6),
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

class _CreateMitarbeiterDialog extends StatefulWidget {
  final String dienstleisterId;
  final String defaultBranche;

  const _CreateMitarbeiterDialog({
    required this.dienstleisterId,
    required this.defaultBranche,
  });

  @override
  State<_CreateMitarbeiterDialog> createState() => _CreateMitarbeiterDialogState();
}

class _CreateMitarbeiterDialogState extends State<_CreateMitarbeiterDialog> {
  static const String _defaultPassword = 'defaultPassword123';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Kein eingeloggter Dienstleister gefunden.');
      }

      final dienstleisterDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.dienstleisterId)
          .get();
      final dienstleisterData = dienstleisterDoc.data();
      if (dienstleisterData == null) {
        throw Exception('Dienstleisterprofil konnte nicht geladen werden.');
      }

      final dienstleisterEmail = (dienstleisterData['email'] as String?)?.trim();
      final dienstleisterName = (dienstleisterData['name'] as String?)?.trim();
      final branche = (dienstleisterData['branche'] as String?)?.trim().isNotEmpty == true
          ? (dienstleisterData['branche'] as String).trim()
          : widget.defaultBranche;

      if (dienstleisterEmail == null || dienstleisterEmail.isEmpty) {
        throw Exception('Die E-Mail-Adresse des Dienstleisters fehlt.');
      }

      final mitarbeiterName = _nameController.text.trim();
      final mitarbeiterEmail = _buildEmployeeEmail(
        dienstleisterEmail: dienstleisterEmail,
        employeeName: mitarbeiterName,
      );

      final existingDocs = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: mitarbeiterEmail)
          .limit(1)
          .get();
      if (existingDocs.docs.isNotEmpty) {
        throw Exception('Für diesen Namen existiert bereits ein Mitarbeiter-Login.');
      }

      final secondaryAppName =
          'employee-creator-${DateTime.now().microsecondsSinceEpoch}';
      final secondaryApp = await Firebase.initializeApp(
        name: secondaryAppName,
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      User? createdUser;

      try {
        final credential = await secondaryAuth.createUserWithEmailAndPassword(
          email: mitarbeiterEmail,
          password: _defaultPassword,
        );
        createdUser = credential.user;
        final employeeUid = createdUser?.uid;
        if (employeeUid == null || employeeUid.isEmpty) {
          throw Exception('Die Authentifizierung für den Mitarbeiter ist fehlgeschlagen.');
        }

        await FirebaseFirestore.instance.collection('users').doc(employeeUid).set({
          'name': mitarbeiterName,
          'email': mitarbeiterEmail,
          'rolle': 'mitarbeiter',
          'dienstleisterId': widget.dienstleisterId,
          'dienstleisterName': dienstleisterName,
          'dienstleisterEmail': dienstleisterEmail,
          'branche': branche,
          'createAt': FieldValue.serverTimestamp(),
          'createdBy': currentUser.uid,
        });

        if (!mounted) return;
        Navigator.of(context).pop(
          _MitarbeiterCreationResult(
            name: mitarbeiterName,
            email: mitarbeiterEmail,
            password: _defaultPassword,
          ),
        );
      } catch (e) {
        await createdUser?.delete();
        rethrow;
      } finally {
        await secondaryAuth.signOut();
        await secondaryApp.delete();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString().replaceFirst('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mitarbeiter erstellen'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'Name des Mitarbeiters',
                  hintText: 'z. B. Jason',
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Bitte einen Namen eingeben.';
                  }
                  if (trimmed.length < 2) {
                    return 'Der Name muss mindestens 2 Zeichen lang sein.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Die Login-E-Mail wird automatisch aus dem Namen des Mitarbeiters und der E-Mail-Adresse des Dienstleisters erstellt.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorText!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Speichern'),
        ),
      ],
    );
  }
}

class _CreateMitarbeiterCard extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateMitarbeiterCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(44),
        child: Ink(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
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
    );
  }
}

class _MitarbeiterCard extends StatelessWidget {
  final String name;
  final String? email;

  const _MitarbeiterCard({required this.name, this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(44),
        border: Border.all(color: Colors.black, width: 4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.person,
            size: 132,
            color: Color(0xFF02152B),
          ),
          const SizedBox(height: 6),
          const CircleAvatar(
            radius: 23,
            backgroundColor: Color(0xFF02152B),
            child: Icon(
              Icons.add,
              size: 34,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 26),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          if (email != null && email!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              email!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _MitarbeiterCreationResult {
  final String name;
  final String email;
  final String password;

  const _MitarbeiterCreationResult({
    required this.name,
    required this.email,
    required this.password,
  });
}

String _buildEmployeeEmail({
  required String dienstleisterEmail,
  required String employeeName,
}) {
  final email = dienstleisterEmail.trim().toLowerCase();
  final atIndex = email.indexOf('@');
  if (atIndex <= 0 || atIndex == email.length - 1) {
    throw Exception('Die Dienstleister-E-Mail ist ungültig.');
  }

  final localPart = email.substring(0, atIndex);
  final domainPart = email.substring(atIndex + 1);
  final sanitizedEmployeePart = _sanitizeEmailPart(employeeName);

  if (sanitizedEmployeePart.isEmpty) {
    throw Exception('Aus dem Mitarbeiternamen konnte keine Login-E-Mail abgeleitet werden.');
  }

  return '$localPart.$sanitizedEmployeePart@$domainPart';
}

String _sanitizeEmailPart(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');

  final replaced = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '.');
  return replaced.replaceAll(RegExp(r'^\.+|\.+$'), '').replaceAll(RegExp(r'\.{2,}'), '.');
}

class _DesktopSidebar extends StatelessWidget {
  final double width;
  final List<_SidebarItemData> items;

  const _DesktopSidebar({
    required this.width,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Material(
                  color: item.isSelected
                      ? const Color(0xFFF2F3F7)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: item.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(item.icon, size: 18, color: const Color(0xFF6B7280)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItemData {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItemData({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });
}
