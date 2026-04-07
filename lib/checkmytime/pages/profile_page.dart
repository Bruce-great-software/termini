import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:termini/checkmytime/pages/login_register_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const _LoggedOutProfileView();
        }

        return _LoggedInProfileView(
          key: ValueKey(user.uid),
          user: user,
        );
      },
    );
  }
}

class _LoggedOutProfileView extends StatelessWidget {
  const _LoggedOutProfileView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: colorScheme.primary.withOpacity(0.10),
                child: Icon(
                  Icons.person_outline,
                  size: 34,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Profil & Login',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Melde dich an oder registriere dich, damit du dein Profil bearbeiten und CheckMyTime vollständig nutzen kannst.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LoginRegisterPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Einloggen oder registrieren'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoggedInProfileView extends StatefulWidget {
  const _LoggedInProfileView({
    super.key,
    required this.user,
  });

  final User user;

  @override
  State<_LoggedInProfileView> createState() => _LoggedInProfileViewState();
}

class _LoggedInProfileViewState extends State<_LoggedInProfileView> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingImage = false;
  bool _isSigningOut = false;

  String _phoneNumber = '';
  String _profileImageUrl = '';
  String _profileImagePath = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();

      final data = doc.data() ?? <String, dynamic>{};

      _nameController.text =
          (data['displayName'] ?? data['name'] ?? '').toString().trim();
      _phoneNumber =
          (data['phoneNumber'] ?? widget.user.phoneNumber ?? '').toString().trim();
      _profileImageUrl = (data['profileImageUrl'] ?? '').toString().trim();
      _profileImagePath = (data['profileImagePath'] ?? '').toString().trim();
    } catch (_) {
      if (!mounted) return;
      _showMessage('Profil konnte nicht geladen werden.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showImageSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Aus Galerie auswählen'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Kamera öffnen'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;
    await _pickAndUploadImage(source);
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
      );

      if (file == null) return;

      setState(() {
        _isUploadingImage = true;
      });

      final storagePath =
          'profile_images/${widget.user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putData(
        await file.readAsBytes(),
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final downloadUrl = await ref.getDownloadURL();

      if (_profileImagePath.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref().child(_profileImagePath).delete();
        } catch (_) {}
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({
        'profileImageUrl': downloadUrl,
        'profileImagePath': storagePath,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _profileImageUrl = downloadUrl;
        _profileImagePath = storagePath;
      });

      _showMessage('Profilbild wurde aktualisiert.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Profilbild konnte nicht hochgeladen werden.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    final displayName = _nameController.text.trim();

    if (displayName.isEmpty) {
      _showMessage('Bitte gib deinen Namen ein.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({
        'displayName': displayName,
        'name': displayName,
        'phoneNumber': _phoneNumber,
        'profileImageUrl': _profileImageUrl,
        'profileImagePath': _profileImagePath,
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _showMessage('Profil wurde gespeichert.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Profil konnte nicht gespeichert werden.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _isSigningOut = true;
    });

    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _showMessage('Du wurdest ausgeloggt.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Ausloggen fehlgeschlagen.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isSigningOut = false;
      });
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildAvatar(ColorScheme colorScheme) {
    final hasImage = _profileImageUrl.isNotEmpty;
    final trimmedName = _nameController.text.trim();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _isUploadingImage ? null : _showImageSourceSheet,
          child: CircleAvatar(
            radius: 52,
            backgroundColor: colorScheme.primary.withOpacity(0.10),
            backgroundImage: hasImage ? NetworkImage(_profileImageUrl) : null,
            child: hasImage
                ? null
                : Text(
              trimmedName.isNotEmpty
                  ? trimmedName.characters.first.toUpperCase()
                  : 'P',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        Positioned(
          right: -4,
          bottom: -4,
          child: Material(
            color: colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _isUploadingImage ? null : _showImageSourceSheet,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _isUploadingImage
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
      ),
      child: Text(value.isEmpty ? 'Keine Angabe' : value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              _buildAvatar(colorScheme),
              const SizedBox(height: 16),
              Text(
                'Profilbild und persönliche Daten',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Hier kannst du deinen Namen und dein Profilbild für CheckMyTime bearbeiten.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Dein Name',
          ),
          onChanged: (_) {
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        _buildReadOnlyField(
          label: 'Telefonnummer',
          value: _phoneNumber,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: (_isSaving || _isUploadingImage || _isSigningOut)
              ? null
              : _saveProfile,
          icon: _isSaving
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.save_outlined),
          label: Text(
            _isSaving ? 'Wird gespeichert...' : 'Profil speichern',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: (_isSaving || _isUploadingImage || _isSigningOut)
              ? null
              : _signOut,
          icon: _isSigningOut
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.logout),
          label: Text(
            _isSigningOut ? 'Wird ausgeloggt...' : 'Ausloggen',
          ),
        ),
      ],
    );
  }
}