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

  final List<String> kategorien = ['Alle', 'friseure', 'kosmetiker', 'massagen'];
  String selectedKategorie = 'Alle';

  final List<String> unterkategorien = ['Alle', 'Damen', 'Herren', 'Kinder'];
  String selectedUnterkategorie = 'Alle';

  String selectedHauptLeistung = 'Alle';
  List<String> kategorienAusFirebase = [];

  Map<String, dynamic>? geoeffneterDienstleister;

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
      body: geoeffneterDienstleister != null
          ? DienstleisterDetailPage(
        dienstleister: geoeffneterDienstleister!,
        selektierteZielgruppe: selectedUnterkategorie.toLowerCase(),
        selektierteKategorie: selectedHauptLeistung.toLowerCase(),
      )
          : _buildBodyByIndex(_selectedIndex),
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
        return dienstleisterListeView();
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

  Widget dienstleisterListeView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .snapshots(),  // Hier verwenden wir snapshots() statt get()
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final dienstleisterListe = snapshot.data!.docs.map((doc) {
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

          return data;
        }).toList();

        dienstleisterListe.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

        final gefiltert = dienstleisterListe; // Hier kannst du später weitere Filter einbauen

        return ListView.builder(
          itemCount: gefiltert.length,
          itemBuilder: (context, index) {
            final data = gefiltert[index];
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
  }

}