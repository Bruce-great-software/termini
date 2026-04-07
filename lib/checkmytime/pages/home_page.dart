import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/appointments_page.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';
import 'package:termini/checkmytime/pages/profile_page.dart';
import 'package:termini/checkmytime/services/notification_service.dart';

class CheckMyTimeHomePage extends StatefulWidget {
  const CheckMyTimeHomePage({super.key});

  @override
  State<CheckMyTimeHomePage> createState() => _CheckMyTimeHomePageState();
}

class _CheckMyTimeHomePageState extends State<CheckMyTimeHomePage> {
  int _selectedIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String? _currentUserId;

  bool _isSearching = false;
  String _searchQuery = '';
  String? _searchError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _searchResults = [];

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _threadsSubscription;

  bool _hasInitializedUnreadState = false;
  Map<String, int> _knownUnreadCountsByThread = {};

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _bindAuthListener();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _threadsSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    await NotificationService.instance.initialize();
    await NotificationService.instance.requestPermissions();
  }

  void _bindAuthListener() {
    _handleAuthChanged(FirebaseAuth.instance.currentUser);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthChanged,
    );
  }

  void _handleAuthChanged(User? user) {
    final newUserId = user?.uid;

    _threadsSubscription?.cancel();
    _threadsSubscription = null;
    _hasInitializedUnreadState = false;
    _knownUnreadCountsByThread = {};

    if (!mounted) return;

    setState(() {
      _currentUserId = newUserId;

      if (newUserId == null) {
        _searchQuery = '';
        _searchError = null;
        _searchResults = [];
        _isSearching = false;
        _searchController.clear();

        if (_selectedIndex == 1) {
          _selectedIndex = 2;
        }
      }
    });

    if (newUserId != null) {
      _listenForIncomingAppointments(newUserId);
    }
  }

  bool _requireLogin({int? switchToTab}) {
    if (_currentUserId != null) {
      return true;
    }

    if (switchToTab != null) {
      setState(() {
        _selectedIndex = switchToTab;
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bitte logge dich zuerst ein oder registriere dich.'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    return false;
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
        backgroundImage: NetworkImage(preview.imageUrl),
      );
    }

    final letter =
    preview.name.isNotEmpty ? preview.name.characters.first.toUpperCase() : '?';

    return CircleAvatar(
      child: Text(
        letter,
        style: theme.textTheme.labelLarge,
      ),
    );
  }

  void _listenForIncomingAppointments(String currentUserId) {
    _threadsSubscription?.cancel();

    _threadsSubscription = FirebaseFirestore.instance
        .collection('contact_threads')
        .where('participantMap.$currentUserId', isEqualTo: true)
        .snapshots()
        .listen((snapshot) async {
      final currentCounts = <String, int>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final unreadCount = (data['unreadCountFor_$currentUserId'] ?? 0) as int;
        final isHiddenForCurrentUser = data['hiddenFor_$currentUserId'] == true;

        if (isHiddenForCurrentUser && unreadCount <= 0) continue;
        currentCounts[doc.id] = unreadCount;
      }

      if (!_hasInitializedUnreadState) {
        _hasInitializedUnreadState = true;
        _knownUnreadCountsByThread = currentCounts;
        return;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final newCount = currentCounts[doc.id] ?? 0;
        if (newCount <= 0) continue;

        final oldCount = _knownUnreadCountsByThread[doc.id] ?? 0;
        if (newCount <= oldCount) continue;

        final participants = List<String>.from(data['participants'] ?? const []);
        final otherId = _otherParticipantId(participants, currentUserId);
        final contactNames =
        Map<String, dynamic>.from(data['contactNames'] ?? const {});
        final otherName =
        (contactNames[otherId] ?? 'Unbekannt').toString().trim();
        final lastInteractionType =
        (data['lastInteractionType'] ?? 'appointment').toString();

        if (lastInteractionType == 'message') {
          final lastMessage =
          (data['lastMessageText'] ?? 'Neue Nachricht').toString().trim();

          await NotificationService.instance.showIncomingChatNotification(
            title: otherName,
            body: lastMessage.isEmpty ? 'Neue Nachricht' : lastMessage,
          );
        } else {
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
    if (!_requireLogin()) return;

    final safeName =
    contactName.trim().isEmpty ? 'Unbekannt' : contactName.trim();
    final safePhone = phoneNumber.trim();
    final currentUserId = _currentUserId;

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

    if (_currentUserId == null) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _searchError = 'Bitte logge dich ein, um andere Nutzer zu suchen.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final snapshot =
      await FirebaseFirestore.instance.collection('users').limit(50).get();

      final lowerQuery = query.toLowerCase();

      final filtered = snapshot.docs.where((doc) {
        if (doc.id == _currentUserId) return false;

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
            textAlign: TextAlign.center,
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
            .where((doc) {
          final data = doc.data();
          final isHidden = data['hiddenFor_$currentUserId'] == true;
          final unreadCount =
          (data['unreadCountFor_$currentUserId'] ?? 0) as int;
          return !isHidden || unreadCount > 0;
        })
            .toList()
          ..sort((a, b) {
            final aTs = a.data()['lastInteractionAt'] as Timestamp?;
            final bTs = b.data()['lastInteractionAt'] as Timestamp?;
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
              style: theme.textTheme.titleMedium,
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
                builder: (context, snapshot) {
                  final preview = snapshot.data ??
                      _ContactPreviewData(
                        name: fallbackName.isEmpty ? 'Unbekannt' : fallbackName,
                        phone: fallbackPhone,
                        imageUrl: '',
                      );

                  return Dismissible(
                    key: ValueKey(doc.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
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
                    child: Card(
                      child: ListTile(
                        leading: _buildContactAvatar(
                          preview: preview,
                          theme: theme,
                        ),
                        title: Text(
                          preview.name,
                          style: TextStyle(
                            fontWeight:
                            hasUnread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          (() {
                            final lastInteractionType =
                            (data['lastInteractionType'] ?? '').toString();
                            final lastMessage =
                            (data['lastMessageText'] ?? '').toString().trim();
                            final lastAppointmentTitle =
                            (data['lastAppointmentTitle'] ?? '')
                                .toString()
                                .trim();

                            if (lastInteractionType == 'message' &&
                                lastMessage.isNotEmpty) {
                              return lastMessage;
                            }

                            if (lastInteractionType == 'appointment' &&
                                lastAppointmentTitle.isNotEmpty) {
                              return 'Termin: $lastAppointmentTitle';
                            }

                            return preview.phone.isNotEmpty
                                ? preview.phone
                                : 'Keine Nummer vorhanden';
                          })(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: hasUnread
                            ? Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFFB7E61E),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        )
                            : const Icon(Icons.chevron_right),
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
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildLoggedOutAppointmentsPlaceholder(
      ThemeData theme,
      ColorScheme colorScheme,
      ) {
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
                radius: 34,
                backgroundColor: colorScheme.primary.withOpacity(0.10),
                child: Icon(
                  Icons.calendar_month_outlined,
                  color: colorScheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Meine Termine',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Bitte logge dich ein oder registriere dich, damit du eingehende und bestätigte Termine sehen kannst.',
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
                    setState(() {
                      _selectedIndex = 2;
                    });
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Zum Profil / Login'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHomeTab(
      ColorScheme colorScheme,
      ThemeData theme,
      String? currentUserId,
      ) {
    final isLoggedIn = currentUserId != null;

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
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoggedIn
                            ? 'Termine einfach wie Nachrichten.'
                            : 'Einloggen und direkt loslegen.',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isLoggedIn
                            ? 'Das ist die neue Startseite für den CheckMyTime-Bereich. Von hier aus bauen wir Schritt für Schritt die neue Logik auf.'
                            : 'Melde dich zuerst an oder registriere dich im Profil-Tab. Danach kannst du Kontakte finden, Termine empfangen und dein Profil vervollständigen.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          if (isLoggedIn) {
                            _showComingSoon('Nutzer finden');
                          } else {
                            setState(() {
                              _selectedIndex = 2;
                            });
                          }
                        },
                        icon: Icon(
                          isLoggedIn
                              ? Icons.person_search_outlined
                              : Icons.login,
                        ),
                        label: Text(
                          isLoggedIn ? 'Nutzer finden' : 'Jetzt einloggen',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Schnellaktionen',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.event_available_outlined,
                  title: 'Termin erstellen',
                  subtitle: isLoggedIn
                      ? 'Später kannst du hier einem anderen Nutzer einen Termin schicken.'
                      : 'Logge dich zuerst ein, damit du später Termine erstellen kannst.',
                  onTap: () {
                    if (!isLoggedIn) {
                      setState(() {
                        _selectedIndex = 2;
                      });
                      return;
                    }
                    _showComingSoon('Termin erstellen');
                  },
                ),
                _ActionCard(
                  icon: Icons.calendar_month_outlined,
                  title: 'Meine Termine',
                  subtitle: isLoggedIn
                      ? 'Hier zeigen wir später eingehende und bestätigte Termine an.'
                      : 'Nach dem Login erscheinen hier deine Termine.',
                  onTap: () {
                    setState(() {
                      _selectedIndex = isLoggedIn ? 1 : 2;
                    });
                  },
                ),
                _ActionCard(
                  icon: Icons.person_outline,
                  title: 'Mein Profil',
                  subtitle: isLoggedIn
                      ? 'Hier kannst du Name, Bild und weitere Angaben ergänzen.'
                      : 'Hier kannst du dich einloggen oder registrieren.',
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
      if (currentUserId == null) {
        return _buildLoggedOutAppointmentsPlaceholder(theme, colorScheme);
      }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('CheckMyTime'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _selectedIndex = 2;
              });
            },
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
            _currentUserId,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index == 1 && _currentUserId == null) {
            setState(() {
              _selectedIndex = 2;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bitte logge dich ein, um deine Termine zu sehen.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }

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