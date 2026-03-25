import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class KundenTerminePage extends StatelessWidget {
  const KundenTerminePage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bitte melde dich an, um deine Termine zu sehen.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('termine')
          .where('kundeId', isEqualTo: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Termine konnten nicht geladen werden.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? const [];
        final termine = docs
            .map((doc) => _KundenTermin.fromMap(doc.id, doc.data()))
            .toList();

        termine.sort(_sortByUpcomingThenStartAtAsc);

        if (termine.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Du hast noch keine Termine.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: termine.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final termin = termine[index];
            return Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                title: Text(
                  termin.titel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(
                          context,
                          termin.startAt,
                          termin.datumFallback,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(
                          context,
                          termin.startAt,
                          termin.startZeitFallback,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(termin.dienstleisterName),
                      Text('bei ${termin.mitarbeiterName}'),
                      if (termin.status.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Status: ${termin.status}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static int _sortByUpcomingThenStartAtAsc(_KundenTermin a, _KundenTermin b) {
    final now = DateTime.now();
    final aDate = a.startAt;
    final bDate = b.startAt;

    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;

    final aIsUpcoming = !aDate.isBefore(now);
    final bIsUpcoming = !bDate.isBefore(now);

    if (aIsUpcoming != bIsUpcoming) {
      return aIsUpcoming ? -1 : 1;
    }

    return aDate.compareTo(bDate);
  }

  static String _formatDate(
    BuildContext context,
    DateTime? startAt,
    String fallback,
  ) {
    if (startAt == null) {
      return fallback.isNotEmpty ? fallback : 'Datum unbekannt';
    }

    return MaterialLocalizations.of(context).formatFullDate(startAt);
  }

  static String _formatTime(
    BuildContext context,
    DateTime? startAt,
    String fallback,
  ) {
    if (startAt == null) {
      return fallback.isNotEmpty ? fallback : 'Uhrzeit unbekannt';
    }
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(startAt),
      alwaysUse24HourFormat: true,
    );
  }
}

class _KundenTermin {
  final String id;
  final DateTime? startAt;
  final String titel;
  final String datumFallback;
  final String startZeitFallback;
  final String dienstleisterName;
  final String mitarbeiterName;
  final String status;

  const _KundenTermin({
    required this.id,
    required this.startAt,
    required this.titel,
    required this.datumFallback,
    required this.startZeitFallback,
    required this.dienstleisterName,
    required this.mitarbeiterName,
    required this.status,
  });

  factory _KundenTermin.fromMap(String id, Map<String, dynamic> data) {
    return _KundenTermin(
      id: id,
      startAt: _parseStartAt(data['startAt']),
      titel: _readString(data['titel'], fallback: 'Termin'),
      datumFallback: _readString(data['datum']),
      startZeitFallback: _readString(data['startZeit']),
      dienstleisterName:
          _readString(data['dienstleisterName'], fallback: 'Dienstleister unbekannt'),
      mitarbeiterName:
          _readString(data['mitarbeiterName'], fallback: 'Mitarbeiter unbekannt'),
      status: _readString(data['status']),
    );
  }

  static DateTime? _parseStartAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static String _readString(dynamic value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }
}
