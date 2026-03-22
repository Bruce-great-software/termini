import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  final ImagePicker _imagePicker = ImagePicker();

  int _selectedIndex = 0;
  int _selectedHomeSidebarIndex = 0;
  String? dienstleisterName;
  String? _selectedMitarbeiterId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _mitarbeiterStream;
  _PendingProfileImage? _pendingProfileImage;
  bool _isProfileImageUploading = false;

  @override
  void initState() {
    super.initState();
    _ladeDienstleisterName();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _mitarbeiterStream = FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'mitarbeiter')
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
        _selectedMitarbeiterId = null;
        _pendingProfileImage = null;
      }
    });
  }

  void _onHomeSidebarTapped(int index) {
    setState(() {
      _selectedIndex = 0;
      _selectedHomeSidebarIndex = index;
      if (index != 1) {
        _selectedMitarbeiterId = null;
        _pendingProfileImage = null;
      }
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

  Future<void> _handleProfileImageAction({
    required String docId,
    required _ProfileImageAction action,
  }) async {
    final source = switch (action) {
      _ProfileImageAction.camera => ImageSource.camera,
      _ProfileImageAction.gallery => ImageSource.gallery,
    };

    try {
      final pickedImage = await _imagePicker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2400,
      );

      if (pickedImage == null) return;

      final imageBytes = await pickedImage.readAsBytes();
      if (!mounted) return;

      setState(() {
        _pendingProfileImage = _PendingProfileImage(
          userDocId: docId,
          sourceBytes: imageBytes,
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == _ProfileImageAction.camera
                ? 'Das Foto konnte nicht aufgenommen werden.'
                : 'Das Bild konnte nicht geladen werden.',
          ),
        ),
      );
    }
  }

  void _cancelPendingProfileImage() {
    if (_isProfileImageUploading) return;
    setState(() => _pendingProfileImage = null);
  }

  Future<void> _savePendingProfileImage(Uint8List croppedBytes) async {
    final pendingImage = _pendingProfileImage;
    if (pendingImage == null || _isProfileImageUploading) return;

    setState(() => _isProfileImageUploading = true);

    final storagePath = 'profile_images/${pendingImage.userDocId}/profile.jpg';

    try {
      final storageRef = FirebaseStorage.instance.ref(storagePath);
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public,max-age=3600',
      );

      await storageRef.putData(croppedBytes, metadata);
      final downloadUrl = await storageRef.getDownloadURL();
      final cacheBustedUrl =
          '$downloadUrl&v=${DateTime.now().millisecondsSinceEpoch}';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(pendingImage.userDocId)
          .update({
        'profileImageUrl': cacheBustedUrl,
        'profileImagePath': storagePath,
      });

      if (!mounted) return;

      setState(() {
        _pendingProfileImage = null;
        _isProfileImageUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profilbild gespeichert.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProfileImageUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Profilbild konnte nicht gespeichert werden.'),
        ),
      );
    }
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
            );
          }
        }

        if (_selectedMitarbeiterId != null && selectedMitarbeiter == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedMitarbeiterId = null;
                _pendingProfileImage = null;
              });
            }
          });
        }

        if (_pendingProfileImage != null &&
            selectedMitarbeiter != null &&
            _pendingProfileImage!.userDocId != selectedMitarbeiter.docId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _pendingProfileImage = null);
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
                                      if (_pendingProfileImage?.userDocId !=
                                          doc.id) {
                                        _pendingProfileImage = null;
                                      }
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
                                child: _ProfileAvatar(
                                  imageUrl:
                                      (data['profileImageUrl'] as String?)?.trim(),
                                  radius: 24,
                                  fallbackLabel: name,
                                  backgroundColor: const Color(0xFF02152B),
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
    final pendingImage = selection != null &&
            _pendingProfileImage?.userDocId == selection.docId
        ? _pendingProfileImage
        : null;

    return Row(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: listContent),
              if (pendingImage != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.white.withOpacity(0.92),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 760,
                          maxHeight: 680,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _ProfileImageEditorCard(
                            imageBytes: pendingImage.sourceBytes,
                            isSaving: _isProfileImageUploading,
                            onCancel: _cancelPendingProfileImage,
                            onConfirm: _savePendingProfileImage,
                          ),
                        ),
                      ),
                    ),
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
          name: selection.name,
          istAktiv: selection.aktiv,
          profileImageUrl: selection.profileImageUrl,
          hasPendingProfileImage:
              _pendingProfileImage?.userDocId == selection.docId,
          isProfileImageSaving: _isProfileImageUploading,
          onClose: () => setState(() {
            _selectedMitarbeiterId = null;
            _pendingProfileImage = null;
          }),
          onNameSave: (name) => _speichereMitarbeiterNamen(
            docId: selection.docId,
            name: name,
          ),
          onStatusChanged: (istAktiv) => _speichereMitarbeiterStatus(
            docId: selection.docId,
            istAktiv: istAktiv,
          ),
          onEditProfileImage: (action) => _handleProfileImageAction(
            docId: selection.docId,
            action: action,
          ),
          onDelete: () => _loescheMitarbeiter(
            docId: selection.docId,
            name: selection.name,
          ),
        ),
      ),
    );
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

  Future<bool> _loescheMitarbeiter({
    required String docId,
    required String name,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).delete();

      if (!mounted) return true;
      setState(() {
        _selectedMitarbeiterId = null;
        _pendingProfileImage = null;
      });
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
                  'role': 'mitarbeiter',
                  'dienstleisterId': user.uid,
                  'createdAt': FieldValue.serverTimestamp(),
                  'aktiv': true,
                  'loginAktiviert': false,
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
    this.profileImageUrl,
    this.profileImagePath,
  });

  final String docId;
  final String name;
  final bool aktiv;
  final String? profileImageUrl;
  final String? profileImagePath;
}

class _PendingProfileImage {
  const _PendingProfileImage({
    required this.userDocId,
    required this.sourceBytes,
  });

  final String userDocId;
  final Uint8List sourceBytes;
}

enum _ProfileImageAction { camera, gallery }

class _MitarbeiterDetailSidebar extends StatefulWidget {
  const _MitarbeiterDetailSidebar({
    super.key,
    required this.name,
    required this.istAktiv,
    required this.profileImageUrl,
    required this.hasPendingProfileImage,
    required this.isProfileImageSaving,
    required this.onClose,
    required this.onNameSave,
    required this.onStatusChanged,
    required this.onEditProfileImage,
    required this.onDelete,
  });

  final String name;
  final bool istAktiv;
  final String? profileImageUrl;
  final bool hasPendingProfileImage;
  final bool isProfileImageSaving;
  final VoidCallback onClose;
  final Future<bool> Function(String name) onNameSave;
  final Future<bool> Function(bool istAktiv) onStatusChanged;
  final Future<void> Function(_ProfileImageAction action) onEditProfileImage;
  final Future<bool> Function() onDelete;

  @override
  State<_MitarbeiterDetailSidebar> createState() =>
      _MitarbeiterDetailSidebarState();
}

class _MitarbeiterDetailSidebarState extends State<_MitarbeiterDetailSidebar> {
  late final TextEditingController _nameController;
  late String _initialName;
  late bool _istAktiv;
  bool _isNameSaving = false;
  bool _isStatusSaving = false;
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
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileHint = widget.hasPendingProfileImage
        ? 'Bild ausgewählt – bitte mittig zuschneiden und mit dem grünen Häkchen speichern.'
        : 'Profilbild auswählen oder aufnehmen.';

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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F8F8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE8E8E8)),
                        ),
                        child: Column(
                          children: [
                            _ProfileAvatar(
                              imageUrl: widget.profileImageUrl,
                              radius: 46,
                              fallbackLabel: null,
                              iconSize: 42,
                              backgroundColor: const Color(0xFF1F1F1F),
                            ),
                            const SizedBox(height: 14),
                            PopupMenuButton<_ProfileImageAction>(
                              enabled: !widget.isProfileImageSaving,
                              onSelected: widget.onEditProfileImage,
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: _ProfileImageAction.camera,
                                  child: _ProfileImageMenuItem(
                                    icon: Icons.photo_camera_outlined,
                                    label: 'Foto aufnehmen',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: _ProfileImageAction.gallery,
                                  child: _ProfileImageMenuItem(
                                    icon: Icons.upload_file_outlined,
                                    label: 'Bild hochladen',
                                  ),
                                ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111111),
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x1A000000),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      widget.isProfileImageSaving
                                          ? Icons.sync
                                          : Icons.edit_outlined,
                                      size: 18,
                                      color: const Color(0xFF24C552),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Bearbeiten',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: const Color(0xFF24C552),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              profileHint,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.black54),
                            ),
                          ],
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

class _ProfileImageEditorCard extends StatefulWidget {
  const _ProfileImageEditorCard({
    required this.imageBytes,
    required this.isSaving,
    required this.onCancel,
    required this.onConfirm,
  });

  final Uint8List imageBytes;
  final bool isSaving;
  final VoidCallback onCancel;
  final Future<void> Function(Uint8List croppedBytes) onConfirm;

  @override
  State<_ProfileImageEditorCard> createState() => _ProfileImageEditorCardState();
}

class _ProfileImageEditorCardState extends State<_ProfileImageEditorCard> {
  final CropController _cropController = CropController();
  bool _isCropping = false;

  Future<void> _confirmCrop() async {
    if (_isCropping || widget.isSaving) return;

    setState(() => _isCropping = true);
    _cropController.cropCircle();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 16,
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profilbild anpassen',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Verschiebe und skaliere das Bild. Erst das grüne Häkchen speichert das Profilbild.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Abbrechen',
                  onPressed:
                      widget.isSaving || _isCropping ? null : widget.onCancel,
                  icon: const Icon(Icons.close),
                ),
                FilledButton(
                  onPressed: widget.isSaving || _isCropping ? null : _confirmCrop,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF24C552),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: widget.isSaving || _isCropping
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 26),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F6F8),
                  ),
                  child: Crop(
                    image: widget.imageBytes,
                    controller: _cropController,
                    withCircleUi: true,
                    interactive: true,
                    fixCropRect: true,
                    initialRectBuilder:
                        InitialRectBuilder.withSizeAndRatio(size: 0.9),
                    baseColor: const Color(0xFFF5F6F8),
                    maskColor: const Color(0x99000000),
                    radius: 20,
                    onCropped: (result) async {
                      switch (result) {
                        case CropSuccess(:final croppedImage):
                          await widget.onConfirm(croppedImage);
                        case CropFailure():
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Das Bild konnte nicht zugeschnitten werden.',
                                ),
                              ),
                            );
                          }
                      }

                      if (mounted) {
                        setState(() => _isCropping = false);
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Colors.black54,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Das Bild bleibt lokal in der Vorschau, bis du es mit dem grünen Häkchen bestätigst.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileImageMenuItem extends StatelessWidget {
  const _ProfileImageMenuItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imageUrl,
    required this.radius,
    required this.fallbackLabel,
    required this.backgroundColor,
    this.iconSize = 26,
  });

  final String? imageUrl;
  final double radius;
  final String? fallbackLabel;
  final double iconSize;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl?.trim();
    final hasImage = trimmedUrl != null && trimmedUrl.isNotEmpty;
    final initials = fallbackLabel?.trim();

    if (hasImage) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: NetworkImage(trimmedUrl),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: initials != null && initials.isNotEmpty
          ? Text(
              initials.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.8,
              ),
            )
          : Icon(
              Icons.person,
              size: iconSize,
              color: Colors.white70,
            ),
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
                              fontWeight: items[i].isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: items[i].isSelected
                                  ? Colors.black87
                                  : Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (i < items.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
