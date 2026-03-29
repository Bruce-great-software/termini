import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class KundenFavoritenPage extends StatelessWidget {
  final String userId;
  final void Function(Map<String, dynamic> dienstleister) onOpenDienstleister;
  final Future<void> Function(String dienstleisterId, bool isFavorit)
  onFavoritStatusChanged;

  const KundenFavoritenPage({
    super.key,
    required this.userId,
    required this.onOpenDienstleister,
    required this.onFavoritStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = userSnapshot.data!.data();
        final favoritenRaw = userData?['favoriten'];
        final favoritIds = <String>[];
        if (favoritenRaw is Map) {
          favoritIds.addAll(
            favoritenRaw.entries
                .where((e) => e.value == true)
                .map((e) => e.key.toString())
                .where((id) => id.trim().isNotEmpty),
          );
        }

        if (favoritIds.isEmpty) {
          return const Center(child: Text('Noch keine Favoriten gespeichert.'));
        }

        return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: () async {
            final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (var i = 0; i < favoritIds.length; i += 10) {
              final end = math.min(i + 10, favoritIds.length);
              final chunk = favoritIds.sublist(i, end);
              final snap = await FirebaseFirestore.instance
                  .collection('users')
                  .where(FieldPath.documentId, whereIn: chunk)
                  .get();
              docs.addAll(snap.docs);
            }
            docs.sort((a, b) {
              final an = (a.data()['name'] ?? '').toString().toLowerCase();
              final bn = (b.data()['name'] ?? '').toString().toLowerCase();
              return an.compareTo(bn);
            });
            return docs;
          }(),
          builder: (context, favSnapshot) {
            if (!favSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = favSnapshot.data!
                .where((d) => (d.data()['rolle'] ?? '').toString() == 'dienstleister')
                .toList();
            if (docs.isEmpty) {
              return const Center(child: Text('Noch keine Favoriten gespeichert.'));
            }

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = Map<String, dynamic>.from(doc.data())..['id'] = doc.id;
                return ListTile(
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: (data['logoUrl'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty
                        ? NetworkImage(data['logoUrl'].toString().trim())
                        : null,
                    child: (data['logoUrl'] ?? '').toString().trim().isEmpty
                        ? const Icon(Icons.storefront, color: Colors.black54)
                        : null,
                  ),
                  title: Text((data['name'] ?? 'Dienstleister').toString()),
                  subtitle: Text(
                    [
                      (data['adresse'] ?? '').toString(),
                      [
                        (data['plz'] ?? '').toString(),
                        (data['ort'] ?? '').toString(),
                      ].where((e) => e.trim().isNotEmpty).join(' ')
                    ].where((e) => e.trim().isNotEmpty).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    onPressed: () => onFavoritStatusChanged(doc.id, false),
                    icon: const Icon(Icons.favorite, color: Colors.red),
                  ),
                  onTap: () => onOpenDienstleister(data),
                );
              },
            );
          },
        );
      },
    );
  }
}