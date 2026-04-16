import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';
import 'package:termini/checkmytime/pages/event_detail_page.dart';
import 'package:termini/checkmytime/services/notification_dispatch_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design-Tokens — 1:1 aus dem HTML-Konzept (checkmytime_user_page_concept.html)
// CSS-Variablen-Mapping:
//   --color-background-primary   → #FFFFFF
//   --color-background-secondary → #F3F4F6
//   --color-background-tertiary  → #F9FAFB
//   --color-border-secondary     → #E5E7EB
//   --color-border-tertiary      → #F1F5F9
//   --color-text-primary         → #111827
//   --color-text-secondary       → #6B7280
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  // Surfaces
  static const bgPrimary = Color(0xFFFFFFFF);
  static const bgSecondary = Color(0xFFF3F4F6);
  static const bgTertiary = Color(0xFFF9FAFB);

  // Borders
  static const borderSecondary = Color(0xFFE5E7EB);
  static const borderTertiary = Color(0xFFF1F5F9);

  // Text
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);

  // Cover (linear-gradient 135°)
  static const coverBg1 = Color(0xFF1C1C40);
  static const coverBg2 = Color(0xFF2D2D6E);
  static const coverBg3 = Color(0xFF1A3A5C);

  // Primary accent (Follow-Button, Tab-Indicator)
  static const blue = Color(0xFF2563EB);

  // Online / Follow
  static const onlineGreen = Color(0xFF22C55E);
  static const notifAccept = Color(0xFF22C55E);

  // Status-Badges
  static const greenBg = Color(0xFFDCFCE7);
  static const greenText = Color(0xFF166534);
  static const blueBg = Color(0xFFDBEAFE);
  static const blueText = Color(0xFF1E40AF);
  static const amberBg = Color(0xFFFEF3C7);
  static const amberText = Color(0xFF92400E);
  static const redBg = Color(0xFFFEE2E2);
  static const redText = Color(0xFF991B1B);

  // Activity-Icon Hintergründe
  static const iconEventBg = Color(0xFFEEF2FF);
  static const iconPhotoBg = Color(0xFFF0FDF4);
  static const iconSocialBg = Color(0xFFFFF7ED);

  // Notif-Banner (follow_request)
  static const bannerBg = Color(0xFFFFF7ED);
  static const bannerBorder = Color(0xFFFCD34D);
  static const bannerText = Color(0xFF92400E);

  // Avatar-Farben (wie Konzept)
  static const List<Color> avatarColors = [
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
  ];

  static const danger = Color(0xFFEF4444);
}

// ─────────────────────────────────────────────────────────────────────────────
// UserPage
// ─────────────────────────────────────────────────────────────────────────────

class UserPage extends StatefulWidget {
  final String userId;
  final String initialName;
  final String initialImageUrl;
  final bool embedded;
  final bool hideTopIdentitySection;
  final VoidCallback? onMessageTap;

  const UserPage({
    super.key,
    required this.userId,
    this.initialName = '',
    this.initialImageUrl = '',
    this.embedded = false,
    this.hideTopIdentitySection = false,
    this.onMessageTap,
  });

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  // Loading
  bool _isLoading = true;
  bool _isFollowLoading = false;
  bool _isBlocking = false;

  // Profile-Daten
  String _displayName = '';
  String _phoneNumber = '';
  String _profileImageUrl = '';
  String _memberSince = '';
  String _bio = '';
  bool _isProfilePublic = true;

  // Follow-State
  bool _isFollowing = false;
  bool _isFollowPending = false;
  int _followerCount = 0;
  int _followingCount = 0;
  int _sharedEventCount = 0;

  bool _hasIncomingFollowRequest = false;

  // Tab-State: 'profil' | 'planungen' | 'events'
  String _activeTab = 'profil';

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get _canSeeFullProfile => _isProfilePublic || _isFollowing;

  // Events-Tab erscheint nur wenn public ODER wenn gefolgt (Konzept-Regel)
  bool get _showEventsTab => _isProfilePublic || _isFollowing;

  @override
  void initState() {
    super.initState();
    _displayName = widget.initialName.trim();
    _profileImageUrl = widget.initialImageUrl.trim();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadUserProfile(),
      _loadFollowState(),
      _loadSharedEventCount(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }


  Future<String> _loadCurrentUserDisplayName() async {
    try {
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      final data = myDoc.data() ?? <String, dynamic>{};
      final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
      return name.isEmpty ? 'Jemand' : name;
    } catch (_) {
      return 'Jemand';
    }
  }

  Future<void> _createNotification({
    required String toUserId,
    required String type,
    required String fromUserId,
    String? fromUserName,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'type': type,
      'toUserId': toUserId,
      'fromUserId': fromUserId,
      if (fromUserName != null) 'fromUserName': fromUserName,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  Future<void> _loadUserProfile() async {
    if (widget.userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;

      final name =
      (data['displayName'] ?? data['name'] ?? '').toString().trim();
      final phone = (data['phoneNumber'] ?? '').toString().trim();
      final image = (data['profileImageUrl'] ?? '').toString().trim();
      final bio = (data['bio'] ?? '').toString().trim();
      final isPublic = data['isProfilePublic'] as bool? ?? true;
      final createdAt = data['createdAt'];

      String memberSince = '';
      if (createdAt is Timestamp) {
        memberSince =
            DateFormat('MMMM yyyy', 'de_DE').format(createdAt.toDate());
      }

      final followers =
          List<String>.from(data['followerIds'] ?? const []).length;
      final following =
          List<String>.from(data['followingIds'] ?? const []).length;

      setState(() {
        if (name.isNotEmpty) _displayName = name;
        if (phone.isNotEmpty) _phoneNumber = phone;
        if (image.isNotEmpty) _profileImageUrl = image;
        _memberSince = memberSince;
        _followerCount = followers;
        _followingCount = following;
        _bio = bio;
        _isProfilePublic = isPublic;
      });
    } catch (_) {}
  }

  Future<void> _loadFollowState() async {
    if (_currentUserId.isEmpty || widget.userId.isEmpty) return;
    try {
      final theirDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final theirData = theirDoc.data();
      if (theirData == null) return;

      final followerIds =
      List<String>.from(theirData['followerIds'] ?? const []);
      final pendingIds =
      List<String>.from(theirData['pendingFollowerIds'] ?? const []);

      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      final myPending = List<String>.from(
          myDoc.data()?['pendingFollowerIds'] ?? const []);

      if (!mounted) return;
      setState(() {
        _isFollowing = followerIds.contains(_currentUserId);
        _isFollowPending = pendingIds.contains(_currentUserId);
        _hasIncomingFollowRequest = myPending.contains(widget.userId);
      });
    } catch (_) {}
  }

  Future<void> _loadSharedEventCount() async {
    if (_currentUserId.isEmpty || widget.userId.isEmpty) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .where('memberIds', arrayContains: _currentUserId)
          .get();
      final count = snapshot.docs.where((doc) {
        final memberIds =
        List<String>.from(doc.data()['memberIds'] ?? const []);
        return memberIds.contains(widget.userId);
      }).length;
      if (mounted) setState(() => _sharedEventCount = count);
    } catch (_) {}
  }

  // ── Follow actions ────────────────────────────────────────────────

  Future<void> _handleFollowTap() async {
    if (_isFollowLoading) return;
    if (widget.userId == _currentUserId) {
      _toast('Du kannst dir nicht selbst folgen.');
      return;
    }
    if (_isFollowing) {
      final ok = await _confirm(
        title: 'Nicht mehr folgen?',
        body:
        'Du siehst dann keine Aktivitäten von $_displayName mehr auf deiner Home.',
        confirm: 'Entfolgen',
        destructive: false,
      );
      if (ok != true) return;
      await _unfollow();
    } else if (_isFollowPending) {
      final ok = await _confirm(
        title: 'Anfrage zurückziehen?',
        body: 'Deine Follow-Anfrage an $_displayName wird zurückgezogen.',
        confirm: 'Zurückziehen',
        destructive: false,
      );
      if (ok != true) return;
      await _cancelRequest();
    } else if (_isProfilePublic) {
      await _follow();
    } else {
      await _sendRequest();
    }
  }

  Future<void> _follow() async {
    setState(() => _isFollowLoading = true);
    try {
      final b = FirebaseFirestore.instance.batch();
      b.set(
        FirebaseFirestore.instance.collection('users').doc(widget.userId),
        {
          'followerIds': FieldValue.arrayUnion([_currentUserId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      b.set(
        FirebaseFirestore.instance.collection('users').doc(_currentUserId),
        {
          'followingIds': FieldValue.arrayUnion([widget.userId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await b.commit();
      setState(() {
        _isFollowing = true;
        _followerCount++;
      });
      _toast('Du folgst jetzt ${_first()}');
    } catch (_) {
      _toast('Aktion konnte nicht ausgeführt werden.');
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _sendRequest() async {
    setState(() => _isFollowLoading = true);
    try {
      final senderName = await _loadCurrentUserDisplayName();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
        'pendingFollowerIds': FieldValue.arrayUnion([_currentUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _createNotification(
        toUserId: widget.userId,
        type: 'follow_request',
        fromUserId: _currentUserId,
        fromUserName: senderName,
      );

      try {
        await NotificationDispatchService.instance.queueFollowRequestNotification(
          recipientUserId: widget.userId,
          senderId: _currentUserId,
          senderName: senderName,
        );
      } catch (_) {}

      setState(() => _isFollowPending = true);
      _toast('Anfrage gesendet');
    } catch (_) {
      _toast('Anfrage konnte nicht gesendet werden.');
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _cancelRequest() async {
    setState(() => _isFollowLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
        'pendingFollowerIds': FieldValue.arrayRemove([_currentUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _isFollowPending = false);
      _toast('Anfrage zurückgezogen');
    } catch (_) {
      _toast('Aktion konnte nicht ausgeführt werden.');
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _unfollow() async {
    setState(() => _isFollowLoading = true);
    try {
      final b = FirebaseFirestore.instance.batch();
      b.set(
        FirebaseFirestore.instance.collection('users').doc(widget.userId),
        {
          'followerIds': FieldValue.arrayRemove([_currentUserId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      b.set(
        FirebaseFirestore.instance.collection('users').doc(_currentUserId),
        {
          'followingIds': FieldValue.arrayRemove([widget.userId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await b.commit();
      setState(() {
        _isFollowing = false;
        _followerCount = (_followerCount - 1).clamp(0, 999999);
        if (!_isProfilePublic) _sharedEventCount = 0;
      });
    } catch (_) {
      _toast('Aktion konnte nicht ausgeführt werden.');
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _acceptIncoming() async {
    try {
      final myName = await _loadCurrentUserDisplayName();

      final b = FirebaseFirestore.instance.batch();
      b.set(
        FirebaseFirestore.instance.collection('users').doc(_currentUserId),
        {
          'pendingFollowerIds': FieldValue.arrayRemove([widget.userId]),
          'followerIds': FieldValue.arrayUnion([widget.userId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      b.set(
        FirebaseFirestore.instance.collection('users').doc(widget.userId),
        {
          'followingIds': FieldValue.arrayUnion([_currentUserId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await b.commit();

      await _createNotification(
        toUserId: widget.userId,
        type: 'follow_request_accepted',
        fromUserId: _currentUserId,
        fromUserName: myName,
      );

      try {
        await NotificationDispatchService.instance.queueFollowAcceptedNotification(
          recipientUserId: widget.userId,
          accepterId: _currentUserId,
          accepterName: myName,
        );
      } catch (_) {}

      setState(() {
        _hasIncomingFollowRequest = false;
        _followerCount++;
      });
      _toast('Anfrage angenommen');
    } catch (_) {
      _toast('Anfrage konnte nicht bearbeitet werden.');
    }
  }

  Future<void> _declineIncoming() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .set({
        'pendingFollowerIds': FieldValue.arrayRemove([widget.userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _hasIncomingFollowRequest = false);
      _toast('Anfrage abgelehnt');
    } catch (_) {
      _toast('Anfrage konnte nicht abgelehnt werden.');
    }
  }

  Future<void> _confirmBlock() async {
    final ok = await _confirm(
      title: '$_displayName blockieren?',
      body:
      'Diese Person kann dir dann keine Nachrichten mehr senden und ihr seht euch nicht mehr gegenseitig.',
      confirm: 'Blockieren',
      destructive: true,
    );
    if (ok != true) return;
    setState(() => _isBlocking = true);
    try {
      final b = FirebaseFirestore.instance.batch();
      b.set(
        FirebaseFirestore.instance.collection('users').doc(_currentUserId),
        {
          'blockedUserIds': FieldValue.arrayUnion([widget.userId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      b.set(
        FirebaseFirestore.instance.collection('users').doc(widget.userId),
        {
          'blockedByIds': FieldValue.arrayUnion([_currentUserId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await b.commit();
      if (!mounted) return;
      _toast('$_displayName wurde blockiert.');
      Navigator.of(context).pop();
    } catch (_) {
      _toast('Benutzer konnte nicht blockiert werden.');
    } finally {
      if (mounted) setState(() => _isBlocking = false);
    }
  }

  Future<void> _reportUser() async {
    final ok = await _confirm(
      title: '$_displayName melden?',
      body:
      'Wir werden diesen Nutzer überprüfen. Danke, dass du uns dabei hilfst, CheckMyTime sicher zu halten.',
      confirm: 'Melden',
      destructive: false,
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'reportedUserId': widget.userId,
        'reportedByUserId': _currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _toast('Meldung wurde übermittelt. Danke!');
    } catch (_) {
      _toast('Meldung konnte nicht übermittelt werden.');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  String _first() {
    final parts = _displayName.trim().split(' ');
    return parts.isNotEmpty ? parts.first : _displayName;
  }

  Color _avatarColor() {
    final idx = _displayName.length % _C.avatarColors.length;
    return _C.avatarColors[idx];
  }

  String _initials() {
    if (_displayName.isEmpty) return '?';
    return _displayName
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirm,
    required bool destructive,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(backgroundColor: _C.danger)
                  : null,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirm),
            ),
          ],
        ),
      );

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: const Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 24, left: 40, right: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        duration: const Duration(milliseconds: 2200),
      ),
    );
  }

  bool _isOnlineLive(Map<String, dynamic>? data) {
    if (data == null || data['isOnline'] != true) return false;
    final lastSeen = data['lastSeenAt'];
    if (lastSeen is! Timestamp) return true;
    return DateTime.now().difference(lastSeen.toDate()) <=
        const Duration(minutes: 3);
  }

  void _setTab(String tab) {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
  }

  // ─────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final safeName =
    _displayName.isNotEmpty ? _displayName : widget.initialName;

    if (widget.embedded) {
      return _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody();
    }

    return Scaffold(
      backgroundColor: _C.bgTertiary,
      appBar: _buildNavHeader(safeName),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  // ── Nav-Header (Konzept: flach, 32×32 Kreisbuttons, 0.5px Border-Bottom) ──

  PreferredSizeWidget _buildNavHeader(String title) {
    return AppBar(
      backgroundColor: _C.bgPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 56,
      leadingWidth: 52,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: _CircleIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      title: Text(
        title.isEmpty ? 'Profil' : title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: _C.textPrimary,
        ),
      ),
      centerTitle: false,
      titleSpacing: 4,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: _CircleIconButton(
              icon: Icons.more_horiz_rounded,
              onTap: _showMenu,
            ),
          ),
        ),
      ],
      shape: const Border(
        bottom: BorderSide(color: _C.borderTertiary, width: 0.5),
      ),
    );
  }

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.bgPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _C.borderSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            _MenuItem(
              icon: Icons.block_outlined,
              label: 'Blockieren',
              destructive: true,
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmBlock();
              },
            ),
            _MenuItem(
              icon: Icons.flag_outlined,
              label: 'Melden',
              onTap: () {
                Navigator.of(ctx).pop();
                _reportUser();
              },
            ),
            _MenuItem(
              icon: Icons.link_rounded,
              label: 'Link kopieren',
              onTap: () {
                Navigator.of(ctx).pop();
                _toast('Profil-Link kopiert');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────

  Widget _buildBody() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.userId.isEmpty
          ? null
          : FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .snapshots(),
      builder: (context, snap) {
        final isOnline = _isOnlineLive(snap.data?.data());
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hasIncomingFollowRequest) _buildNotifBanner(),
              _buildCover(isOnline),
              Transform.translate(
                offset: const Offset(0, -20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _buildProfileInfoArea(isOnline),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                child: _buildMainContent(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Notif-Banner (Konzept: amber bg, padding 10×12, margin 10 12 0) ──

  Widget _buildNotifBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _C.bannerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.bannerBorder, width: 0.5),
      ),
      child: Row(
        children: [
          const Text('👤', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  color: _C.bannerText,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: _displayName.isEmpty ? 'Jemand' : _displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' möchte dir folgen'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _NotifMiniBtn(
            label: 'Annehmen',
            bg: _C.notifAccept,
            fg: Colors.white,
            onTap: _acceptIncoming,
          ),
          const SizedBox(width: 6),
          _NotifMiniBtn(
            label: 'Ablehnen',
            bg: _C.bgSecondary,
            fg: _C.textSecondary,
            onTap: _declineIncoming,
          ),
        ],
      ),
    );
  }

  // ── Cover (Konzept: 100px, Gradient 135°, Dot-Pattern, Avatar -28px) ──

  Widget _buildCover(bool isOnline) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: 100,
          width: double.infinity,
          child: CustomPaint(painter: _CoverPainter()),
        ),
        Positioned(
          top: 10,
          right: 16,
          child: _PrivacyBadge(isPublic: _isProfilePublic),
        ),
        Positioned(
          bottom: -28,
          left: 16,
          child: _buildAvatar(isOnline),
        ),
      ],
    );
  }

  Widget _buildAvatar(bool isOnline) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _avatarColor(),
            border: Border.all(color: _C.bgPrimary, width: 3),
          ),
          clipBehavior: Clip.antiAlias,
          child: _profileImageUrl.isNotEmpty
              ? Image.network(
            _profileImageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _avatarInitials(),
          )
              : _avatarInitials(),
        ),
        if (_isFollowing && isOnline)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _C.onlineGreen,
                border: Border.all(color: _C.bgPrimary, width: 2.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _avatarInitials() {
    return Center(
      child: Text(
        _initials(),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }

  // ── Profile-Info-Area (Konzept: 36 top / 14 bottom / 16 side) ──

  Widget _buildProfileInfoArea(bool isOnline) {
    return Container(
      decoration: BoxDecoration(
        color: _C.bgPrimary,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _C.borderTertiary, width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 38, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _displayName.isNotEmpty ? _displayName : 'Unbekannt',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _C.textPrimary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _isFollowing && isOnline
                      ? _C.onlineGreen
                      : _C.textSecondary.withValues(alpha: 0.28),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isFollowing && isOnline
                      ? 'Online'
                      : (_memberSince.isNotEmpty
                      ? 'Mitglied seit $_memberSince'
                      : 'Mitglied'),
                  style: TextStyle(
                    fontSize: 13,
                    color: _isFollowing && isOnline
                        ? _C.onlineGreen
                        : _C.textSecondary,
                    fontWeight: _isFollowing && isOnline
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (_canSeeFullProfile && _bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _bio,
              style: const TextStyle(
                fontSize: 13,
                color: _C.textSecondary,
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: _C.bgTertiary,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _C.borderTertiary, width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _StatItem(
                    value: '$_sharedEventCount',
                    label: 'Gemeinsam',
                  ),
                ),
                Container(width: 0.5, height: 28, color: _C.borderTertiary),
                Expanded(
                  child: _StatItem(
                    value: '$_followerCount',
                    label: 'Follower',
                  ),
                ),
                Container(width: 0.5, height: 28, color: _C.borderTertiary),
                Expanded(
                  child: _StatItem(
                    value: '$_followingCount',
                    label: 'Gefolgt',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildActionRow(),
        ],
      ),
    );
  }

  // ── Follow-Button (Konzept: radius 20, padding 8×18, font 13/500) ──

  Widget _buildFollowButton() {
    if (_isFollowLoading) {
      return const SizedBox(
        width: 96,
        height: 32,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: _C.blue),
          ),
        ),
      );
    }

    String label;
    Color bg, fg;
    Color? borderColor;

    if (_isFollowing) {
      label = 'Gefolgt';
      bg = _C.bgSecondary;
      fg = _C.textPrimary;
      borderColor = _C.borderSecondary;
    } else if (_isFollowPending) {
      label = 'Angefragt';
      bg = _C.bgSecondary;
      fg = _C.textSecondary;
      borderColor = _C.borderSecondary;
    } else {
      label = _isProfilePublic ? 'Folgen' : 'Anfragen';
      bg = _C.blue;
      fg = Colors.white;
      borderColor = null;
    }

    return GestureDetector(
      onTap: _handleFollowTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: borderColor != null
              ? Border.all(color: borderColor, width: 0.5)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }

  // ── Action-Row (Konzept: Nachricht + Planungen wenn isFollowing) ──

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Nachricht',
            icon: Icons.chat_bubble_outline_rounded,
            onTap: () {
              if (widget.onMessageTap != null) {
                widget.onMessageTap!();
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ContactThreadPage(
                      contactId: widget.userId,
                      contactName: _displayName.isEmpty
                          ? widget.initialName
                          : _displayName,
                      phoneNumber: _phoneNumber,
                    ),
                  ),
                );
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildFollowActionButton(),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    if (!_isProfilePublic && !_isFollowing) {
      return _PrivateOverlay(
        firstName: _first(),
        isPending: _isFollowPending,
        onFollowTap: _handleFollowTap,
        onCancel: _cancelRequest,
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.userId.isEmpty
          ? null
          : FirebaseFirestore.instance
          .collection('events')
          .where('memberIds', arrayContains: widget.userId)
          .orderBy('eventDate', descending: true)
          .limit(4)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !(snap.hasData && (snap.data?.docs.isNotEmpty ?? false))) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 56),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return const _ProfileSection(
            title: 'Aktivitäten',
            child: _ProfileEmptyState(
              icon: Icons.auto_awesome_rounded,
              title: 'Noch keine Aktivitäten',
              desc: 'Hier erscheinen zukünftige Aktivitäten.',
            ),
          );
        }

        return _ProfileSection(
          title: 'Aktivitäten',
          subtitle: 'Neueste Aktivitäten von diesem Profil',
          child: _ContentCard(
            children: docs.map((doc) {
              final d = doc.data();
              final title = (d['title'] ?? 'Event').toString();
              final date = d['eventDate'] as Timestamp?;
              final isOrg = (d['createdBy'] ?? '') == widget.userId;
              final memberCount =
                  List<String>.from(d['memberIds'] ?? const []).length;
              final dateStr = date != null
                  ? DateFormat('EE, d. MMM', 'de_DE').format(date.toDate())
                  : '';

              return _ActivityItem(
                iconEmoji: isOrg ? '🎯' : '📅',
                iconBg: isOrg ? _C.iconSocialBg : _C.iconEventBg,
                title: isOrg
                    ? 'Veranstaltet $title'
                    : 'Nimmt an $title teil',
                meta: memberCount > 0
                    ? '$dateStr · $memberCount Teilnehmer'
                    : dateStr,
                badgeLabel: isOrg ? 'Veranstalter' : 'Zugesagt',
                badgeBg: isOrg ? _C.blueBg : _C.greenBg,
                badgeColor: isOrg ? _C.blueText : _C.greenText,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EventDetailPage(
                      eventId: doc.id,
                      view: EventDetailView.openEvent,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildFollowActionButton() {
    String label;
    IconData icon;
    Color backgroundColor;
    Color foregroundColor;
    Color? borderColor;

    if (_isFollowLoading) {
      return Container(
        height: 46,
        decoration: BoxDecoration(
          color: _C.bgSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.borderSecondary, width: 0.5),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: _C.blue,
          ),
        ),
      );
    }

    if (_isFollowing) {
      label = 'Gefolgt';
      icon = Icons.check_rounded;
      backgroundColor = const Color(0xFFEDE9FE);
      foregroundColor = const Color(0xFF5B21B6);
      borderColor = null;
    } else if (_isFollowPending) {
      label = 'Angefragt';
      icon = Icons.schedule_rounded;
      backgroundColor = _C.bgSecondary;
      foregroundColor = _C.textSecondary;
      borderColor = _C.borderSecondary;
    } else {
      label = _isProfilePublic ? 'Folgen' : 'Anfragen';
      icon = _isProfilePublic
          ? Icons.person_add_alt_1_rounded
          : Icons.lock_outline_rounded;
      backgroundColor = _C.blue;
      foregroundColor = Colors.white;
      borderColor = null;
    }

    return GestureDetector(
      onTap: _handleFollowTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: borderColor != null
              ? Border.all(color: borderColor, width: 0.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foregroundColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab-Bar (Konzept: dynamische Tabs) ──

  Widget _buildTabBar() {
    final tabs = <Map<String, String>>[
      {'key': 'profil', 'label': 'Profil'},
      {'key': 'planungen', 'label': 'Planungen'},
    ];
    if (_showEventsTab) {
      tabs.add({'key': 'events', 'label': 'Events'});
    }

    // Fallback falls aktiver Tab nicht mehr verfügbar
    if (!tabs.any((t) => t['key'] == _activeTab)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _activeTab = 'profil');
      });
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        color: _C.bgPrimary,
        border: Border(
          bottom: BorderSide(color: _C.borderTertiary, width: 0.5),
        ),
      ),
      child: Row(
        children: tabs
            .map(
              (t) => Expanded(
            child: _TabItem(
              label: t['label']!,
              active: _activeTab == t['key'],
              onTap: () => _setTab(t['key']!),
            ),
          ),
        )
            .toList(),
      ),
    );
  }

  // ── Tab-Content Router ──

  Widget _buildTabContent() {
    switch (_activeTab) {
      case 'planungen':
        return _buildPlanungenTab();
      case 'events':
        return _buildEventsTab();
      case 'profil':
      default:
        return _buildProfilTab();
    }
  }

  // ── Profil-Tab ──

  Widget _buildProfilTab() {
    if (!_isProfilePublic && !_isFollowing) {
      return _PrivateOverlay(
        firstName: _first(),
        isPending: _isFollowPending,
        onFollowTap: _handleFollowTap,
        onCancel: _cancelRequest,
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.userId.isEmpty
          ? null
          : FirebaseFirestore.instance
          .collection('events')
          .where('memberIds', arrayContains: widget.userId)
          .orderBy('eventDate', descending: true)
          .limit(4)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty &&
            snap.connectionState != ConnectionState.waiting) {
          return const _EmptyStateInline(
            emoji: '✨',
            title: 'Noch keine Aktivitäten',
            desc: 'Hier erscheinen zukünftige Aktivitäten.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ContentCard(
              children: docs.map((doc) {
                final d = doc.data();
                final title = (d['title'] ?? 'Event').toString();
                final date = d['eventDate'] as Timestamp?;
                final isOrg = (d['createdBy'] ?? '') == widget.userId;
                final memberCount =
                    List<String>.from(d['memberIds'] ?? const []).length;
                final dateStr = date != null
                    ? DateFormat('EE, d. MMM', 'de_DE')
                    .format(date.toDate())
                    : '';

                return _ActivityItem(
                  iconEmoji: isOrg ? '🎯' : '📅',
                  iconBg: isOrg ? _C.iconSocialBg : _C.iconEventBg,
                  title: isOrg
                      ? 'Veranstaltet $title'
                      : 'Nimmt an $title teil',
                  meta: memberCount > 0
                      ? '$dateStr · $memberCount Teilnehmer'
                      : dateStr,
                  badgeLabel: isOrg ? 'Veranstalter' : 'Zugesagt',
                  badgeBg: isOrg ? _C.blueBg : _C.greenBg,
                  badgeColor: isOrg ? _C.blueText : _C.greenText,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EventDetailPage(
                        eventId: doc.id,
                        view: EventDetailView.openEvent,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            _ContentCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Text(
                    _isFollowing
                        ? 'Du folgst ${_first()}'
                        : 'Öffentliches Profil',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _C.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ── Planungen-Tab ──

  Widget _buildPlanungenTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _currentUserId.isEmpty
          ? null
          : FirebaseFirestore.instance
          .collection('events')
          .where('memberIds', arrayContains: _currentUserId)
          .orderBy('eventDate', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final all = snap.data?.docs ?? [];

        final shared = all.where((doc) {
          final m = List<String>.from(doc.data()['memberIds'] ?? const []);
          return m.contains(widget.userId);
        }).toList();

        final invitedByOther = all.where((doc) {
          final d = doc.data();
          final createdBy = (d['createdBy'] ?? '').toString();
          final invited = List<String>.from(d['invitedUserIds'] ?? const []);
          return createdBy == widget.userId && invited.contains(_currentUserId);
        }).toList();

        if (shared.isEmpty && invitedByOther.isEmpty) {
          return const _EmptyStateInline(
            emoji: '📋',
            title: 'Noch keine gemeinsamen Planungen',
            desc:
            'Ihr habt noch keine direkten Planungen. Nachrichten und gemeinsame Events bleiben trotzdem jederzeit möglich.',
          );
        }

        final items = <_PlanningEntry>[];
        for (final doc in shared) {
          items.add(_PlanningEntry.fromShared(doc, _currentUserId));
        }
        for (final doc in invitedByOther) {
          if (shared.any((s) => s.id == doc.id)) continue;
          items.add(_PlanningEntry.fromInvitation(doc, _first()));
        }

        items.sort((a, b) {
          final aDate = a.eventDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.eventDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          return aDate.compareTo(bDate);
        });

        final invitations = items
            .where((e) => e.isInvitation && !e.isPast)
            .toList();
        final active = items
            .where((e) => !e.isPast && !e.isInvitation)
            .toList();
        final past = items.where((e) => e.isPast).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (active.isNotEmpty)
              _buildPlanningSection(
                title: 'Aktiv & offen',
                items: active,
              ),
            if (invitations.isNotEmpty) ...[
              if (active.isNotEmpty) const SizedBox(height: 10),
              _buildPlanningSection(
                title: 'Einladungen',
                items: invitations,
              ),
            ],
            if (past.isNotEmpty) ...[
              if (active.isNotEmpty || invitations.isNotEmpty)
                const SizedBox(height: 10),
              _buildPlanningSection(
                title: 'Vergangen',
                items: past,
              ),
            ],
            const SizedBox(height: 10),
            _ContentCard(
              children: [
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Direkter Planungskontext',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _C.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _buildSummary(shared.length, invitations.length),
                        style: const TextStyle(
                          fontSize: 12,
                          color: _C.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlanningSection({
    required String title,
    required List<_PlanningEntry> items,
  }) {
    return _ContentCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _C.textSecondary,
            ),
          ),
        ),
        ...items.map((e) {
          return _PlanningItem(
            initials: _initials(),
            avatarBg: _avatarColor().withValues(alpha: 0.15),
            avatarColor: _avatarColor(),
            title: e.title,
            subtitle: e.subtitle,
            statusLabel: e.statusLabel,
            statusBg: e.statusBg,
            statusColor: e.statusColor,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EventDetailPage(
                  eventId: e.eventId,
                  view: e.isInvitation
                      ? EventDetailView.invitation
                      : EventDetailView.openEvent,
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  String _buildSummary(int sharedCount, int invitedCount) {
    final parts = <String>[];
    parts.add(
        '$sharedCount gemeinsame${sharedCount == 1 ? 's Event' : ' Events'}');
    if (invitedCount > 0) {
      parts.add(
          '$invitedCount offene Einladung${invitedCount == 1 ? '' : 'en'}');
    }
    return parts.join(' · ');
  }

  // ── Events-Tab ──

  Widget _buildEventsTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.userId.isEmpty
          ? null
          : FirebaseFirestore.instance
          .collection('events')
          .where('memberIds', arrayContains: widget.userId)
          .orderBy('eventDate', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyStateInline(
            emoji: '📅',
            title: 'Noch keine Events',
            desc: '${_first()} hat aktuell keine Events.',
          );
        }

        final now = DateTime.now();
        final upcoming = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final past = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        for (final doc in docs) {
          final date = (doc.data()['eventDate'] as Timestamp?)?.toDate();
          if (date != null && date.isBefore(now)) {
            past.add(doc);
          } else {
            upcoming.add(doc);
          }
        }

        Widget buildSection(
            String title,
            List<QueryDocumentSnapshot<Map<String, dynamic>>> sectionDocs,
            ) {
          return _ContentCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.textSecondary,
                  ),
                ),
              ),
              ...sectionDocs.map((doc) {
                final d = doc.data();
                final title = (d['title'] ?? 'Event').toString();
                final date = d['eventDate'] as Timestamp?;
                final memberCount =
                    List<String>.from(d['memberIds'] ?? const []).length;
                final isOrg = (d['createdBy'] ?? '') == widget.userId;
                final dateStr = date != null
                    ? DateFormat('EE, d. MMM', 'de_DE').format(date.toDate())
                    : '';

                return _ActivityItem(
                  iconEmoji: isOrg ? '🎯' : '🎱',
                  iconBg: isOrg ? _C.iconSocialBg : _C.iconEventBg,
                  title: title,
                  meta: memberCount > 0
                      ? '$dateStr · $memberCount Teilnehmer'
                      : dateStr,
                  badgeLabel: isOrg ? 'Veranstalter' : 'Teilnahme',
                  badgeBg: isOrg ? _C.blueBg : _C.greenBg,
                  badgeColor: isOrg ? _C.blueText : _C.greenText,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EventDetailPage(
                        eventId: doc.id,
                        view: EventDetailView.openEvent,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (upcoming.isNotEmpty)
              buildSection('Kommend', upcoming),
            if (past.isNotEmpty) ...[
              if (upcoming.isNotEmpty) const SizedBox(height: 10),
              buildSection('Vergangen', past),
            ],
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Sub-Widgets
// ═════════════════════════════════════════════════════════════════════════════

// ── Cover-Painter: Gradient 135° + zwei radial-Dot-Pattern ──

class _CoverPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradPaint = Paint()
      ..shader = const LinearGradient(
        colors: [_C.coverBg1, _C.coverBg2, _C.coverBg3],
        stops: [0.0, 0.5, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRect(rect, gradPaint);

    // Dot-Pattern (zwei radial gradients — 20%/50% und 80%/20%)
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.15);
    const spacing = 30.0;
    const dotRadius = 1.0;

    final ox1 = size.width * 0.2;
    final oy1 = size.height * 0.5;
    for (double x = ox1 - spacing * 10;
    x < size.width + spacing;
    x += spacing) {
      for (double y = oy1 - spacing * 10;
      y < size.height + spacing;
      y += spacing) {
        if (x >= 0 && y >= 0) {
          canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
        }
      }
    }

    final ox2 = size.width * 0.8;
    final oy2 = size.height * 0.2;
    for (double x = ox2 - spacing * 10;
    x < size.width + spacing;
    x += spacing) {
      for (double y = oy2 - spacing * 10;
      y < size.height + spacing;
      y += spacing) {
        if (x >= 0 && y >= 0) {
          canvas.drawCircle(
              Offset(x + 15, y + 15), dotRadius, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CoverPainter old) => false;
}

// ── Privacy-Badge (Konzept: rgba(0,0,0,0.5), radius 20, padding 3×10) ──

class _PrivacyBadge extends StatelessWidget {
  final bool isPublic;
  const _PrivacyBadge({required this.isPublic});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isPublic ? '🌐' : '🔒',
            style: const TextStyle(fontSize: 11, height: 1),
          ),
          const SizedBox(width: 5),
          Text(
            isPublic ? 'Öffentlich' : 'Privat',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Circle-Icon-Button (32×32, bg secondary) ──

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _C.bgSecondary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 16, color: _C.textSecondary),
        ),
      ),
    );
  }
}

// ── Menu-Item ──

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? _C.danger : _C.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notif-Mini-Button ──

class _NotifMiniBtn extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  const _NotifMiniBtn({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }
}

// ── Stat-Item (Konzept: val 17px/500/textPrimary, lbl 11px/textSecondary) ──

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: _C.textPrimary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: _C.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Action-Button (Konzept: radius 8, padding 9×0, bg secondary) ──

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _C.bgSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.borderSecondary, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: _C.textPrimary),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _C.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tab-Item (Konzept: padding 12×4, font 13/500, border-bottom 2px) ──

class _TabItem extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? _C.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? _C.blue : _C.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Content-Card (Konzept: bg primary, radius 12, border 0.5 tertiary) ──

class _ContentCard extends StatelessWidget {
  final List<Widget> children;
  const _ContentCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.bgPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.borderTertiary, width: 0.5),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: List.generate(children.length, (i) {
          return Column(
            children: [
              children[i],
              if (i < children.length - 1)
                const Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: _C.borderTertiary,
                ),
            ],
          );
        }),
      ),
    );
  }
}

// ── Activity-Item (Konzept: padding 12×14, icon 36×36 rounded 8) ──

class _ActivityItem extends StatelessWidget {
  final String iconEmoji;
  final Color iconBg;
  final String title;
  final String meta;
  final String badgeLabel;
  final Color badgeBg;
  final Color badgeColor;
  final VoidCallback? onTap;

  const _ActivityItem({
    required this.iconEmoji,
    required this.iconBg,
    required this.title,
    required this.meta,
    required this.badgeLabel,
    required this.badgeBg,
    required this.badgeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                iconEmoji,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _C.textPrimary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _C.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: badgeColor,
                      ),
                    ),
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

// ── Planning-Item (Konzept: padding 12×14, avatar 40×40, status rechts) ──

class _PlanningItem extends StatelessWidget {
  final String initials;
  final Color avatarBg;
  final Color avatarColor;
  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusBg;
  final Color statusColor;
  final VoidCallback? onTap;

  const _PlanningItem({
    required this.initials,
    required this.avatarBg,
    required this.avatarColor,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusBg,
    required this.statusColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: avatarBg,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: avatarColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _C.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _C.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Planning-Entry Datenklasse ──

class _PlanningEntry {
  final String eventId;
  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusBg;
  final Color statusColor;
  final bool isInvitation;
  final DateTime? eventDate;

  _PlanningEntry({
    required this.eventId,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusBg,
    required this.statusColor,
    required this.isInvitation,
    required this.eventDate,
  });

  bool get isPast => eventDate != null && eventDate!.isBefore(DateTime.now());

  factory _PlanningEntry.fromShared(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      String myUid,
      ) {
    final d = doc.data();
    final title = (d['title'] ?? 'Event').toString();
    final date = d['eventDate'] as Timestamp?;
    final eventDate = date?.toDate();
    final dateStr = eventDate != null
        ? DateFormat('EE, d. MMM', 'de_DE').format(eventDate)
        : '';
    final status = _resolveStatus(d, myUid);
    return _PlanningEntry(
      eventId: doc.id,
      title: title,
      subtitle: '$dateStr · Gemeinsame Planung',
      statusLabel: status.label,
      statusBg: status.bg,
      statusColor: status.color,
      isInvitation: status.label == 'Einladung offen',
      eventDate: eventDate,
    );
  }

  factory _PlanningEntry.fromInvitation(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      String firstName,
      ) {
    final d = doc.data();
    final title = (d['title'] ?? 'Event').toString();
    final date = d['eventDate'] as Timestamp?;
    final eventDate = date?.toDate();
    final dateStr = eventDate != null
        ? DateFormat('EE, d. MMM', 'de_DE').format(eventDate)
        : '';
    return _PlanningEntry(
      eventId: doc.id,
      title: title,
      subtitle: '$dateStr · Einladung von $firstName',
      statusLabel: 'Einladung offen',
      statusBg: _C.blueBg,
      statusColor: _C.blueText,
      isInvitation: true,
      eventDate: eventDate,
    );
  }

  static _Status _resolveStatus(Map<String, dynamic> d, String uid) {
    final accepted = List<String>.from(d['acceptedUserIds'] ?? const []);
    final maybe = List<String>.from(d['maybeUserIds'] ?? const []);
    final declined = List<String>.from(d['declinedUserIds'] ?? const []);
    final invited = List<String>.from(d['invitedUserIds'] ?? const []);

    if (accepted.contains(uid)) {
      return const _Status('Zugesagt', _C.greenBg, _C.greenText);
    }
    if (maybe.contains(uid)) {
      return const _Status('Vielleicht', _C.amberBg, _C.amberText);
    }
    if (declined.contains(uid)) {
      return const _Status('Abgesagt', _C.redBg, _C.redText);
    }
    if (invited.contains(uid)) {
      return const _Status('Einladung offen', _C.blueBg, _C.blueText);
    }
    return const _Status('Teilnahme', _C.blueBg, _C.blueText);
  }
}

class _Status {
  final String label;
  final Color bg;
  final Color color;
  const _Status(this.label, this.bg, this.color);
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _ProfileSection({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _C.textPrimary,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _C.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class _ProfileEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _ProfileEmptyState({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      decoration: BoxDecoration(
        color: _C.bgPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.borderTertiary, width: 0.5),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: _C.bgSecondary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: _C.blue, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _C.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              desc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: _C.textSecondary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty-State inline ──

class _EmptyStateInline extends StatelessWidget {
  final String emoji;
  final String title;
  final String desc;
  const _EmptyStateInline({
    required this.emoji,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _C.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: _C.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Private-Overlay (Konzept: lock 56×56, padding 32×16) ──

class _PrivateOverlay extends StatelessWidget {
  final String firstName;
  final bool isPending;
  final VoidCallback onFollowTap;
  final VoidCallback onCancel;

  const _PrivateOverlay({
    required this.firstName,
    required this.isPending,
    required this.onFollowTap,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: _C.bgPrimary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.borderTertiary, width: 0.5),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: _C.bgSecondary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.lock_outline_rounded,
              color: _C.blue,
              size: 32,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Dieses Profil ist privat',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _C.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: Text(
              'Folge $firstName, um Aktivitäten, Bio und weitere Inhalte zu sehen.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: _C.textSecondary,
                height: 1.65,
              ),
            ),
          ),
          if (isPending) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 290),
              child: Text(
                'Deine Anfrage wurde gesendet. Sobald $firstName sie annimmt, siehst du hier mehr.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: _C.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: onCancel,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _C.bgSecondary,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _C.borderSecondary,
                    width: 0.5,
                  ),
                ),
                child: const Text(
                  'Anfrage zurückziehen',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _C.textSecondary,
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 22),
            GestureDetector(
              onTap: onFollowTap,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: _C.blue,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'Anfrage senden',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
