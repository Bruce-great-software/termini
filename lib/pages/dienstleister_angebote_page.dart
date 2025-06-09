import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DienstleisterAngebotePage extends StatelessWidget {
  const DienstleisterAngebotePage({super.key});

  @override
  Widget build(BuildContext context) {
    final String? dienstleisterId = FirebaseAuth.instance.currentUser?.uid;

    if (dienstleisterId == null) {
      return const Center(child: Text('Nicht eingeloggt'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Leistungen')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('angebote')
            .where('dienstleisterId', isEqualTo: dienstleisterId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Noch keine Leistungen erstellt.'));
          }

          final angebote = snapshot.data!.docs;

          return ListView.builder(
            itemCount: angebote.length,
            itemBuilder: (context, index) {
              final data = angebote[index].data() as Map<String, dynamic>;

              return ListTile(
                title: Text(data['titel'] ?? 'Kein Titel'),
                subtitle: Text("Kategorie: ${data['kategorie']}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    FirebaseFirestore.instance
                        .collection('angebote')
                        .doc(angebote[index].id)
                        .delete();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
