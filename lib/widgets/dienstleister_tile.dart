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

    return ListTile(
      title: Text(data['name'] ?? 'Kein Name'),
      subtitle: Text(
        '${data['adresse'] ?? 'Keine Adresse'}, ${data['plz'] ?? ''} ${data['ort'] ?? ''}',
      ),
      isThreeLine: true,
      trailing: distance != null
          ? Text('${distance.toStringAsFixed(1)} km')
          : const Text('—'),
      onTap: onTap,
    );
  }
}