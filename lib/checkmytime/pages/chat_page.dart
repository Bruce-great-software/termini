import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';

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

  static const online = Color(0xFF00FFA3);
  static const danger = Color(0xFFFF3B6B);

  static List<BoxShadow> glow(Color c, {double blur = 18, double alpha = 0.28}) => [
    BoxShadow(
      color: c.withValues(alpha: alpha),
      blurRadius: blur,
      spreadRadius: 0,
    ),
  ];
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const Duration _onlineGracePeriod = Duration(minutes: 3);

  final TextEditingController _searchController = TextEditingController();
  final Map<String, _ContactPreviewData> _contactPreviewCache = {};

  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: _Neon.surface,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: _Neon.stroke),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.22),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ],
  );

  String _otherParticipantId(List<String> participants, String currentUserId) =>
      participants.firstWhere((id) => id != currentUserId, orElse: () => '');

  bool _isUserOnline(Map<String, dynamic>? data) {
    if (data == null || data['isOnline'] != true) return false;
    final lastSeen = data['lastSeenAt'];
    if (lastSeen is! Timestamp) return true;
    return DateTime.now().difference(lastSeen.toDate()) <= _onlineGracePeriod;
  }

  bool _isOtherUserTyping(
      Map<String, dynamic> data,
      String currentUserId,
      String otherParticipantId,
      ) {
    final typingTimestamp = data['typingAt'] as Timestamp? ??
        data['typingUpdatedAt'] as Timestamp? ??
        data['currentlyTypingAt'] as Timestamp?;

    final isTypingFresh = typingTimestamp != null &&
        DateTime.now().difference(typingTimestamp.toDate()) <=
            const Duration(seconds: 8);

    final typingBy = (data['typingBy'] ??
        data['typingUserId'] ??
        data['typingUid'] ??
        data['currentlyTypingUserId'] ??
        '')
        .toString()
        .trim();

    if (typingBy.isNotEmpty) {
      return typingBy == otherParticipantId &&
          typingBy != currentUserId &&
          isTypingFresh;
    }

    final typingIds = List<String>.from(
      data['typingUserIds'] ?? data['currentlyTypingUserIds'] ?? const [],
    );

    return typingIds.contains(otherParticipantId) &&
        !typingIds.contains(currentUserId) &&
        isTypingFresh;
  }

  String _formatVoiceDuration(dynamic value) {
    if (value == null) return '';
    if (value is int) {
      final minutes = value ~/ 60;
      final seconds = value % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return value.toString().trim();
  }

  String _threadPreviewText(
      Map<String, dynamic> data, {
        required bool isTyping,
        required bool isOnline,
      }) {
    if (isTyping) return 'Schreibt gerade…';

    final lastMessageType = (data['lastMessageType'] ??
        data['messageType'] ??
        data['lastInteractionType'] ??
        '')
        .toString()
        .trim()
        .toLowerCase();

    final voiceDuration = _formatVoiceDuration(
      data['lastVoiceDuration'] ??
          data['lastVoiceDurationSeconds'] ??
          data['lastAudioDuration'] ??
          data['lastMessageDuration'],
    );

    if (lastMessageType == 'voice' ||
        lastMessageType == 'audio' ||
        lastMessageType == 'sprachnachricht') {
      return voiceDuration.isNotEmpty
          ? 'Sprachnachricht · $voiceDuration'
          : 'Sprachnachricht';
    }

    for (final candidate in [
      data['lastMessageText'],
      data['lastMessage'],
      data['lastMessagePreview'],
      data['lastText'],
      data['lastInteractionText'],
      data['lastAppointmentTitle'],
    ]) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    return isOnline ? 'Online jetzt' : 'Noch keine Nachricht';
  }

  String _formatThreadTime(Map<String, dynamic> data) {
    final timestamp =
        data['updatedAt'] as Timestamp? ?? data['lastInteractionAt'] as Timestamp?;
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) return 'Jetzt';
    if (difference.inMinutes < 60) return '${difference.inMinutes} Min.';
    if (difference.inHours < 24) return '${difference.inHours} Std.';

    final today = DateTime(now.year, now.month, now.day);
    final dayDifference =
        today.difference(DateTime(date.year, date.month, date.day)).inDays;

    if (dayDifference == 1) return 'Gestern';
    if (dayDifference < 7) {
      const weekdays = ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'];
      return weekdays[date.weekday - 1];
    }

    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }

  Future<_ContactPreviewData> _loadContactPreview({
    required String contactId,
    required String fallbackName,
    required String fallbackPhone,
  }) async {
    final safeContactId = contactId.trim();

    if (safeContactId.isEmpty) {
      return _ContactPreviewData(
        name: fallbackName.trim().isEmpty ? 'Unbekannt' : fallbackName.trim(),
        phone: fallbackPhone.trim(),
        imageUrl: '',
      );
    }

    if (_contactPreviewCache.containsKey(safeContactId)) {
      return _contactPreviewCache[safeContactId]!;
    }

    var resolvedName = fallbackName.trim();
    var resolvedPhone = fallbackPhone.trim();
    var resolvedImageUrl = '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(safeContactId)
          .get();
      final data = doc.data();

      if (data != null) {
        final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final phone = (data['phoneNumber'] ?? '').toString().trim();
        final imageUrl = (data['profileImageUrl'] ?? '').toString().trim();

        if (name.isNotEmpty) resolvedName = name;
        if (phone.isNotEmpty) resolvedPhone = phone;
        if (imageUrl.isNotEmpty) resolvedImageUrl = imageUrl;
      }
    } catch (_) {}

    if (resolvedName.isEmpty) resolvedName = 'Unbekannt';

    final preview = _ContactPreviewData(
      name: resolvedName,
      phone: resolvedPhone,
      imageUrl: resolvedImageUrl,
    );
    _contactPreviewCache[safeContactId] = preview;
    return preview;
  }

  Widget _buildAvatar({
    required _ContactPreviewData preview,
    bool isOnline = false,
  }) {
    Widget avatar;
    if (preview.imageUrl.isNotEmpty) {
      avatar = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isOnline ? _Neon.online : _Neon.strokeStrong,
            width: 2.4,
          ),
          boxShadow: isOnline ? _Neon.glow(_Neon.online, blur: 16, alpha: 0.20) : null,
        ),
        child: CircleAvatar(
          radius: 25,
          backgroundImage: NetworkImage(preview.imageUrl),
          backgroundColor: _Neon.surfaceHigh,
        ),
      );
    } else {
      final letter = preview.name.isNotEmpty
          ? preview.name.characters.first.toUpperCase()
          : '?';
      avatar = Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [_Neon.cyan, _Neon.purple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: isOnline ? _Neon.online : _Neon.strokeStrong,
            width: 2.2,
          ),
          boxShadow: [
            ..._Neon.glow(_Neon.cyan, blur: 18, alpha: 0.16),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: const TextStyle(
            color: _Neon.bg,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      );
    }

    if (!isOnline) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _Neon.online,
              border: Border.all(color: _Neon.bg, width: 2),
              boxShadow: _Neon.glow(_Neon.online, blur: 10, alpha: 0.35),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: _Neon.bgElevated,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _Neon.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(
          color: _Neon.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: _Neon.cyan,
        onChanged: (value) {
          setState(() => _searchQuery = value.trim().toLowerCase());
        },
        decoration: InputDecoration(
          hintText: 'Nach Chats suchen',
          hintStyle: const TextStyle(color: _Neon.textMuted),
          prefixIcon: const Icon(Icons.search_rounded, color: _Neon.textSecondary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
            icon: const Icon(Icons.close_rounded, color: _Neon.textSecondary),
          )
              : null,
          border: InputBorder.none,
        ),
      ),
    );
  }

  bool _matchesSearch({
    required _ContactPreviewData preview,
    required String previewText,
    required String trailingTimeText,
  }) {
    if (_searchQuery.isEmpty) return true;
    final haystack =
    '${preview.name} ${preview.phone} $previewText $trailingTimeText'
        .toLowerCase();
    return haystack.contains(_searchQuery);
  }

  Widget _buildThreadRow({
    required _ContactPreviewData preview,
    required bool hasUnread,
    required int unreadCount,
    required bool isOnline,
    required String previewText,
    required String trailingTimeText,
    required bool isTyping,
    required bool showDivider,
    required bool isFirst,
    required bool isLast,
    required VoidCallback? onTap,
  }) {
    final topRadius = isFirst ? const Radius.circular(24) : Radius.zero;
    final bottomRadius = isLast ? const Radius.circular(24) : Radius.zero;
    final previewColor = isTyping
        ? _Neon.cyan
        : hasUnread
        ? _Neon.textPrimary
        : _Neon.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.only(
          topLeft: topRadius,
          topRight: topRadius,
          bottomLeft: bottomRadius,
          bottomRight: bottomRadius,
        ),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvatar(preview: preview, isOnline: isOnline),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                preview.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _Neon.textPrimary,
                                  fontSize: 16,
                                  fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w700,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            if (trailingTimeText.trim().isNotEmpty)
                              Text(
                                trailingTimeText,
                                style: TextStyle(
                                  color: hasUnread ? _Neon.cyan : _Neon.textMuted,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                previewText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: previewColor,
                                  fontSize: 14,
                                  fontWeight: isTyping || hasUnread
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  fontStyle: isTyping
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ),
                            if (hasUnread) ...[
                              const SizedBox(width: 10),
                              _ChatUnreadBadge(count: unreadCount),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (showDivider) ...[
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: _Neon.stroke.withValues(alpha: 0.85),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineFollowingSection(String currentUserId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .snapshots(),
      builder: (context, currentUserSnapshot) {
        final currentUserData =
            currentUserSnapshot.data?.data() ?? const <String, dynamic>{};
        final followingIds = List<String>.from(
          currentUserData['followingIds'] ?? const <String>[],
        ).where((id) => id.trim().isNotEmpty && id != currentUserId).toList();

        if (followingIds.isEmpty) return const SizedBox.shrink();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: followingIds.take(10).toList())
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();

            final onlineDocs = snapshot.data!.docs
                .where((doc) => _isUserOnline(doc.data()))
                .toList()
              ..sort((a, b) {
                String name(Map<String, dynamic> d) =>
                    (d['displayName'] ?? d['name'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                return name(a.data()).compareTo(name(b.data()));
              });

            if (onlineDocs.isEmpty) return const SizedBox.shrink();

            return Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _Neon.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _Neon.stroke),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: onlineDocs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final doc = onlineDocs[index];
                    final data = doc.data();
                    final rawName =
                    (data['displayName'] ?? data['name'] ?? '').toString().trim();
                    final preview = _ContactPreviewData(
                      name: rawName.isEmpty ? 'Unbekannt' : rawName,
                      phone: (data['phoneNumber'] ?? '').toString().trim(),
                      imageUrl: (data['profileImageUrl'] ?? '').toString().trim(),
                    );

                    return Tooltip(
                      message: preview.name,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ContactThreadPage(
                              contactId: doc.id,
                              contactName: preview.name,
                              phoneNumber: preview.phone,
                            ),
                          ),
                        ),
                        child: SizedBox(
                          width: 72,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildAvatar(preview: preview, isOnline: true),
                              const SizedBox(height: 6),
                              Text(
                                preview.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _Neon.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: _Neon.bgElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _Neon.stroke),
              boxShadow: _Neon.glow(_Neon.cyan, blur: 20, alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 30,
              color: _Neon.cyan,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Noch keine Chats',
            style: TextStyle(
              color: _Neon.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sobald du mit jemandem geschrieben hast, erscheint der Chat hier.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _Neon.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    if (currentUserId == null) {
      return const Center(
        child: Text(
          'Du bist aktuell nicht eingeloggt.',
          style: TextStyle(color: _Neon.textPrimary),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _Neon.bg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A0A0F),
            Color(0xFF10101A),
            Color(0xFF0A0A0F),
          ],
        ),
      ),
      child: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('contact_threads')
              .where('participantMap.$currentUserId', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _Neon.cyan),
              );
            }

            final allDocs = [...snapshot.data?.docs ?? []]
                .where((doc) => doc.data()['hiddenFor_$currentUserId'] != true)
                .toList()
              ..sort((a, b) {
                final aData = a.data();
                final bData = b.data();
                final aUnread = (aData['unreadCountFor_$currentUserId'] ?? 0) as int;
                final bUnread = (bData['unreadCountFor_$currentUserId'] ?? 0) as int;

                if (aUnread != bUnread) return bUnread.compareTo(aUnread);

                final aTs = aData['updatedAt'] as Timestamp? ??
                    aData['lastInteractionAt'] as Timestamp?;
                final bTs = bData['updatedAt'] as Timestamp? ??
                    bData['lastInteractionAt'] as Timestamp?;

                if (aTs == null && bTs == null) return 0;
                if (aTs == null) return 1;
                if (bTs == null) return -1;
                return bTs.compareTo(aTs);
              });

            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const Text(
                  'Chats',
                  style: TextStyle(
                    color: _Neon.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Alle Unterhaltungen mit echtem Chat-Verlauf.',
                  style: TextStyle(
                    color: _Neon.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                _buildSearchField(),
                _buildOnlineFollowingSection(currentUserId),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      'Kontakte',
                      style: TextStyle(
                        color: _Neon.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _Neon.bgElevated,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _Neon.stroke),
                      ),
                      child: Text(
                        '${allDocs.length}',
                        style: const TextStyle(
                          color: _Neon.cyan,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (allDocs.isEmpty)
                  _buildEmptyState()
                else
                  Container(
                    decoration: _cardDecoration(),
                    child: Column(
                      children: List.generate(allDocs.length, (index) {
                        final doc = allDocs[index];
                        final data = doc.data();
                        final participants =
                        List<String>.from(data['participants'] ?? const []);
                        final otherId =
                        _otherParticipantId(participants, currentUserId).trim();

                        final contactNames = Map<String, dynamic>.from(
                          data['contactNames'] ?? const {},
                        );
                        final contactPhones = Map<String, dynamic>.from(
                          data['contactPhones'] ?? const {},
                        );

                        final fallbackName =
                        (contactNames[otherId] ?? 'Unbekannt').toString().trim();
                        final fallbackPhone =
                        (contactPhones[otherId] ?? '').toString().trim();
                        final unreadCount =
                        (data['unreadCountFor_$currentUserId'] ?? 0) as int;

                        if (otherId.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return FutureBuilder<_ContactPreviewData>(
                          future: _loadContactPreview(
                            contactId: otherId,
                            fallbackName: fallbackName,
                            fallbackPhone: fallbackPhone,
                          ),
                          builder: (context, previewSnapshot) {
                            final preview = previewSnapshot.data ??
                                _ContactPreviewData(
                                  name: fallbackName.isEmpty
                                      ? 'Unbekannt'
                                      : fallbackName,
                                  phone: fallbackPhone,
                                  imageUrl: '',
                                );

                            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(otherId)
                                  .snapshots(),
                              builder: (context, presenceSnapshot) {
                                final isOnline =
                                _isUserOnline(presenceSnapshot.data?.data());
                                final isTyping = _isOtherUserTyping(
                                  data,
                                  currentUserId,
                                  otherId,
                                );
                                final previewText = _threadPreviewText(
                                  data,
                                  isTyping: isTyping,
                                  isOnline: isOnline,
                                );
                                final trailingTimeText = _formatThreadTime(data);

                                if (!_matchesSearch(
                                  preview: preview,
                                  previewText: previewText,
                                  trailingTimeText: trailingTimeText,
                                )) {
                                  return const SizedBox.shrink();
                                }

                                return _buildThreadRow(
                                  preview: preview,
                                  hasUnread: unreadCount > 0,
                                  unreadCount: unreadCount,
                                  isOnline: isOnline,
                                  previewText: previewText,
                                  trailingTimeText: trailingTimeText,
                                  isTyping: isTyping,
                                  showDivider: index < allDocs.length - 1,
                                  isFirst: index == 0,
                                  isLast: index == allDocs.length - 1,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ContactThreadPage(
                                        contactId: otherId,
                                        contactName: preview.name,
                                        phoneNumber: preview.phone,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      }),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChatUnreadBadge extends StatelessWidget {
  final int count;

  const _ChatUnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: _Neon.lime,
        borderRadius: BorderRadius.circular(999),
        boxShadow: _Neon.glow(_Neon.lime, blur: 14, alpha: 0.20),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ContactPreviewData {
  final String name;
  final String phone;
  final String imageUrl;

  const _ContactPreviewData({
    required this.name,
    required this.phone,
    required this.imageUrl,
  });
}
