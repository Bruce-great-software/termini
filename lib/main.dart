import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:termini/pages/all_places_page.dart';
import 'firebase_options.dart';
import 'pages/alle_dienstleister_page.dart';
import 'pages/dienstleister_main_page.dart';
import 'pages/admin_page.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _handleStart() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const AlleDienstleisterPage();
    }

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = userDoc.data();
    final rolle = data?['rolle'];
    final dienstleisterId = data?['dienstleisterId'];
    final branche = data?['branche'];

    if (rolle == 'admin') {
      return const AlleDienstleisterPage();
    } else if (rolle == 'dienstleister' && dienstleisterId != null && branche != null) {
      return DienstleisterMainPage(
        branche: branche,
        dienstleisterId: dienstleisterId,
      );
    } else {
      return const AlleDienstleisterPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Termini',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: FutureBuilder(
        future: _handleStart(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            return const Scaffold(
              body: Center(child: Text('Fehler beim Laden.')),
            );
          } else {
            return snapshot.data as Widget;
          }
        },
      ),
    );
  }
}
