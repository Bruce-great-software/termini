import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'alle_dienstleister_page.dart';
import 'login_register_page.dart';

enum _SuggestionType { leistung, dienstleister }

class _SearchSuggestion {
  final _SuggestionType type;
  final String title;
  final String subtitle;
  final String? logoUrl;

  const _SearchSuggestion.leistung(this.title)
      : type = _SuggestionType.leistung,
        subtitle = '',
        logoUrl = null;

  const _SearchSuggestion.dienstleister({
    required this.title,
    required this.subtitle,
    required this.logoUrl,
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
      String eingabe) async {
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
            'name': (data['name'] ?? '').toString(),
            'ort': (data['ort'] ?? '').toString(),
            'plz': (data['plz'] ?? '').toString(),
            'logoUrl': (data['logoUrl'] ?? '').toString(),
          };
        })
        .where((d) => (d['name'] as String).toLowerCase().contains(search))
        .toList();

    matches.sort((a, b) => (a['name'] as String)
        .toLowerCase()
        .compareTo((b['name'] as String).toLowerCase()));
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

  @override
  void dispose() {
    _suchfeldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 760,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/termini.png',
                    fit: BoxFit.cover,
                  ),

                  Container(
                    color: Colors.black.withOpacity(0.28),
                  ),

                  Column(
                    children: [
                      Container(
                        height: 76,
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        color: Colors.white,
                        child: Row(
                          children: [
                            const Text(
                              'TERMINI',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 4,
                                color: Colors.black,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black87,
                              ),
                              child: const Text(
                                'Friseur',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black87,
                              ),
                              child: const Text(
                                'Barbershop',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black87,
                              ),
                              child: const Text(
                                'Kosmetik',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 28),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF111111),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginRegisterPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.person_outline, size: 20),
                              label: const Text(
                                'Mein Konto',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Buchen Sie Ihren Termin',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 54,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'Schnell • Einfach • Online',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 38),

                                Container(
                                  constraints:
                                  const BoxConstraints(maxWidth: 920),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.18),
                                        blurRadius: 24,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 6,
                                          ),
                                          decoration: const BoxDecoration(
                                            border: Border(
                                              right: BorderSide(
                                                color: Color(0xFFE6E6E6),
                                              ),
                                            ),
                                          ),
                                          child: Autocomplete<_SearchSuggestion>(
                                            optionsBuilder: (textEditingValue) async {
                                              if (textEditingValue.text.trim().isEmpty) {
                                                return const Iterable<_SearchSuggestion>.empty();
                                              }
                                              final vorschlaegeLeistungen =
                                                  await _ladeLeistungsVorschlaege(
                                                      textEditingValue.text);
                                              final vorschlaegeDienstleister =
                                                  await _ladeDienstleisterVorschlaege(
                                                      textEditingValue.text);

                                              final leistungen = vorschlaegeLeistungen
                                                  .map((e) => _SearchSuggestion.leistung(e))
                                                  .toList();
                                              final dienstleister =
                                                  vorschlaegeDienstleister
                                                      .map(
                                                        (e) =>
                                                            _SearchSuggestion.dienstleister(
                                                          title:
                                                              (e['name'] ?? '').toString(),
                                                          subtitle:
                                                              '${(e['plz'] ?? '').toString()} ${(e['ort'] ?? '').toString()}'
                                                                  .trim(),
                                                          logoUrl:
                                                              (e['logoUrl'] ?? '')
                                                                  .toString(),
                                                        ),
                                                      )
                                                      .toList();

                                              return [...dienstleister, ...leistungen];
                                            },
                                            displayStringForOption: (option) => option.title,
                                            onSelected: (auswahl) {
                                              _suchfeldController.text = auswahl.title;
                                            },
                                            optionsViewBuilder:
                                                (context, onSelected, options) {
                                              final items = options.toList();
                                              return Align(
                                                alignment: Alignment.topLeft,
                                                child: Material(
                                                  elevation: 4,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: ConstrainedBox(
                                                    constraints: const BoxConstraints(
                                                      maxHeight: 320,
                                                      maxWidth: 540,
                                                    ),
                                                    child: ListView.separated(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                              vertical: 8),
                                                      shrinkWrap: true,
                                                      itemCount: items.length,
                                                      separatorBuilder: (_, __) =>
                                                          const Divider(height: 1),
                                                      itemBuilder:
                                                          (context, index) {
                                                        final item = items[index];
                                                        if (item.type ==
                                                            _SuggestionType
                                                                .dienstleister) {
                                                          return ListTile(
                                                            leading: CircleAvatar(
                                                              radius: 22,
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFFE0E0E0),
                                                              backgroundImage: (item
                                                                          .logoUrl ??
                                                                      '')
                                                                  .trim()
                                                                  .isNotEmpty
                                                                  ? NetworkImage(item
                                                                      .logoUrl!
                                                                      .trim())
                                                                  : null,
                                                              child: (item.logoUrl ??
                                                                          '')
                                                                      .trim()
                                                                      .isEmpty
                                                                  ? const Icon(
                                                                      Icons
                                                                          .storefront,
                                                                      color: Colors
                                                                          .black54,
                                                                    )
                                                                  : null,
                                                            ),
                                                            title: RichText(
                                                              text:
                                                                  _buildHighlightedSpan(
                                                                fullText: item.title,
                                                                query:
                                                                    _suchfeldController
                                                                        .text,
                                                                baseStyle: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodyLarge,
                                                              ),
                                                            ),
                                                            subtitle: RichText(
                                                              text:
                                                                  _buildHighlightedSpan(
                                                                fullText:
                                                                    item.subtitle,
                                                                query:
                                                                    _suchfeldController
                                                                        .text,
                                                                baseStyle: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodyMedium,
                                                              ),
                                                            ),
                                                            onTap: () =>
                                                                onSelected(item),
                                                          );
                                                        }
                                                        return ListTile(
                                                          leading:
                                                              const Icon(Icons.search),
                                                          title: RichText(
                                                            text:
                                                                _buildHighlightedSpan(
                                                              fullText: item.title,
                                                              query:
                                                                  _suchfeldController
                                                                      .text,
                                                              baseStyle: Theme.of(
                                                                      context)
                                                                  .textTheme
                                                                  .bodyLarge,
                                                            ),
                                                          ),
                                                          onTap: () =>
                                                              onSelected(item),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                            fieldViewBuilder: (context, controller,
                                                focusNode, onEditingComplete) {
                                              if (_suchfeldController.text !=
                                                  controller.text) {
                                                _suchfeldController.value =
                                                    controller.value;
                                              }
                                              return TextField(
                                                controller: controller,
                                                focusNode: focusNode,
                                                onEditingComplete:
                                                    onEditingComplete,
                                                decoration: const InputDecoration(
                                                  border: InputBorder.none,
                                                  isDense: true,
                                                  hintText:
                                                      'Salonname, Dienstleistung...',
                                                  labelText: 'Was suchen Sie?',
                                                  labelStyle: TextStyle(
                                                    color: Color(0xFF8A8A8A),
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 6,
                                          ),
                                          child: const TextField(
                                            decoration: InputDecoration(
                                              border: InputBorder.none,
                                              isDense: true,
                                              hintText: 'Adresse, Stadt...',
                                              labelText: 'Wo',
                                              labelStyle: TextStyle(
                                                color: Color(0xFF8A8A8A),
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        height: 56,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                            const Color(0xFF111111),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 28,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.circular(12),
                                            ),
                                          ),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                const AlleDienstleisterPage(),
                                              ),
                                            );
                                          },
                                          child: const Text(
                                            'Suchen',
                                            style: TextStyle(

                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
    );
  }
}
