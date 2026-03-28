import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dienstleister_detail_page.dart';
import 'login_register_page.dart';

class KundenFavoritenPage extends StatelessWidget {
  const KundenFavoritenPage({super.key});

  String _resolveLogoUrl(Map<String, dynamic> data) {
    final logoUrl = (data['logoUrl'] as String?)?.trim();
    if (logoUrl != null && logoUrl.isNotEmpty) return logoUrl;

    final profileImageUrl = (data['profileImageUrl'] as String?)?.trim();
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      return profileImageUrl;
    }

    final imageUrl = (data['imageUrl'] as String?)?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;

    return '';
  }

  String _addressLine(Map<String, dynamic> data) {
    final adresse = (data['adresse'] as String?)?.trim() ?? '';
    final plz = (data['plz'] as String?)?.trim() ?? '';
    final ort = (data['ort'] as String?)?.trim() ?? '';

    final cityLine = [plz, ort].where((s) => s.isNotEmpty).join(' ');
    return [adresse, cityLine].where((s) => s.isNotEmpty).join(', ');
  }

  Future<void> _removeFavorite({
    required String kundeId,
    required String dienstleisterId,
  }) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(kundeId)
        .collection('favoriten')
        .doc(dienstleisterId)
        .delete();
  }

  Future<void> _openDetailPage(BuildContext context, String dienstleisterId,
      Map<String, dynamic> favoritenData) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(dienstleisterId)
        .get();

    final dienstleisterData = userDoc.data() ?? <String, dynamic>{};
    dienstleisterData['id'] = dienstleisterId;

    if ((dienstleisterData['name'] as String?)?.trim().isEmpty ?? true) {
      dienstleisterData['name'] = favoritenData['name'];
    }
    if ((dienstleisterData['adresse'] as String?)?.trim().isEmpty ?? true) {
      dienstleisterData['adresse'] = favoritenData['adresse'];
    }
    if ((dienstleisterData['plz'] as String?)?.trim().isEmpty ?? true) {
      dienstleisterData['plz'] = favoritenData['plz'];
    }
    if ((dienstleisterData['ort'] as String?)?.trim().isEmpty ?? true) {
      dienstleisterData['ort'] = favoritenData['ort'];
    }

    final resolvedLogo = _resolveLogoUrl(dienstleisterData);
    if (resolvedLogo.isEmpty) {
      final fallbackLogo = (favoritenData['logoUrl'] as String?)?.trim() ?? '';
      if (fallbackLogo.isNotEmpty) {
        dienstleisterData['logoUrl'] = fallbackLogo;
      }
    } else {
      dienstleisterData['logoUrl'] = resolvedLogo;
    }

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DienstleisterDetailPage(
          dienstleister: dienstleisterData,
          selektierteZielgruppe: 'alle',
          selektierteKategorie: 'alle',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const LoginRegisterPage();
    }

    final favoritenStream = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('favoriten')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: favoritenStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text('Favoriten konnten nicht geladen werden.'),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.favorite_border, size: 52, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Du hast noch keine Favoriten.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Speichere Dienstleister mit dem Herzsymbol, um sie hier schnell wiederzufinden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final dienstleisterId =
                ((data['dienstleisterId'] as String?)?.trim().isNotEmpty ?? false)
                    ? (data['dienstleisterId'] as String).trim()
                    : doc.id;

            final name = (data['name'] as String?)?.trim().isNotEmpty == true
                ? (data['name'] as String).trim()
                : 'Unbekannter Dienstleister';
            final logoUrl = _resolveLogoUrl(data);
            final addressLine = _addressLine(data);

            return Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onTap: () => _openDetailPage(context, dienstleisterId, data),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: logoUrl.isNotEmpty
                      ? Image.network(
                          logoUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 56,
                            height: 56,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.store, color: Colors.grey),
                          ),
                        )
                      : Container(
                          width: 56,
                          height: 56,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.store, color: Colors.grey),
                        ),
                ),
                title: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: addressLine.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          addressLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                trailing: IconButton(
                  icon: const Icon(Icons.favorite, color: Colors.redAccent),
                  onPressed: () => _removeFavorite(
                    kundeId: currentUser.uid,
                    dienstleisterId: dienstleisterId,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
