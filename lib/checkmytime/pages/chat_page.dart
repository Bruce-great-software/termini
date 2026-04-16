import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';

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

  String _otherParticipantId(List<String> participants, String currentUserId) {
    for (final id in participants) {
      if (id != currentUserId) return id;
    }
    return '';
  }

  bool _isUserOnline(Map<String, dynamic>? data) {
    if (data == null || data['isOnline'] != true) {
      return false;
    }

    final lastSeen = data['lastSeenAt'];
    if (lastSeen is! Timestamp) return true;

    return DateTime.now().difference(lastSeen.toDate()) <= _onlineGracePeriod;
  }

  bool _isOtherUserTyping(
      Map<String, dynamic> data,
      String currentUserId,
      String otherParticipantId,
      ) {
    final typingTimestamp =
        data['typingAt'] as Timestamp? ??
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
        required String currentUserId,
        required String otherParticipantId,
        required bool isOnline,
      }) {
    if (_isOtherUserTyping(data, currentUserId, otherParticipantId)) {
      return 'Schreibt gerade…';
    }

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

    final previewCandidates = [
      data['lastMessageText'],
      data['lastMessage'],
      data['lastMessagePreview'],
      data['lastText'],
      data['lastInteractionText'],
      data['lastAppointmentTitle'],
    ];

    for (final candidate in previewCandidates) {
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
    final otherDay = DateTime(date.year, date.month, date.day);
    final dayDifference = today.difference(otherDay).inDays;

    if (dayDifference == 1) return 'Gestern';
    if (dayDifference < 7) {
      const weekdays = [
        'Mo.',
        'Di.',
        'Mi.',
        'Do.',
        'Fr.',
        'Sa.',
        'So.',
      ];
      return weekdays[date.weekday - 1];
    }

    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }

  Future<_ContactPreviewData> _loadContactPreview({
    required String contactId,
    required String fallbackName,
    required String fallbackPhone,
  }) async {
    if (_contactPreviewCache.containsKey(contactId)) {
      return _contactPreviewCache[contactId]!;
    }

    var resolvedName = fallbackName.trim();
    var resolvedPhone = fallbackPhone.trim();
    var resolvedImageUrl = '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(contactId)
          .get();
      final data = doc.data();

      if (data != null) {
        final firestoreName =
        (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final firestorePhone = (data['phoneNumber'] ?? '').toString().trim();
        final firestoreImageUrl =
        (data['profileImageUrl'] ?? '').toString().trim();

        if (firestoreName.isNotEmpty) {
          resolvedName = firestoreName;
        }
        if (firestorePhone.isNotEmpty) {
          resolvedPhone = firestorePhone;
        }
        if (firestoreImageUrl.isNotEmpty) {
          resolvedImageUrl = firestoreImageUrl;
        }
      }
    } catch (_) {}

    if (resolvedName.isEmpty) {
      resolvedName = 'Unbekannt';
    }

    final preview = _ContactPreviewData(
      name: resolvedName,
      phone: resolvedPhone,
      imageUrl: resolvedImageUrl,
    );
    _contactPreviewCache[contactId] = preview;
    return preview;
  }

  Widget _buildContactAvatar({
    required _ContactPreviewData preview,
    required ThemeData theme,
    bool isOnline = false,
  }) {
    final colorScheme = theme.colorScheme;

    if (preview.imageUrl.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isOnline
              ? Border.all(color: const Color(0xFF19B35E), width: 2.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.14),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: CircleAvatar(
          radius: 25,
          backgroundImage: NetworkImage(preview.imageUrl),
        ),
      );
    }

    final letter =
    preview.name.isNotEmpty ? preview.name.characters.first.toUpperCase() : '?';

    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isOnline
            ? Border.all(color: const Color(0xFF19B35E), width: 2.5)
            : null,
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: theme.textTheme.titleMedium?.copyWith(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPresenceAvatar({
    required _ContactPreviewData preview,
    required ThemeData theme,
    required bool isOnline,
  }) {
    final avatar = _buildContactAvatar(
      preview: preview,
      theme: theme,
      isOnline: isOnline,
    );
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
              color: const Color(0xFF19B35E),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim().toLowerCase();
          });
        },
        decoration: InputDecoration(
          hintText: 'Nach Chats suchen',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
              });
            },
            icon: const Icon(Icons.close),
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

    final haystack = [
      preview.name,
      preview.phone,
      previewText,
      trailingTimeText,
    ].join(' ').toLowerCase();

    return haystack.contains(_searchQuery);
  }

  Widget _buildThreadRow({
    required ThemeData theme,
    required ColorScheme colorScheme,
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
    required VoidCallback onTap,
  }) {
    final topRadius = isFirst ? const Radius.circular(24) : Radius.zero;
    final bottomRadius = isLast ? const Radius.circular(24) : Radius.zero;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
      height: 1.1,
    );
    final previewColor = isTyping
        ? colorScheme.primary
        : hasUnread
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

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
                  _buildPresenceAvatar(
                    preview: preview,
                    theme: theme,
                    isOnline: isOnline,
                  ),
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
                                style: titleStyle,
                              ),
                            ),
                            if (trailingTimeText.trim().isNotEmpty)
                              Text(
                                trailingTimeText,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: hasUnread
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w600,
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
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: previewColor,
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
                  color: colorScheme.outlineVariant.withValues(alpha: 0.65),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildOnlineFollowingSection(
      ThemeData theme,
      ColorScheme colorScheme,
      String currentUserId,
      ) {
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

        if (followingIds.isEmpty) {
          return const SizedBox.shrink();
        }

        final visibleFollowingIds = followingIds.take(10).toList();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: visibleFollowingIds)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox.shrink();
            }

            final onlineDocs = snapshot.data!.docs.where((doc) {
              return _isUserOnline(doc.data());
            }).toList()
              ..sort((a, b) {
                final aName =
                (a.data()['displayName'] ?? a.data()['name'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                final bName =
                (b.data()['displayName'] ?? b.data()['name'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                return aName.compareTo(bName);
              });

            if (onlineDocs.isEmpty) {
              return const SizedBox.shrink();
            }

            return Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.04),
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
                    final preview = _ContactPreviewData(
                      name: (data['displayName'] ?? data['name'] ?? 'Unbekannt')
                          .toString()
                          .trim()
                          .isEmpty
                          ? 'Unbekannt'
                          : (data['displayName'] ?? data['name'] ?? 'Unbekannt')
                          .toString()
                          .trim(),
                      phone: (data['phoneNumber'] ?? '').toString().trim(),
                      imageUrl: (data['profileImageUrl'] ?? '').toString().trim(),
                    );

                    return Tooltip(
                      message: preview.name,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ContactThreadPage(
                                contactId: doc.id,
                                contactName: preview.name,
                                phoneNumber: preview.phone,
                              ),
                            ),
                          );
                        },
                        child: SizedBox(
                          width: 72,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildPresenceAvatar(
                                preview: preview,
                                theme: theme,
                                isOnline: true,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                preview.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurface,
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

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 30,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Noch keine Chats',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sobald du mit jemandem geschrieben hast, erscheint der Chat hier.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (currentUserId == null) {
      return Center(
        child: Text(
          'Du bist aktuell nicht eingeloggt.',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('contact_threads')
          .where('participantMap.$currentUserId', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = [...snapshot.data?.docs ?? []]
            .where((doc) => doc.data()['hiddenFor_$currentUserId'] != true)
            .toList()
          ..sort((a, b) {
            final aData = a.data();
            final bData = b.data();
            final aUnread = (aData['unreadCountFor_$currentUserId'] ?? 0) as int;
            final bUnread = (bData['unreadCountFor_$currentUserId'] ?? 0) as int;

            if (aUnread != bUnread) {
              return bUnread.compareTo(aUnread);
            }

            final aTs =
                aData['updatedAt'] as Timestamp? ??
                    aData['lastInteractionAt'] as Timestamp?;
            final bTs =
                bData['updatedAt'] as Timestamp? ??
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
            _buildSearchField(theme, colorScheme),
            _buildOnlineFollowingSection(theme, colorScheme, currentUserId),
            const SizedBox(height: 18),
            Text(
              'Kontakte',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Alle Unterhaltungen mit echtem Chat-Verlauf.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            if (allDocs.isEmpty)
              _buildEmptyState(theme, colorScheme)
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colorScheme.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: List.generate(allDocs.length, (index) {
                    final doc = allDocs[index];
                    final data = doc.data();
                    final participants = List<String>.from(
                      data['participants'] ?? const [],
                    );
                    final otherId = _otherParticipantId(participants, currentUserId);
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
                    final hasUnread = unreadCount > 0;
                    final isFirst = index == 0;
                    final isLast = index == allDocs.length - 1;

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
                            final isOnline = _isUserOnline(
                              presenceSnapshot.data?.data(),
                            );
                            final isTyping = _isOtherUserTyping(
                              data,
                              currentUserId,
                              otherId,
                            );
                            final previewText = _threadPreviewText(
                              data,
                              currentUserId: currentUserId,
                              otherParticipantId: otherId,
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
                              theme: theme,
                              colorScheme: colorScheme,
                              preview: preview,
                              hasUnread: hasUnread,
                              unreadCount: unreadCount,
                              isOnline: isOnline,
                              previewText: previewText,
                              trailingTimeText: trailingTimeText,
                              isTyping: isTyping,
                              showDivider: !isLast,
                              isFirst: isFirst,
                              isLast: isLast,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ContactThreadPage(
                                      contactId: otherId,
                                      contactName: preview.name,
                                      phoneNumber: preview.phone,
                                    ),
                                  ),
                                );
                              },
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
        color: const Color(0xFFB7E61E),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.black,
          fontWeight: FontWeight.w800,
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
