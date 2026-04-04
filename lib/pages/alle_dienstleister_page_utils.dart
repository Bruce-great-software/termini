import 'package:flutter/material.dart';

class AlleDienstleisterPageUtils {
  const AlleDienstleisterPageUtils._();

  static TextSpan buildHighlightedSpan({
    required String fullText,
    required String query,
    TextStyle? baseStyle,
  }) {
    final q = query.trim();
    if (q.isEmpty) {
      return TextSpan(text: fullText, style: baseStyle);
    }

    final lowerText = fullText.toLowerCase();
    final lowerQuery = q.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        if (start < fullText.length) {
          spans.add(TextSpan(text: fullText.substring(start), style: baseStyle));
        }
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: fullText.substring(start, index), style: baseStyle));
      }

      spans.add(
        TextSpan(
          text: fullText.substring(index, index + q.length),
          style: (baseStyle ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.underline,
          ),
        ),
      );
      start = index + q.length;
    }

    return TextSpan(children: spans, style: baseStyle);
  }

  static List<TextSpan> buildHighlightedSpans(String text, String query) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return [TextSpan(text: text)];
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = normalizedQuery.toLowerCase();
    final idx = lowerText.indexOf(lowerQuery);
    if (idx < 0) {
      return [TextSpan(text: text)];
    }

    final before = text.substring(0, idx);
    final match = text.substring(idx, idx + normalizedQuery.length);
    final after = text.substring(idx + normalizedQuery.length);

    return [
      if (before.isNotEmpty) TextSpan(text: before),
      TextSpan(
        text: match,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      if (after.isNotEmpty) TextSpan(text: after),
    ];
  }

  static String buildLocationChipLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    final match = RegExp(r'^\d{4,6}\s+(.+)$').firstMatch(trimmed);
    if (match != null) {
      final cityPart = (match.group(1) ?? '').trim();
      if (cityPart.isNotEmpty) return cityPart;
    }
    return trimmed;
  }

  static bool matchesSelectedLocation({
    required bool isCurrentLocationSelected,
    required String? selectedLocationValue,
    required String? selectedLocationLabel,
    required Map<String, dynamic> data,
  }) {
    if (!isCurrentLocationSelected) return true;

    final rawSelection = (selectedLocationValue ?? selectedLocationLabel ?? '').trim();
    if (rawSelection.isEmpty) return true;

    final normalizedSelection = rawSelection.toLowerCase();
    if (normalizedSelection == 'ganz deutschland') return true;

    final ort = (data['ort'] ?? '').toString().trim().toLowerCase();
    final plz = (data['plz'] ?? '').toString().trim().toLowerCase();
    final adresse = (data['adresse'] ?? '').toString().trim().toLowerCase();

    final match = RegExp(r'^(\d{4,6})\s+(.+)$').firstMatch(normalizedSelection);
    if (match != null) {
      final selectedPlz = (match.group(1) ?? '').trim();
      final selectedOrt = (match.group(2) ?? '').trim();

      final plzPasst = selectedPlz.isEmpty || plz.contains(selectedPlz);
      final ortPasst =
          selectedOrt.isEmpty || ort.contains(selectedOrt) || adresse.contains(selectedOrt);
      return plzPasst && ortPasst;
    }

    return ort.contains(normalizedSelection) ||
        plz.contains(normalizedSelection) ||
        adresse.contains(normalizedSelection);
  }
}
