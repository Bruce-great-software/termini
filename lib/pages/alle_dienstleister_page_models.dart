import 'package:flutter/material.dart';

/// Sortierreihenfolge für Preise / Distanz
/// Wird bewusst ausgelagert, damit die Page nur noch Rendering-Logik enthält.
enum SortOrder { none, priceAsc, priceDesc, distanceAsc }

enum SuggestionType { leistung, dienstleister }

class SearchSuggestion {
  final SuggestionType type;
  final String title;
  final String subtitle;
  final String? dienstleisterId;
  final String? logoUrl;

  const SearchSuggestion.leistung(this.title)
      : type = SuggestionType.leistung,
        subtitle = '',
        dienstleisterId = null,
        logoUrl = null;

  const SearchSuggestion.dienstleister({
    required this.title,
    required this.subtitle,
    required this.dienstleisterId,
    required this.logoUrl,
  }) : type = SuggestionType.dienstleister;
}

enum LocationSuggestionType { currentLocation, countryWide, ort }

class LocationSuggestion {
  final LocationSuggestionType type;
  final String label;
  final String fillValue;

  const LocationSuggestion._({
    required this.type,
    required this.label,
    required this.fillValue,
  });

  factory LocationSuggestion.currentLocation(String city) {
    final trimmedCity = city.trim();
    return LocationSuggestion._(
      type: LocationSuggestionType.currentLocation,
      label: 'Aktueller Standort',
      fillValue: trimmedCity.isNotEmpty ? trimmedCity : 'Aktueller Standort',
    );
  }

  const LocationSuggestion.countryWide()
      : this._(
          type: LocationSuggestionType.countryWide,
          label: 'Ganz Deutschland',
          fillValue: 'Ganz Deutschland',
        );

  factory LocationSuggestion.ort(String value) => LocationSuggestion._(
        type: LocationSuggestionType.ort,
        label: value,
        fillValue: value,
      );
}
