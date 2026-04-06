import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/appointments_page.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';
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

  bool _isSearching = false;
  String _searchQuery = '';
  String? _searchError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _searchResults = [];
  final List<_RecentContact> _recentContacts = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _appointmentsSubscription;
  bool _hasInitializedUnreadState = false;
  Set<String> _knownUnreadIncomingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _listenForIncomingAppointments();
  }

  Future<void> _initializeNotifications() async {
    await NotificationService.instance.initialize();
    await NotificationService.instance.requestPermissions();
  }

  @override
  void dispose() {
    _appointmentsSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _listenForIncomingAppointments() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    _appointmentsSubscription?.cancel();
    _appointmentsSubscription = FirebaseFirestore.instance
        .collection('appointments')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .listen((snapshot) async {
      final currentUnreadIds = <String>{};
      final unreadDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final createdBy = (data['createdBy'] ?? '').toString();
        final status = (data['status'] ?? '').toString();
        final isReadByRecipient = data['isReadByRecipient'] == true;

        if (createdBy != currentUserId &&
            status == 'pending' &&
            !isReadByRecipient) {
          currentUnreadIds.add(doc.id);
          unreadDocs.add(doc);
        }
      }

      if (!_hasInitializedUnreadState) {
        _hasInitializedUnreadState = true;
        _knownUnreadIncomingIds = currentUnreadIds;
        return;
      }

      final newDocs = unreadDocs
          .where((doc) => !_knownUnreadIncomingIds.contains(doc.id))
          .toList(growable: false);

      for (final doc in newDocs) {
        final data = doc.data();
        final title = (data['title'] ?? 'Termin').toString();

        await NotificationService.instance.showIncomingAppointmentNotification(
          title: 'Neuer Terminvorschlag',
          body: 'Du hast einen neuen Terminvorschlag: $title',
        );
      }

      _knownUnreadIncomingIds = currentUnreadIds;
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
    final safeName =
    contactName.trim().isEmpty ? 'Unbekannt' : contactName.trim();
    final safePhone = phoneNumber.trim();

    _resetSearch();

    setState(() {
      _recentContacts.removeWhere((contact) => contact.contactId == contactId);
      _recentContacts.insert(
        0,
        _RecentContact(
          contactId: contactId,
          contactName: safeName,
          phoneNumber: safePhone,
        ),
      );
    });

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

  Future<Map<String, _RecentContact>> _loadMissingContacts(
      List<String> contactIds,
      ) async {
    final result = <String, _RecentContact>{};

    for (final id in contactIds) {
      try {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(id).get();
        final data = doc.data();
        if (data == null) continue;

        final name = (data['displayName'] ?? data['name'] ?? 'Unbekannt')
            .toString()
            .trim();
        final phone = (data['phoneNumber'] ?? '').toString().trim();

        result[id] = _RecentContact(
          contactId: id,
          contactName: name.isEmpty ? 'Unbekannt' : name,
          phoneNumber: phone,
        );
      } catch (_) {}
    }

    return result;
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

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gefundene Personen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ..._searchResults.map((doc) {
            final data = doc.data();
            final displayName =
            (data['displayName'] ?? data['name'] ?? 'Unbekannt')
                .toString()
                .trim();
            final phoneNumber = (data['phoneNumber'] ?? '').toString().trim();

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    displayName.isNotEmpty
                        ? displayName.characters.first.toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(
                  displayName.isNotEmpty ? displayName : 'Unbekannt',
                ),
                subtitle: Text(
                  phoneNumber.isNotEmpty
                      ? phoneNumber
                      : 'Keine Nummer vorhanden',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _openContact(
                    contactId: doc.id,
                    contactName: displayName,
                    phoneNumber: phoneNumber,
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRecentContactsSection(String currentUserId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('participants', arrayContains: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCounts = <String, int>{};

        for (final doc in snapshot.data?.docs ?? const []) {
          final data = doc.data();
          final createdBy = (data['createdBy'] ?? '').toString();
          final status = (data['status'] ?? '').toString();
          final isReadByRecipient = data['isReadByRecipient'] == true;

          if (createdBy != currentUserId &&
              status == 'pending' &&
              !isReadByRecipient) {
            unreadCounts[createdBy] = (unreadCounts[createdBy] ?? 0) + 1;
          }
        }

        if (_recentContacts.isEmpty && unreadCounts.isEmpty) {
          return const SizedBox.shrink();
        }

        final recentMap = <String, _RecentContact>{
          for (final contact in _recentContacts) contact.contactId: contact,
        };

        final missingIds = unreadCounts.keys
            .where((id) => !recentMap.containsKey(id))
            .toList(growable: false);

        return FutureBuilder<Map<String, _RecentContact>>(
          future: _loadMissingContacts(missingIds),
          builder: (context, contactSnapshot) {
            final mergedMap = <String, _RecentContact>{
              ...recentMap,
              ...?contactSnapshot.data,
            };

            final orderedIds = <String>[];

            final unreadIds = unreadCounts.keys.toList()
              ..sort(
                    (a, b) =>
                    (unreadCounts[b] ?? 0).compareTo(unreadCounts[a] ?? 0),
              );
            orderedIds.addAll(unreadIds);

            for (final contact in _recentContacts) {
              if (!orderedIds.contains(contact.contactId)) {
                orderedIds.add(contact.contactId);
              }
            }

            final items = orderedIds
                .map((id) {
              final contact = mergedMap[id];
              if (contact == null) return null;
              return _HomeContactItem(
                contact: contact,
                unreadCount: unreadCounts[id] ?? 0,
              );
            })
                .whereType<_HomeContactItem>()
                .toList();

            if (items.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zuletzt geöffnet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ...items.map((item) {
                  final avatarLetter =
                  item.contact.contactName.characters.first.toUpperCase();
                  final hasUnread = item.unreadCount > 0;

                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(avatarLetter),
                      ),
                      title: Text(
                        item.contact.contactName,
                        style: TextStyle(
                          fontWeight:
                          hasUnread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        item.contact.phoneNumber.isEmpty
                            ? 'Keine Nummer vorhanden'
                            : item.contact.phoneNumber,
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
                          '${item.unreadCount}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      )
                          : const Icon(Icons.chevron_right),
                      onTap: () {
                        _openContact(
                          contactId: item.contact.contactId,
                          contactName: item.contact.contactName,
                          phoneNumber: item.contact.phoneNumber,
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],
            );
          },
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
                if (currentUserId != null) _buildRecentContactsSection(currentUserId),
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
                        'Termine einfach wie Nachrichten.',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Das ist die neue Startseite für den CheckMyTime-Bereich. '
                            'Von hier aus bauen wir Schritt für Schritt die neue Logik auf.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _showComingSoon('Nutzer finden'),
                        icon: const Icon(Icons.person_search_outlined),
                        label: const Text('Nutzer finden'),
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
                  subtitle:
                  'Später kannst du hier einem anderen Nutzer einen Termin schicken.',
                  onTap: () => _showComingSoon('Termin erstellen'),
                ),
                _ActionCard(
                  icon: Icons.calendar_month_outlined,
                  title: 'Meine Termine',
                  subtitle:
                  'Hier zeigen wir später eingehende und bestätigte Termine an.',
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
                  'Hier können später Name, Bild und weitere Angaben ergänzt werden.',
                  onTap: () => _showComingSoon('Mein Profil'),
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
      return Center(
        child: Text(
          'Profil kommt als Nächstes.',
          style: theme.textTheme.bodyLarge,
        ),
      );
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
            onPressed: () => _showComingSoon('Einstellungen'),
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

          if (index == 2) {
            _showComingSoon('Profil');
          }
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

class _RecentContact {
  final String contactId;
  final String contactName;
  final String phoneNumber;

  const _RecentContact({
    required this.contactId,
    required this.contactName,
    required this.phoneNumber,
  });
}

class _HomeContactItem {
  final _RecentContact contact;
  final int unreadCount;

  const _HomeContactItem({
    required this.contact,
    required this.unreadCount,
  });
}
