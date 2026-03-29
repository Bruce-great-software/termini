import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class DienstleisterBilderPage extends StatefulWidget {
  const DienstleisterBilderPage({super.key});

  @override
  State<DienstleisterBilderPage> createState() => _DienstleisterBilderPageState();
}

class _DienstleisterBilderPageState extends State<DienstleisterBilderPage> {
  bool _isUploading = false;

  Future<void> _bildHinzufuegen() async {
    if (_isUploading) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht eingeloggt.')),
      );
      return;
    }

    try {
      setState(() => _isUploading = true);

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        return;
      }

      final bytes = await pickedFile.readAsBytes();
      if (bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Das ausgewählte Bild ist leer.')),
        );
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'dienstleister_gallery/${user.uid}/$timestamp.jpg';
      final ref = FirebaseStorage.instance.ref().child(path);

      await ref.putData(bytes);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bilder')
          .add({
        'url': url,
        'path': path,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bild erfolgreich hochgeladen.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Hochladen: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _bildLoeschen({
    required String dokumentId,
    required String path,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (path.trim().isNotEmpty) {
        await FirebaseStorage.instance.ref().child(path).delete();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bilder')
          .doc(dokumentId)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bild gelöscht.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Löschen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Nicht eingeloggt.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bilder')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bilder',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Lade Fotos deines Salons hoch. Diese Bilder können später Kunden angezeigt werden.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _isUploading ? null : _bildHinzufuegen,
                        icon: _isUploading
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(_isUploading ? 'Lädt...' : 'Bild hinzufügen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (snapshot.hasError)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Bilder konnten nicht geladen werden.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    )
                  else if (docs.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white,
                        ),
                        child: const Text(
                          'Noch keine Bilder vorhanden. Füge dein erstes Bild hinzu.',
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final crossAxisCount = width >= 1100
                              ? 4
                              : width >= 780
                              ? 3
                              : width >= 520
                              ? 2
                              : 1;

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1,
                            ),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data();
                              final imageUrl = (data['url'] ?? '').toString().trim();
                              final path = (data['path'] ?? '').toString().trim();

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Container(color: const Color(0xFFF3F4F6)),
                                    if (imageUrl.isNotEmpty)
                                      Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                        const Center(
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            color: Colors.black45,
                                          ),
                                        ),
                                      )
                                    else
                                      const Center(
                                        child: Icon(
                                          Icons.image_not_supported_outlined,
                                          color: Colors.black45,
                                        ),
                                      ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Material(
                                        color: const Color(0xB3000000),
                                        borderRadius: BorderRadius.circular(20),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(20),
                                          onTap: () => _bildLoeschen(
                                            dokumentId: doc.id,
                                            path: path,
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Icon(
                                              Icons.delete_outline,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}