import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dienstleister_detail_page.dart';
import 'login_register_page.dart';

class KundenFavoritenPage extends StatelessWidget {
  const KundenFavoritenPage({super.key});

  Future<List<Map<String, dynamic>>> _loadFavoriten(
    List<String> favoritenIds,
  ) async {
    if (favoritenIds.isEmpty) return const <Map<String, dynamic>>[];

    final firestore = FirebaseFirestore.instance;
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];

    for (var i = 0; i < favoritenIds.length; i += 10) {
      final end = (i + 10 < favoritenIds.length) ? i + 10 : favoritenIds.length;
      final chunk = favoritenIds.sublist(i, end);

      final snap = await firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .where('rolle', isEqualTo: 'dienstleister')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        result.add({
          ...data,
          'id': doc.id,
          if (!(data['dienstleisterId'] is String) ||
              (data['dienstleisterId'] as String).trim().isEmpty)
            'dienstleisterId': doc.id,
        });
      }
    }

    final indexById = <String, Map<String, dynamic>>{
      for (final entry in result) (entry['id'] as String): entry,
    };

    return favoritenIds
        .where(indexById.containsKey)
        .map((id) => indexById[id]!)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const LoginRegisterPage();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (userSnapshot.hasError) {
          return const Center(
            child: Text('Favoriten konnten nicht geladen werden.'),
          );
        }

        final favoritenRaw = userSnapshot.data?.data()?['favoriten'];
        final favoritenIds = (favoritenRaw is List)
            ? favoritenRaw
                .map((e) => e.toString().trim())
                .where((id) => id.isNotEmpty)
                .toList()
            : <String>[];

        if (favoritenIds.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.favorite_border, size: 56, color: Colors.black45),
                SizedBox(height: 12),
                Text(
                  'Noch keine Favoriten gespeichert',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  'Tippe bei einem Dienstleister auf das Herz.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          );
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadFavoriten(favoritenIds),
          builder: (context, favSnapshot) {
            if (favSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (favSnapshot.hasError) {
              return const Center(
                child: Text('Favoriten konnten nicht geladen werden.'),
              );
            }

            final favoriten = favSnapshot.data ?? const <Map<String, dynamic>>[];
            if (favoriten.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.storefront_outlined, size: 52, color: Colors.black45),
                    SizedBox(height: 10),
                    Text('Keine passenden Dienstleister gefunden.'),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              itemCount: favoriten.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final eintrag = favoriten[index];
                final name = ((eintrag['name'] as String?)?.trim().isNotEmpty ?? false)
                    ? (eintrag['name'] as String).trim()
                    : 'Dienstleister';
                final logoUrl = ((eintrag['logoUrl'] as String?)?.trim().isNotEmpty ?? false)
                    ? (eintrag['logoUrl'] as String).trim()
                    : '';

                String? adresse;
                final street = (eintrag['strasse'] as String?)?.trim();
                final hausnummer = (eintrag['hausnummer'] as String?)?.trim();
                final plz = (eintrag['plz'] as String?)?.trim();
                final ort = (eintrag['ort'] as String?)?.trim();
                final teile = <String>[
                  if (street != null && street.isNotEmpty) street,
                  if (hausnummer != null && hausnummer.isNotEmpty) hausnummer,
                ];
                final ortTeile = <String>[
                  if (plz != null && plz.isNotEmpty) plz,
                  if (ort != null && ort.isNotEmpty) ort,
                ];
                if (teile.isNotEmpty || ortTeile.isNotEmpty) {
                  adresse = '${teile.join(' ')}${teile.isNotEmpty && ortTeile.isNotEmpty ? ', ' : ''}${ortTeile.join(' ')}';
                }

                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 1,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DienstleisterDetailPage(
                            dienstleister: eintrag,
                            selektierteZielgruppe: 'alle',
                            selektierteKategorie: 'alle',
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 54,
                              height: 54,
                              child: logoUrl.isNotEmpty
                                  ? Image.network(
                                      logoUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: const Color(0xFFF3F4F6),
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.storefront, color: Colors.black54),
                                      ),
                                    )
                                  : Container(
                                      color: const Color(0xFFF3F4F6),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.storefront, color: Colors.black54),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (adresse != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    adresse,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.black54),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.favorite, color: Colors.redAccent),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
