class FilterHelper {
  /// Gibt alle Leistungskategorien zurück, die zur ausgewählten Kategorie + Zielgruppe passen.
  static List<String> getLeistungskategorien({
    required List<Map<String, dynamic>> alleDienstleister,
    required String selectedKategorie,
    required String selectedUnterkategorie,
  }) {
    final List<String> kategorien = [];

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
              if (!kategorien.contains(key)) {
                kategorien.add(key);
              }
            }
          }
        }
      }
    }

    return kategorien;
  }
}
