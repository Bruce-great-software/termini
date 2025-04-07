import 'package:flutter/material.dart';

class DienstleisterTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const DienstleisterTile({
    super.key,
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final distance = data['distance'];
    final logoUrl = data['logoUrl']; // ← Stelle sicher, dass dieses Feld in Firestore vorhanden ist

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Logo links
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: logoUrl != null
                    ? Image.network(
                  logoUrl,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                )
                    : Container(
                  width: 60,
                  height: 60,
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.store, size: 30, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 12),
              // Name, Adresse, Entfernung
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name'] ?? 'Kein Name',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${data['adresse'] ?? 'Keine Adresse'}, ${data['plz'] ?? ''} ${data['ort'] ?? ''}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    if (distance != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${distance.toStringAsFixed(1)} km entfernt',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
