import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingImage = false;

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
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? <String, dynamic>{};

      _nameController.text =
          (data['displayName'] ?? data['name'] ?? '').toString().trim();
      _phoneNumber =
          (data['phoneNumber'] ?? user.phoneNumber ?? '').toString().trim();
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

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

      final bytes = await file.readAsBytes();
      final storagePath =
          'profile_images/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await ref.getDownloadURL();

      if (_profileImagePath.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref().child(_profileImagePath).delete();
        } catch (_) {}
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    final displayName = _nameController.text.trim();

    if (displayName.isEmpty) {
      _showMessage('Bitte gib deinen Namen ein.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
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
              _nameController.text.trim().isNotEmpty
                  ? _nameController.text.trim().characters.first
                  .toUpperCase()
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
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : user == null
            ? const Center(
          child: Text('Du bist aktuell nicht eingeloggt.'),
        )
            : ListView(
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
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              label: 'Telefonnummer',
              value: _phoneNumber,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
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
          ],
        ),
      ),
    );
  }
}
