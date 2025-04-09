import 'package:flutter/material.dart';

class DienstleisterHomePage extends StatelessWidget {
  const DienstleisterHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dienstleister Home')),
      body: const Center(child: Text('Willkommen beim Dienstleister-Dashboard!')),
    );
  }
}
