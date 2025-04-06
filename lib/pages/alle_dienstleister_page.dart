import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dienstleister_detail_page.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';
import '../services/location_service.dart';


class AlleDienstleisterPage extends StatefulWidget {
  const AlleDienstleisterPage({super.key});

  @override
  State<AlleDienstleisterPage> createState() => _AlleDienstleisterPageState();
}

class _AlleDienstleisterPageState extends State<AlleDienstleisterPage> with WidgetsBindingObserver {
  Position? userPosition;
  bool isLoading = true;

  final List<String> kategorien = ['Alle', 'friseure', 'kosmetiker', 'massagen'];
  String selectedKategorie = 'Alle';

  final List<String> unterkategorien = ['Alle', 'Damen', 'Herren', 'Kinder'];
  String selectedUnterkategorie = 'Alle';

  String selectedHauptLeistung = 'Alle';
  List<String> kategorienAusFirebase = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initLocation();
    }
  }

  Future<void> _initLocation() async {
    setState(() => isLoading = true);
    userPosition = await LocationService.initLocation(
      context: context,
      onExitApp: () => SystemChannels.platform.invokeMethod('SystemNavigator.pop'),
      onOpenAppSettings: () => AppSettings.openAppSettings(),
    );
    setState(() => isLoading = false);
  }


  void aktualisiereKategorienAusFirebase(List<Map<String, dynamic>> alleDienstleister) {
    kategorienAusFirebase = [];
    if (selectedUnterkategorie != 'Alle') {
      for (var e in alleDienstleister) {
        final passtZurKategorie = selectedKategorie == 'Alle' || e['branche'] == selectedKategorie;
        final passtZurUnterkategorie = e['zielgruppen'] != null &&
            (e['zielgruppen'] as List).contains(selectedUnterkategorie.toLowerCase());
        if (passtZurKategorie && passtZurUnterkategorie) {
          final leistungen = e['leistungen'];
          if (leistungen != null && leistungen[selectedUnterkategorie.toLowerCase()] != null) {
            final map = leistungen[selectedUnterkategorie.toLowerCase()] as Map<String, dynamic>;
            for (var key in map.keys) {
              if (!kategorienAusFirebase.contains(key)) {
                kategorienAusFirebase.add(key);
              }
            }
          }
        }
      }
    }
  }

  void oeffneDienstleisterDetails(Map<String, dynamic> dienstleister) {
    final zielgruppe = selectedUnterkategorie.toLowerCase();
    final kategorie = selectedHauptLeistung.toLowerCase();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DienstleisterDetailPage(
          dienstleister: dienstleister,
          selektierteZielgruppe: zielgruppe,
          selektierteKategorie: kategorie,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || userPosition == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dienstleister')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collectionGroup('dienstleister').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final dienstleisterGesamt = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            data['branche'] = doc.reference.parent.parent?.id;

            if (data['geo'] != null) {
              final geo = data['geo'];
              final distanceInMeters = Geolocator.distanceBetween(
                userPosition!.latitude,
                userPosition!.longitude,
                geo.latitude,
                geo.longitude,
              );
              data['distance'] = distanceInMeters / 1000;
            }

            return data;
          }).toList();

          final gefiltert = dienstleisterGesamt.where((e) {
            final passtZurKategorie = selectedKategorie == 'Alle' || e['branche'] == selectedKategorie;
            final passtZurUnterkategorie = selectedUnterkategorie == 'Alle' ||
                (e['zielgruppen'] != null &&
                    (e['zielgruppen'] as List).contains(selectedUnterkategorie.toLowerCase()));
            final passtZurLeistung = selectedHauptLeistung == 'Alle' ||
                (e['leistungen'] != null &&
                    e['leistungen'][selectedUnterkategorie.toLowerCase()] != null &&
                    (e['leistungen'][selectedUnterkategorie.toLowerCase()] as Map<String, dynamic>)
                        .containsKey(selectedHauptLeistung.toLowerCase()));
            return passtZurKategorie && passtZurUnterkategorie && passtZurLeistung;
          }).toList();

          final basisGefiltert = dienstleisterGesamt.where((e) {
            final passtZurKategorie = selectedKategorie == 'Alle' || e['branche'] == selectedKategorie;
            final passtZurUnterkategorie = selectedUnterkategorie == 'Alle' ||
                (e['zielgruppen'] != null &&
                    (e['zielgruppen'] as List).contains(selectedUnterkategorie.toLowerCase()));
            return passtZurKategorie && passtZurUnterkategorie;
          }).toList();

          aktualisiereKategorienAusFirebase(basisGefiltert);

          return Column(
            children: [
              // Kategorie-Filter
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
                            selectedUnterkategorie = 'Alle';
                            selectedHauptLeistung = 'Alle';
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              // Zielgruppen-Filter
              if (selectedKategorie == 'friseure')
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: unterkategorien.map((option) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(option),
                          selected: selectedUnterkategorie == option,
                          onSelected: (_) {
                            setState(() {
                              selectedUnterkategorie = option;
                              selectedHauptLeistung = 'Alle';
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              // Leistungen-Filter
              if (kategorienAusFirebase.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: kategorienAusFirebase.map((kategorie) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(kategorie[0].toUpperCase() + kategorie.substring(1)),
                          selected: selectedHauptLeistung == kategorie,
                          onSelected: (_) {
                            setState(() {
                              selectedHauptLeistung = kategorie;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              // Dienstleister-Liste
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
                        '${data['adresse'] ?? 'Keine Adresse'}, ${data['plz'] ?? ''} ${data['ort'] ?? ''}',
                      ),
                      isThreeLine: true,
                      trailing: distance != null
                          ? Text('${distance.toStringAsFixed(1)} km')
                          : const Text('—'),
                      onTap: () => oeffneDienstleisterDetails(data),
                    );
                  },
                ),
              )
            ],
          );
        },
      ),
    );
  }
}
