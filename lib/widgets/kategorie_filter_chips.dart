import 'package:flutter/material.dart';

class KategorieFilterChips extends StatelessWidget {
  final List<String> kategorien;
  final String selectedKategorie;
  final ValueChanged<String> onChanged;

  const KategorieFilterChips({
    super.key,
    required this.kategorien,
    required this.selectedKategorie,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: kategorien.map((kategorie) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(kategorie[0].toUpperCase() + kategorie.substring(1)),
              selected: selectedKategorie == kategorie,
              onSelected: (_) => onChanged(kategorie),
            ),
          );
        }).toList(),
      ),
    );
  }
}