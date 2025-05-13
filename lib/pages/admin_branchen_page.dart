import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_branchen_verwaltung.dart';

class AdminBranchenPage extends StatelessWidget {
  const AdminBranchenPage({super.key});

  Future<void> _neueBrancheDialog(BuildContext context) async {
    String neueBranche = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Neue Branche hinzufügen'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Branchenname'),
          onChanged: (value) => neueBranche = value.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (neueBranche.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('branchen')
                    .doc(neueBranche.toLowerCase())
                    .set({'name': neueBranche});
              }
              Navigator.pop(context);
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
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
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('branchen').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Keine Branchen vorhanden.'));
                }

                final docs = snapshot.data!.docs;

                // Fallback-Sortierung nach name oder id
                docs.sort((a, b) {
                  final aName = a.data()!.toString().contains('name') ? a['name'] : a.id;
                  final bName = b.data()!.toString().contains('name') ? b['name'] : b.id;
                  return aName.compareTo(bName);
                });

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data.containsKey('name') ? data['name'] : doc.id;
                    final aktiv = data['aktiv'] ?? true;


                    return ListTile(
                      title: Text(
                        name[0].toUpperCase() + name.substring(1),
                        style: const TextStyle(fontSize: 16),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: aktiv,
                            onChanged: (value) {
                              FirebaseFirestore.instance
                                  .collection('branchen')
                                  .doc(doc.id)
                                  .update({'aktiv': value});
                            },
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminBranchenVerwaltungPage(branchenId: doc.id),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _neueBrancheDialog(context),
        child: const Icon(Icons.add),
        tooltip: 'Neue Branche hinzufügen',
      ),
    );
  }
}
