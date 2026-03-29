import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:image_picker/image_picker.dart';

import 'alle_dienstleister_page.dart';
import 'dienstleister_angebote_page.dart';
import 'dienstleister_bilder_page.dart';
import 'dienstleister_edit_page.dart';
import 'dienstleister_kalender_page.dart';

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
  static const int _defaultKalenderFarbeValue = 0xFF4285F4;
  static const List<int> _kalenderFarbPalette = [
    0xFF4285F4,
    0xFF0F9D58,
    0xFFF4B400,
    0xFFDB4437,
    0xFFAB47BC,
    0xFF00ACC1,
    0xFFFF7043,
    0xFF7CB342,
    0xFF5C6BC0,
    0xFFE91E63,
  ];
  static const List<_OeffnungszeitenTagDefinition> _tageDerWoche = [
    _OeffnungszeitenTagDefinition(key: 'montag', label: 'Montag'),
    _OeffnungszeitenTagDefinition(key: 'dienstag', label: 'Dienstag'),
    _OeffnungszeitenTagDefinition(key: 'mittwoch', label: 'Mittwoch'),
    _OeffnungszeitenTagDefinition(key: 'donnerstag', label: 'Donnerstag'),
    _OeffnungszeitenTagDefinition(key: 'freitag', label: 'Freitag'),
    _OeffnungszeitenTagDefinition(key: 'samstag', label: 'Samstag'),
    _OeffnungszeitenTagDefinition(key: 'sonntag', label: 'Sonntag'),
  ];

  int _selectedIndex = 0;
  int _selectedHomeSidebarIndex = 0;
  int _selectedProfilSidebarIndex = 0;
  String? dienstleisterName;
  String? _selectedMitarbeiterId;
  String? _selectedOeffnungszeitenTagKey;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _mitarbeiterStream;
  Uint8List? _pendingProfileImageBytes;
  String? _pendingProfileImageMitarbeiterId;
  bool _isProfileImageUploading = false;
  bool _isInitializingOeffnungszeiten = false;
  bool _isUploadingLogo = false;

  int _resolveKalenderFarbeValue(Map<String, dynamic> data) {
    final rawValue = data['kalenderFarbe'];

    if (rawValue is int) {
      return rawValue;
    }

    if (rawValue is String) {
      final trimmed = rawValue.trim();
      if (trimmed.isNotEmpty) {
        final parsed = int.tryParse(trimmed);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return _defaultKalenderFarbeValue;
  }

  @override
  void initState() {
    super.initState();
    _ladeDienstleisterName();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _mitarbeiterStream = FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'mitarbeiter')
          .where('dienstleisterId', isEqualTo: uid)
          .snapshots();
    }
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
      if (index != 3) {
        _selectedProfilSidebarIndex = 0;
      }
    });
  }

  void _onHomeSidebarTapped(int index) {
    setState(() {
      _selectedIndex = 0;
      _selectedHomeSidebarIndex = index;
    });
  }

  void _onProfilSidebarTapped(int index) {
    setState(() {
      _selectedIndex = 3;
      _selectedProfilSidebarIndex = index;
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

  Future<void> _pickAndUploadLogo() async {
    if (_isUploadingLogo) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      setState(() => _isUploadingLogo = true);

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        if (mounted) {
          setState(() => _isUploadingLogo = false);
        }
        return;
      }

      final bytes = await pickedFile.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          setState(() => _isUploadingLogo = false);
        }
        return;
      }

      final storagePath = 'profile_images/dienstleister_${user.uid}.jpg';
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);

      await storageRef.putData(bytes);
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'logoUrl': downloadUrl,
        'logoPath': storagePath,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Hochladen des Profilbilds: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingLogo = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildCurrentHomeContent(),
      DienstleisterKalenderPage(dienstleisterId: widget.dienstleisterId),
      const DienstleisterAngebotePage(showScaffold: false),
      _buildCurrentProfilContent(),
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
              if (isDesktopLayout && _selectedIndex != 1)
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
        switch (_selectedHomeSidebarIndex) {
          case 1:
            return 'Mitarbeiter';
          case 2:
            return 'Öffnungszeiten';
          case 0:
          default:
            return 'Hallo, ${dienstleisterName ?? '...'}';
        }
      case 1:
        return 'Kalender';
      case 2:
        return 'Leistungen';
      case 3:
        return _selectedProfilSidebarIndex == 1 ? 'Bilder' : 'Profil';
      default:
        return '';
    }
  }

  Widget _buildCurrentHomeContent() {
    switch (_selectedHomeSidebarIndex) {
      case 1:
        return _buildMitarbeiterPage();
      case 2:
        return _buildOeffnungszeitenPage();
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
          _SidebarItemData(
            title: 'Öffnungszeiten',
            icon: Icons.access_time_outlined,
            isSelected: _selectedHomeSidebarIndex == 2,
            onTap: () => _onHomeSidebarTapped(2),
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
            isSelected: _selectedProfilSidebarIndex == 0,
            onTap: () => _onProfilSidebarTapped(0),
          ),
          _SidebarItemData(
            title: 'Bilder',
            icon: Icons.photo_library_outlined,
            isSelected: _selectedProfilSidebarIndex == 1,
            onTap: () => _onProfilSidebarTapped(1),
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _buildCurrentProfilContent() {
    switch (_selectedProfilSidebarIndex) {
      case 1:
        return const DienstleisterBilderPage();
      case 0:
      default:
        return _buildProfilPage();
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

  Map<String, dynamic> _defaultOeffnungszeitenMap() {
    return {
      'montag': {'aktiv': true, 'von': '09:00', 'bis': '18:00'},
      'dienstag': {'aktiv': true, 'von': '09:00', 'bis': '18:00'},
      'mittwoch': {'aktiv': true, 'von': '09:00', 'bis': '18:00'},
      'donnerstag': {'aktiv': true, 'von': '09:00', 'bis': '18:00'},
      'freitag': {'aktiv': true, 'von': '09:00', 'bis': '18:00'},
      'samstag': {'aktiv': false, 'von': '', 'bis': ''},
      'sonntag': {'aktiv': false, 'von': '', 'bis': ''},
    };
  }

  Map<String, dynamic> _normalizeOeffnungszeiten(Map<String, dynamic>? raw) {
    final defaults = _defaultOeffnungszeitenMap();
    final source = raw ?? const <String, dynamic>{};
    final normalized = <String, dynamic>{};

    for (final tag in _tageDerWoche) {
      final defaultTag =
      Map<String, dynamic>.from(defaults[tag.key] as Map<String, dynamic>);
      final currentValue = source[tag.key];
      final currentTag = currentValue is Map
          ? Map<String, dynamic>.from(currentValue as Map)
          : const <String, dynamic>{};

      normalized[tag.key] = {
        'aktiv': currentTag['aktiv'] is bool
            ? currentTag['aktiv']
            : defaultTag['aktiv'],
        'von': (currentTag['von'] as String?)?.trim() ?? defaultTag['von'],
        'bis': (currentTag['bis'] as String?)?.trim() ?? defaultTag['bis'],
      };
    }

    return normalized;
  }

  bool _oeffnungszeitenNeedInitialization(Map<String, dynamic>? raw) {
    if (raw == null) return true;

    for (final tag in _tageDerWoche) {
      final dayValue = raw[tag.key];
      if (dayValue is! Map) {
        return true;
      }

      final dayMap = Map<String, dynamic>.from(dayValue as Map);
      if (dayMap['aktiv'] is! bool ||
          dayMap['von'] is! String ||
          dayMap['bis'] is! String) {
        return true;
      }
    }

    return false;
  }

  Future<void> _ensureOeffnungszeitenInitialized(
      Map<String, dynamic>? raw,
      ) async {
    if (_isInitializingOeffnungszeiten) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !_oeffnungszeitenNeedInitialization(raw)) return;

    setState(() => _isInitializingOeffnungszeiten = true);

    try {
      final normalized = _normalizeOeffnungszeiten(raw);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'oeffnungszeiten': normalized,
      }, SetOptions(merge: true));
    } finally {
      if (mounted) {
        setState(() => _isInitializingOeffnungszeiten = false);
      }
    }
  }

  String _buildOeffnungszeitenSubtitle(_OeffnungszeitenTag tag) {
    if (!tag.aktiv) {
      return 'Geschlossen';
    }

    final von = tag.von.trim();
    final bis = tag.bis.trim();
    if (von.isEmpty || bis.isEmpty) {
      return 'Offen';
    }

    return 'Offen $von - $bis';
  }

  Widget _buildOeffnungszeitenPage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Nicht eingeloggt.'));
    }

    final isDesktopLayout = MediaQuery.sizeOf(context).width >= 1100;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final rawData = snapshot.data?.data();
        final rawOeffnungszeiten = rawData?['oeffnungszeiten'];
        final normalized = _normalizeOeffnungszeiten(
          rawOeffnungszeiten is Map
              ? Map<String, dynamic>.from(rawOeffnungszeiten)
              : null,
        );

        if (_oeffnungszeitenNeedInitialization(
          rawOeffnungszeiten is Map
              ? Map<String, dynamic>.from(rawOeffnungszeiten)
              : null,
        )) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _ensureOeffnungszeitenInitialized(
                rawOeffnungszeiten is Map
                    ? Map<String, dynamic>.from(rawOeffnungszeiten)
                    : null,
              );
            }
          });
        }

        final tage = _tageDerWoche.map((tag) {
          final values = Map<String, dynamic>.from(
            normalized[tag.key] as Map<String, dynamic>,
          );
          return _OeffnungszeitenTag(
            key: tag.key,
            label: tag.label,
            aktiv: values['aktiv'] == true,
            von: (values['von'] as String?)?.trim() ?? '',
            bis: (values['bis'] as String?)?.trim() ?? '',
          );
        }).toList();

        _OeffnungszeitenTag? selectedTag;
        for (final tag in tage) {
          if (tag.key == _selectedOeffnungszeitenTagKey) {
            selectedTag = tag;
            break;
          }
        }

        final listContent = _buildOeffnungszeitenListContent(
          snapshot: snapshot,
          tage: tage,
          isDesktopLayout: isDesktopLayout,
        );

        if (!isDesktopLayout) {
          return listContent;
        }

        return _buildOeffnungszeitenDesktopContent(
          listContent: listContent,
          selection: selectedTag,
        );
      },
    );
  }

  Widget _buildOeffnungszeitenListContent({
    required AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
    required List<_OeffnungszeitenTag> tage,
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
                'Verwalte deine Öffnungszeiten',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Wochentage (${tage.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Die Öffnungszeiten konnten nicht geladen werden.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: tage.asMap().entries.map((entry) {
                      final index = entry.key;
                      final tag = entry.value;
                      final isSelected = tag.key == _selectedOeffnungszeitenTagKey;

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
                                _selectedOeffnungszeitenTagKey = tag.key;
                              })
                                  : null,
                              mouseCursor: isDesktopLayout
                                  ? SystemMouseCursors.click
                                  : MouseCursor.defer,
                              hoverColor: const Color(0xFFF5F5F5),
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF02152B),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.access_time_outlined,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                tag.label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(_buildOeffnungszeitenSubtitle(tag)),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 20,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          if (index < tage.length - 1)
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

  Widget _buildOeffnungszeitenDesktopContent({
    required Widget listContent,
    required _OeffnungszeitenTag? selection,
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
            child: _buildOeffnungszeitenDesktopDrawer(selection!),
          )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildOeffnungszeitenDesktopDrawer(_OeffnungszeitenTag selection) {
    return Material(
      color: Colors.white,
      elevation: 14,
      child: SafeArea(
        child: _OeffnungszeitenDetailSidebar(
          key: ValueKey(selection.key),
          day: selection,
          onClose: () => setState(() => _selectedOeffnungszeitenTagKey = null),
          onStatusChanged: (aktiv) => _speichereOeffnungszeitenStatus(
            tagKey: selection.key,
            aktiv: aktiv,
          ),
          onVonChanged: (zeit) => _speichereOeffnungszeitenZeit(
            tagKey: selection.key,
            feld: 'von',
            zeit: zeit,
          ),
          onBisChanged: (zeit) => _speichereOeffnungszeitenZeit(
            tagKey: selection.key,
            feld: 'bis',
            zeit: zeit,
          ),
        ),
      ),
    );
  }

  Widget _buildMitarbeiterPage() {
    if (_mitarbeiterStream == null) {
      return const Center(child: Text('Nicht eingeloggt.'));
    }

    final isDesktopLayout = MediaQuery.sizeOf(context).width >= 1100;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _mitarbeiterStream,
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
              profileImageUrl: (data['profileImageUrl'] as String?)?.trim(),
              profileImagePath: (data['profileImagePath'] as String?)?.trim(),
              kalenderFarbeValue: _resolveKalenderFarbeValue(data),
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
                        final profileImageUrl =
                        (data['profileImageUrl'] as String?)?.trim();
                        final kalenderFarbeValue =
                        _resolveKalenderFarbeValue(data);

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
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x14000000),
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Color(kalenderFarbeValue),
                                      width: 2,
                                    ),
                                  ),
                                  child: _MitarbeiterAvatar(
                                    radius: 24,
                                    name: name,
                                    imageUrl: profileImageUrl,
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
    final showEditor =
        selection != null &&
            _pendingProfileImageBytes != null &&
            _pendingProfileImageMitarbeiterId == selection.docId;

    return Row(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              listContent,
              if (showEditor)
                _MitarbeiterImageEditorOverlay(
                  imageBytes: _pendingProfileImageBytes!,
                  isSaving: _isProfileImageUploading,
                  onCancel:
                  _isProfileImageUploading ? null : _verwerfeLokalesProfilbild,
                  onConfirm: _isProfileImageUploading
                      ? null
                      : (croppedBytes) => _speichereProfilbild(
                    docId: selection.docId,
                    croppedBytes: croppedBytes,
                    previousProfileImagePath: selection.profileImagePath,
                  ),
                ),
            ],
          ),
        ),
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
          docId: selection.docId,
          name: selection.name,
          istAktiv: selection.aktiv,
          profileImageUrl: selection.profileImageUrl,
          localProfileImageBytes:
          _pendingProfileImageMitarbeiterId == selection.docId
              ? _pendingProfileImageBytes
              : null,
          hasPendingProfileImage:
          _pendingProfileImageMitarbeiterId == selection.docId &&
              _pendingProfileImageBytes != null,
          isProfileImageBusy: _isProfileImageUploading,
          onClose: () => setState(() => _selectedMitarbeiterId = null),
          onNameSave: (name) => _speichereMitarbeiterNamen(
            docId: selection.docId,
            name: name,
          ),
          onStatusChanged: (istAktiv) => _speichereMitarbeiterStatus(
            docId: selection.docId,
            istAktiv: istAktiv,
          ),
          initialKalenderFarbeValue: selection.kalenderFarbeValue,
          kalenderFarbPalette: _kalenderFarbPalette,
          onKalenderFarbeChanged: (farbeValue) => _speichereMitarbeiterFarbe(
            docId: selection.docId,
            farbeValue: farbeValue,
          ),
          onDelete: () => _loescheMitarbeiter(
            docId: selection.docId,
            name: selection.name,
          ),
          onTakePhoto: () => _waehleProfilbild(
            docId: selection.docId,
            source: ImageSource.camera,
          ),
          onUploadPhoto: () => _waehleProfilbild(
            docId: selection.docId,
            source: ImageSource.gallery,
          ),
          onRemovePhoto: () => _entferneProfilbild(
            docId: selection.docId,
            currentProfileImagePath: selection.profileImagePath,
          ),
        ),
      ),
    );
  }

  String _buildProfileImageStoragePath(String docId) {
    return 'profile_images/$docId.jpg';
  }

  Future<void> _waehleProfilbild({
    required String docId,
    required ImageSource source,
  }) async {
    if (_isProfileImageUploading) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 95,
      );

      if (pickedFile == null) {
        return;
      }

      final bytes = await pickedFile.readAsBytes();
      if (!mounted || bytes.isEmpty) return;

      setState(() {
        _pendingProfileImageMitarbeiterId = docId;
        _pendingProfileImageBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? 'Das Foto konnte nicht aufgenommen werden.'
                : 'Das Bild konnte nicht ausgewählt werden.',
          ),
        ),
      );
    }
  }

  void _verwerfeLokalesProfilbild() {
    if (!mounted) return;
    setState(() {
      _pendingProfileImageBytes = null;
      _pendingProfileImageMitarbeiterId = null;
    });
  }

  Future<void> _speichereProfilbild({
    required String docId,
    required Uint8List croppedBytes,
    String? previousProfileImagePath,
  }) async {
    if (_isProfileImageUploading) return;

    setState(() {
      _isProfileImageUploading = true;
    });

    final storagePath = _buildProfileImageStoragePath(docId);

    try {
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);
      await storageRef.putData(croppedBytes);
      final downloadUrl = await storageRef.getDownloadURL();

      final previousPath = previousProfileImagePath?.trim();
      if (previousPath != null &&
          previousPath.isNotEmpty &&
          previousPath != storagePath) {
        try {
          await FirebaseStorage.instance.ref().child(previousPath).delete();
        } on FirebaseException catch (error) {
          if (error.code != 'object-not-found') {
            rethrow;
          }
        }
      }

      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'profileImageUrl': downloadUrl,
        'profileImagePath': storagePath,
      });

      if (!mounted) return;
      setState(() {
        _pendingProfileImageBytes = null;
        _pendingProfileImageMitarbeiterId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profilbild gespeichert.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Profilbild konnte nicht gespeichert werden.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProfileImageUploading = false;
        });
      }
    }
  }

  Future<void> _entferneProfilbild({
    required String docId,
    String? currentProfileImagePath,
  }) async {
    if (_isProfileImageUploading) return;

    setState(() {
      _isProfileImageUploading = true;
    });

    final existingPath = currentProfileImagePath?.trim();
    final storagePath = existingPath != null && existingPath.isNotEmpty
        ? existingPath
        : _buildProfileImageStoragePath(docId);

    try {
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);

      try {
        await storageRef.delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') {
          rethrow;
        }
      }

      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'profileImageUrl': FieldValue.delete(),
        'profileImagePath': FieldValue.delete(),
      });

      if (!mounted) return;
      setState(() {
        if (_pendingProfileImageMitarbeiterId == docId) {
          _pendingProfileImageBytes = null;
          _pendingProfileImageMitarbeiterId = null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profilbild entfernt.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Profilbild konnte nicht entfernt werden.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProfileImageUploading = false;
        });
      }
    }
  }

  Future<bool> _speichereOeffnungszeitenStatus({
    required String tagKey,
    required bool aktiv,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'oeffnungszeiten.$tagKey.aktiv': aktiv,
      });

      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Öffnungsstatus gespeichert.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Öffnungsstatus konnte nicht gespeichert werden.'),
        ),
      );
      return false;
    }
  }

  Future<bool> _speichereOeffnungszeitenZeit({
    required String tagKey,
    required String feld,
    required String zeit,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'oeffnungszeiten.$tagKey.$feld': zeit,
      });

      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uhrzeit gespeichert.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Uhrzeit konnte nicht gespeichert werden.'),
        ),
      );
      return false;
    }
  }

  Future<bool> _speichereMitarbeiterNamen({
    required String docId,
    required String name,
  }) async {
    final bereinigterName = name.trim();
    if (bereinigterName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte geben Sie einen Namen ein.')),
      );
      return false;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update(
        {'name': bereinigterName},
      );

      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name gespeichert.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Name konnte nicht gespeichert werden.'),
        ),
      );
      return false;
    }
  }

  Future<bool> _speichereMitarbeiterStatus({
    required String docId,
    required bool istAktiv,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update(
        {'aktiv': istAktiv},
      );

      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status gespeichert.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Status konnte nicht gespeichert werden.'),
        ),
      );
      return false;
    }
  }

  Future<bool> _speichereMitarbeiterFarbe({
    required String docId,
    required int farbeValue,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update(
        {'kalenderFarbe': farbeValue},
      );

      if (!mounted) return true;
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Kalenderfarbe konnte nicht gespeichert werden.'),
        ),
      );
      return false;
    }
  }

  Future<bool> _loescheMitarbeiter({
    required String docId,
    required String name,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).delete();

      if (!mounted) return true;
      setState(() => _selectedMitarbeiterId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('„$name“ wurde gelöscht.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Mitarbeiter konnte nicht gelöscht werden.'),
        ),
      );
      return false;
    }
  }

  Future<void> _zeigeMitarbeiterErstellenDialog() async {
    final nameController = TextEditingController();
    String? fehlertext;
    bool wirdGespeichert = false;

    final erstellterMitarbeiterName = await showDialog<String>(
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
                  'rolle': 'mitarbeiter',
                  'dienstleisterId': user.uid,
                  'createdAt': FieldValue.serverTimestamp(),
                  'aktiv': true,
                  'loginAktiviert': false,
                  'kalenderFarbe': _defaultKalenderFarbeValue,
                });

                if (!mounted || !dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(name);
              } catch (_) {
                if (!dialogContext.mounted) return;
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

    if (!mounted || erstellterMitarbeiterName == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mitarbeiter „$erstellterMitarbeiterName“ wurde erstellt.'),
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

    if (user == null) {
      return const Center(child: Text('Nicht eingeloggt.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data();
        final logoUrl = (userData?['logoUrl'] as String?)?.trim() ?? '';

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: _isUploadingLogo ? null : _pickAndUploadLogo,
                  borderRadius: BorderRadius.circular(50),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.blueAccent,
                            width: 2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: logoUrl.isNotEmpty
                              ? Image.network(
                            logoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.person,
                                size: 42,
                                color: Color(0xFF02152B),
                              );
                            },
                          )
                              : const Icon(
                            Icons.person,
                            size: 42,
                            color: Color(0xFF02152B),
                          ),
                        ),
                      ),
                      if (_isUploadingLogo)
                        Container(
                          width: 96,
                          height: 96,
                          decoration: const BoxDecoration(
                            color: Color(0x66000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(30),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DienstleisterEditPageEditPage(
                          userId: user.uid,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Persönliche Daten bearbeiten'),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _logout,
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Abmelden'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SelectedMitarbeiter {
  const _SelectedMitarbeiter({
    required this.docId,
    required this.name,
    required this.aktiv,
    required this.kalenderFarbeValue,
    this.profileImageUrl,
    this.profileImagePath,
  });

  final String docId;
  final String name;
  final bool aktiv;
  final int kalenderFarbeValue;
  final String? profileImageUrl;
  final String? profileImagePath;
}

class _OeffnungszeitenTagDefinition {
  const _OeffnungszeitenTagDefinition({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;
}

class _OeffnungszeitenTag {
  const _OeffnungszeitenTag({
    required this.key,
    required this.label,
    required this.aktiv,
    required this.von,
    required this.bis,
  });

  final String key;
  final String label;
  final bool aktiv;
  final String von;
  final String bis;
}

class _MitarbeiterDetailSidebar extends StatefulWidget {
  const _MitarbeiterDetailSidebar({
    super.key,
    required this.docId,
    required this.name,
    required this.istAktiv,
    this.profileImageUrl,
    this.localProfileImageBytes,
    required this.hasPendingProfileImage,
    required this.isProfileImageBusy,
    required this.onClose,
    required this.onNameSave,
    required this.onStatusChanged,
    required this.initialKalenderFarbeValue,
    required this.kalenderFarbPalette,
    required this.onKalenderFarbeChanged,
    required this.onDelete,
    required this.onTakePhoto,
    required this.onUploadPhoto,
    required this.onRemovePhoto,
  });

  final String docId;
  final String name;
  final bool istAktiv;
  final String? profileImageUrl;
  final Uint8List? localProfileImageBytes;
  final bool hasPendingProfileImage;
  final bool isProfileImageBusy;
  final VoidCallback onClose;
  final Future<bool> Function(String name) onNameSave;
  final Future<bool> Function(bool istAktiv) onStatusChanged;
  final int initialKalenderFarbeValue;
  final List<int> kalenderFarbPalette;
  final Future<bool> Function(int farbeValue) onKalenderFarbeChanged;
  final Future<bool> Function() onDelete;
  final Future<void> Function() onTakePhoto;
  final Future<void> Function() onUploadPhoto;
  final Future<void> Function() onRemovePhoto;

  @override
  State<_MitarbeiterDetailSidebar> createState() =>
      _MitarbeiterDetailSidebarState();
}

class _MitarbeiterDetailSidebarState extends State<_MitarbeiterDetailSidebar> {
  late final TextEditingController _nameController;
  late String _initialName;
  late bool _istAktiv;
  late int _kalenderFarbeValue;
  bool _isNameSaving = false;
  bool _isStatusSaving = false;
  bool _isColorSaving = false;
  bool _isDeleting = false;

  bool get _hasNameChanged =>
      _nameController.text.trim() != _initialName.trim();

  String get _deleteDialogName {
    final name = _initialName.trim();
    return name.isEmpty ? 'Unbenannt' : name;
  }

  void _handleNameChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleProfileImageMenuSelection(_ProfileImageMenuAction action) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      switch (action) {
        case _ProfileImageMenuAction.takePhoto:
          await widget.onTakePhoto();
          break;
        case _ProfileImageMenuAction.uploadPhoto:
          await widget.onUploadPhoto();
          break;
        case _ProfileImageMenuAction.removePhoto:
          await widget.onRemovePhoto();
          break;
      }
    });
  }

  Future<void> _saveName() async {
    if (_isNameSaving || !_hasNameChanged) return;

    setState(() => _isNameSaving = true);
    final bereinigterName = _nameController.text.trim();

    try {
      final erfolgreich = await widget.onNameSave(bereinigterName);
      if (erfolgreich && mounted) {
        setState(() {
          _initialName = bereinigterName;
          _nameController.value = _nameController.value.copyWith(
            text: bereinigterName,
            selection: TextSelection.collapsed(
              offset: bereinigterName.length,
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isNameSaving = false);
      }
    }
  }

  Future<void> _handleStatusChanged(bool value) async {
    if (_isStatusSaving || value == _istAktiv) return;

    final vorherigerStatus = _istAktiv;
    setState(() {
      _istAktiv = value;
      _isStatusSaving = true;
    });

    final erfolgreich = await widget.onStatusChanged(value);

    if (!mounted) return;
    setState(() {
      if (!erfolgreich) {
        _istAktiv = vorherigerStatus;
      }
      _isStatusSaving = false;
    });
  }

  Future<void> _confirmDelete() async {
    if (_isDeleting) return;

    final bestaetigt = await showDialog<bool>(
      context: context,
      barrierDismissible: !_isDeleting,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text(
            'Mitarbeiter löschen',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Soll „$_deleteDialogName“ wirklich gelöscht werden?',
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isDeleting
                        ? null
                        : () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Löschen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isDeleting
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Abbrechen'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (bestaetigt != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await widget.onDelete();
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _handleColorSelected(int farbeValue) async {
    if (_isColorSaving || farbeValue == _kalenderFarbeValue) return;

    final vorherigeFarbe = _kalenderFarbeValue;
    setState(() {
      _kalenderFarbeValue = farbeValue;
      _isColorSaving = true;
    });

    final erfolgreich = await widget.onKalenderFarbeChanged(farbeValue);

    if (!mounted) return;
    setState(() {
      if (!erfolgreich) {
        _kalenderFarbeValue = vorherigeFarbe;
      }
      _isColorSaving = false;
    });
  }

  Widget _buildSaveAction({required bool visible}) {
    if (!visible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: InkWell(
          onTap: _isNameSaving ? null : _saveName,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: _isNameSaving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(
                Icons.check,
                size: 32,
                color: Color(0xFF24C552),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _nameController.addListener(_handleNameChanged);
    _initialName = widget.name;
    _istAktiv = widget.istAktiv;
    _kalenderFarbeValue = widget.initialKalenderFarbeValue;
  }

  @override
  void didUpdateWidget(covariant _MitarbeiterDetailSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      _initialName = widget.name;
      _nameController.value = _nameController.value.copyWith(
        text: widget.name,
        selection: TextSelection.collapsed(offset: widget.name.length),
      );
    }
    if (oldWidget.istAktiv != widget.istAktiv) {
      _istAktiv = widget.istAktiv;
    }
    if (oldWidget.initialKalenderFarbeValue != widget.initialKalenderFarbeValue) {
      _kalenderFarbeValue = widget.initialKalenderFarbeValue;
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasProfileImage =
        (widget.profileImageUrl?.trim().isNotEmpty ?? false) ||
            widget.localProfileImageBytes != null;

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
                  title: 'Profilbild',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Color(_kalenderFarbeValue),
                            width: 2,
                          ),
                        ),
                        child: _MitarbeiterAvatar(
                          radius: 42,
                          name: widget.name,
                          imageUrl: widget.profileImageUrl,
                          imageBytes: widget.localProfileImageBytes,
                          usePlaceholderIcon: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      PopupMenuButton<_ProfileImageMenuAction>(
                        enabled: !widget.isProfileImageBusy,
                        tooltip: 'Profilbild bearbeiten',
                        onSelected: _handleProfileImageMenuSelection,
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: _ProfileImageMenuAction.takePhoto,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.photo_camera_outlined),
                              title: Text('Foto aufnehmen'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: _ProfileImageMenuAction.uploadPhoto,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.upload_outlined),
                              title: Text('Bild hochladen'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _ProfileImageMenuAction.removePhoto,
                            enabled: hasProfileImage,
                            child: const ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline),
                              title: Text('Bild entfernen'),
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              widget.isProfileImageBusy
                                  ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                                  : const Icon(Icons.edit_outlined, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                widget.hasPendingProfileImage
                                    ? 'Bearbeiten fortsetzen'
                                    : 'Bearbeiten',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _MitarbeiterSidebarSection(
                  title: 'Name',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _saveName(),
                          decoration: const InputDecoration(
                            hintText: 'Name des Mitarbeiters',
                          ),
                        ),
                      ),
                      _buildSaveAction(visible: _hasNameChanged),
                    ],
                  ),
                ),
                _MitarbeiterSidebarSection(
                  title: 'Status',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _istAktiv
                          ? const Color(0x142EAD62)
                          : const Color(0x14D92D20),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _istAktiv
                            ? const Color(0xFF2EAD62)
                            : const Color(0xFFD92D20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Switch(
                          value: _istAktiv,
                          onChanged:
                          _isStatusSaving ? null : _handleStatusChanged,
                          activeColor: Colors.white,
                          activeTrackColor: const Color(0xFF2EAD62),
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor: const Color(0xFFD92D20),
                          materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                        ),
                        const SizedBox(width: 12),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeInOut,
                          style: Theme.of(context).textTheme.titleSmall!.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _istAktiv
                                ? const Color(0xFF1F7A42)
                                : const Color(0xFFB42318),
                          ),
                          child: Text(_istAktiv ? 'Aktiv' : 'Inaktiv'),
                        ),
                      ],
                    ),
                  ),
                ),
                _MitarbeiterSidebarSection(
                  title: 'Kalenderfarbe',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: widget.kalenderFarbPalette.map((farbeValue) {
                          final farbe = Color(farbeValue);
                          final isSelected = _kalenderFarbeValue == farbeValue;
                          final iconColor = farbe.computeLuminance() > 0.5
                              ? Colors.black87
                              : Colors.white;

                          return InkWell(
                            onTap: _isColorSaving
                                ? null
                                : () => _handleColorSelected(farbeValue),
                            borderRadius: BorderRadius.circular(999),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: farbe,
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF111827)
                                      : Colors.transparent,
                                  width: 2.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: isSelected
                                  ? Icon(
                                Icons.check,
                                size: 18,
                                color: iconColor,
                              )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      if (_isColorSaving) ...[
                        const SizedBox(height: 10),
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isDeleting ? null : _confirmDelete,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE53935),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              icon: _isDeleting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFE53935),
                ),
              )
                  : const Icon(Icons.delete_outline),
              label: const Text(
                'Mitarbeiter löschen',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
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

class _OeffnungszeitenDetailSidebar extends StatefulWidget {
  const _OeffnungszeitenDetailSidebar({
    super.key,
    required this.day,
    required this.onClose,
    required this.onStatusChanged,
    required this.onVonChanged,
    required this.onBisChanged,
  });

  final _OeffnungszeitenTag day;
  final VoidCallback onClose;
  final Future<bool> Function(bool aktiv) onStatusChanged;
  final Future<bool> Function(String zeit) onVonChanged;
  final Future<bool> Function(String zeit) onBisChanged;

  @override
  State<_OeffnungszeitenDetailSidebar> createState() =>
      _OeffnungszeitenDetailSidebarState();
}

class _OeffnungszeitenDetailSidebarState
    extends State<_OeffnungszeitenDetailSidebar> {
  late bool _istAktiv;
  late String _von;
  late String _bis;
  bool _isStatusSaving = false;
  bool _isVonSaving = false;
  bool _isBisSaving = false;

  Future<void> _handleStatusChanged(bool value) async {
    if (_isStatusSaving || value == _istAktiv) return;

    final previous = _istAktiv;
    setState(() {
      _istAktiv = value;
      _isStatusSaving = true;
    });

    final success = await widget.onStatusChanged(value);
    if (!mounted) return;

    setState(() {
      if (!success) {
        _istAktiv = previous;
      }
      _isStatusSaving = false;
    });
  }

  Future<void> _pickTime({
    required String title,
    required String currentValue,
    required bool isSaving,
    required Future<bool> Function(String zeit) onSave,
    required ValueSetter<String> onLocalUpdate,
    required ValueSetter<bool> onSavingChanged,
  }) async {
    if (isSaving) return;

    final initial =
        _parseTimeString(currentValue) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: title,
    );

    if (!mounted || picked == null) return;

    final formatted = _formatTimeOfDay(picked);
    final previous = currentValue;
    setState(() {
      onLocalUpdate(formatted);
      onSavingChanged(true);
    });

    final success = await onSave(formatted);
    if (!mounted) return;

    setState(() {
      if (!success) {
        onLocalUpdate(previous);
      }
      onSavingChanged(false);
    });
  }

  TimeOfDay? _parseTimeString(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTimeOfDay(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildTimeTile({
    required String title,
    required String value,
    required bool isSaving,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: isSaving ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value.isEmpty ? 'Uhrzeit wählen' : value,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              isSaving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.schedule_outlined),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _istAktiv = widget.day.aktiv;
    _von = widget.day.von;
    _bis = widget.day.bis;
  }

  @override
  void didUpdateWidget(covariant _OeffnungszeitenDetailSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day.key != widget.day.key ||
        oldWidget.day.aktiv != widget.day.aktiv ||
        oldWidget.day.von != widget.day.von ||
        oldWidget.day.bis != widget.day.bis) {
      _istAktiv = widget.day.aktiv;
      _von = widget.day.von;
      _bis = widget.day.bis;
    }
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
                      'Öffnungszeiten bearbeiten',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.day.label,
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
                  title: 'Status',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _istAktiv
                          ? const Color(0x142EAD62)
                          : const Color(0x14D92D20),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _istAktiv
                            ? const Color(0xFF2EAD62)
                            : const Color(0xFFD92D20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Switch(
                          value: _istAktiv,
                          onChanged:
                          _isStatusSaving ? null : _handleStatusChanged,
                          activeColor: Colors.white,
                          activeTrackColor: const Color(0xFF2EAD62),
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor: const Color(0xFFD92D20),
                          materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                        ),
                        const SizedBox(width: 12),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeInOut,
                          style: Theme.of(context).textTheme.titleSmall!.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _istAktiv
                                ? const Color(0xFF1F7A42)
                                : const Color(0xFFB42318),
                          ),
                          child: Text(_istAktiv ? 'Offen' : 'Geschlossen'),
                        ),
                      ],
                    ),
                  ),
                ),
                _MitarbeiterSidebarSection(
                  title: 'Von',
                  child: _buildTimeTile(
                    title: 'Startzeit',
                    value: _von,
                    isSaving: _isVonSaving,
                    onTap: () => _pickTime(
                      title: 'Von',
                      currentValue: _von,
                      isSaving: _isVonSaving,
                      onSave: widget.onVonChanged,
                      onLocalUpdate: (value) => _von = value,
                      onSavingChanged: (saving) => _isVonSaving = saving,
                    ),
                  ),
                ),
                _MitarbeiterSidebarSection(
                  title: 'Bis',
                  child: _buildTimeTile(
                    title: 'Endzeit',
                    value: _bis,
                    isSaving: _isBisSaving,
                    onTap: () => _pickTime(
                      title: 'Bis',
                      currentValue: _bis,
                      isSaving: _isBisSaving,
                      onSave: widget.onBisChanged,
                      onLocalUpdate: (value) => _bis = value,
                      onSavingChanged: (saving) => _isBisSaving = saving,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _ProfileImageMenuAction { takePhoto, uploadPhoto, removePhoto }

class _MitarbeiterAvatar extends StatelessWidget {
  const _MitarbeiterAvatar({
    required this.radius,
    required this.name,
    this.imageUrl,
    this.imageBytes,
    this.usePlaceholderIcon = false,
  });

  final double radius;
  final String? name;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final bool usePlaceholderIcon;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl?.trim();
    final trimmedName = name?.trim();

    if (imageBytes != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE5E7EB),
        backgroundImage: MemoryImage(imageBytes!),
      );
    }

    if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE5E7EB),
        backgroundImage: NetworkImage(trimmedUrl),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF02152B),
      child: usePlaceholderIcon
          ? Icon(
        Icons.person,
        color: Colors.white,
        size: radius,
      )
          : Text(
        (trimmedName != null && trimmedName.isNotEmpty)
            ? trimmedName.characters.first.toUpperCase()
            : '?',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.75,
        ),
      ),
    );
  }
}

class _MitarbeiterImageEditorOverlay extends StatefulWidget {
  const _MitarbeiterImageEditorOverlay({
    required this.imageBytes,
    required this.isSaving,
    required this.onConfirm,
    this.onCancel,
  });

  final Uint8List imageBytes;
  final bool isSaving;
  final ValueChanged<Uint8List>? onConfirm;
  final VoidCallback? onCancel;

  @override
  State<_MitarbeiterImageEditorOverlay> createState() =>
      _MitarbeiterImageEditorOverlayState();
}

class _MitarbeiterImageEditorOverlayState
    extends State<_MitarbeiterImageEditorOverlay> {
  final CropController _cropController = CropController();

  bool _isCropping = false;
  double _aspectRatio = 1;

  @override
  void didUpdateWidget(covariant _MitarbeiterImageEditorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) {
      _isCropping = false;
    }
  }

  void _confirmCrop() {
    if (_isCropping || widget.isSaving || widget.onConfirm == null) return;
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: 1,
      child: ColoredBox(
        color: const Color(0xB3121722),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 760,
              maxHeight: 720,
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 28,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Profilbild anpassen',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Verschiebe und schneide das Bild zu, bevor du es speicherst.',
                                  style: TextStyle(
                                    color: Color(0xFFD1D5DB),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Abbrechen',
                            onPressed: widget.isSaving ? null : widget.onCancel,
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Crop(
                            controller: _cropController,
                            image: widget.imageBytes,
                            initialRectBuilder:
                            InitialRectBuilder.withSizeAndRatio(
                              size: 0.8,
                              aspectRatio: _aspectRatio,
                            ),
                            baseColor: const Color(0xFF111827),
                            maskColor: const Color(0xA6000000),
                            radius: 22,
                            withCircleUi: false,
                            interactive: true,
                            fixCropRect: false,
                            aspectRatio: _aspectRatio,
                            onCropped: (result) {
                              if (!mounted) return;
                              switch (result) {
                                case CropSuccess(:final croppedImage):
                                  setState(() {
                                    _isCropping = false;
                                  });
                                  widget.onConfirm?.call(croppedImage);
                                  break;
                                case CropFailure():
                                  setState(() {
                                    _isCropping = false;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Das Bild konnte nicht zugeschnitten werden.',
                                      ),
                                    ),
                                  );
                                  break;
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          SegmentedButton<double>(
                            segments: const [
                              ButtonSegment<double>(
                                value: 1,
                                icon: Icon(Icons.crop_square),
                                label: Text('1:1'),
                              ),
                              ButtonSegment<double>(
                                value: 0.8,
                                icon: Icon(Icons.portrait),
                                label: Text('4:5'),
                              ),
                            ],
                            selected: {_aspectRatio},
                            onSelectionChanged: (values) {
                              final nextValue = values.firstOrNull;
                              if (nextValue == null) return;
                              setState(() {
                                _aspectRatio = nextValue;
                              });
                            },
                            style: ButtonStyle(
                              foregroundColor: MaterialStateProperty.all(
                                Colors.white,
                              ),
                            ),
                          ),
                          const Spacer(),
                          OutlinedButton(
                            onPressed: widget.isSaving ? null : widget.onCancel,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                            ),
                            child: const Text('Abbrechen'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: (widget.isSaving || _isCropping)
                                ? null
                                : _confirmCrop,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF24C552),
                              foregroundColor: Colors.white,
                            ),
                            child: widget.isSaving
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : _isCropping
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Icon(Icons.check),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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
