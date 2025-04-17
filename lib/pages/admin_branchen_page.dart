import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_branchen_verwaltung.dart';

class AdminBranchenPage extends StatelessWidget {
  const AdminBranchenPage({super.key});

  Future<Set<String>> _ladeBranchen() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('rolle', isEqualTo: 'dienstleister')
        .get();

    final alleBranchen = snapshot.docs
        .map((doc) => doc['branche']?.toString().toLowerCase())
        .where((branche) => branche != null && branche.isNotEmpty)
        .toSet();

    return alleBranchen.cast<String>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text('Branchen verwalten', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Set<String>>(
              future: _ladeBranchen(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Keine Branchen vorhanden.'));
                }

                final branchen = snapshot.data!.toList()..sort();

                return ListView.builder(
                  itemCount: branchen.length,
                  itemBuilder: (context, index) {
                    final name = branchen[index];
                    return ListTile(
                      title: Text(name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminBranchenVerwaltungPage(branchenId: name),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}