import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AngeboteView extends StatelessWidget {
  const AngeboteView({
    super.key,
    required this.angeboteStream,
    required this.builder,
    this.emptyText = 'Keine Angebote vorhanden.',
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>> angeboteStream;
  final Widget Function(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) builder;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: angeboteStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (docs.isEmpty) {
          return Center(child: Text(emptyText));
        }

        return builder(context, docs);
      },
    );
  }
}
