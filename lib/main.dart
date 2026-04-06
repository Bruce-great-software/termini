import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:termini/pages/all_places_page.dart';
import 'package:termini/checkmytime/pages/home_page.dart';
import 'firebase_options.dart';
import 'pages/alle_dienstleister_page.dart';
import 'pages/dienstleister_main_page.dart';
import 'pages/admin_page.dart';

import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await initializeDateFormatting('de_DE');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _handleStart() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const AlleDienstleisterPage();
    }

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = userDoc.data();
    final rolle = data?['rolle'];
    final dienstleisterId = data?['dienstleisterId'];
    final branche = data?['branche'];

    if (rolle == 'admin') {
      return const AlleDienstleisterPage();
    } else if ((rolle == 'dienstleister' || rolle == 'mitarbeiter') &&
        (dienstleisterId != null || rolle == 'mitarbeiter') &&
        branche != null) {
      return DienstleisterMainPage(
        branche: branche,
        dienstleisterId: (dienstleisterId ?? user.uid) as String,
      );
    } else {
      return const CheckMyTimeHomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF061F73),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Termini',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FC),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: colorScheme.surface,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide(color: colorScheme.outlineVariant),
          labelStyle: TextStyle(color: colorScheme.onSurface),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(height: 1.4),
        ),
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
