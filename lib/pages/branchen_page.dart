import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BranchenPage extends StatelessWidget {
  const BranchenPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Branchen')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('branchen').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final branchen = snapshot.data?.docs ?? [];

          if (branchen.isEmpty) {
            return const Center(child: Text('Keine Branchen gefunden.'));
          }

          return ListView.builder(
            itemCount: branchen.length,
            itemBuilder: (context, index) {
              final data = branchen[index].data() as Map<String, dynamic>;
              final brancheId = branchen[index].id;
              final name = data['name'] ?? brancheId;

              return ListTile(
                title: Text(name),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // hier später Filter oder Navigation zur Liste
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Branche: $brancheId ausgewählt')),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
