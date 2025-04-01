import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:termini/pages/alle_dienstleister_page.dart';
import 'package:termini/pages/branchen_page.dart';
import 'firebase_options.dart';
import 'pages/friseur_list_page.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termini',
      debugShowCheckedModeBanner: false,
      home: const AlleDienstleisterPage(), // ← Zeigt die Friseur-Liste an
    );
  }
}
