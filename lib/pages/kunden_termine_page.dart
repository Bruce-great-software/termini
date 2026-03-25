import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class KundenTerminePage extends StatelessWidget {
  const KundenTerminePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meine Termine')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Bitte melde dich an, um deine Termine zu sehen.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Meine Termine'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Anstehende Termine'),
              Tab(text: 'Vergangene Termine'),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('termine')
              .where('kundeId', isEqualTo: user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Termine konnten nicht geladen werden.'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = (snapshot.data?.docs ?? const [])
                .map((d) => _Termin.fromMap(d.id, d.data()))
                .where((t) => t.startAt != null)
                .toList();

            items.sort((a, b) => a.startAt!.compareTo(b.startAt!));

            final now = DateTime.now();
            final upcoming = items.where((t) => !t.startAt!.isBefore(now)).toList();
            final past = items.where((t) => t.startAt!.isBefore(now)).toList().reversed.toList();

            return TabBarView(
              children: [
                _TermineList(
                  termine: upcoming,
                  emptyText: 'Du hast keine anstehenden Termine.',
                ),
                _TermineList(
                  termine: past,
                  emptyText: 'Du hast keine vergangenen Termine.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TermineList extends StatelessWidget {
  final List<_Termin> termine;
  final String emptyText;

  const _TermineList({required this.termine, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (termine.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyText, textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: termine.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final termin = termine[index];
        return _TerminCard(termin: termin);
      },
    );
  }
}

class _TerminCard extends StatelessWidget {
  final _Termin termin;

  const _TerminCard({required this.termin});

  @override
  Widget build(BuildContext context) {
    final dt = termin.startAt!;
    final dateText = _capitalize(DateFormat('EEEE, d. MMMM', 'de_DE').format(dt));
    final timeText = DateFormat('HH:mm', 'de_DE').format(dt);

    final theme = Theme.of(context);
    const headerColor = Color(0xFF1F3A57);

    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(color: headerColor),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dateText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.access_time, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  timeText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _MitarbeiterAvatar(
                  imageUrl: termin.mitarbeiterBildUrl,
                  fallbackName: termin.mitarbeiterName,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        termin.dienstleisterName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        termin.mitarbeiterName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.grey.shade500),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MitarbeiterAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackName;

  const _MitarbeiterAvatar({
    required this.imageUrl,
    required this.fallbackName,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl?.trim() ?? '';
    final initials = _initialsFromName(fallbackName);

    if (trimmedUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: NetworkImage(trimmedUrl),
      );
    }

    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.grey.shade200,
      child: Text(
        initials,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Termin {
  final String id;
  final DateTime? startAt;
  final String dienstleisterName;
  final String mitarbeiterName;
  final String? mitarbeiterBildUrl;

  const _Termin({
    required this.id,
    required this.startAt,
    required this.dienstleisterName,
    required this.mitarbeiterName,
    required this.mitarbeiterBildUrl,
  });

  factory _Termin.fromMap(String id, Map<String, dynamic> data) {
    return _Termin(
      id: id,
      startAt: _parseDateTime(data['startAt']),
      dienstleisterName: _readString(data['dienstleisterName'], 'Dienstleister'),
      mitarbeiterName: _readString(data['mitarbeiterName'], 'Mitarbeiter'),
      mitarbeiterBildUrl: _readNullableString(data['mitarbeiterBildUrl']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _readString(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  static String? _readNullableString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }
}

String _capitalize(String text) {
  if (text.isEmpty) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

String _initialsFromName(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}
