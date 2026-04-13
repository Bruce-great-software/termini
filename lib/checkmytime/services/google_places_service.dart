import 'dart:convert';

import 'package:http/http.dart' as http;

class GooglePlacesService {
  GooglePlacesService._();

  static final GooglePlacesService instance = GooglePlacesService._();

  static const String _apiKey = 'AIzaSyCCQtsYRGUDMsRLemzsZ8QQ99_Vg6rbIm0';

  static const String _autocompleteUrl =
      'https://places.googleapis.com/v1/places:autocomplete';
  static const String _detailsBaseUrl =
      'https://places.googleapis.com/v1/places';

  Future<List<GooglePlaceSuggestion>> fetchAutocomplete({
    required String input,
    String? sessionToken,
  }) async {
    final query = input.trim();
    if (query.length < 2) return const [];

    try {
      final response = await http.post(
        Uri.parse(_autocompleteUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,

          // Zum Testen bewusst * damit keine falsche FieldMask blockiert.
          'X-Goog-FieldMask': '*',
        },
        body: json.encode({
          'input': query,
          'languageCode': 'de',
          'includedRegionCodes': ['DE'],
          if (sessionToken != null && sessionToken.isNotEmpty)
            'sessionToken': sessionToken,
        }),
      );

      print('Places Autocomplete Status: ${response.statusCode}');
      print('Places Autocomplete Body: ${response.body}');

      if (response.statusCode != 200) {
        return const [];
      }

      final data = json.decode(response.body);
      if (data is! Map) return const [];

      final map = Map<String, dynamic>.from(data as Map);
      final suggestions = (map['suggestions'] as List?) ?? const [];

      return suggestions
          .map(
            (item) => GooglePlaceSuggestion.fromNewApiJson(
          item is Map<String, dynamic>
              ? item
              : Map<String, dynamic>.from(item as Map),
        ),
      )
          .where((item) => item.placeId.isNotEmpty)
          .toList();
    } catch (e) {
      print('Places Autocomplete Exception: $e');
      return const [];
    }
  }

  Future<GooglePlaceDetails?> fetchPlaceDetails({
    required String placeId,
    String? sessionToken,
  }) async {
    final normalizedPlaceId = placeId.trim();
    if (normalizedPlaceId.isEmpty) return null;

    try {
      final uri = Uri.parse(
        '$_detailsBaseUrl/$normalizedPlaceId'
            '?languageCode=de'
            '${sessionToken == null || sessionToken.isEmpty ? '' : '&sessionToken=$sessionToken'}',
      );

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,

          // Ebenfalls bewusst * zum Testen.
          'X-Goog-FieldMask': '*',
        },
      );

      print('Place Details Status: ${response.statusCode}');
      print('Place Details Body: ${response.body}');

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body);
      if (data is! Map) return null;

      return GooglePlaceDetails.fromNewApiJson(
        Map<String, dynamic>.from(data as Map),
      );
    } catch (e) {
      print('Place Details Exception: $e');
      return null;
    }
  }
}

class GooglePlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  const GooglePlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory GooglePlaceSuggestion.fromNewApiJson(Map<String, dynamic> json) {
    final placePrediction = _asMap(json['placePrediction']);
    final textMap = _asMap(placePrediction['text']);
    final structured = _asMap(placePrediction['structuredFormat']);
    final mainTextMap = _asMap(structured['mainText']);
    final secondaryTextMap = _asMap(structured['secondaryText']);

    final description = (textMap['text'] ?? '').toString().trim();
    final mainText = (mainTextMap['text'] ?? description).toString().trim();
    final secondaryText =
    (secondaryTextMap['text'] ?? '').toString().trim();

    return GooglePlaceSuggestion(
      placeId: (placePrediction['placeId'] ?? '').toString().trim(),
      description: description,
      mainText: mainText.isEmpty ? description : mainText,
      secondaryText: secondaryText,
    );
  }
}

class GooglePlaceDetails {
  final String placeId;
  final String name;
  final String formattedAddress;
  final double? latitude;
  final double? longitude;
  final String city;
  final String postalCode;
  final String country;
  final String street;
  final String streetNumber;

  const GooglePlaceDetails({
    required this.placeId,
    required this.name,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.postalCode,
    required this.country,
    required this.street,
    required this.streetNumber,
  });

  factory GooglePlaceDetails.fromNewApiJson(Map<String, dynamic> json) {
    final locationMap = _asMap(json['location']);
    final displayNameMap = _asMap(json['displayName']);

    final addressComponents =
        (json['addressComponents'] as List?)?.whereType<Object>().toList() ??
            const <Object>[];

    String street = '';
    String streetNumber = '';
    String postalCode = '';
    String city = '';
    String country = '';

    for (final component in addressComponents) {
      final componentMap = _asMap(component);
      final types = (componentMap['types'] as List?)
          ?.map((item) => item.toString())
          .toList() ??
          const <String>[];

      final longText = _extractComponentText(componentMap['longText']);
      final shortText = _extractComponentText(componentMap['shortText']);
      final value = longText.isNotEmpty ? longText : shortText;

      if (types.contains('route')) {
        street = value;
      } else if (types.contains('street_number')) {
        streetNumber = value;
      } else if (types.contains('postal_code')) {
        postalCode = value;
      } else if (types.contains('locality') ||
          types.contains('postal_town') ||
          types.contains('administrative_area_level_3')) {
        city = value;
      } else if (types.contains('country')) {
        country = value;
      }
    }

    return GooglePlaceDetails(
      placeId: (json['id'] ?? '').toString().trim(),
      name: (displayNameMap['text'] ?? '').toString().trim(),
      formattedAddress: (json['formattedAddress'] ?? '').toString().trim(),
      latitude: _toDouble(locationMap['latitude']),
      longitude: _toDouble(locationMap['longitude']),
      city: city,
      postalCode: postalCode,
      country: country,
      street: street,
      streetNumber: streetNumber,
    );
  }

  String get displayText {
    if (name.isNotEmpty) return name;
    if (formattedAddress.isNotEmpty) return formattedAddress;
    return '';
  }

  String get streetLine {
    return [street, streetNumber]
        .where((part) => part.trim().isNotEmpty)
        .join(' ')
        .trim();
  }

  GooglePlaceDetails copyWith({
    String? placeId,
    String? name,
    String? formattedAddress,
    double? latitude,
    double? longitude,
    String? city,
    String? postalCode,
    String? country,
    String? street,
    String? streetNumber,
  }) {
    return GooglePlaceDetails(
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      street: street ?? this.street,
      streetNumber: streetNumber ?? this.streetNumber,
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

String _extractComponentText(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();

  final map = _asMap(value);
  return (map['text'] ?? '').toString().trim();
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}