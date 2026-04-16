import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:termini/checkmytime/pages/login_register_page.dart';
import 'package:termini/checkmytime/services/activity_service.dart';
import 'package:termini/checkmytime/widgets/checkmytime_ui.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = snapshot.data;

        if (user == null) {
          return const _LoggedOutProfileView();
        }

        return _LoggedInProfileView(key: ValueKey(user.uid), user: user);
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

    return CheckMyTimeGradientBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          CheckMyTimeHeroCard(
            eyebrow: 'Profil',
            title: 'Profil und Login',
            description:
                'Melde dich an oder registriere dich, damit du dein Profil bearbeiten und CheckMyTime vollstaendig nutzen kannst.',
            trailing: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.person_outline,
                size: 34,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          CheckMyTimeSectionCard(
            child: Column(
              children: [
                Text(
                  'Mit deinem Profil kannst du Kontaktdaten pflegen, ein Bild hinterlegen und spaeter leichter gefunden werden.',
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
      ),
    );
  }
}

class _LoggedInProfileView extends StatefulWidget {
  const _LoggedInProfileView({super.key, required this.user});

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
  bool _isProfilePublic = true;
  bool _isUpdatingPrivacy = false;

  String _phoneNumber = '';
  String _profileImageUrl = '';
  String _profileImagePath = '';
  String _initialDisplayName = '';
  String _initialProfileImageUrl = '';

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
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.user.uid)
              .get();

      final data = doc.data() ?? <String, dynamic>{};

      _nameController.text =
          (data['displayName'] ?? data['name'] ?? '').toString().trim();
      _phoneNumber =
          (data['phoneNumber'] ?? widget.user.phoneNumber ?? '')
              .toString()
              .trim();
      _profileImageUrl = (data['profileImageUrl'] ?? '').toString().trim();
      _profileImagePath = (data['profileImagePath'] ?? '').toString().trim();
      _isProfilePublic = data['isProfilePublic'] as bool? ?? true;
      _initialDisplayName = _nameController.text.trim();
      _initialProfileImageUrl = _profileImageUrl;
    } catch (_) {
      if (!mounted) return;
      _showMessage('Profil konnte nicht geladen werden.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
                title: const Text('Aus Galerie auswaehlen'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Kamera oeffnen'),
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
          await FirebaseStorage.instance
              .ref()
              .child(_profileImagePath)
              .delete();
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
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
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
            'isProfilePublic': _isProfilePublic,
            'profileCompleted': true,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      final hasRelevantProfileChange =
          displayName != _initialDisplayName ||
          _profileImageUrl != _initialProfileImageUrl;

      if (hasRelevantProfileChange) {
        try {
          await ActivityService.instance.recordProfileUpdated(
            actorUserId: widget.user.uid,
            actorName: displayName,
            actorImageUrl: _profileImageUrl,
            isProfilePublic: _isProfilePublic,
          );
        } catch (_) {}
      }

      _initialDisplayName = displayName;
      _initialProfileImageUrl = _profileImageUrl;

      if (!mounted) return;
      _showMessage('Profil wurde gespeichert.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Profil konnte nicht gespeichert werden.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }


  Future<void> _toggleProfilePrivacy(bool value) async {
    if (_isUpdatingPrivacy) return;

    final previousValue = _isProfilePublic;
    setState(() {
      _isProfilePublic = value;
      _isUpdatingPrivacy = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({
            'isProfilePublic': value,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;
      _showMessage(
        value
            ? 'Dein Profil ist jetzt öffentlich.'
            : 'Dein Profil ist jetzt privat. Neue Follower müssen zuerst anfragen.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProfilePublic = previousValue;
      });
      _showMessage('Sichtbarkeit konnte nicht aktualisiert werden.');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingPrivacy = false;
        });
      }
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
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
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
            backgroundColor: colorScheme.primary.withValues(alpha: 0.10),
            backgroundImage: hasImage ? NetworkImage(_profileImageUrl) : null,
            child:
                hasImage
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
                child:
                    _isUploadingImage
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return CheckMyTimeGradientBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          CheckMyTimeHeroCard(
            eyebrow: 'Mein Profil',
            title: 'Profilbild und persoenliche Daten',
            description:
                'Hier kannst du deinen Namen und dein Profilbild fuer CheckMyTime bearbeiten.',
            trailing: _buildAvatar(colorScheme),
          ),
          const SizedBox(height: 20),
          CheckMyTimeSectionCard(
            child: TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Dein Name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 16),
          CheckMyTimeSectionCard(
            padding: const EdgeInsets.all(16),
            child: CheckMyTimeInfoRow(
              icon: Icons.phone_outlined,
              label: 'Telefonnummer',
              value: _phoneNumber.isEmpty ? 'Keine Angabe' : _phoneNumber,
            ),
          ),
          const SizedBox(height: 16),
          CheckMyTimeSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isProfilePublic ? Icons.public : Icons.lock_outline,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Profilsichtbarkeit',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isProfilePublic
                                ? 'Öffentlich · Jede:r kann dein Profil finden und dir direkt folgen.'
                                : 'Privat · Neue Follower senden zuerst eine Anfrage. Bestehende Follower bleiben erhalten.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: _isProfilePublic,
                      onChanged: (_isSaving || _isUploadingImage || _isSigningOut || _isUpdatingPrivacy)
                          ? null
                          : _toggleProfilePrivacy,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Tipp: Wenn dein Profil privat ist, bleiben Nachrichten und gemeinsame Planungen weiterhin möglich.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CheckMyTimeSectionCard(
            child: Column(
              children: [
                Text(
                  'Profilbild aendern',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tippe auf dein Avatarbild oben, um ein Foto aus der Galerie oder Kamera zu waehlen.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        (_isSaving || _isUploadingImage || _isSigningOut)
                            ? null
                            : _saveProfile,
                    icon:
                        _isSaving
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
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        (_isSaving || _isUploadingImage || _isSigningOut)
                            ? null
                            : _signOut,
                    icon:
                        _isSigningOut
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
