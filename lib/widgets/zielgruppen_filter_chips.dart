import 'package:flutter/material.dart';

class ZielgruppenFilterChips extends StatelessWidget {
  final List<String> zielgruppen;
  final String selectedZielgruppe;
  final ValueChanged<String> onChanged;

  const ZielgruppenFilterChips({
    super.key,
    required this.zielgruppen,
    required this.selectedZielgruppe,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: zielgruppen.map((zielgruppe) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(zielgruppe),
              selected: selectedZielgruppe == zielgruppe,
              onSelected: (_) => onChanged(zielgruppe),
            ),
          );
        }).toList(),
      ),
    );
  }
}
