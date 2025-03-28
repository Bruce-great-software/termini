import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FriseurListPage extends StatelessWidget {
  const FriseurListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friseure')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('branchen')
            .doc('friseure')
            .collection('dienstleister')
            .orderBy('name') // oder createdAt
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final friseure = snapshot.data?.docs ?? [];

          if (friseure.isEmpty) {
            return const Center(child: Text('Keine Friseure gefunden.'));
          }

          return ListView.builder(
            itemCount: friseure.length,
            itemBuilder: (context, index) {
              final data = friseure[index].data() as Map<String, dynamic>;

              return ListTile(
                title: Text(data['name'] ?? 'Kein Name'),
                subtitle: Text(data['adresse'] ?? 'Keine Adresse'),
                trailing: const Icon(Icons.content_cut),
              );
            },
          );
        },
      ),
    );
  }
}
