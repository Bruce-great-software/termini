import 'package:flutter/material.dart';

class LeistungsFilterChips extends StatelessWidget {
  final List<String> leistungskategorien;
  final String selectedLeistung;
  final ValueChanged<String> onChanged;

  const LeistungsFilterChips({
    super.key,
    required this.leistungskategorien,
    required this.selectedLeistung,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: leistungskategorien.map((kategorie) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(kategorie[0].toUpperCase() + kategorie.substring(1)),
              selected: selectedLeistung == kategorie,
              onSelected: (_) => onChanged(kategorie),
            ),
          );
        }).toList(),
      ),
    );
  }
}
