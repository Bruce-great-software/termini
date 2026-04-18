import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:termini/checkmytime/pages/login_register_page.dart';
import 'package:termini/checkmytime/services/activity_service.dart';

class _Neon {
  static const bg = Color(0xFF0A0A0F);
  static const bgElevated = Color(0xFF15151C);
  static const surface = Color(0xFF1E1E28);
  static const surfaceHigh = Color(0xFF262633);
  static const stroke = Color(0xFF2E2E3D);
  static const strokeStrong = Color(0xFF3A3A4D);

  static const textPrimary = Color(0xFFF5F5FA);
  static const textSecondary = Color(0xFFA0A0B8);
  static const textMuted = Color(0xFF6B6B80);

  static const cyan = Color(0xFF00E5FF);
  static const pink = Color(0xFFFF2E93);
  static const lime = Color(0xFFC6FF4A);
  static const purple = Color(0xFF8B5CF6);
  static const danger = Color(0xFFFF3B6B);

  static List<BoxShadow> glow(
      Color color, {
        double blur = 18,
        double alpha = 0.35,
      }) => [
    BoxShadow(
      color: color.withValues(alpha: alpha),
      blurRadius: blur,
      spreadRadius: 0,
    ),
  ];
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Neon.bg, _Neon.bgElevated],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _Neon.cyan),
              );
            }

            final user = snapshot.data;
            if (user == null) {
              return const _LoggedOutProfileView();
            }

            return _LoggedInProfileView(key: ValueKey(user.uid), user: user);
          },
        ),
      ),
    );
  }
}

class _LoggedOutProfileView extends StatelessWidget {
  const _LoggedOutProfileView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const _ProfileHeroCard(
          eyebrow: 'PROFIL',
          title: 'Dein CheckMyTime Konto',
          description:
          'Melde dich an oder registriere dich, damit du dein Profil bearbeiten, Kontakte verwalten und alle Funktionen nutzen kannst.',
          avatarLabel: 'P',
          isLoggedOut: true,
        ),
        const SizedBox(height: 18),
        _NeonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('LOGIN', accent: _Neon.cyan),
              const SizedBox(height: 14),
              const Text(
                'Mit deinem Profil kannst du ein Bild hinterlegen, gefunden werden und deine Aktivitäten verwalten.',
                style: TextStyle(
                  color: _Neon.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: _PrimaryNeonButton(
                  icon: Icons.login_rounded,
                  label: 'Einloggen oder registrieren',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LoginRegisterPage(),
                      ),
                    );
                  },
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
  const _LoggedInProfileView({super.key, required this.user});

  final User user;

  @override
  State<_LoggedInProfileView> createState() => _LoggedInProfileViewState();
}

class _LoggedInProfileViewState extends State<_LoggedInProfileView> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final FocusNode _nameFocusNode = FocusNode();

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
    _nameFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
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
      backgroundColor: _Neon.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: _Neon.strokeStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                _BottomSheetActionTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Aus Galerie auswählen',
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
                const SizedBox(height: 10),
                _BottomSheetActionTile(
                  icon: Icons.photo_camera_outlined,
                  title: 'Kamera öffnen',
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
              ],
            ),
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
      SnackBar(
        content: Text(
          text,
          style: const TextStyle(color: _Neon.textPrimary),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _Neon.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _Neon.strokeStrong),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final hasImage = _profileImageUrl.isNotEmpty;
    final trimmedName = _nameController.text.trim();
    final initial = trimmedName.isNotEmpty
        ? trimmedName.characters.first.toUpperCase()
        : 'P';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _isUploadingImage ? null : _showImageSourceSheet,
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _Neon.cyan, width: 2),
              boxShadow: _Neon.glow(_Neon.cyan, blur: 18, alpha: 0.28),
              gradient: hasImage
                  ? null
                  : const LinearGradient(
                colors: [_Neon.cyan, _Neon.purple, _Neon.pink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              image: hasImage
                  ? DecorationImage(
                image: NetworkImage(_profileImageUrl),
                fit: BoxFit.cover,
              )
                  : null,
            ),
            child: hasImage
                ? null
                : Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Material(
            color: _Neon.surfaceHigh,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _isUploadingImage ? null : _showImageSourceSheet,
              customBorder: const CircleBorder(),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _Neon.cyan),
                  boxShadow: _Neon.glow(_Neon.cyan, blur: 12, alpha: 0.25),
                ),
                child: _isUploadingImage
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _Neon.cyan,
                  ),
                )
                    : const Icon(
                  Icons.camera_alt_rounded,
                  color: _Neon.cyan,
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _Neon.cyan),
      );
    }

    final displayName = _nameController.text.trim();
    final effectiveName = displayName.isNotEmpty ? displayName : 'Dein Profil';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _ProfileHeroCard(
          eyebrow: 'MEIN PROFIL',
          title: effectiveName,
          description:
          'Bearbeite hier dein Profilbild, deinen Namen und die Sichtbarkeit deines Kontos.',
          avatar: _buildAvatar(),
          statusLabel: _isProfilePublic ? 'ÖFFENTLICH' : 'PRIVAT',
          statusAccent: _isProfilePublic ? _Neon.cyan : _Neon.pink,
        ),
        const SizedBox(height: 18),
        _NeonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('PERSÖNLICHE DATEN', accent: _Neon.cyan),
              const SizedBox(height: 14),
              _NeonInput(
                controller: _nameController,
                focusNode: _nameFocusNode,
                label: 'Name',
                hint: 'Dein Name',
                icon: Icons.badge_outlined,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              _InfoTile(
                icon: Icons.phone_outlined,
                label: 'Telefonnummer',
                value: _phoneNumber.isEmpty ? 'Keine Angabe' : _phoneNumber,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _NeonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('SICHTBARKEIT', accent: _Neon.pink),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (_isProfilePublic ? _Neon.cyan : _Neon.pink)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (_isProfilePublic ? _Neon.cyan : _Neon.pink)
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(
                      _isProfilePublic ? Icons.public : Icons.lock_outline,
                      color: _isProfilePublic ? _Neon.cyan : _Neon.pink,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profilsichtbarkeit',
                          style: TextStyle(
                            color: _Neon.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isProfilePublic
                              ? 'Öffentlich · Jede:r kann dein Profil finden und dir direkt folgen.'
                              : 'Privat · Neue Follower senden zuerst eine Anfrage. Bestehende Follower bleiben erhalten.',
                          style: const TextStyle(
                            color: _Neon.textSecondary,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _isProfilePublic,
                    activeColor: _Neon.cyan,
                    inactiveThumbColor: _Neon.pink,
                    inactiveTrackColor: _Neon.pink.withValues(alpha: 0.28),
                    onChanged: (_isSaving ||
                        _isUploadingImage ||
                        _isSigningOut ||
                        _isUpdatingPrivacy)
                        ? null
                        : _toggleProfilePrivacy,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Tipp: Wenn dein Profil privat ist, bleiben Nachrichten und gemeinsame Planungen weiterhin möglich.',
                style: TextStyle(
                  color: _Neon.textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _NeonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('AKTIONEN', accent: _Neon.lime),
              const SizedBox(height: 14),
              const Text(
                'Tippe auf dein Avatarbild, um ein neues Foto aus der Galerie oder Kamera zu wählen.',
                style: TextStyle(
                  color: _Neon.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: _PrimaryNeonButton(
                  icon: _isSaving ? null : Icons.save_outlined,
                  label: _isSaving ? 'Wird gespeichert...' : 'Profil speichern',
                  isLoading: _isSaving,
                  onTap: (_isSaving || _isUploadingImage || _isSigningOut)
                      ? null
                      : _saveProfile,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _SecondaryNeonButton(
                  icon: _isSigningOut ? null : Icons.logout_rounded,
                  label: _isSigningOut ? 'Wird ausgeloggt...' : 'Ausloggen',
                  isLoading: _isSigningOut,
                  onTap: (_isSaving || _isUploadingImage || _isSigningOut)
                      ? null
                      : _signOut,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    this.avatar,
    this.avatarLabel,
    this.statusLabel,
    this.statusAccent,
    this.isLoggedOut = false,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget? avatar;
  final String? avatarLabel;
  final String? statusLabel;
  final Color? statusAccent;
  final bool isLoggedOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _Neon.strokeStrong),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _Neon.surfaceHigh,
                      _Neon.purple.withValues(alpha: 0.18),
                      _Neon.surface,
                      _Neon.cyan.withValues(alpha: 0.12),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -30,
              right: -20,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _Neon.pink.withValues(alpha: 0.08),
                  boxShadow: _Neon.glow(_Neon.pink, blur: 60, alpha: 0.16),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              left: -10,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _Neon.cyan.withValues(alpha: 0.08),
                  boxShadow: _Neon.glow(_Neon.cyan, blur: 60, alpha: 0.16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isLoggedOut ? _Neon.pink : _Neon.cyan,
                          boxShadow: _Neon.glow(
                            isLoggedOut ? _Neon.pink : _Neon.cyan,
                            blur: 10,
                            alpha: 0.9,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        eyebrow,
                        style: const TextStyle(
                          color: _Neon.textSecondary,
                          fontSize: 11,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (statusLabel != null && statusAccent != null)
                        _StatusPill(
                          label: statusLabel!,
                          accent: statusAccent!,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [_Neon.cyan, _Neon.pink],
                    ).createShader(bounds),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                        height: 1.05,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: _Neon.textSecondary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: avatar ?? _FallbackHeroAvatar(label: avatarLabel ?? 'P'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackHeroAvatar extends StatelessWidget {
  const _FallbackHeroAvatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [_Neon.cyan, _Neon.purple, _Neon.pink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: _Neon.glow(_Neon.purple, blur: 18, alpha: 0.28),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _NeonCard extends StatelessWidget {
  const _NeonCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _Neon.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _Neon.stroke),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
            boxShadow: _Neon.glow(accent, blur: 10, alpha: 0.8),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: _Neon.textSecondary,
            fontSize: 11,
            letterSpacing: 1.7,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NeonInput extends StatelessWidget {
  const _NeonInput({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: _Neon.bgElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: focusNode.hasFocus ? _Neon.cyan : _Neon.stroke,
          width: 1.2,
        ),
        boxShadow: focusNode.hasFocus
            ? _Neon.glow(_Neon.cyan, blur: 16, alpha: 0.22)
            : null,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: const TextStyle(color: _Neon.textPrimary, fontSize: 15),
        cursorColor: _Neon.cyan,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: _Neon.textSecondary),
          hintStyle: const TextStyle(color: _Neon.textMuted),
          prefixIcon: Icon(icon, color: _Neon.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Neon.bgElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Neon.stroke),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _Neon.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _Neon.cyan),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _Neon.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: _Neon.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
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

class _PrimaryNeonButton extends StatelessWidget {
  const _PrimaryNeonButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_Neon.cyan, _Neon.pink]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: onTap != null ? _Neon.glow(_Neon.cyan, blur: 18, alpha: 0.2) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, color: Colors.white, size: 20),
                if (isLoading || icon != null) const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryNeonButton extends StatelessWidget {
  const _SecondaryNeonButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Neon.surfaceHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _Neon.strokeStrong),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _Neon.textPrimary,
                  ),
                )
              else if (icon != null)
                Icon(icon, color: _Neon.textPrimary, size: 20),
              if (isLoading || icon != null) const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: _Neon.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomSheetActionTile extends StatelessWidget {
  const _BottomSheetActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Neon.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _Neon.stroke),
          ),
          child: Row(
            children: [
              Icon(icon, color: _Neon.cyan),
              const SizedBox(width: 14),
              Text(
                title,
                style: const TextStyle(
                  color: _Neon.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
