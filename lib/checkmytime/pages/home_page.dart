import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/contact_thread_page.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  Widget _buildRecentContacts() {
    if (_recentContacts.isEmpty) {
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
        ..._recentContacts.map((contact) {
          final avatarLetter =
          contact.contactName.characters.first.toUpperCase();

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(avatarLetter),
              ),
              title: Text(contact.contactName),
              subtitle: Text(
                contact.phoneNumber.isEmpty
                    ? 'Keine Nummer vorhanden'
                    : contact.phoneNumber,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _openContact(
                  contactId: contact.contactId,
                  contactName: contact.contactName,
                  phoneNumber: contact.phoneNumber,
                );
              },
            ),
          );
        }),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDefaultContent(ColorScheme colorScheme, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRecentContacts(),
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
          onTap: () => _showComingSoon('Meine Termine'),
        ),
        _ActionCard(
          icon: Icons.person_outline,
          title: 'Mein Profil',
          subtitle:
          'Hier können später Name, Bild und weitere Angaben ergänzt werden.',
          onTap: () => _showComingSoon('Mein Profil'),
        ),
      ],
    );
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
            onPressed: () => _showComingSoon('Einstellungen'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocusNode.unfocus(),
          child: ListView(
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
                  child: _buildDefaultContent(colorScheme, theme),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });

          if (index == 1) {
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
