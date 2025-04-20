import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/location_service.dart';
import '../widgets/dienstleister_tile.dart';
import 'dienstleister_detail_page.dart';
import 'login_register_page.dart';
import 'kunden_profil_page.dart';

class AlleDienstleisterPage extends StatefulWidget {
  const AlleDienstleisterPage({super.key});

  @override
  State<AlleDienstleisterPage> createState() => _AlleDienstleisterPageState();
}

class _AlleDienstleisterPageState extends State<AlleDienstleisterPage> with WidgetsBindingObserver {
  Position? userPosition;
  bool isLoading = true;

  int _selectedIndex = 0;

  List<String> verfuegbareBranchen = [];
  List<String> ausgewaehlteBranchen = [];

  List<String> verfuegbareZielgruppen = [];
  List<String> ausgewaehlteZielgruppen = [];

  List<String> verfuegbareKategorien = [];
  List<String> ausgewaehlteKategorien = [];

  bool filterChipOffen = false;

  Map<String, dynamic>? geoeffneterDienstleister;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
    _ladeBranchen();
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

  Future<void> _ladeBranchen() async {
    final snapshot = await FirebaseFirestore.instance.collection('branchen').get();
    final alleBranchen = snapshot.docs.map((doc) => doc.id).toList();
    setState(() {
      verfuegbareBranchen = alleBranchen;
    });
  }

  Future<void> _ladeZielgruppenUndKategorien() async {
    if (ausgewaehlteBranchen.isEmpty) {
      setState(() {
        verfuegbareZielgruppen = [];
        verfuegbareKategorien = [];
      });
      return;
    }

    final doc = await FirebaseFirestore.instance.collection('branchen').doc(ausgewaehlteBranchen.first).get();
    final data = doc.data();
    if (data == null || !data.containsKey('zielgruppen')) return;

    final zielgruppenMap = Map<String, dynamic>.from(data['zielgruppen']);
    final zielgruppen = zielgruppenMap.keys.toList();

    setState(() {
      verfuegbareZielgruppen = zielgruppen;
      verfuegbareKategorien = [];
      ausgewaehlteZielgruppen = [];
      ausgewaehlteKategorien = [];
    });
  }

  Future<void> _ladeKategorienZuZielgruppe(String zielgruppe) async {
    final doc = await FirebaseFirestore.instance.collection('branchen').doc(ausgewaehlteBranchen.first).get();
    final data = doc.data();
    if (data == null || !data.containsKey('zielgruppen')) return;

    final zielgruppenMap = Map<String, dynamic>.from(data['zielgruppen']);
    final kategorieMap = zielgruppenMap[zielgruppe]['leistungskategorien'] as Map<String, dynamic>;
    final kategorien = kategorieMap.keys.toList();

    setState(() {
      verfuegbareKategorien = kategorien;
      ausgewaehlteKategorien = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || userPosition == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dienstleister'),
        leading: geoeffneterDienstleister != null
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              geoeffneterDienstleister = null;
            });
          },
        )
            : null,
      ),
      body: _buildBodyByIndex(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            geoeffneterDienstleister = null;
            _selectedIndex = index;
          });
        },
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        backgroundColor: Colors.white,
        elevation: 8,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Suchen'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_border), label: 'Favoriten'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Termine'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }

  Widget _buildBodyByIndex(int index) {
    switch (index) {
      case 0:
        return geoeffneterDienstleister != null
            ? DienstleisterDetailPage(
          dienstleister: geoeffneterDienstleister!,
          selektierteZielgruppe: 'alle',
          selektierteKategorie: 'alle',
        )
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(),
                      ],
                    ),
                  ),
                  if (filterChipOffen)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildChipReihe(verfuegbareBranchen, ausgewaehlteBranchen, (branche) {
                          setState(() {
                            ausgewaehlteBranchen = [branche];
                            _ladeZielgruppenUndKategorien();
                          });
                        }),
                        _buildChipReihe(verfuegbareZielgruppen, ausgewaehlteZielgruppen, (zielgruppe) {
                          setState(() {
                            ausgewaehlteZielgruppen = [zielgruppe];
                            _ladeKategorienZuZielgruppe(zielgruppe);
                          });
                        }),
                        _buildChipReihe(verfuegbareKategorien, ausgewaehlteKategorien, (kategorie) {
                          setState(() {
                            if (ausgewaehlteKategorien.contains(kategorie)) {
                              ausgewaehlteKategorien.remove(kategorie);
                            } else {
                              ausgewaehlteKategorien.add(kategorie);
                            }
                          });
                        }),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(child: dienstleisterListeView()),
          ],
        );
      case 1:
        return const Center(child: Text('Favoriten kommen bald!'));
      case 2:
        return const Center(child: Text('Buchungen kommen bald!'));
      case 3:
        final user = FirebaseAuth.instance.currentUser;
        return user == null ? const LoginRegisterPage() : const KundenProfilPage();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFilterChip() {
    return GestureDetector(
      onTap: () => setState(() => filterChipOffen = !filterChipOffen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: const [
            Icon(Icons.filter_list, size: 20),
            SizedBox(width: 4),
            Text('Filter'),
          ],
        ),
      ),
    );
  }

  Widget _buildChipReihe(List<String> items, List<String> selectedItems, Function(String) onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((item) {
            final selected = selectedItems.contains(item);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                label: Text(
                  items == verfuegbareBranchen ? '${item[0].toUpperCase()}${item.substring(1)}' : item,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    if (selected) {
                      selectedItems.remove(item);
                      if (items == verfuegbareBranchen) {
                        ausgewaehlteZielgruppen.clear();
                        ausgewaehlteKategorien.clear();
                        verfuegbareZielgruppen.clear();
                        verfuegbareKategorien.clear();
                      } else if (items == verfuegbareZielgruppen) {
                        ausgewaehlteKategorien.clear();
                        verfuegbareKategorien.clear();
                      }
                    } else {
                      if (items == verfuegbareBranchen) {
                        selectedItems.clear();
                        selectedItems.add(item);
                        _ladeZielgruppenUndKategorien();
                      } else if (items == verfuegbareZielgruppen) {
                        selectedItems.clear();
                        selectedItems.add(item);
                        if (ausgewaehlteBranchen.isNotEmpty) {
                          _ladeKategorienZuZielgruppe(item);
                        }
                      } else {
                        selectedItems.add(item);
                      }
                    }
                  });
                },
                selectedColor: Colors.green,
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: Colors.black,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget dienstleisterListeView() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final List<Map<String, dynamic>> dienstleisterMitLeistungen = [];
        final docs = snapshot.data!.docs;

        return FutureBuilder(
          future: Future.wait(docs.map((doc) async {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;

            if (data['geo'] != null) {
              final geo = data['geo'] as GeoPoint;
              final distanceInMeters = Geolocator.distanceBetween(
                userPosition!.latitude,
                userPosition!.longitude,
                geo.latitude,
                geo.longitude,
              );
              data['distance'] = distanceInMeters / 1000;
            } else {
              data['distance'] = double.infinity;
            }

            final leistungenSnap = await FirebaseFirestore.instance
                .collection('users')
                .doc(doc.id)
                .collection('leistungen')
                .get();

            final leistungen = leistungenSnap.docs.map((l) => l.data()).toList();
            data['leistungen'] = leistungen;

            final branche = data['branche']?.toString();
            final zielgruppen = leistungen.map((l) => l['zielgruppe']?.toString()).toSet();
            final kategorien = leistungen.map((l) => l['kategorie']?.toString()).toSet();

            final branchePasst = ausgewaehlteBranchen.isEmpty || ausgewaehlteBranchen.contains(branche);
            final zielgruppePasst = ausgewaehlteZielgruppen.isEmpty || zielgruppen.any(ausgewaehlteZielgruppen.contains);
            final kategoriePasst = ausgewaehlteKategorien.isEmpty || kategorien.any(ausgewaehlteKategorien.contains);

            if (branchePasst && zielgruppePasst && kategoriePasst) {
              dienstleisterMitLeistungen.add(data);
            }
          })),
          builder: (context, AsyncSnapshot<List<void>> snapshot2) {
            if (snapshot2.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            dienstleisterMitLeistungen.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

            return ListView.builder(
              itemCount: dienstleisterMitLeistungen.length,
              itemBuilder: (context, index) {
                final data = dienstleisterMitLeistungen[index];
                return DienstleisterTile(
                  data: data,
                  onTap: () {
                    setState(() {
                      geoeffneterDienstleister = data;
                    });
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
