import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'alle_dienstleister_page.dart';
import 'dienstleister_detail_page.dart';
import 'login_register_page.dart';

enum _SuggestionType { leistung, dienstleister }

class _SearchSuggestion {
  final _SuggestionType type;
  final String title;
  final String subtitle;
  final String? logoUrl;
  final String? dienstleisterId;

  const _SearchSuggestion.leistung(this.title)
      : type = _SuggestionType.leistung,
        subtitle = '',
        logoUrl = null,
        dienstleisterId = null;

  const _SearchSuggestion.dienstleister({
    required this.title,
    required this.subtitle,
    required this.logoUrl,
    required this.dienstleisterId,
  }) : type = _SuggestionType.dienstleister;
}

class WebStartPage extends StatefulWidget {
  const WebStartPage({super.key});

  @override
  State<WebStartPage> createState() => _WebStartPageState();
}

class _WebStartPageState extends State<WebStartPage> {
  final TextEditingController _suchfeldController = TextEditingController();

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

  Future<List<Map<String, dynamic>>> _ladeDienstleisterVorschlaege(
    String eingabe,
  ) async {
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
          };
        })
        .where((d) => (d['name'] as String).toLowerCase().contains(search))
        .toList();

    matches.sort(
      (a, b) =>
          (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()),
    );
    return matches.take(8).toList();
  }

  TextSpan _buildHighlightedSpan({
    required String fullText,
    required String query,
    TextStyle? baseStyle,
  }) {
    final q = query.trim();
    if (q.isEmpty) return TextSpan(text: fullText, style: baseStyle);

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

  Future<void> _openDienstleisterFromSuggestion(_SearchSuggestion auswahl) async {
    final id = (auswahl.dienstleisterId ?? '').trim();
    if (id.isEmpty) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
    if (!doc.exists || !mounted) return;

    final data = doc.data() ?? {};
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DienstleisterDetailPage(
          dienstleister: {
            ...data,
            'id': doc.id,
          },
          selektierteZielgruppe: 'alle',
          selektierteKategorie: 'alle',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _suchfeldController.dispose();
    super.dispose();
  }

  Widget _buildFilterChip(String label) {
    return OutlinedButton.icon(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1D1D1D),
        backgroundColor: Colors.white,
        side: BorderSide(color: Colors.black.withOpacity(0.08)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/termini.png', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.24)),
          ),
          SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  child: Row(
                    children: [
                      const Text(
                        'TERMINI',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      ...['Friseur', 'Barbershop', 'Nagelstudio', 'Kosmetikstudio'].map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF313131),
                            ),
                            child: Text(item, style: const TextStyle(fontSize: 25)),
                          ),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          elevation: 0,
                        ),
                        child: const Text('Partner werden'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginRegisterPage()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Mein Konto'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Container(
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  const Icon(Icons.search, color: Color(0xFF555555)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Autocomplete<_SearchSuggestion>(
                                      optionsBuilder: (textEditingValue) async {
                                        if (textEditingValue.text.trim().isEmpty) {
                                          return const Iterable<_SearchSuggestion>.empty();
                                        }
                                        final vorschlaegeLeistungen =
                                            await _ladeLeistungsVorschlaege(textEditingValue.text);
                                        final vorschlaegeDienstleister =
                                            await _ladeDienstleisterVorschlaege(textEditingValue.text);

                                        final leistungen = vorschlaegeLeistungen
                                            .map((e) => _SearchSuggestion.leistung(e))
                                            .toList();
                                        final dienstleister = vorschlaegeDienstleister
                                            .map(
                                              (e) => _SearchSuggestion.dienstleister(
                                                title: (e['name'] ?? '').toString(),
                                                subtitle:
                                                    '${(e['plz'] ?? '').toString()} ${(e['ort'] ?? '').toString()}'.trim(),
                                                logoUrl: (e['logoUrl'] ?? '').toString(),
                                                dienstleisterId: (e['id'] ?? '').toString(),
                                              ),
                                            )
                                            .toList();

                                        return [...dienstleister, ...leistungen];
                                      },
                                      displayStringForOption: (option) => option.title,
                                      onSelected: (auswahl) async {
                                        _suchfeldController.text = auswahl.title;
                                        if (auswahl.type == _SuggestionType.dienstleister &&
                                            (auswahl.dienstleisterId ?? '').trim().isNotEmpty) {
                                          await _openDienstleisterFromSuggestion(auswahl);
                                        }
                                      },
                                      optionsViewBuilder: (context, onSelected, options) {
                                        final items = options.toList();
                                        return Align(
                                          alignment: Alignment.topLeft,
                                          child: Material(
                                            elevation: 4,
                                            borderRadius: BorderRadius.circular(12),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxHeight: 320,
                                                maxWidth: 540,
                                              ),
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
                                                        backgroundImage: (item.logoUrl ?? '')
                                                                .trim()
                                                                .isNotEmpty
                                                            ? NetworkImage(item.logoUrl!.trim())
                                                            : null,
                                                        child: (item.logoUrl ?? '').trim().isEmpty
                                                            ? const Icon(
                                                                Icons.storefront,
                                                                color: Colors.black54,
                                                              )
                                                            : null,
                                                      ),
                                                      title: RichText(
                                                        text: _buildHighlightedSpan(
                                                          fullText: item.title,
                                                          query: _suchfeldController.text,
                                                          baseStyle:
                                                              Theme.of(context).textTheme.bodyLarge,
                                                        ),
                                                      ),
                                                      subtitle: RichText(
                                                        text: _buildHighlightedSpan(
                                                          fullText: item.subtitle,
                                                          query: _suchfeldController.text,
                                                          baseStyle:
                                                              Theme.of(context).textTheme.bodyMedium,
                                                        ),
                                                      ),
                                                      onTap: () => onSelected(item),
                                                    );
                                                  }
                                                  return ListTile(
                                                    leading: const Icon(Icons.search),
                                                    title: RichText(
                                                      text: _buildHighlightedSpan(
                                                        fullText: item.title,
                                                        query: _suchfeldController.text,
                                                        baseStyle:
                                                            Theme.of(context).textTheme.bodyLarge,
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
                                      fieldViewBuilder: (
                                        context,
                                        controller,
                                        focusNode,
                                        onEditingComplete,
                                      ) {
                                        if (_suchfeldController.text != controller.text) {
                                          _suchfeldController.value = controller.value;
                                        }
                                        return TextField(
                                          controller: controller,
                                          focusNode: focusNode,
                                          onEditingComplete: onEditingComplete,
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            isDense: true,
                                            hintText: 'Leistung, oder Dienstleister',
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Container(
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: const Row(
                                children: [
                                  Icon(Icons.location_on_outlined, color: Color(0xFF555555)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        hintText: 'Ort oder PLZ',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.tune_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildFilterChip('Branchen'),
                          const SizedBox(width: 10),
                          _buildFilterChip('Leistungen'),
                          const SizedBox(width: 10),
                          _buildFilterChip('Sortieren'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .where('rolle', isEqualTo: 'dienstleister')
                            .limit(20)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 48),
                              child: CircularProgressIndicator(color: Colors.white),
                            );
                          }

                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Keine Dienstleister gefunden.',
                                style: TextStyle(fontSize: 16),
                              ),
                            );
                          }

                          return Column(
                            children: docs.map((doc) {
                              final data = doc.data();
                              final name = (data['name'] ?? 'Dienstleister').toString();
                              final strasse = (data['strasse'] ?? '').toString();
                              final hausnummer = (data['hausnummer'] ?? '').toString();
                              final plz = (data['plz'] ?? '').toString();
                              final ort = (data['ort'] ?? '').toString();
                              final logoUrl = (data['logoUrl'] ?? '').toString();
                              final branche = (data['kategorie'] ?? 'Friseure').toString();

                              final adresse =
                                  '$strasse $hausnummer, $plz $ort'.replaceAll(RegExp(r'\s+'), ' ').trim();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(22),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DienstleisterDetailPage(
                                          dienstleister: {
                                            ...data,
                                            'id': doc.id,
                                          },
                                          selektierteZielgruppe: 'alle',
                                          selektierteKategorie: 'alle',
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.96),
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(16),
                                          child: Container(
                                            height: 92,
                                            width: 92,
                                            color: const Color(0xFFE7E7E7),
                                            child: (logoUrl.trim().isNotEmpty)
                                                ? Image.network(logoUrl, fit: BoxFit.cover)
                                                : const Icon(Icons.store_mall_directory_rounded),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontSize: 35,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF1F1F1F),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                adresse,
                                                style: const TextStyle(
                                                  fontSize: 28,
                                                  color: Color(0xFF555555),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFEFEFFF),
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: Text(
                                                      branche,
                                                      style: const TextStyle(
                                                        color: Color(0xFF4C5AA9),
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFEFEFFF),
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: const Text(
                                                      '• 5,0 (32+)',
                                                      style: TextStyle(
                                                        color: Color(0xFF4C5AA9),
                                                        fontWeight: FontWeight.w600,
                                                      ),
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
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: 240,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AlleDienstleisterPage(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Mehr anzeigen'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
