import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class AlleDienstleisterPage extends StatefulWidget {
  const AlleDienstleisterPage({super.key});

  @override
  State<AlleDienstleisterPage> createState() => _AlleDienstleisterPageState();
}

class _AlleDienstleisterPageState extends State<AlleDienstleisterPage> {
  List<Map<String, dynamic>> alleDienstleister = [];
  bool isLoading = true;
  Position? userPosition;

  final List<String> kategorien = ['Alle', 'friseure', 'kosmetiker', 'massagen'];
  String selectedKategorie = 'Alle';

  @override
  void initState() {
    super.initState();
    ladeAlleDienstleister();
  }

  Future<void> ladeAlleDienstleister() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => isLoading = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => isLoading = false);
      return;
    }

    userPosition = await Geolocator.getCurrentPosition();

    final branchenSnapshot = await FirebaseFirestore.instance.collection('branchen').get();
    List<Map<String, dynamic>> dienstleisterGesamt = [];

    for (var branche in branchenSnapshot.docs) {
      final brancheId = branche.id;
      final dienstleisterSnapshot = await FirebaseFirestore.instance
          .collection('branchen')
          .doc(brancheId)
          .collection('dienstleister')
          .get();

      for (var doc in dienstleisterSnapshot.docs) {
        final data = doc.data();
        data['branche'] = brancheId;

        if (data['geo'] != null && userPosition != null) {
          final geo = data['geo'];
          final distanceInMeters = Geolocator.distanceBetween(
            userPosition!.latitude,
            userPosition!.longitude,
            geo.latitude,
            geo.longitude,
          );
          data['distance'] = distanceInMeters / 1000;
        }

        dienstleisterGesamt.add(data);
      }
    }

    dienstleisterGesamt.sort((a, b) => (a['distance'] ?? 99999).compareTo(b['distance'] ?? 99999));

    setState(() {
      alleDienstleister = dienstleisterGesamt;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gefiltert = alleDienstleister.where((e) {
      if (selectedKategorie == 'Alle') return true;
      return e['branche'] == selectedKategorie;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Dienstleister')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Row(
              children: kategorien.map((kategorie) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(kategorie[0].toUpperCase() + kategorie.substring(1)),
                    selected: selectedKategorie == kategorie,
                    onSelected: (_) {
                      setState(() {
                        selectedKategorie = kategorie;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: gefiltert.isEmpty
                ? const Center(child: Text('Keine Dienstleister gefunden.'))
                : ListView.builder(
              itemCount: gefiltert.length,
              itemBuilder: (context, index) {
                final data = gefiltert[index];
                final distance = data['distance'];

                return ListTile(
                  title: Text(data['name'] ?? 'Kein Name'),
                  subtitle: Text(
                    '${data['adresse'] ?? 'Keine Adresse'}, '
                        '${data['plz'] ?? ''} ${data['ort'] ?? ''}',
                  ),
                  isThreeLine: true,
                  trailing: distance != null
                      ? Text('${distance.toStringAsFixed(1)} km')
                      : const Text('—'),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
