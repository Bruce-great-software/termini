import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class KundenTermineDetailPage extends StatelessWidget {
  final DateTime startAt;
  final String? mitarbeiterId;
  final String dienstleisterName;
  final String mitarbeiterName;
  final String status;

  const KundenTermineDetailPage({
    super.key,
    required this.startAt,
    required this.mitarbeiterId,
    required this.dienstleisterName,
    required this.mitarbeiterName,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final dateText = _capitalize(DateFormat('EEEE, d. MMMM', 'de_DE').format(startAt));
    final timeText = DateFormat('HH:mm', 'de_DE').format(startAt);

    final theme = Theme.of(context);
    const headerColor = Color(0xFF1F3A57);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informationen zum Termin'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: Colors.white,
                elevation: 1,
                borderRadius: BorderRadius.circular(8),
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
                            mitarbeiterId: mitarbeiterId,
                            fallbackName: mitarbeiterName,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dienstleisterName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  mitarbeiterName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  status,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
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
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('TODO: Termin absagen')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF443A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  child: const Text('Termin absagen'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MitarbeiterAvatar extends StatelessWidget {
  final String? mitarbeiterId;
  final String fallbackName;

  const _MitarbeiterAvatar({
    required this.mitarbeiterId,
    required this.fallbackName,
  });

  @override
  Widget build(BuildContext context) {
    final employeeId = mitarbeiterId?.trim() ?? '';
    if (employeeId.isEmpty) {
      return _buildFallbackAvatar(context);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(employeeId).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final profileImageUrl = (data?['profileImageUrl'] as String?)?.trim() ?? '';

        if (profileImageUrl.isNotEmpty) {
          return CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: NetworkImage(profileImageUrl),
          );
        }

        return _buildFallbackAvatar(context);
      },
    );
  }

  Widget _buildFallbackAvatar(BuildContext context) {
    final initials = _initialsFromName(fallbackName);
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
