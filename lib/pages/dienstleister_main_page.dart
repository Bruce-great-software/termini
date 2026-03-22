import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:image_picker/image_picker.dart';

import 'alle_dienstleister_page.dart';
import 'dienstleister_angebote_page.dart';
import 'dienstleister_edit_page.dart';
import '../utils/app_snackbar.dart';

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
  Stream<QuerySnapshot<Map<String, dynamic>>>? _mitarbeiterStream;
  final ImagePicker _imagePicker = ImagePicker();
  CropController _profileImageCropController = CropController();
  Uint8List? _pendingProfileImageBytes;
  String? _pendingProfileImageDocId;
  String? _pendingProfileImageName;
  bool _isUploadingProfileImage = false;

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
                _verwerfeLokalesProfilbild();
              });
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
                                        if (_selectedMitarbeiterId != doc.id) {
                                          _verwerfeLokalesProfilbild();
                                        }
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

  bool _zeigtLokalesProfilbildFuer(String docId) =>
      _pendingProfileImageBytes != null && _pendingProfileImageDocId == docId;

  void _verwerfeLokalesProfilbild() {
    _pendingProfileImageBytes = null;
    _pendingProfileImageDocId = null;
    _pendingProfileImageName = null;
    _isUploadingProfileImage = false;
    _profileImageCropController = CropController();
  }

  Future<void> _handleProfilbildAktion({
    required _SelectedMitarbeiter selection,
    required _ProfileImageAction action,
  }) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: action == _ProfileImageAction.kamera
            ? ImageSource.camera
            : ImageSource.gallery,
      );

      if (pickedFile == null) return;

      final bytes = await pickedFile.readAsBytes();
      if (!mounted) return;

      setState(() {
        _pendingProfileImageBytes = bytes;
        _pendingProfileImageDocId = selection.docId;
        _pendingProfileImageName = selection.name;
        _profileImageCropController = CropController();
      });
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        const SnackBar(
          content: Text('Das Bild konnte nicht ausgewählt werden.'),
        ),
      );
    }
  }

  Future<void> _handleProfilbildZugeschnitten(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        await _uploadProfilbild(croppedImage);
      case CropFailure():
        if (!mounted) return;
        showAppSnackBar(
          context,
          const SnackBar(
            content: Text('Das Bild konnte nicht zugeschnitten werden.'),
          ),
        );
    }
  }

  Future<void> _uploadProfilbild(Uint8List croppedImage) async {
    final docId = _pendingProfileImageDocId;
    if (docId == null || _isUploadingProfileImage) return;

    setState(() => _isUploadingProfileImage = true);

    final path = 'profile_images/$docId/profile.jpg';

    try {
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putData(
        croppedImage,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'profileImageUrl': downloadUrl,
        'profileImagePath': path,
      });

      if (!mounted) return;
      setState(_verwerfeLokalesProfilbild);
      showAppSnackBar(
        context,
        const SnackBar(content: Text('Profilbild gespeichert.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isUploadingProfileImage = false);
      showAppSnackBar(
        context,
        const SnackBar(
          content: Text('Das Profilbild konnte nicht gespeichert werden.'),
        ),
      );
    }
  }

  Widget _buildProfilbildVorschauOverlay() {
    final imageBytes = _pendingProfileImageBytes;
    if (imageBytes == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCCFFFFFF),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
            child: Card(
              elevation: 14,
              margin: const EdgeInsets.all(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Profilbild anpassen',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Passe das Bild für ${_pendingProfileImageName ?? 'den Mitarbeiter'} an und bestätige mit dem grünen Haken.',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Abbrechen',
                          onPressed: _isUploadingProfileImage
                              ? null
                              : () => setState(_verwerfeLokalesProfilbild),
                          icon: const Icon(Icons.close),
                        ),
                        IconButton(
                          tooltip: 'Speichern',
                          onPressed: _isUploadingProfileImage
                              ? null
                              : _profileImageCropController.cropCircle,
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF24C552),
                            foregroundColor: Colors.white,
                          ),
                          icon: _isUploadingProfileImage
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
                    const SizedBox(height: 20),
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: ColoredBox(
                          color: const Color(0xFF111827),
                          child: Crop(
                            image: imageBytes,
                            controller: _profileImageCropController,
                            onCropped: _handleProfilbildZugeschnitten,
                            withCircleUi: true,
                            interactive: true,
                            fixCropRect: true,
                            baseColor: const Color(0xFF111827),
                            maskColor: const Color(0x99000000),
                            progressIndicator: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: listContent),
              if (selection != null && _zeigtLokalesProfilbildFuer(selection.docId))
                _buildProfilbildVorschauOverlay(),
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
          isProfileImageUploading:
              _isUploadingProfileImage && _pendingProfileImageDocId == selection.docId,
          onClose: () => setState(() {
            _selectedMitarbeiterId = null;
            _verwerfeLokalesProfilbild();
          }),
          onNameSave: (name) => _speichereMitarbeiterNamen(
            docId: selection.docId,
            name: name,
          ),
          onStatusChanged: (istAktiv) => _speichereMitarbeiterStatus(
            docId: selection.docId,
            istAktiv: istAktiv,
          ),
          onDelete: () => _loescheMitarbeiter(
            docId: selection.docId,
            name: selection.name,
          ),
          onProfileImageActionSelected: (action) => _handleProfilbildAktion(
            selection: selection,
            action: action,
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
      showAppSnackBar(context,
        const SnackBar(content: Text('Bitte geben Sie einen Namen ein.')),
      );
      return false;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update(
        {'name': bereinigterName},
      );

      if (!mounted) return true;
      showAppSnackBar(context,
        const SnackBar(content: Text('Name gespeichert.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      showAppSnackBar(context,
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
      showAppSnackBar(context,
        const SnackBar(content: Text('Status gespeichert.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      showAppSnackBar(context,
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
        if (_pendingProfileImageDocId == docId) {
          _verwerfeLokalesProfilbild();
        }
      });
      showAppSnackBar(context,
        SnackBar(content: Text('„$name“ wurde gelöscht.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      showAppSnackBar(context,
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

    final erstellterMitarbeiterName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            void bestaetigen() {
              final name = nameController.text.trim();

              if (name.isEmpty) {
                setDialogState(() {
                  fehlertext = 'Bitte geben Sie einen Namen ein.';
                });
                return;
              }

              Navigator.of(dialogContext).pop(name);
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
                  onSubmitted: (_) => bestaetigen(),
                  decoration: InputDecoration(
                    labelText: 'Name des Mitarbeiters',
                    errorText: fehlertext,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: bestaetigen,
                  child: const Text('Erstellen'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();

    if (!mounted || erstellterMitarbeiterName == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showAppSnackBar(context,
        const SnackBar(content: Text('Sie sind nicht eingeloggt.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').add({
        'name': erstellterMitarbeiterName,
        'role': 'mitarbeiter',
        'dienstleisterId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'aktiv': true,
        'loginAktiviert': false,
      });

      if (!mounted) return;
      showAppSnackBar(context,
        SnackBar(
          content: Text('Mitarbeiter „$erstellterMitarbeiterName“ wurde erstellt.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context,
        const SnackBar(
          content: Text('Der Mitarbeiter konnte nicht erstellt werden.'),
        ),
      );
    }
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
    required this.profileImageUrl,
    required this.profileImagePath,
  });

  final String docId;
  final String name;
  final bool aktiv;
  final String? profileImageUrl;
  final String? profileImagePath;
}

enum _ProfileImageAction { kamera, galerie }

class _MitarbeiterDetailSidebar extends StatefulWidget {
  const _MitarbeiterDetailSidebar({
    super.key,
    required this.name,
    required this.istAktiv,
    required this.profileImageUrl,
    required this.isProfileImageUploading,
    required this.onClose,
    required this.onNameSave,
    required this.onStatusChanged,
    required this.onDelete,
    required this.onProfileImageActionSelected,
  });

  final String name;
  final bool istAktiv;
  final String? profileImageUrl;
  final bool isProfileImageUploading;
  final VoidCallback onClose;
  final Future<bool> Function(String name) onNameSave;
  final Future<bool> Function(bool istAktiv) onStatusChanged;
  final Future<bool> Function() onDelete;
  final Future<void> Function(_ProfileImageAction action)
      onProfileImageActionSelected;

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

  Widget _buildProfilbildAvatar() {
    final imageUrl = widget.profileImageUrl;

    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.person,
                size: 52,
                color: Colors.white70,
              ),
            )
          : const Icon(
              Icons.person,
              size: 52,
              color: Colors.white70,
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
                  child: Center(
                    child: Column(
                      children: [
                        _buildProfilbildAvatar(),
                        const SizedBox(height: 14),
                        PopupMenuButton<_ProfileImageAction>(
                          enabled: !widget.isProfileImageUploading,
                          tooltip: 'Profilbild bearbeiten',
                          onSelected: (action) {
                            widget.onProfileImageActionSelected(action);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _ProfileImageAction.kamera,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.photo_camera_outlined),
                                title: Text('Foto aufnehmen'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _ProfileImageAction.galerie,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.folder_outlined),
                                title: Text('Bild hochladen'),
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111827),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                widget.isProfileImageUploading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF24C552),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: Color(0xFF24C552),
                                      ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Bearbeiten',
                                  style: TextStyle(
                                    color: Color(0xFF24C552),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
