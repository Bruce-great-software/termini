import 'dart:math' as math; // für Chunking bei arrayContainsAny (<=10)
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';

import '../services/location_service.dart';
import '../widgets/dienstleister_tile.dart';
import 'dienstleister_detail_page.dart';
import 'kunden_favoriten_page.dart';
import 'kunden_termine_page.dart';
import 'login_register_page.dart';
import 'kunden_profil_page.dart';
import 'package:http/http.dart' as http;
import 'partner_werden_page.dart';

import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sortierreihenfolge für Preise / Distanz
enum SortOrder { none, priceAsc, priceDesc, distanceAsc }

enum _SuggestionType { leistung, dienstleister, branche }

class _SearchSuggestion {
  final _SuggestionType type;
  final String title;
  final String subtitle;
  final String? dienstleisterId;
  final String? logoUrl;

  const _SearchSuggestion.leistung(this.title)
      : type = _SuggestionType.leistung,
        subtitle = '',
        dienstleisterId = null,
        logoUrl = null;

  const _SearchSuggestion.branche(this.title)
      : type = _SuggestionType.branche,
        subtitle = '',
        dienstleisterId = null,
        logoUrl = null;

  const _SearchSuggestion.dienstleister({
    required this.title,
    required this.subtitle,
    required this.dienstleisterId,
    required this.logoUrl,
  }) : type = _SuggestionType.dienstleister;
}


enum _LocationSuggestionType { currentLocation, countryWide, ort }

class _LocationSuggestion {
  final _LocationSuggestionType type;
  final String label;
  final String fillValue;

  const _LocationSuggestion._({
    required this.type,
    required this.label,
    required this.fillValue,
  });

  factory _LocationSuggestion.currentLocation(String city) {
    final trimmedCity = city.trim();
    return _LocationSuggestion._(
      type: _LocationSuggestionType.currentLocation,
      label: 'Aktueller Standort',
      fillValue: trimmedCity.isNotEmpty ? trimmedCity : 'Aktueller Standort',
    );
  }

  const _LocationSuggestion.countryWide()
      : this._(
    type: _LocationSuggestionType.countryWide,
    label: 'Ganz Deutschland',
    fillValue: 'Ganz Deutschland',
  );

  factory _LocationSuggestion.ort(String value) => _LocationSuggestion._(
    type: _LocationSuggestionType.ort,
    label: value,
    fillValue: value,
  );
}

class _AddressActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _AddressActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD8F4F6),
        foregroundColor: const Color(0xFF0B7B8A),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class AlleDienstleisterPage extends StatefulWidget {
  final int initialTabIndex;

  const AlleDienstleisterPage({super.key, this.initialTabIndex = 0});

  @override
  State<AlleDienstleisterPage> createState() => _AlleDienstleisterPageState();
}

class _AlleDienstleisterPageState extends State<AlleDienstleisterPage>
    with WidgetsBindingObserver {
  final TextEditingController _suchfeldController = TextEditingController();
  final TextEditingController _ortsuchfeldController = TextEditingController();
  static const String _googlePlacesApiKey = 'AIzaSyAAydUpc7KvbbEGeUDsw4DF8w2BkpL_Rq0';
  bool _isSearchMode = false;
  String _searchQuery = '';
  bool _isExternalSearchLoading = false;
  List<Map<String, dynamic>> _externalSearchResults = [];
  final List<String> _letzteOrtssuchen = [];

  void _onSuchbegriffChanged(String wert) {
    if (kDebugMode) print("Suchbegriff: $wert");
  }

  TextSpan _buildHighlightedSpan({
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

  Future<void> _activateSearchMode(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      _clearSearchMode();
      return;
    }

    setState(() {
      _searchQuery = q;
      _isSearchMode = true;
      _isExternalSearchLoading = true;
      _externalSearchResults = [];
    });

    final results = await _searchGooglePlaces(q);
    if (!mounted) return;
    setState(() {
      _externalSearchResults = results;
      _isExternalSearchLoading = false;
    });
  }

  void _clearSearchMode() {
    setState(() {
      _isSearchMode = false;
      _searchQuery = '';
      _isExternalSearchLoading = false;
      _externalSearchResults = [];
    });
  }


  void _clearSelectedLocation({bool clearTextField = true}) {
    if (clearTextField) {
      _ortsuchfeldController.clear();
    }
    setState(() {
      _isCurrentLocationSelected = false;
      _selectedLocationValue = null;
      _selectedLocationLabel = null;
    });
  }

  void _setSelectedLocation(
      String value, {
        bool addToRecent = true,
        bool updateTextField = true,
      }) {
    final selected = value.trim();
    if (selected.isEmpty) {
      _clearSelectedLocation(clearTextField: updateTextField);
      return;
    }

    if (addToRecent) {
      _letzteOrtssuchen.removeWhere(
            (e) => e.toLowerCase() == selected.toLowerCase(),
      );
      _letzteOrtssuchen.insert(0, selected);
      if (_letzteOrtssuchen.length > 6) {
        _letzteOrtssuchen.removeRange(6, _letzteOrtssuchen.length);
      }
    }

    if (updateTextField) {
      _ortsuchfeldController.value = TextEditingValue(
        text: selected,
        selection: TextSelection.collapsed(offset: selected.length),
      );
    }

    setState(() {
      _isCurrentLocationSelected = true;
      _selectedLocationValue = selected;
      _selectedLocationLabel = _buildLocationChipLabel(selected);
    });
  }

  void _handleLocationFieldChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _clearSelectedLocation(clearTextField: false);
      return;
    }

    setState(() {
      _isCurrentLocationSelected = true;
      _selectedLocationValue = trimmed;
      _selectedLocationLabel = _buildLocationChipLabel(trimmed);
    });
  }

  Future<void> _showLocationSelectionSheet() async {
    final initialLocationText = _isCurrentLocationSelected
        ? (_selectedLocationValue ?? _selectedLocationLabel ?? currentCity ?? '').trim()
        : _suchfeldController.text.trim();
    final controller = TextEditingController(text: initialLocationText);
    List<String> ortVorschlaege = [];
    bool laedtOrtsVorschlaege = false;
    String letzterSuchwert = initialLocationText.trim().toLowerCase();

    Future<void> ladeOrtsVorschlaege(
        String input,
        StateSetter setModalState,
        ) async {
      final normalized = input.trim().toLowerCase();
      letzterSuchwert = normalized;
      if (normalized.isEmpty) {
        setModalState(() {
          ortVorschlaege = [];
          laedtOrtsVorschlaege = false;
        });
        return;
      }

      setModalState(() => laedtOrtsVorschlaege = true);
      final treffer = await _ladeOrtsVorschlaege(normalized);
      if (!mounted) return;
      if (letzterSuchwert != normalized) return;
      setModalState(() {
        ortVorschlaege = treffer;
        laedtOrtsVorschlaege = false;
      });
    }

    if (letzterSuchwert.isNotEmpty) {
      ortVorschlaege = await _ladeOrtsVorschlaege(letzterSuchwert);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = controller.text.trim().toLowerCase();
            final gefilterteLetzteSuchen = _letzteOrtssuchen
                .where((e) => query.isEmpty || e.toLowerCase().contains(query))
                .toList();

            void selectLocation(
                String value, {
                  bool addToRecent = true,
                  bool isCurrentLocationSelection = false,
                }) {
              final selected = value.trim();
              if (selected.isEmpty) return;

              if (addToRecent) {
                setState(() {
                  _letzteOrtssuchen.removeWhere(
                        (e) => e.toLowerCase() == selected.toLowerCase(),
                  );
                  _letzteOrtssuchen.insert(0, selected);
                  if (_letzteOrtssuchen.length > 6) {
                    _letzteOrtssuchen.removeRange(6, _letzteOrtssuchen.length);
                  }
                });
              }

              setState(() {
                _isCurrentLocationSelected = isCurrentLocationSelection;
                _selectedLocationValue = isCurrentLocationSelection ? selected : null;
                _selectedLocationLabel = isCurrentLocationSelection
                    ? _buildLocationChipLabel(selected)
                    : null;
              });
              _suchfeldController.text = selected;
              Navigator.of(ctx).pop();
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check, color: Color(0xFFC5E86C)),
                        const SizedBox(width: 10),
                        Text(
                          'Ortsauswahl',
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText:
                        currentCity != null ? 'Suche in $currentCity' : 'Ort oder PLZ',
                        hintStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.search, color: Colors.white70),
                        filled: true,
                        fillColor: const Color(0xFF232323),
                        contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Colors.white54),
                        ),
                      ),
                      onChanged: (value) async {
                        setModalState(() {});
                        await ladeOrtsVorschlaege(value, setModalState);
                      },
                      onSubmitted: (v) => selectLocation(
                        v,
                        isCurrentLocationSelection: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Vorschläge',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.my_location, color: Colors.white70),
                            title: const Text(
                              'Aktueller Standort',
                              style: TextStyle(color: Colors.white),
                            ),
                            onTap: () => selectLocation(
                              currentCity ?? 'Aktueller Standort',
                              addToRecent: false,
                              isCurrentLocationSelection: true,
                            ),
                          ),
                          const Divider(color: Colors.white12, height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.public, color: Colors.white70),
                            title: const Text(
                              'Ganz Deutschland',
                              style: TextStyle(color: Colors.white),
                            ),
                            onTap: () => selectLocation('Ganz Deutschland', addToRecent: false),
                          ),
                          const Divider(color: Colors.white12, height: 1),
                          if (controller.text.trim().isNotEmpty &&
                              ortVorschlaege.isNotEmpty) ...[
                            ...ortVorschlaege.map(
                                  (eintrag) => Column(
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.location_on_outlined,
                                      color: Colors.white70,
                                    ),
                                    title: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                        children: _buildHighlightedSpans(
                                          eintrag,
                                          controller.text.trim(),
                                        ),
                                      ),
                                    ),
                                    onTap: () => selectLocation(
                                      eintrag,
                                      isCurrentLocationSelection: true,
                                    ),
                                  ),
                                  const Divider(color: Colors.white12, height: 1),
                                ],
                              ),
                            ),
                          ] else if (laedtOrtsVorschlaege) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                            const Divider(color: Colors.white12, height: 1),
                          ],
                          if (gefilterteLetzteSuchen.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: Text(
                                'Letzte Orts-Suchanfragen erscheinen hier.',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          else
                            ...gefilterteLetzteSuchen.map(
                                  (eintrag) => Column(
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading:
                                    const Icon(Icons.location_on_outlined, color: Colors.white70),
                                    title: Text(
                                      eintrag,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    onTap: () => selectLocation(
                                      eintrag,
                                      isCurrentLocationSelection: true,
                                    ),
                                  ),
                                  const Divider(color: Colors.white12, height: 1),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<String>> _ladeOrtsVorschlaege(String eingabe) async {
    final query = eingabe.trim().toLowerCase();
    if (query.isEmpty) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('rolle', isEqualTo: 'dienstleister')
        .limit(200)
        .get();

    final startsWith = <String>{};
    final contains = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final plz = (data['plz'] ?? '').toString().trim();
      final ort = (data['ort'] ?? '').toString().trim();
      if (plz.isEmpty && ort.isEmpty) continue;

      final combined = [plz, ort].where((e) => e.isNotEmpty).join(' ').trim();
      if (combined.isEmpty) continue;

      final plzLower = plz.toLowerCase();
      final ortLower = ort.toLowerCase();

      final prefixMatch =
          plzLower.startsWith(query) || ortLower.startsWith(query);
      final containsMatch =
          plzLower.contains(query) || ortLower.contains(query);

      if (prefixMatch) {
        startsWith.add(combined);
      } else if (containsMatch) {
        contains.add(combined);
      }
    }

    final sortFn = (String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());
    final sortedStartsWith = startsWith.toList()..sort(sortFn);
    final sortedContains = contains.toList()..sort(sortFn);

    return [...sortedStartsWith, ...sortedContains].take(8).toList();
  }

  List<TextSpan> _buildHighlightedSpans(String text, String query) {
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

  String _buildLocationChipLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    final match = RegExp(r'^\d{4,6}\s+(.+)$').firstMatch(trimmed);
    if (match != null) {
      final cityPart = (match.group(1) ?? '').trim();
      if (cityPart.isNotEmpty) return cityPart;
    }
    return trimmed;
  }

  bool _matchesSelectedLocation(Map<String, dynamic> data) {
    if (!_isCurrentLocationSelected) return true;

    final rawSelection =
    (_selectedLocationValue ?? _selectedLocationLabel ?? '').trim();
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
      final ortPasst = selectedOrt.isEmpty ||
          ort.contains(selectedOrt) ||
          adresse.contains(selectedOrt);
      return plzPasst && ortPasst;
    }

    return ort.contains(normalizedSelection) ||
        plz.contains(normalizedSelection) ||
        adresse.contains(normalizedSelection);
  }

  Future<List<Map<String, dynamic>>> _searchGooglePlaces(String query) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json'
            '?query=${Uri.encodeQueryComponent(query)}'
            '&language=de'
            '&key=$_googlePlacesApiKey',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body) as Map<String, dynamic>;
      final status = data['status']?.toString() ?? '';
      if (status != 'OK' && status != 'ZERO_RESULTS') return [];
      final results = (data['results'] as List?) ?? [];
      return results.map((e) {
        final item = Map<String, dynamic>.from(e as Map);
        return {
          'name': (item['name'] ?? '').toString(),
          'address': (item['formatted_address'] ?? item['vicinity'] ?? '').toString(),
        };
      }).where((e) => (e['name'] as String).trim().isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  // Helper, um Tastatur/Fokus sicher zu schließen
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _resetAllFiltersAndSearch([TextEditingController? c]) {
    c?.clear();
    _suchfeldController.clear();
    _ortsuchfeldController.clear();
    _dismissKeyboard();

    setState(() {
      _ausgewaehlteLeistung = null;
      _isCurrentLocationSelected = false;
      _selectedLocationLabel = null;
      _selectedLocationValue = null;
      _gefilterteDienstleisterIds = [];
      _sortOrder = SortOrder.none;
      _isSearchMode = false;
      _searchQuery = '';
      _isExternalSearchLoading = false;
      _externalSearchResults = [];

      ausgewaehlteBranchen.clear();
      ausgewaehlteZielgruppen.clear();
      ausgewaehlteKategorien.clear();
      ausgewaehlteLeistungen.clear();
    });

    _ladeZielgruppenUndKategorien();
  }

  String? _ausgewaehlteLeistung;
  List<String> _gefilterteDienstleisterIds = [];

  /// Sortierreihenfolge (im Filter-Sheet & Sortier-Chip auswählbar)
  SortOrder _sortOrder = SortOrder.none;

  /// fixe Zielgruppen-Liste für den „Für wen?“-Block
  final List<String> _zielgruppenFix = const ['Damen', 'Herren', 'Kinder'];

  // ===================== Angebote-basierte Filter-Helfer =====================

  /// Mehrere Branchen → Menge an Dienstleister-IDs (ODER-Verknüpfung)
  Future<Set<String>?> _dienstleisterIdsFuerBranchen(List<String>? branchen) async {
    if (branchen == null || branchen.isEmpty) return null;
    final ids = <String>{};

    // Firestore whereIn max 10
    for (var i = 0; i < branchen.length; i += 10) {
      final end = math.min(i + 10, branchen.length);
      final chunk = branchen.sublist(i, end);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .where('branche', whereIn: chunk)
          .get();
      ids.addAll(snap.docs.map((d) => d.id));
    }
    return ids;
  }

  Future<void> _applyOfferFiltersFromSelections({List<String>? branchen}) async {
    if (ausgewaehlteLeistungen.isEmpty) {
      setState(() => _gefilterteDienstleisterIds = []);
      return;
    }

    final branchIds = await _dienstleisterIdsFuerBranchen(branchen);
    final resultIds = <String>{};

    for (final entry in ausgewaehlteLeistungen.entries) {
      final kategorie = entry.key;
      final leistungen = entry.value;
      if (leistungen.isEmpty) continue;

      for (var i = 0; i < leistungen.length; i += 10) {
        final end = math.min(i + 10, leistungen.length);
        final chunk = leistungen.sublist(i, end);

        final qSnap = await FirebaseFirestore.instance
            .collection('angebote')
            .where('kategorie', isEqualTo: kategorie)
            .where('leistungen', arrayContainsAny: chunk)
            .get();

        for (final d in qSnap.docs) {
          final id = (d.data()['dienstleisterId'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          if (branchIds != null && !branchIds.contains(id)) continue;
          resultIds.add(id);
        }
      }
    }

    setState(() {
      _gefilterteDienstleisterIds = resultIds.toList();
    });
  }

  Future<int> _countMatchesBasedOnSelections({
    List<String>? branchen,
    List<String>? zielgruppen,
  }) async {
    final selectedZielgruppen = zielgruppen ?? ausgewaehlteZielgruppen;

    if (ausgewaehlteLeistungen.isEmpty) {
      final selBranchen =
          branchen ?? (ausgewaehlteBranchen.isNotEmpty ? ausgewaehlteBranchen : null);
      final branchIds = await _dienstleisterIdsFuerBranchen(selBranchen);

      if (selectedZielgruppen.isNotEmpty) {
        final offersSnap =
            await FirebaseFirestore.instance.collection('angebote').get();
        final ids = <String>{};

        for (final doc in offersSnap.docs) {
          final data = doc.data();
          final id = (data['dienstleisterId'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          if (branchIds != null && !branchIds.contains(id)) continue;

          final zgMap = data['zielgruppen'];
          if (zgMap is! Map) continue;

          final hasMatch = selectedZielgruppen.any((zg) => zgMap.containsKey(zg));
          if (hasMatch) ids.add(id);
        }
        return ids.length;
      }

      if (branchIds != null) return branchIds.length;

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .get();
      return snap.size;
    }

    final branchIds = await _dienstleisterIdsFuerBranchen(branchen ?? ausgewaehlteBranchen);
    final ids = <String>{};

    for (final entry in ausgewaehlteLeistungen.entries) {
      final kategorie = entry.key;
      final leistungen = entry.value;
      if (leistungen.isEmpty) continue;

      for (var i = 0; i < leistungen.length; i += 10) {
        final end = math.min(i + 10, leistungen.length);
        final chunk = leistungen.sublist(i, end);

        final q = await FirebaseFirestore.instance
            .collection('angebote')
            .where('kategorie', isEqualTo: kategorie)
            .where('leistungen', arrayContainsAny: chunk)
            .get();

        for (final d in q.docs) {
          final id = (d.data()['dienstleisterId'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          if (branchIds != null && !branchIds.contains(id)) continue;
          ids.add(id);
        }
      }
    }

    return ids.length;
  }

  Future<List<String>> _ladeLeistungskategorienAusAngeboten(List<String>? branchen) async {
    // Ohne Branchen: alle Kategorien
    if (branchen == null || branchen.isEmpty) {
      final snap = await FirebaseFirestore.instance.collection('angebote').get();
      final cats = snap.docs
          .map((d) => (d.data()['kategorie'] as String?)?.trim())
          .where((s) => s != null && s!.isNotEmpty)
          .map((s) => s!)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return cats;
    }

    final ids = await _dienstleisterIdsFuerBranchen(branchen) ?? <String>{};
    if (ids.isEmpty) return [];

    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final idList = ids.toList();

    for (var i = 0; i < idList.length; i += 10) {
      final end = math.min(i + 10, idList.length);
      final chunk = idList.sublist(i, end);
      final aSnap = await FirebaseFirestore.instance
          .collection('angebote')
          .where('dienstleisterId', whereIn: chunk)
          .get();
      allDocs.addAll(aSnap.docs);
    }

    final cats = allDocs
        .map((d) => (d.data()['kategorie'] as String?)?.trim())
        .where((s) => s != null && s!.isNotEmpty)
        .map((s) => s!)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return cats;
  }

  Future<List<String>> _ladeLeistungenFuerKategorieAusAngeboten(
      String kategorie, List<String>? branchen) async {
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

    if (branchen == null || branchen.isEmpty) {
      final q = await FirebaseFirestore.instance
          .collection('angebote')
          .where('kategorie', isEqualTo: kategorie)
          .get();
      docs = q.docs;
    } else {
      final ids = await _dienstleisterIdsFuerBranchen(branchen) ?? <String>{};
      if (ids.isEmpty) return [];
      final tmp = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final idList = ids.toList();

      for (var i = 0; i < idList.length; i += 10) {
        final end = math.min(i + 10, idList.length);
        final chunk = idList.sublist(i, end);
        final aSnap = await FirebaseFirestore.instance
            .collection('angebote')
            .where('kategorie', isEqualTo: kategorie)
            .where('dienstleisterId', whereIn: chunk)
            .get();
        tmp.addAll(aSnap.docs);
      }
      docs = tmp;
    }

    final set = <String>{};
    for (final d in docs) {
      final data = d.data();
      final arr = data['leistungen'];
      if (arr is List) {
        for (final e in arr) {
          final s = (e as String?)?.trim();
          if (s != null && s.isNotEmpty) set.add(s);
        }
      } else {
        final titel = (data['titel'] as String?)?.trim();
        if (titel != null && titel.contains('–')) {
          final part = titel.split('–').last.trim();
          if (part.isNotEmpty) set.add(part);
        }
      }
    }

    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<void> _openLeistungskategorieDialog(String kategorie, {List<String>? branchen}) async {
    final leistungen = await _ladeLeistungenFuerKategorieAusAngeboten(kategorie, branchen);

    final initial = Set<String>.from(ausgewaehlteLeistungen[kategorie] ?? []);
    final tempSelected = Set<String>.from(initial);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: StatefulBuilder(
            builder: (context, setLocal) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, left: 20, right: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          kategorie,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: leistungen.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final name = leistungen[i];
                          final checked = tempSelected.contains(name);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) {
                              setLocal(() {
                                if (v == true) {
                                  tempSelected.add(name);
                                } else {
                                  tempSelected.remove(name);
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.trailing,
                            title: Text(name),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Abbrechen'),
                            ),
                          ),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                setState(() {
                                  if (tempSelected.isEmpty) {
                                    ausgewaehlteLeistungen.remove(kategorie);
                                    ausgewaehlteKategorien.removeWhere((e) => e == kategorie);
                                  } else {
                                    ausgewaehlteLeistungen[kategorie] = tempSelected.toList();
                                    if (!ausgewaehlteKategorien.contains(kategorie)) {
                                      ausgewaehlteKategorien.add(kategorie);
                                    }
                                  }
                                });
                                Navigator.of(context).pop();
                              },
                              child: const Text('OK'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    setState(() {}); // Oberfläche aktualisieren
  }

  Future<List<String>> _ladeLeistungsVorschlaege(String eingabe) async {
    if (eingabe.trim().isEmpty) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('angebote')
        .limit(50)
        .get();

    return snapshot.docs
        .map((doc) => doc['titel'].toString())
        .where((titel) => titel.toLowerCase().contains(eingabe.toLowerCase()))
        .toSet()
        .toList();
  }

  Future<List<Map<String, dynamic>>> _ladeDienstleisterVorschlaege(String eingabe) async {
    final search = eingabe.trim().toLowerCase();
    if (search.isEmpty) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('rolle', isEqualTo: 'dienstleister')
        .get();

    final matches = snapshot.docs
        .map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': (data['name'] ?? '').toString(),
        'ort': (data['ort'] ?? '').toString(),
        'plz': (data['plz'] ?? '').toString(),
        'logoUrl': (data['logoUrl'] ?? '').toString(),
        ...data,
      };
    })
        .where((d) => (d['name'] as String).toLowerCase().contains(search))
        .toList();

    matches.sort((a, b) =>
        (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
    return matches.take(8).toList();
  }

  Future<List<String>> _ladeBranchenVorschlaege(String eingabe) async {
    final search = eingabe.trim().toLowerCase();
    if (search.isEmpty) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('branchen')
        .get();

    final matches = snapshot.docs
        .map((doc) => (doc['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty && name.toLowerCase().contains(search))
        .toSet()
        .toList();

    matches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return matches.take(8).toList();
  }

  Future<void> _openDienstleisterFromSuggestion(Map<String, dynamic> suggestion) async {
    final data = Map<String, dynamic>.from(suggestion);
    final geo = data['geo'];
    if (geo is GeoPoint && userPosition != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        userPosition!.latitude,
        userPosition!.longitude,
        geo.latitude,
        geo.longitude,
      );
      data['distance'] = distanceInMeters / 1000;
    }

    if (!mounted) return;
    _clearSearchMode();
    setState(() {
      geoeffneterDienstleister = data;
      _dienstleisterFavorisiert = _favoritenIds.contains(data['id']);
    });
    _dismissKeyboard();
  }

  Future<void> _ladeDienstleisterZuLeistung(String titel) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('angebote')
        .where('titel', isEqualTo: titel)
        .get();

    final ids =
    snapshot.docs.map((doc) => doc['dienstleisterId'].toString()).toList();

    setState(() {
      _gefilterteDienstleisterIds = ids;
    });
  }

  Future<void> _applySelectionFromTitle(String titel) async {
    final parts = titel.split(RegExp(r'\s*[–—-]\s*'));
    String? kategorie;
    String? leistung;

    if (parts.length >= 2) {
      kategorie = parts.first.trim();
      leistung = parts.sublist(1).join(' – ').trim();
    }

    if (kategorie == null || kategorie.isEmpty || leistung == null || leistung.isEmpty) {
      await _ladeDienstleisterZuLeistung(titel);
      return;
    }

    setState(() {
      ausgewaehlteLeistungen.clear();
      ausgewaehlteKategorien.clear();
      ausgewaehlteLeistungen[kategorie!] = [leistung!];
      ausgewaehlteKategorien = [kategorie!];
    });

    final List<String>? aktuelleBranchen =
    ausgewaehlteBranchen.isNotEmpty ? List<String>.from(ausgewaehlteBranchen) : null;
    await _applyOfferFiltersFromSelections(branchen: aktuelleBranchen);
  }

  Future<void> _applyBrancheSelectionFromSearch(String branche) async {
    final trimmed = branche.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      ausgewaehlteBranchen
        ..clear()
        ..add(trimmed);
      _ausgewaehlteLeistung = null;
      _gefilterteDienstleisterIds = [];
      _isSearchMode = false;
      _searchQuery = '';
      _isExternalSearchLoading = false;
      _externalSearchResults = [];
    });

    await _applyOfferFiltersFromSelections(
      branchen: List<String>.from(ausgewaehlteBranchen),
    );
  }

  // ---- Preis-Helper ---------------------------------------------------------
  double? _preisToDouble(dynamic p) {
    if (p == null) return null;
    if (p is num) return p.toDouble();
    if (p is String) {
      final cleaned = p.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
      if (cleaned.isEmpty) return null;
      try {
        return double.parse(cleaned);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  double? _lowestPriceInOffers(List<Map<String, dynamic>>? offers) {
    if (offers == null || offers.isEmpty) return null;
    double? minP;
    for (final o in offers) {
      final p = _preisToDouble(o['preis']);
      if (p == null) continue;
      if (minP == null || p < minP) minP = p;
    }
    return minP;
  }

  // ---------- Farben für Zielgruppen ----------
  static const String _zgDamen = 'Damen';
  static const String _zgHerren = 'Herren';
  static const String _zgKinder = 'Kinder';

  Color _colorForZielgruppe(String? zg) {
    switch (zg) {
      case _zgDamen:
        return const Color(0xFFE91E63); // Pink
      case _zgKinder:
        return const Color(0xFFFFC107); // Gelb (Amber)
      case _zgHerren:
      default:
        return Colors.blueAccent; // Blau
    }
  }

  Future<List<Map<String, dynamic>>> _ladePassendeAngeboteFuerDienstleister(
      String dienstleisterId,
      ) async {
    if (ausgewaehlteLeistungen.isEmpty) return [];

    final selectedGroups = List<String>.from(ausgewaehlteZielgruppen);
    final results = <Map<String, dynamic>>[];
    final seenPair = <String>{};

    for (final entry in ausgewaehlteLeistungen.entries) {
      final kategorie = entry.key;
      final leistungen = entry.value;
      if (leistungen.isEmpty) continue;

      for (var i = 0; i < leistungen.length; i += 10) {
        final end = math.min(i + 10, leistungen.length);
        final chunk = leistungen.sublist(i, end);

        final q = await FirebaseFirestore.instance
            .collection('angebote')
            .where('dienstleisterId', isEqualTo: dienstleisterId)
            .where('kategorie', isEqualTo: kategorie)
            .where('leistungen', arrayContainsAny: chunk)
            .get();

        for (final d in q.docs) {
          final data = d.data();
          final titel = (data['titel'] as String?) ?? '${data['kategorie']}';
          final zgMap = (data['zielgruppen'] is Map)
              ? Map<String, dynamic>.from(data['zielgruppen'])
              : null;

          if (selectedGroups.isNotEmpty) {
            for (final g in selectedGroups) {
              final grp = zgMap?[g];
              if (grp is Map) {
                final key = '${d.id}|$g';
                if (seenPair.add(key)) {
                  results.add({
                    'docId': d.id,
                    'titel': titel,
                    'kategorie': data['kategorie'],
                    'preis': grp['preis'],
                    'dauer': grp['dauer'],
                    'zielgruppe': g,
                    'chipColor': _colorForZielgruppe(g),
                  });
                }
              }
            }
            continue;
          }

          if (zgMap != null && zgMap.isNotEmpty) {
            for (final entry in zgMap.entries) {
              final g = entry.key.toString();
              final grp = entry.value;
              if (grp is! Map) continue;
              final key = '${d.id}|$g';
              if (seenPair.add(key)) {
                results.add({
                  'docId': d.id,
                  'titel': titel,
                  'kategorie': data['kategorie'],
                  'preis': grp['preis'],
                  'dauer': grp['dauer'],
                  'zielgruppe': g,
                  'chipColor': _colorForZielgruppe(g),
                });
              }
            }
          } else {
            final key = '${d.id}|_global';
            if (seenPair.add(key)) {
              results.add({
                'docId': d.id,
                'titel': titel,
                'kategorie': data['kategorie'],
                'preis': data['preis'],
                'dauer': data['dauer'],
                'zielgruppe': null,
                'chipColor': _colorForZielgruppe('Herren'),
              });
            }
          }
        }
      }
    }

    if (_sortOrder == SortOrder.priceAsc || _sortOrder == SortOrder.priceDesc) {
      double? _toDouble(dynamic p) {
        if (p == null) return null;
        if (p is num) return p.toDouble();
        if (p is String) {
          final cleaned =
          p.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
          if (cleaned.isEmpty) return null;
          return double.tryParse(cleaned);
        }
        return null;
      }

      results.sort((a, b) {
        final ap = _toDouble(a['preis']);
        final bp = _toDouble(b['preis']);
        if (ap == null && bp == null) return 0;
        if (ap == null) return 1;
        if (bp == null) return -1;
        return _sortOrder == SortOrder.priceAsc ? ap.compareTo(bp) : bp.compareTo(ap);
      });
    }

    return results;
  }

  String? currentCity;
  bool _isCurrentLocationSelected = false;
  String? _selectedLocationLabel;
  String? _selectedLocationValue;
  Position? userPosition;
  bool isLoading = true;
  int _selectedIndex = 0;

  List<String> verfuegbareBranchen = [];
  List<String> ausgewaehlteBranchen = [];

  List<String> verfuegbareZielgruppen = [];
  List<String> ausgewaehlteZielgruppen = [];

  List<String> verfuegbareKategorien = [];
  List<String> ausgewaehlteKategorien = [];

  Map<String, List<String>> kategorieZuLeistungen = {};
  Map<String, List<String>> ausgewaehlteLeistungen = {};
  String? offeneKategorie;

  bool filterChipOffen = false;
  Map<String, dynamic>? geoeffneterDienstleister;
  bool _dienstleisterFavorisiert = false;
  final Set<String> _favoritenIds = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex.clamp(0, 3);
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _suchfeldController.dispose();
    _ortsuchfeldController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initLocation();
    }
  }

  Future<void> _ermittleOrtAusKoordinaten() async {
    if (userPosition == null) return;

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        userPosition!.latitude,
        userPosition!.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark ort = placemarks.first;
        setState(() {
          currentCity = ort.locality ??
              ort.subAdministrativeArea ??
              ort.administrativeArea ??
              'Unbekannt';
        });
      }
    } catch (e) {
      if (kDebugMode) print("Fehler beim Reverse Geocoding: $e");
    }
  }

  Future<void> _initLocation() async {
    setState(() => isLoading = true);
    userPosition = await LocationService.initLocation(
      context: context,
      onExitApp: () => SystemChannels.platform.invokeMethod('SystemNavigator.pop'),
      onOpenAppSettings: () => AppSettings.openAppSettings(),
    );
    await _ermittleOrtAusKoordinaten();
    await _ladeFavoriten();
    setState(() => isLoading = false);
  }

  String? get _aktuellerUserId => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _ladeFavoriten() async {
    final userId = _aktuellerUserId;
    if (userId == null) return;

    final userSnap =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    final favoritenRaw = userSnap.data()?['favoriten'];

    final favoritIds = <String>{};
    if (favoritenRaw is Map) {
      favoritIds.addAll(
        favoritenRaw.entries
            .where((e) => e.value == true)
            .map((e) => e.key.toString())
            .where((id) => id.trim().isNotEmpty),
      );
    }

    if (!mounted) return;
    setState(() {
      _favoritenIds
        ..clear()
        ..addAll(favoritIds);
      final aktuelleId = (geoeffneterDienstleister?['id'] ?? '').toString();
      _dienstleisterFavorisiert =
          aktuelleId.isNotEmpty && _favoritenIds.contains(aktuelleId);
    });
  }

  Future<void> _setFavoritStatus({
    required String dienstleisterId,
    required bool isFavorit,
  }) async {
    final userId = _aktuellerUserId;
    if (userId == null || dienstleisterId.trim().isEmpty) return;

    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'favoriten.$dienstleisterId': isFavorit ? true : FieldValue.delete(),
    });

    if (!mounted) return;
    setState(() {
      if (isFavorit) {
        _favoritenIds.add(dienstleisterId);
      } else {
        _favoritenIds.remove(dienstleisterId);
      }
      final aktuelleId = (geoeffneterDienstleister?['id'] ?? '').toString();
      if (aktuelleId == dienstleisterId) {
        _dienstleisterFavorisiert = isFavorit;
      }
    });
  }

  Future<void> _ladeZielgruppenUndKategorien() async {
    if (ausgewaehlteBranchen.isEmpty) {
      setState(() {
        verfuegbareZielgruppen = [];
        verfuegbareKategorien = [];
        kategorieZuLeistungen = {};
      });
      return;
    }

    // Beibehaltung des bisherigen Verhaltens (erste Branche),
    // um möglichst wenig in die übrige Logik einzugreifen.
    final doc = await FirebaseFirestore.instance
        .collection('branchen')
        .doc(ausgewaehlteBranchen.first)
        .get();
    final data = doc.data();
    if (data == null || !data.containsKey('zielgruppen')) return;

    final zielgruppenMap = Map<String, dynamic>.from(data['zielgruppen']);
    final zielgruppen = zielgruppenMap.keys.toList();

    setState(() {
      verfuegbareZielgruppen = zielgruppen;
      verfuegbareKategorien = [];
      kategorieZuLeistungen = {};
      ausgewaehlteZielgruppen = [];
      ausgewaehlteKategorien = [];
      ausgewaehlteLeistungen = {};
    });
  }

  // Badge zählt: Branche + Zielgruppen + Anzahl Leistungen + Sortierung
  int get _filterBadgeCount {
    int n = 0;
    if (ausgewaehlteBranchen.isNotEmpty) n += 1;
    n += ausgewaehlteZielgruppen.length;
    n += ausgewaehlteLeistungen.values.fold<int>(
      0,
          (sum, list) => sum + list.length,
    );
    if (_sortOrder != SortOrder.none) n += 1;
    return n;
  }

  // ---------- Quick-Sheet für Branchen (Multi-Select) ----------
  Future<void> _showBranchenQuickSheet() async {
    _dismissKeyboard();

    final tempSelected = <String>{}..addAll(ausgewaehlteBranchen);

    int previewCount =
    await _countMatchesBasedOnSelections(branchen: tempSelected.toList());

    final snap = await FirebaseFirestore.instance
        .collection('branchen')
        .where('aktiv', isEqualTo: true)
        .get();

    final branchen = snap.docs
        .map((d) => ((d.data()['name'] as String?) ?? d.id).trim())
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> _recalc() async {
              final c = await _countMatchesBasedOnSelections(
                  branchen: tempSelected.toList());
              setLocal(() => previewCount = c);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Branche wählen',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: branchen.length,
                        itemBuilder: (_, i) {
                          final b = branchen[i];
                          final checked = tempSelected.contains(b);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) async {
                              setLocal(() {
                                if (v == true) {
                                  tempSelected.add(b);
                                } else {
                                  tempSelected.remove(b);
                                }
                              });
                              await _recalc();
                            },
                            controlAffinity: ListTileControlAffinity.trailing,
                            title: Text(b[0].toUpperCase() + b.substring(1)),
                            dense: true,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            ausgewaehlteBranchen
                              ..clear()
                              ..addAll(tempSelected);
                          });

                          await _applyOfferFiltersFromSelections(
                              branchen: tempSelected.toList());
                          _ladeZielgruppenUndKategorien();

                          if (mounted) Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          'Anwenden – $previewCount Treffer',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- LEISTUNGEN-SHEET (für den „Leistungen“-Chip) ----------
  Future<void> _showLeistungenSheet() async {
    _dismissKeyboard();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Leistungen',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                ausgewaehlteKategorien.clear();
                                ausgewaehlteLeistungen.clear();
                              });
                              setModal(() {});
                            },
                            child: const Text('Zurücksetzen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      FutureBuilder<List<String>>(
                        future: _ladeLeistungskategorienAusAngeboten(
                            ausgewaehlteBranchen),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                  'Fehler beim Laden der Kategorien aus Angeboten'),
                            );
                          }

                          final items = snapshot.data ?? [];
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child:
                              Text('Keine Leistungskategorien vorhanden.'),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final name = items[i];
                              final selectedList =
                              (ausgewaehlteLeistungen[name] ??
                                  const <String>[]);

                              return ListTile(
                                dense: true,
                                title: Text(name),
                                subtitle: (selectedList.isNotEmpty)
                                    ? Padding(
                                  padding:
                                  const EdgeInsets.only(top: 6),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: selectedList.map((s) {
                                        return Padding(
                                          padding:
                                          const EdgeInsets.only(
                                              right: 6),
                                          child: InputChip(
                                            label: Text(s),
                                            selected: true,
                                            showCheckmark: false,
                                            selectedColor: Colors
                                                .blueAccent
                                                .withOpacity(.12),
                                            labelStyle:
                                            const TextStyle(
                                                color: Colors
                                                    .blueAccent),
                                            shape: const StadiumBorder(
                                              side: BorderSide(
                                                  color: Colors
                                                      .blueAccent),
                                            ),
                                            deleteIcon: const Icon(
                                                Icons.close,
                                                size: 18,
                                                color: Colors
                                                    .blueAccent),
                                            onDeleted: () {
                                              setState(() {
                                                ausgewaehlteLeistungen[
                                                name]!
                                                    .remove(s);
                                                if (ausgewaehlteLeistungen[
                                                name]!
                                                    .isEmpty) {
                                                  ausgewaehlteLeistungen
                                                      .remove(name);
                                                  ausgewaehlteKategorien
                                                      .removeWhere(
                                                          (e) =>
                                                      e == name);
                                                }
                                              });
                                              setModal(() {});
                                            },
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                )
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selectedList.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                          BorderRadius.circular(12),
                                          color: Colors.orange.shade100,
                                        ),
                                        child: Text(
                                          '${selectedList.length}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () async {
                                  await _openLeistungskategorieDialog(name,
                                      branchen: ausgewaehlteBranchen);
                                  setModal(() {});
                                },
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),

                  // Anwenden
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: ElevatedButton(
                        onPressed: () async {
                          await _applyOfferFiltersFromSelections(
                              branchen: ausgewaehlteBranchen);
                          if (mounted) Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Anwenden'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------- Sortier-Sheet (für Sortieren-Chip) ----------
  Future<void> _showSortSheet() async {
    SortOrder temp = _sortOrder;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Sortieren',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        TextButton(
                          onPressed: () => setLocal(() => temp = SortOrder.none),
                          child: const Text('Zurücksetzen'),
                        ),
                      ],
                    ),
                    RadioListTile<SortOrder>(
                      value: SortOrder.priceAsc,
                      groupValue: temp,
                      onChanged: (v) => setLocal(() => temp = v!),
                      title: const Text('Niedrigster Preis'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                    RadioListTile<SortOrder>(
                      value: SortOrder.priceDesc,
                      groupValue: temp,
                      onChanged: (v) => setLocal(() => temp = v!),
                      title: const Text('Höchster Preis'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                    RadioListTile<SortOrder>(
                      value: SortOrder.distanceAsc,
                      groupValue: temp,
                      onChanged: (v) => setLocal(() => temp = v!),
                      title: const Text('In meiner Nähe'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _sortOrder = temp);
                          Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Anwenden'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- Vollständiges Filter-Sheet ----------
  Future<void> _showBranchenFilterSheet() async {
    // Multi-Select als temporäre Menge
    final Set<String> tempBranchen = {...ausgewaehlteBranchen};

    SortOrder tempSortOrder = _sortOrder;
    final List<String> tempZielgruppen = List<String>.from(ausgewaehlteZielgruppen);

    int previewCount = await _countMatchesBasedOnSelections(
      branchen: tempBranchen.toList(),
      zielgruppen: tempZielgruppen,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // FULLSCREEN
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> _recalc() async {
              final c = await _countMatchesBasedOnSelections(
                branchen: tempBranchen.toList(),
                zielgruppen: tempZielgruppen,
              );
              setModalState(() => previewCount = c);
            }

            return SizedBox(
              height: MediaQuery.of(context).size.height,
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Filter',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          TextButton(
                            onPressed: () async {
                              setState(() {
                                ausgewaehlteBranchen.clear();
                                ausgewaehlteKategorien.clear();
                                ausgewaehlteLeistungen.clear();
                                ausgewaehlteZielgruppen.clear();
                                _sortOrder = SortOrder.none;
                              });
                              setModalState(() {
                                tempBranchen.clear();
                                tempZielgruppen.clear();
                                tempSortOrder = SortOrder.none;
                              });
                              _dismissKeyboard();
                              await _recalc();
                            },
                            child: const Text('Zurücksetzen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Für wen?
                      Text(
                        'Für wen?',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _zielgruppenFix.map((zg) {
                          final selected = tempZielgruppen.contains(zg);
                          return FilterChip(
                            label: Text(
                              zg,
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.black,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            selected: selected,
                            onSelected: (_) async {
                              setModalState(() {
                                if (selected) {
                                  tempZielgruppen.remove(zg);
                                } else {
                                  tempZielgruppen.add(zg);
                                }
                              });
                              await _recalc();
                            },
                            selectedColor: Colors.blueAccent,
                            backgroundColor: Colors.white,
                            checkmarkColor: Colors.white,
                            shape: const StadiumBorder(
                              side: BorderSide(color: Colors.black),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 20),

                      // Branchen (Multi-Select)
                      Text(
                        'Branchen',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('branchen')
                            .where('aktiv', isEqualTo: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final branchen = snapshot.data!.docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return (data['name'] as String?) ?? doc.id;
                          }).toList()
                            ..sort((a, b) =>
                                a.toLowerCase().compareTo(b.toLowerCase()));

                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: branchen.map((b) {
                              final selected = tempBranchen.contains(b);
                              return FilterChip(
                                label: Text(
                                  b[0].toUpperCase() + b.substring(1),
                                  style: TextStyle(
                                    color: selected ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                selected: selected,
                                onSelected: (_) async {
                                  setModalState(() {
                                    if (selected) {
                                      tempBranchen.remove(b);
                                    } else {
                                      tempBranchen.add(b);
                                    }
                                  });
                                  await _recalc();
                                },
                                selectedColor: Colors.blueAccent,
                                backgroundColor: Colors.white,
                                checkmarkColor: Colors.white,
                                shape: const StadiumBorder(
                                  side: BorderSide(color: Colors.black),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // Leistungen
                      Text(
                        'Leistungen',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),

                      FutureBuilder<List<String>>(
                        future: _ladeLeistungskategorienAusAngeboten(
                            tempBranchen.toList()),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('Fehler beim Laden der Kategorien aus Angeboten'),
                            );
                          }

                          final items = snapshot.data ?? [];
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('Keine Leistungskategorien vorhanden.'),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final name = items[i];
                              final selectedList =
                              (ausgewaehlteLeistungen[name] ?? const <String>[]);

                              return ListTile(
                                dense: true,
                                title: Text(name),
                                subtitle: (selectedList.isNotEmpty)
                                    ? Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: selectedList.map((s) {
                                        return Padding(
                                          padding:
                                          const EdgeInsets.only(right: 6),
                                          child: InputChip(
                                            label: Text(s),
                                            selected: true,
                                            showCheckmark: false,
                                            selectedColor: Colors.blueAccent
                                                .withOpacity(.12),
                                            labelStyle: const TextStyle(
                                                color: Colors.blueAccent),
                                            shape: const StadiumBorder(
                                              side: BorderSide(
                                                  color: Colors.blueAccent),
                                            ),
                                            deleteIcon: const Icon(Icons.close,
                                                size: 18,
                                                color: Colors.blueAccent),
                                            onDeleted: () async {
                                              setState(() {
                                                ausgewaehlteLeistungen[name]!
                                                    .remove(s);
                                                if (ausgewaehlteLeistungen[name]!
                                                    .isEmpty) {
                                                  ausgewaehlteLeistungen
                                                      .remove(name);
                                                  ausgewaehlteKategorien
                                                      .removeWhere(
                                                          (e) => e == name);
                                                }
                                              });
                                              await _countMatchesBasedOnSelections(
                                                  branchen:
                                                  tempBranchen.toList())
                                                  .then((c) => setModalState(
                                                      () => previewCount = c));
                                            },
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                )
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selectedList.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          color: Colors.orange.shade100,
                                        ),
                                        child: Text(
                                          '${selectedList.length}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () async {
                                  await _openLeistungskategorieDialog(name,
                                      branchen: tempBranchen.toList());
                                  await _recalc();
                                  setModalState(() {});
                                },
                              );
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // Sortieren (neue Bezeichnungen + Distanz)
                      Text(
                        'Sortieren',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      RadioListTile<SortOrder>(
                        value: SortOrder.priceAsc,
                        groupValue: tempSortOrder,
                        onChanged: (v) => setModalState(() => tempSortOrder = v!),
                        title: const Text('Niedrigster Preis'),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                      RadioListTile<SortOrder>(
                        value: SortOrder.priceDesc,
                        groupValue: tempSortOrder,
                        onChanged: (v) => setModalState(() => tempSortOrder = v!),
                        title: const Text('Höchster Preis'),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                      RadioListTile<SortOrder>(
                        value: SortOrder.distanceAsc,
                        groupValue: tempSortOrder,
                        onChanged: (v) => setModalState(() => tempSortOrder = v!),
                        title: const Text('In meiner Nähe'),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                    ],
                  ),

                  // Schwebender Button
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            _sortOrder = tempSortOrder;
                            ausgewaehlteZielgruppen =
                            List<String>.from(tempZielgruppen);
                          });

                          await _applyOfferFiltersFromSelections(
                              branchen: tempBranchen.toList());
                          setState(() {
                            ausgewaehlteBranchen
                              ..clear()
                              ..addAll(tempBranchen);
                          });
                          _ladeZielgruppenUndKategorien();

                          _dismissKeyboard();
                          if (mounted) Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const StadiumBorder(),
                          elevation: 4,
                        ),
                        child: Text(
                          '$previewCount Treffer',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------------

  Widget _buildWebBackground({required Widget child}) {
    if (!kIsWeb) return child;

    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/termini.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: child,
    );
  }

  void _openProfilFromWebHeader() {
    setState(() {
      geoeffneterDienstleister = null;
      _dienstleisterFavorisiert = false;
      _selectedIndex = 3;
    });
  }

  Widget _buildWebHeader() {
    final labels = ['Friseur', 'Barbershop', 'Nagelstudio', 'Kosmetikstudio'];

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0x14000000)),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'TERMINI',
            style: TextStyle(
              color: Colors.black,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.6,
              height: 1,
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 34,
                runSpacing: 8,
                children: labels
                    .map(
                      (label) => Text(
                    label,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(width: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PartnerWerdenPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Partner werden',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _openProfilFromWebHeader,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.person_outline, size: 18),
            label: const Text(
              'Mein Konto',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebPageShell({required Widget child}) {
    if (!kIsWeb || geoeffneterDienstleister != null) {
      return child;
    }

    return Column(
      children: [
        _buildWebHeader(),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildBodyByIndex(int index) {
    switch (index) {
      case 0:
        return geoeffneterDienstleister != null
            ? DienstleisterDetailPage(
          dienstleister: geoeffneterDienstleister!,
          selektierteZielgruppe: 'alle',
          selektierteKategorie: 'alle',
          onNavigateToTermine: () {
            if (!mounted) return;
            setState(() {
              geoeffneterDienstleister = null;
              _selectedIndex = 2;
            });
          },
        )
            : Column(
          children: [
            Padding(
              padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSuchfeldMitFilterButton(),
                ],
              ),
            ),
            Expanded(child: dienstleisterListeView()),
          ],
        );
      case 1:
        final userId = _aktuellerUserId;
        if (userId == null) return const LoginRegisterPage();
        return KundenFavoritenPage(
          userId: userId,
          onFavoritStatusChanged: (dienstleisterId, isFavorit) =>
              _setFavoritStatus(
                dienstleisterId: dienstleisterId,
                isFavorit: isFavorit,
              ),
          onOpenDienstleister: (dienstleister) {
            setState(() {
              _selectedIndex = 0;
              geoeffneterDienstleister = dienstleister;
              _dienstleisterFavorisiert = true;
            });
          },
        );
      case 2:
        return const KundenTerminePage();
      case 3:
        final user = FirebaseAuth.instance.currentUser;
        return user == null ? const LoginRegisterPage() : const KundenProfilPage();
      default:
        return const SizedBox.shrink();
    }
  }


// ---------- Inline-Chips unter dem Suchfeld ----------
  Widget _buildInlineFilterChips() {
    final bool branchenAktiv = ausgewaehlteBranchen.isNotEmpty;
    final String branchenText =
        'Branchen${branchenAktiv ? '(${ausgewaehlteBranchen.length})' : ''}';

    final int zielgruppenCount = ausgewaehlteZielgruppen.length;
    final bool zielgruppenAktiv = zielgruppenCount > 0;
    final String zielgruppenText =
        'Für wen${zielgruppenAktiv ? '($zielgruppenCount)' : ''}';

    final int leistungenCount =
    ausgewaehlteLeistungen.values.fold<int>(0, (s, l) => s + l.length);
    final bool leistungenAktiv = leistungenCount > 0;
    final String leistungenText =
        'Leistungen${leistungenAktiv ? '($leistungenCount)' : ''}';

    final bool sortAktiv = _sortOrder != SortOrder.none;

    final List<Widget> chips = [];

    // Branchen
    chips.add(
      InputChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                branchenText,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: branchenAktiv ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!branchenAktiv) ...[
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Colors.black54),
            ],
          ],
        ),
        selected: branchenAktiv,
        onSelected: (_) => _showBranchenQuickSheet(),
        onDeleted: branchenAktiv
            ? () async {
          setState(() {
            ausgewaehlteBranchen.clear();
          });
          await _applyOfferFiltersFromSelections(branchen: null);
          _ladeZielgruppenUndKategorien();
        }
            : null,
        deleteIcon: Icon(Icons.close,
            size: 18, color: branchenAktiv ? Colors.white : Colors.black54),
        selectedColor: Colors.blueAccent,
        backgroundColor: Colors.white,
        shape: const StadiumBorder(side: BorderSide(color: Colors.black)),
      ),
    );

    // Für wen? (nur sichtbar, wenn Zielgruppe aktiv gefiltert ist)
    if (zielgruppenAktiv) {
      chips.add(
        InputChip(
          label: Text(
            zielgruppenText,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          selected: true,
          onSelected: (_) => _showBranchenFilterSheet(),
          onDeleted: () async {
            setState(() {
              ausgewaehlteZielgruppen.clear();
            });
            await _applyOfferFiltersFromSelections(
              branchen: ausgewaehlteBranchen,
            );
          },
          deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white),
          selectedColor: Colors.blueAccent,
          backgroundColor: Colors.white,
          shape: const StadiumBorder(side: BorderSide(color: Colors.black)),
        ),
      );
    }

    // Leistungen (öffnet das Leistungen-Sheet)
    chips.add(
      InputChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                leistungenText,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: leistungenAktiv ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!leistungenAktiv) ...[
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Colors.black54),
            ],
          ],
        ),
        selected: leistungenAktiv,
        onSelected: (_) => _showLeistungenSheet(),
        onDeleted: leistungenAktiv
            ? () async {
          setState(() {
            ausgewaehlteKategorien.clear();
            ausgewaehlteLeistungen.clear();
          });
          await _applyOfferFiltersFromSelections(
              branchen: ausgewaehlteBranchen);
        }
            : null,
        deleteIcon: Icon(Icons.close,
            size: 18, color: leistungenAktiv ? Colors.white : Colors.black54),
        selectedColor: Colors.blueAccent,
        backgroundColor: Colors.white,
        shape: const StadiumBorder(side: BorderSide(color: Colors.black)),
      ),
    );
    // Sortieren
    chips.add(
      InputChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sortieren', style: TextStyle(fontWeight: FontWeight.w600)),
            if (!sortAktiv) ...[
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Colors.black54),
            ],
          ],
        ),
        selected: sortAktiv,
        onSelected: (_) => _showSortSheet(),
        onDeleted:
        sortAktiv ? () => setState(() => _sortOrder = SortOrder.none) : null,
        deleteIcon: Icon(Icons.close,
            size: 18, color: sortAktiv ? Colors.white : Colors.black54),
        selectedColor: Colors.blueAccent,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(color: sortAktiv ? Colors.white : Colors.black),
        shape: const StadiumBorder(side: BorderSide(color: Colors.black)),
      ),
    );

    if (!kIsWeb && _isCurrentLocationSelected) {
      final ortLabel =
      (_selectedLocationLabel ?? _selectedLocationValue ?? currentCity ?? '')
          .trim();
      if (ortLabel.isNotEmpty) {
        chips.add(
          InputChip(
            avatar: const Icon(
              Icons.location_on_outlined,
              size: 18,
              color: Color(0xFF1B8A3C),
            ),
            label: Text(
              ortLabel,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1B8A3C),
                fontWeight: FontWeight.w600,
              ),
            ),
            onSelected: (_) async {
              _dismissKeyboard();
              await _showLocationSelectionSheet();
            },
            onDeleted: () {
              _clearSelectedLocation();
            },
            deleteIcon: const Icon(
              Icons.close,
              size: 18,
              color: Color(0xFF1B8A3C),
            ),
            backgroundColor: const Color(0xFFE8F5E9),
            shape: const StadiumBorder(
              side: BorderSide(color: Color(0xFF34C759)),
            ),
          ),
        );
      }
    }

    // >>> HIER WIEDER DRIN: Kategorie-Chips (z. B. „Augenbrauen“) <<<
    for (final kategorie in ausgewaehlteKategorien) {
      final bool aktiv =
      (ausgewaehlteLeistungen[kategorie]?.isNotEmpty ?? false);

      chips.add(
        InputChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  kategorie,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: aktiv ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!aktiv) ...[
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: Colors.black54),
              ],
            ],
          ),
          selected: aktiv,
          onSelected: (_) async {
            await _openLeistungskategorieDialog(kategorie,
                branchen: ausgewaehlteBranchen);
            await _applyOfferFiltersFromSelections(
                branchen: ausgewaehlteBranchen);
            setState(() {});
          },
          onDeleted: aktiv
              ? () async {
            setState(() {
              ausgewaehlteLeistungen.remove(kategorie);
              ausgewaehlteKategorien.removeWhere((e) => e == kategorie);
            });
            await _applyOfferFiltersFromSelections(
                branchen: ausgewaehlteBranchen);
          }
              : null,
          deleteIcon: Icon(Icons.close,
              size: 18, color: aktiv ? Colors.white : Colors.black54),
          selectedColor: Colors.blueAccent,
          backgroundColor: Colors.white,
          shape: const StadiumBorder(side: BorderSide(color: Colors.black)),
        ),
      );
    }

    // HORIZONTALE, SCROLLBARE EIN-ZEILIGE REIHE
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            chips[i],
            if (i != chips.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ---------- Suchfeld + Filterbutton ----------
  Widget _buildLeistungSuchfeld() {
    return Autocomplete<_SearchSuggestion>(
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (textEditingValue.text == '') {
          return const Iterable<_SearchSuggestion>.empty();
        }
        final vorschlaegeLeistungen =
        await _ladeLeistungsVorschlaege(textEditingValue.text);
        final vorschlaegeDienstleister =
        await _ladeDienstleisterVorschlaege(textEditingValue.text);
        final vorschlaegeBranchen =
        await _ladeBranchenVorschlaege(textEditingValue.text);

        final leistungen =
        vorschlaegeLeistungen.map((e) => _SearchSuggestion.leistung(e)).toList();
        final dienstleister = vorschlaegeDienstleister
            .map(
              (e) => _SearchSuggestion.dienstleister(
            title: (e['name'] ?? '').toString(),
            subtitle:
            '${(e['plz'] ?? '').toString()} ${(e['ort'] ?? '').toString()}'.trim(),
            dienstleisterId: (e['id'] ?? '').toString(),
            logoUrl: (e['logoUrl'] ?? '').toString(),
          ),
        )
            .toList();
        final branchen =
        vorschlaegeBranchen.map((e) => _SearchSuggestion.branche(e)).toList();

        return [...dienstleister, ...branchen, ...leistungen];
      },
      displayStringForOption: (option) => option.title,
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList();
        final highlightQuery = _suchfeldController.text;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320, maxWidth: 700),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item.type == _SuggestionType.dienstleister) {
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFE0E0E0),
                        backgroundImage: (item.logoUrl ?? '').trim().isNotEmpty
                            ? NetworkImage(item.logoUrl!.trim())
                            : null,
                        child: (item.logoUrl ?? '').trim().isEmpty
                            ? const Icon(Icons.storefront, color: Colors.black54)
                            : null,
                      ),
                      title: RichText(
                        text: _buildHighlightedSpan(
                          fullText: item.title,
                          query: highlightQuery,
                          baseStyle: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      subtitle: RichText(
                        text: _buildHighlightedSpan(
                          fullText: item.subtitle,
                          query: highlightQuery,
                          baseStyle: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      onTap: () => onSelected(item),
                    );
                  }
                  if (item.type == _SuggestionType.branche) {
                    return ListTile(
                      leading: const Icon(Icons.sell_outlined),
                      title: RichText(
                        text: _buildHighlightedSpan(
                          fullText: item.title,
                          query: highlightQuery,
                          baseStyle: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      subtitle: const Text('Branche'),
                      onTap: () => onSelected(item),
                    );
                  }
                  return ListTile(
                    leading: const Icon(Icons.search),
                    title: RichText(
                      text: _buildHighlightedSpan(
                        fullText: item.title,
                        query: highlightQuery,
                        baseStyle: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    onTap: () => onSelected(item),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (_SearchSuggestion auswahl) async {
        _suchfeldController.text = auswahl.title;
        if (auswahl.type == _SuggestionType.dienstleister &&
            (auswahl.dienstleisterId ?? '').isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(auswahl.dienstleisterId)
              .get();
          if (!doc.exists) return;
          final data = doc.data() ?? {};
          await _openDienstleisterFromSuggestion({
            ...data,
            'id': doc.id,
          });
          return;
        }
        if (auswahl.type == _SuggestionType.branche) {
          await _applyBrancheSelectionFromSearch(auswahl.title);
          _dismissKeyboard();
          return;
        }

        setState(() {
          _ausgewaehlteLeistung = auswahl.title;
        });
        _clearSearchMode();
        await _applySelectionFromTitle(auswahl.title);
        _dismissKeyboard();
      },
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        if (_suchfeldController.text != controller.text) {
          _suchfeldController.value = controller.value;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onEditingComplete: onEditingComplete,
          onSubmitted: (text) async {
            await _activateSearchMode(text);
            _dismissKeyboard();
          },
          onChanged: (text) {
            _suchfeldController.value = controller.value;
            _onSuchbegriffChanged(text);
            if (text.trim().isEmpty) {
              _clearSearchMode();
            }
          },
          decoration: InputDecoration(
            hintText: 'Leistung, Dienstleister oder Branche',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: kIsWeb
                ? (controller.text.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                controller.clear();
                _suchfeldController.clear();
                _clearSearchMode();
              },
            )
                : null)
                : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      controller.clear();
                      _suchfeldController.clear();
                      _clearSearchMode();
                    },
                  ),
                IconButton(
                  tooltip: 'Ort auswählen',
                  icon: Icon(
                    Icons.location_on_outlined,
                    color:
                    _isCurrentLocationSelected ? const Color(0xFF34C759) : null,
                  ),
                  onPressed: () async {
                    _dismissKeyboard();
                    await _showLocationSelectionSheet();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrtSuchfeld() {
    return Autocomplete<_LocationSuggestion>(
      optionsBuilder: (TextEditingValue textEditingValue) async {
        final query = textEditingValue.text.trim();
        final items = <_LocationSuggestion>[
          _LocationSuggestion.currentLocation(currentCity ?? ''),
          const _LocationSuggestion.countryWide(),
        ];

        if (query.isNotEmpty) {
          final vorschlaege = await _ladeOrtsVorschlaege(query);
          for (final ort in vorschlaege) {
            if (!items.any(
                  (item) => item.fillValue.toLowerCase() == ort.toLowerCase(),
            )) {
              items.add(_LocationSuggestion.ort(ort));
            }
          }
        }

        return items;
      },
      displayStringForOption: (option) => option.fillValue,
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList();
        final highlightQuery = _ortsuchfeldController.text;
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: kIsWeb ? 340 : MediaQuery.of(context).size.width - 32,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final icon = switch (item.type) {
                      _LocationSuggestionType.currentLocation => Icons.my_location,
                      _LocationSuggestionType.countryWide => Icons.public,
                      _LocationSuggestionType.ort => Icons.location_on_outlined,
                    };
                    final textToHighlight = item.type == _LocationSuggestionType.ort
                        ? item.fillValue
                        : item.label;
                    return ListTile(
                      leading: Icon(icon, color: Colors.black54),
                      title: RichText(
                        text: _buildHighlightedSpan(
                          fullText: textToHighlight,
                          query: highlightQuery,
                          baseStyle: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      onTap: () => onSelected(item),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      onSelected: (_LocationSuggestion auswahl) {
        final selectedValue = switch (auswahl.type) {
          _LocationSuggestionType.currentLocation =>
          (currentCity ?? '').trim().isNotEmpty ? currentCity!.trim() : 'Aktueller Standort',
          _LocationSuggestionType.countryWide => 'Ganz Deutschland',
          _LocationSuggestionType.ort => auswahl.fillValue,
        };
        _setSelectedLocation(selectedValue);
        _dismissKeyboard();
      },
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        if (_ortsuchfeldController.text != controller.text) {
          _ortsuchfeldController.value = controller.value;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onEditingComplete: onEditingComplete,
          onSubmitted: (text) {
            final trimmed = text.trim();
            if (trimmed.isEmpty) {
              _clearSelectedLocation(clearTextField: false);
            } else {
              _setSelectedLocation(trimmed, addToRecent: true, updateTextField: false);
            }
            _dismissKeyboard();
          },
          onChanged: (text) {
            _ortsuchfeldController.value = controller.value;
            _handleLocationFieldChanged(text);
          },
          decoration: InputDecoration(
            hintText: 'Ort oder PLZ',
            prefixIcon: Icon(
              Icons.location_on_outlined,
              color: _isCurrentLocationSelected ? const Color(0xFF34C759) : null,
            ),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                controller.clear();
                _ortsuchfeldController.clear();
                _clearSelectedLocation(clearTextField: false);
              },
            )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildSuchfeldMitFilterButton() {
    final suchfeld = _buildLeistungSuchfeld();
    final ortSuchfeld = _buildOrtSuchfeld();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (kIsWeb) ...[
              Expanded(flex: 7, child: suchfeld),
              const SizedBox(width: 10),
              SizedBox(width: 320, child: ortSuchfeld),
            ] else ...[
              Expanded(child: suchfeld),
            ],
            const SizedBox(width: 8),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Filter',
                  iconSize: 26,
                  color: _filterBadgeCount > 0 ? Colors.blueAccent : null,
                  icon: const Icon(CupertinoIcons.slider_horizontal_3),
                  onPressed: () async {
                    _dismissKeyboard();
                    await _showBranchenFilterSheet();
                  },
                ),
                if (_filterBadgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        _filterBadgeCount > 99 ? '99+' : '$_filterBadgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildInlineFilterChips(),
      ],
    );
  }

  // ----------------------------------------------------------

  Widget _buildChipReihe(
      List<String> items, List<String> selectedItems, Function(String) onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((item) {
            final selected = selectedItems.contains(item);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                label: Text(
                  item[0].toUpperCase() + item.substring(1),
                ),
                selected: selected,
                onSelected: (_) => onTap(item),
                selectedColor: const Color(0xFFF7931E),
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                shape: const StadiumBorder(
                  side: BorderSide(color: Colors.black),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterChip() {
    return GestureDetector(
      onTap: () => setState(() => filterChipOffen = !filterChipOffen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: [
            Icon(Icons.filter_list, size: 20),
            SizedBox(width: 4),
            Text('Filter'),
          ],
        ),
      ),
    );
  }

  Widget dienstleisterListeView() {
    if (_isSearchMode) {
      return _buildSearchResultsView();
    }
    return _buildDefaultDienstleisterListeView();
  }

  Widget _buildSearchResultsView() {
    final search = _searchQuery.trim().toLowerCase();
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<Map<String, dynamic>> interneTreffer = [];
        final docs = snapshot.data!.docs;

        return FutureBuilder(
          future: Future.wait(docs.map((doc) async {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;

            if (data['geo'] != null) {
              final geo = data['geo'] as GeoPoint;
              final distanceInMeters = Geolocator.distanceBetween(
                userPosition!.latitude,
                userPosition!.longitude,
                geo.latitude,
                geo.longitude,
              );
              data['distance'] = distanceInMeters / 1000;
            } else {
              data['distance'] = double.infinity;
            }

            final suchFelder = <String>[
              (data['name'] ?? '').toString(),
              (data['branche'] ?? '').toString(),
              (data['adresse'] ?? '').toString(),
              (data['ort'] ?? '').toString(),
              (data['plz'] ?? '').toString(),
              (data['strasse'] ?? '').toString(),
              (data['hausnummer'] ?? '').toString(),
            ].join(' ').toLowerCase();

            if (!suchFelder.contains(search)) return;

            if (!_matchesSelectedLocation(data)) return;

            final branche = data['branche']?.toString();
            final branchePasst = ausgewaehlteBranchen.isEmpty ||
                ausgewaehlteBranchen.contains(branche);
            if (!branchePasst) return;

            interneTreffer.add(data);
          })),
          builder: (context, AsyncSnapshot<List<void>> snapshot2) {
            if (snapshot2.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            interneTreffer.sort((a, b) =>
                (a['distance'] as double).compareTo(b['distance'] as double));

            return ListView(
              children: [
                if (interneTreffer.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: Text(
                      'Interne Treffer',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ...interneTreffer.map((data) => DienstleisterTile(
                  data: data,
                  matchedOffers:
                  (data['matchedOffers'] as List<Map<String, dynamic>>?),
                  onTap: () {
                    final id = (data['id'] ?? '').toString();
                    setState(() {
                      geoeffneterDienstleister = data;
                      _dienstleisterFavorisiert = _favoritenIds.contains(id);
                    });
                  },
                )),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Externe Treffer (Google)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_isExternalSearchLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_externalSearchResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Text('Keine externen Treffer gefunden.'),
                  )
                else
                  ..._externalSearchResults.map(
                        (item) => _buildExternalResultCard(
                      name: (item['name'] ?? '').toString(),
                      address: (item['address'] ?? '').toString(),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Externer Eintrag ohne Detailseite.'),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildExternalResultCard({
    required String name,
    required String address,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEDED),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.storefront, size: 34, color: Colors.black54),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          address,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.place_rounded,
                                size: 15, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 5),
                            Text(
                              'Externer Treffer',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultDienstleisterListeView() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'dienstleister')
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<Map<String, dynamic>> dienstleisterMitLeistungen = [];
        final docs = snapshot.data!.docs;

        return FutureBuilder(
          future: Future.wait(docs.map((doc) async {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;

            if (data['geo'] != null) {
              final geo = data['geo'] as GeoPoint;
              final distanceInMeters = Geolocator.distanceBetween(
                userPosition!.latitude,
                userPosition!.longitude,
                geo.latitude,
                geo.longitude,
              );
              data['distance'] = distanceInMeters / 1000;
            } else {
              data['distance'] = double.infinity;
            }

            if (_gefilterteDienstleisterIds.isNotEmpty) {
              if (_gefilterteDienstleisterIds.contains(data['id'])) {
                if (!_matchesSelectedLocation(data)) {
                  return;
                }
                final matched =
                await _ladePassendeAngeboteFuerDienstleister(data['id']);
                if (matched.isNotEmpty) {
                  data['matchedOffers'] = matched;
                  dienstleisterMitLeistungen.add(data);
                }
              }
              return;
            }

            final angeboteSnap = await FirebaseFirestore.instance
                .collection('angebote')
                .where('dienstleisterId', isEqualTo: doc.id)
                .get();

            final angebote = angeboteSnap.docs.map((a) => a.data()).toList();
            data['angebote'] = angebote;

            final branche = data['branche']?.toString();
            final zielgruppen = <String>{};
            final kategorien = <String>{};

            for (final angebot in angebote) {
              final kategorie = (angebot['kategorie'] as String?)?.trim();
              if (kategorie != null && kategorie.isNotEmpty) {
                kategorien.add(kategorie);
              }

              final zgMap = angebot['zielgruppen'];
              if (zgMap is Map) {
                for (final key in zgMap.keys) {
                  final zg = key.toString().trim();
                  if (zg.isNotEmpty) zielgruppen.add(zg);
                }
              }
            }

            final branchePasst = ausgewaehlteBranchen.isEmpty ||
                ausgewaehlteBranchen.contains(branche);
            final zielgruppePasst = ausgewaehlteZielgruppen.isEmpty ||
                zielgruppen.any(ausgewaehlteZielgruppen.contains);
            final kategoriePasst = ausgewaehlteKategorien.isEmpty ||
                kategorien.any(ausgewaehlteKategorien.contains);

            bool leistungPasst = true;
            if (ausgewaehlteLeistungen.isNotEmpty) {
              leistungPasst = ausgewaehlteLeistungen.entries.every((entry) {
                final selectedKategorie = entry.key;
                final selectedLeistungen = entry.value.toSet();
                if (selectedLeistungen.isEmpty) return true;

                return angebote.any((angebot) {
                  final angebotKategorie = (angebot['kategorie'] as String?)?.trim();
                  if (angebotKategorie != selectedKategorie) return false;

                  final leistungsliste =
                      (angebot['leistungen'] as List?)?.cast<String>() ?? const <String>[];
                  final angebotSet = leistungsliste.map((e) => e.trim()).toSet();
                  return selectedLeistungen.every(angebotSet.contains);
                });
              });
            }

            if (branchePasst &&
                zielgruppePasst &&
                kategoriePasst &&
                leistungPasst &&
                _matchesSelectedLocation(data)) {
              dienstleisterMitLeistungen.add(data);
            }
          })),
          builder: (context, AsyncSnapshot<List<void>> snapshot2) {
            if (snapshot2.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Sortierung anwenden
            if (_sortOrder == SortOrder.priceAsc ||
                _sortOrder == SortOrder.priceDesc) {
              if (_gefilterteDienstleisterIds.isNotEmpty) {
                dienstleisterMitLeistungen.sort((a, b) {
                  final ap = _lowestPriceInOffers(
                      (a['matchedOffers'] as List<Map<String, dynamic>>?));
                  final bp = _lowestPriceInOffers(
                      (b['matchedOffers'] as List<Map<String, dynamic>>?));
                  int cmp;
                  if (ap == null && bp == null) {
                    cmp = 0;
                  } else if (ap == null) {
                    cmp = 1;
                  } else if (bp == null) {
                    cmp = -1;
                  } else {
                    cmp = _sortOrder == SortOrder.priceAsc
                        ? ap.compareTo(bp)
                        : bp.compareTo(ap);
                  }
                  if (cmp == 0) {
                    cmp = (a['distance'] as double)
                        .compareTo(b['distance'] as double);
                  }
                  return cmp;
                });
              } else {
                // keine Preisinfos → Distanz
                dienstleisterMitLeistungen.sort((a, b) =>
                    (a['distance'] as double).compareTo(b['distance'] as double));
              }
            } else if (_sortOrder == SortOrder.distanceAsc) {
              dienstleisterMitLeistungen.sort((a, b) =>
                  (a['distance'] as double).compareTo(b['distance'] as double));
            } else {
              // Default: Distanz
              dienstleisterMitLeistungen.sort((a, b) =>
                  (a['distance'] as double).compareTo(b['distance'] as double));
            }

            return ListView.builder(
              itemCount: dienstleisterMitLeistungen.length,
              itemBuilder: (context, index) {
                final data = dienstleisterMitLeistungen[index];
                return DienstleisterTile(
                  data: data,
                  matchedOffers:
                  (data['matchedOffers'] as List<Map<String, dynamic>>?),
                  onTap: () {
                    final id = (data['id'] ?? '').toString();
                    setState(() {
                      geoeffneterDienstleister = data;
                      _dienstleisterFavorisiert = _favoritenIds.contains(id);
                    });
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatOeffnungszeitForTag(Map<String, dynamic> oeffnungszeiten, String key) {
    final raw = oeffnungszeiten[key];
    if (raw is! Map) return 'Geschlossen';
    final map = Map<String, dynamic>.from(raw);
    final aktiv = map['aktiv'] is bool ? map['aktiv'] as bool : false;
    if (!aktiv) return 'Geschlossen';
    final von = (map['von'] ?? '').toString().trim();
    final bis = (map['bis'] ?? '').toString().trim();
    if (von.isEmpty || bis.isEmpty) return 'Geschlossen';
    return '$von - $bis';
  }

  Future<void> _launchExternalUri(Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konnte Navigation nicht öffnen.')),
      );
    }
  }

  Future<void> _openRouteInMaps({
    required double latitude,
    required double longitude,
  }) async {
    final destination = '$latitude,$longitude';
    final mapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination='
          '${Uri.encodeComponent(destination)}&travelmode=driving',
    );
    await _launchExternalUri(mapsUri);
  }

  Future<void> _startNavigation({
    required double latitude,
    required double longitude,
  }) async {
    final destination = '$latitude,$longitude';
    final navigationUri = Uri.parse(
      'google.navigation:q=${Uri.encodeComponent(destination)}&mode=d',
    );
    if (await canLaunchUrl(navigationUri)) {
      await _launchExternalUri(navigationUri);
      return;
    }
    await _openRouteInMaps(
      latitude: latitude,
      longitude: longitude,
    );
  }

  void _showDienstleisterInfoSheet() {
    final data = geoeffneterDienstleister;
    if (data == null) return;

    final name = (data['name'] ?? 'Dienstleister').toString().trim();
    final strasse = (data['strasse'] ?? data['adresse'] ?? '').toString().trim();
    final hausnummer = (data['hausnummer'] ?? '').toString().trim();
    final plz = (data['plz'] ?? '').toString().trim();
    final ort = (data['ort'] ?? '').toString().trim();
    final zeile1 = [strasse, hausnummer].where((e) => e.isNotEmpty).join(' ');
    final zeile2 = [plz, ort].where((e) => e.isNotEmpty).join(' ');
    final dienstleisterId = (data['id'] ?? '').toString().trim();
    final oeffnungszeiten = data['oeffnungszeiten'] is Map
        ? Map<String, dynamic>.from(data['oeffnungszeiten'] as Map)
        : <String, dynamic>{};
    final geo = data['geo'];
    final hasGeo = geo is GeoPoint;
    final destinationLatitude = hasGeo ? geo.latitude : null;
    final destinationLongitude = hasGeo ? geo.longitude : null;

    const tage = <MapEntry<String, String>>[
      MapEntry('montag', 'Montag'),
      MapEntry('dienstag', 'Dienstag'),
      MapEntry('mittwoch', 'Mittwoch'),
      MapEntry('donnerstag', 'Donnerstag'),
      MapEntry('freitag', 'Freitag'),
      MapEntry('samstag', 'Samstag'),
      MapEntry('sonntag', 'Sonntag'),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 6,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8FC),
              borderRadius: BorderRadius.circular(28),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      name.isEmpty ? 'Dienstleister' : name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 18),
                              const SizedBox(width: 6),
                              const Text(
                                'Adresse',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              _AddressActionButton(
                                label: 'Route',
                                icon: Icons.directions,
                                onPressed: hasGeo
                                    ? () => _openRouteInMaps(
                                  latitude: destinationLatitude!,
                                  longitude: destinationLongitude!,
                                )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              _AddressActionButton(
                                label: 'Starten',
                                icon: Icons.navigation,
                                onPressed: hasGeo
                                    ? () => _startNavigation(
                                  latitude: destinationLatitude!,
                                  longitude: destinationLongitude!,
                                )
                                    : null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (zeile1.isNotEmpty) Text(zeile1),
                          if (zeile2.isNotEmpty) Text(zeile2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.schedule_outlined, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Öffnungszeiten',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...tage.map(
                                (tag) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(tag.value),
                                  Text(
                                    _formatOeffnungszeitForTag(
                                      oeffnungszeiten,
                                      tag.key,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.groups_2_outlined, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Mitarbeiter',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (dienstleisterId.isEmpty)
                            const Text('Keine Mitarbeiter gefunden.')
                          else
                            FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              future: FirebaseFirestore.instance
                                  .collection('users')
                                  .where('rolle', isEqualTo: 'mitarbeiter')
                                  .where('dienstleisterId', isEqualTo: dienstleisterId)
                                  .get(),
                              builder: (context, snap) {
                                if (snap.connectionState == ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }
                                final docs = snap.data?.docs ??
                                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                                if (docs.isEmpty) {
                                  return const Text('Keine Mitarbeiter gefunden.');
                                }
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: docs.map((doc) {
                                    final d = doc.data();
                                    final mitarbeiterName =
                                    (d['name'] ?? '').toString().trim();
                                    final profileImageUrl =
                                    (d['profileImageUrl'] ?? '').toString().trim();
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F2F8),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 12,
                                            backgroundColor: Colors.grey.shade300,
                                            backgroundImage: profileImageUrl.isNotEmpty
                                                ? NetworkImage(profileImageUrl)
                                                : null,
                                            child: profileImageUrl.isEmpty
                                                ? const Icon(
                                              Icons.person,
                                              size: 14,
                                              color: Colors.black54,
                                            )
                                                : null,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            mitarbeiterName.isEmpty
                                                ? 'Mitarbeiter'
                                                : mitarbeiterName,
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || userPosition == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bool showDefaultAppBar = !kIsWeb || geoeffneterDienstleister != null;

    return Scaffold(
      backgroundColor: kIsWeb ? Colors.transparent : null,
      appBar: showDefaultAppBar
          ? AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          geoeffneterDienstleister != null
              ? ((geoeffneterDienstleister!['name'] ?? '').toString().trim().isNotEmpty
              ? geoeffneterDienstleister!['name'].toString().trim()
              : 'Dienstleister')
              : (currentCity != null ? currentCity! : 'Ort wird geladen...'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        leading: geoeffneterDienstleister != null
            ? IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            setState(() {
              geoeffneterDienstleister = null;
              _dienstleisterFavorisiert = false;
            });
          },
        )
            : null,
        actions: geoeffneterDienstleister != null
            ? [
          IconButton(
            tooltip: 'Info',
            onPressed: _showDienstleisterInfoSheet,
            icon: const Icon(Icons.info_outline, color: Colors.black),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () {
                final dienstleisterId =
                (geoeffneterDienstleister?['id'] ?? '').toString();
                final next = !_dienstleisterFavorisiert;
                _setFavoritStatus(
                  dienstleisterId: dienstleisterId,
                  isFavorit: next,
                );
              },
              icon: _dienstleisterFavorisiert
                  ? const Icon(Icons.favorite, color: Colors.red)
                  : const Icon(Icons.favorite_border, color: Colors.black),
            ),
          ),
        ]
            : null,
      )
          : null,
      body: _buildWebBackground(
        child: _buildWebPageShell(
          child: _buildBodyByIndex(_selectedIndex),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            geoeffneterDienstleister = null;
            _dienstleisterFavorisiert = false;
            _selectedIndex = index;
          });
        },
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        backgroundColor: Colors.white,
        elevation: 8,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Suchen'),
          BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border), label: 'Favoriten'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: 'Termine'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }
}
