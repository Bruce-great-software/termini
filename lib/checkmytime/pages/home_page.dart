import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/appointments_page.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';
import 'package:termini/checkmytime/pages/profile_page.dart';
import 'package:termini/checkmytime/services/notification_service.dart';
import 'package:termini/checkmytime/pages/events_page.dart';

class CheckMyTimeHomePage extends StatefulWidget {
  const CheckMyTimeHomePage({super.key});

  @override
  State<CheckMyTimeHomePage> createState() => _CheckMyTimeHomePageState();
}

class _CheckMyTimeHomePageState extends State<CheckMyTimeHomePage> {
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isSearching = false;
  String _searchQuery = '';
  String? _searchError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _searchResults = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _threadsSubscription;
  bool _hasInitializedUnreadState = false;
  Map<String, int> _knownUnreadCountsByThread = {};

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _listenForIncomingAppointments();
  }

  @override
  void dispose() {
    _threadsSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    await NotificationService.instance.initialize();
    await NotificationService.instance.requestPermissions();
  }

  String _buildThreadId(String uidA, String uidB) {
    final ids = [uidA, uidB]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  String _otherParticipantId(List<String> participants, String currentUserId) {
    for (final id in participants) {
      if (id != currentUserId) return id;
    }
    return '';
  }

  void _listenForIncomingAppointments() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    _threadsSubscription?.cancel();
    _threadsSubscription = FirebaseFirestore.instance
        .collection('contact_threads')
        .where('participantMap.$currentUserId', isEqualTo: true)
        .snapshots()
        .listen((snapshot) async {
      final currentCounts = <String, int>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['hiddenFor_$currentUserId'] == true) continue;
        final unreadCount = (data['unreadCountFor_$currentUserId'] ?? 0) as int;
        currentCounts[doc.id] = unreadCount;
      }

      if (!_hasInitializedUnreadState) {
        _hasInitializedUnreadState = true;
        _knownUnreadCountsByThread = currentCounts;
        return;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['hiddenFor_$currentUserId'] == true) continue;

        final newCount = currentCounts[doc.id] ?? 0;
        final oldCount = _knownUnreadCountsByThread[doc.id] ?? 0;

        if (newCount > oldCount) {
          final participants = List<String>.from(data['participants'] ?? const []);
          final otherId = _otherParticipantId(participants, currentUserId);
          final contactNames =
          Map<String, dynamic>.from(data['contactNames'] ?? const {});
          final otherName =
          (contactNames[otherId] ?? 'Unbekannt').toString().trim();
          final lastTitle =
          (data['lastAppointmentTitle'] ?? 'Termin').toString().trim();

          await NotificationService.instance.showIncomingAppointmentNotification(
            title: 'Neuer Terminvorschlag',
            body: '$otherName: $lastTitle',
          );
        }
      }

      _knownUnreadCountsByThread = currentCounts;
    });
  }

  Future<_ContactPreviewData> _loadContactPreview({
    required String contactId,
    required String fallbackName,
    required String fallbackPhone,
  }) async {
    var resolvedName = fallbackName.trim();
    var resolvedPhone = fallbackPhone.trim();
    var resolvedImageUrl = '';

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(contactId).get();
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

    return _ContactPreviewData(
      name: resolvedName,
      phone: resolvedPhone,
      imageUrl: resolvedImageUrl,
    );
  }

  Widget _buildContactAvatar({
    required _ContactPreviewData preview,
    required ThemeData theme,
  }) {
    if (preview.imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(preview.imageUrl),
      );
    }

    final letter =
    preview.name.isNotEmpty ? preview.name.characters.first.toUpperCase() : '?';

    return CircleAvatar(
      radius: 20,
      child: Text(
        letter,
        style: theme.textTheme.labelLarge,
      ),
    );
  }

  Widget _buildThreadRow({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required _ContactPreviewData preview,
    required bool hasUnread,
    required int unreadCount,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildContactAvatar(
                preview: preview,
                theme: theme,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  preview.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              hasUnread
                  ? Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: Color(0xFFB7E61E),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$unreadCount',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
                  : Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label kommt als Nächstes.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _resetSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _searchError = null;
      _searchResults = [];
      _isSearching = false;
    });
  }

  Future<void> _openContact({
    required String contactId,
    required String contactName,
    required String phoneNumber,
  }) async {
    final safeName =
    contactName.trim().isEmpty ? 'Unbekannt' : contactName.trim();
    final safePhone = phoneNumber.trim();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    _resetSearch();

    if (currentUserId != null && contactId.isNotEmpty) {
      final threadId = _buildThreadId(currentUserId, contactId);
      try {
        await FirebaseFirestore.instance
            .collection('contact_threads')
            .doc(threadId)
            .set({
          'participants': [currentUserId, contactId]..sort(),
          'participantMap': {
            currentUserId: true,
            contactId: true,
          },
          'contactNames': {
            contactId: safeName,
          },
          'contactPhones': {
            contactId: safePhone,
          },
          'hiddenFor_$currentUserId': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'unreadCountFor_$currentUserId': 0,
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactThreadPage(
          contactId: contactId,
          contactName: safeName,
          phoneNumber: safePhone,
        ),
      ),
    );

    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  Future<void> _searchUsers(String value) async {
    final query = value.trim();

    setState(() {
      _searchQuery = query;
      _searchError = null;
    });

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final snapshot =
      await FirebaseFirestore.instance.collection('users').limit(50).get();

      final lowerQuery = query.toLowerCase();

      final filtered = snapshot.docs.where((doc) {
        if (doc.id == currentUid) return false;

        final data = doc.data();
        final displayName =
        (data['displayName'] ?? '').toString().trim().toLowerCase();
        final legacyName = (data['name'] ?? '').toString().trim().toLowerCase();
        final phoneNumber =
        (data['phoneNumber'] ?? '').toString().trim().toLowerCase();

        return displayName.contains(lowerQuery) ||
            legacyName.contains(lowerQuery) ||
            phoneNumber.contains(lowerQuery);
      }).toList();

      if (!mounted) return;

      setState(() {
        _searchResults = filtered;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _searchError = 'Fehler bei der Suche.';
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Center(
          child: Text(
            _searchError!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(
          child: Text('Keine Person gefunden.'),
        ),
      );
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gefundene Personen',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ..._searchResults.map((doc) {
            final data = doc.data();
            final fallbackName =
            (data['displayName'] ?? data['name'] ?? 'Unbekannt')
                .toString()
                .trim();
            final fallbackPhone = (data['phoneNumber'] ?? '').toString().trim();

            return FutureBuilder<_ContactPreviewData>(
              future: _loadContactPreview(
                contactId: doc.id,
                fallbackName: fallbackName,
                fallbackPhone: fallbackPhone,
              ),
              builder: (context, snapshot) {
                final preview = snapshot.data ??
                    _ContactPreviewData(
                      name: fallbackName.isEmpty ? 'Unbekannt' : fallbackName,
                      phone: fallbackPhone,
                      imageUrl: '',
                    );

                return Card(
                  child: ListTile(
                    leading: _buildContactAvatar(
                      preview: preview,
                      theme: theme,
                    ),
                    title: Text(preview.name),
                    subtitle: Text(
                      preview.phone.isNotEmpty
                          ? preview.phone
                          : 'Keine Nummer vorhanden',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _openContact(
                        contactId: doc.id,
                        contactName: preview.name,
                        phoneNumber: preview.phone,
                      );
                    },
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Future<void> _hideThreadForCurrentUser(
      String threadId,
      String currentUserId,
      ) async {
    try {
      await FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(threadId)
          .set({
        'hiddenFor_$currentUserId': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kontakt wurde von der Startseite entfernt.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kontakt konnte nicht entfernt werden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildThreadsSection(String currentUserId) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('contact_threads')
          .where('participantMap.$currentUserId', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = [...snapshot.data?.docs ?? []]
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

            final aTs = aData['lastInteractionAt'] as Timestamp?;
            final bTs = bData['lastInteractionAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kontakte',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final data = doc.data();
              final participants =
              List<String>.from(data['participants'] ?? const []);
              final otherId = _otherParticipantId(participants, currentUserId);
              final contactNames =
              Map<String, dynamic>.from(data['contactNames'] ?? const {});
              final contactPhones =
              Map<String, dynamic>.from(data['contactPhones'] ?? const {});

              final fallbackName =
              (contactNames[otherId] ?? 'Unbekannt').toString().trim();
              final fallbackPhone =
              (contactPhones[otherId] ?? '').toString().trim();
              final unreadCount =
              (data['unreadCountFor_$currentUserId'] ?? 0) as int;
              final hasUnread = unreadCount > 0;

              return FutureBuilder<_ContactPreviewData>(
                future: _loadContactPreview(
                  contactId: otherId,
                  fallbackName: fallbackName,
                  fallbackPhone: fallbackPhone,
                ),
                builder: (context, previewSnapshot) {
                  final preview = previewSnapshot.data ??
                      _ContactPreviewData(
                        name: fallbackName.isEmpty ? 'Unbekannt' : fallbackName,
                        phone: fallbackPhone,
                        imageUrl: '',
                      );

                  return Dismissible(
                    key: ValueKey(doc.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: colorScheme.error,
                      ),
                    ),
                    confirmDismiss: (_) async {
                      await _hideThreadForCurrentUser(doc.id, currentUserId);
                      return true;
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildThreadRow(
                        theme: theme,
                        colorScheme: colorScheme,
                        preview: preview,
                        hasUnread: hasUnread,
                        unreadCount: unreadCount,
                        onTap: () {
                          _openContact(
                            contactId: otherId,
                            contactName: preview.name,
                            phoneNumber: preview.phone,
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildHomeTab(
      ColorScheme colorScheme,
      ThemeData theme,
      String? currentUserId,
      ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _searchUsers,
          decoration: InputDecoration(
            hintText: 'Nach Name oder Nummer suchen',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
              onPressed: _resetSearch,
              icon: const Icon(Icons.close),
            )
                : IconButton(
              onPressed: () => _showComingSoon('Filter'),
              icon: const Icon(Icons.tune),
            ),
          ),
        ),
        if (_searchQuery.isNotEmpty)
          _buildSearchResults()
        else
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentUserId != null) _buildThreadsSection(currentUserId),
                Text(
                  'Schnellaktionen',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.celebration_outlined,
                  title: 'Events',
                  subtitle:
                  'Hier planst und verwaltest du später gemeinsame Aktivitäten und Einladungen.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const EventsPage(),
                      ),
                    );
                  },
                ),
                _ActionCard(
                  icon: Icons.calendar_month_outlined,
                  title: 'Termine',
                  subtitle:
                  'Hier verwaltest du deine festen Termine und gemeinsame Vorschläge.',
                  onTap: () {
                    setState(() {
                      _selectedIndex = 1;
                    });
                  },
                ),
                _ActionCard(
                  icon: Icons.person_outline,
                  title: 'Mein Profil',
                  subtitle:
                  'Hier kannst du Name, Bild und weitere Angaben ergänzen.',
                  onTap: () {
                    setState(() {
                      _selectedIndex = 2;
                    });
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBody(
      ColorScheme colorScheme,
      ThemeData theme,
      String? currentUserId,
      ) {
    if (_selectedIndex == 1) {
      return const AppointmentsPage();
    }

    if (_selectedIndex == 2) {
      return const ProfilePage();
    }

    return _buildHomeTab(colorScheme, theme, currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CheckMyTime'),
        actions: [
          IconButton(
            onPressed: () => setState(() {
              _selectedIndex = 2;
            }),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocusNode.unfocus(),
          child: _buildBody(
            colorScheme,
            theme,
            currentUserId,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Termine',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: colorScheme.primary.withOpacity(0.10),
                child: Icon(icon, color: colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
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