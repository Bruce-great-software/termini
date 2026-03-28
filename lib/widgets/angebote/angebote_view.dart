import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum AngeboteViewMode { customer, selection }

class AngebotSelectionItem {
  final String category;
  final String title;
  final String subtitle;
  final double? price;
  final double? originalPrice;
  final int? duration;

  const AngebotSelectionItem({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.originalPrice,
    required this.duration,
  });
}

class AngeboteView extends StatefulWidget {
  const AngeboteView({
    super.key,
    required this.angeboteStream,
    required this.builder,
    this.emptyText = 'Keine Angebote vorhanden.',
  })  : mode = AngeboteViewMode.customer,
        dienstleisterId = null,
        initialSelection = const <AngebotSelectionItem>[],
        onSelectionChanged = null;

  const AngeboteView.selection({
    super.key,
    required this.dienstleisterId,
    this.initialSelection = const <AngebotSelectionItem>[],
    this.onSelectionChanged,
    this.emptyText = 'Keine Angebote vorhanden.',
  })  : mode = AngeboteViewMode.selection,
        angeboteStream = null,
        builder = null;

  final AngeboteViewMode mode;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? angeboteStream;
  final Widget Function(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  )? builder;
  final String emptyText;

  final String? dienstleisterId;
  final List<AngebotSelectionItem> initialSelection;
  final ValueChanged<List<AngebotSelectionItem>>? onSelectionChanged;

  @override
  State<AngeboteView> createState() => _AngeboteViewState();
}

class _AngeboteViewState extends State<AngeboteView> {
  String _zielgruppe = 'Damen';
  String? _selectedKategorie;
  final Set<String> _selectedKeys = <String>{};

  @override
  void initState() {
    super.initState();
    for (final item in widget.initialSelection) {
      _selectedKeys.add(_buildSelectionKey(item));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == AngeboteViewMode.customer) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.angeboteStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs =
              snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (docs.isEmpty) {
            return Center(child: Text(widget.emptyText));
          }

          return widget.builder!(context, docs);
        },
      );
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final dienstleisterId = currentUser?.uid.trim().isNotEmpty == true
        ? currentUser!.uid.trim()
        : (widget.dienstleisterId ?? '').trim();

    if (dienstleisterId.isEmpty) {
      return Center(child: Text(widget.emptyText));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('angebote')
          .where('dienstleisterId', isEqualTo: dienstleisterId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs =
            snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (docs.isEmpty) {
          return Center(child: Text(widget.emptyText));
        }

        final entries = docs
            .map((doc) => _mapDocToSelectionItem(doc.data(), _zielgruppe))
            .whereType<AngebotSelectionItem>()
            .toList(growable: false);

        if (entries.isEmpty) {
          return Center(child: Text(widget.emptyText));
        }

        final kategorien = entries
            .map((entry) => entry.category.trim().isNotEmpty ? entry.category : 'Leistungen')
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        final selectedKategorie = (_selectedKategorie != null &&
                kategorien.contains(_selectedKategorie))
            ? _selectedKategorie
            : kategorien.first;
        _selectedKategorie = selectedKategorie;

        final visible = entries.where((entry) {
          final category = entry.category.trim().isNotEmpty ? entry.category : 'Leistungen';
          return category == selectedKategorie;
        }).toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CupertinoSegmentedControl<String>(
              children: const {
                'Damen': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text('Damen'),
                ),
                'Herren': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text('Herren'),
                ),
                'Kinder': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text('Kinder'),
                ),
              },
              groupValue: _zielgruppe,
              onValueChanged: (value) => setState(() => _zielgruppe = value),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: kategorien.map((kategorie) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(kategorie),
                      selected: _selectedKategorie == kategorie,
                      onSelected: (_) => setState(() => _selectedKategorie = kategorie),
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = visible[index];
                  final key = _buildSelectionKey(item);
                  final isSelected = _selectedKeys.contains(key);

                  final subtitleParts = <String>[
                    if (item.subtitle.trim().isNotEmpty) item.subtitle.trim(),
                    if (item.duration != null && item.duration! > 0) '${item.duration} Min',
                    if (item.price != null && item.price! > 0) _formatEuro(item.price!),
                  ];

                  return CheckboxListTile(
                    value: isSelected,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: subtitleParts.isEmpty
                        ? null
                        : Text(
                            subtitleParts.join(' • '),
                            style: const TextStyle(color: Color(0xFF667085)),
                          ),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        if (value) {
                          _selectedKeys.add(key);
                        } else {
                          _selectedKeys.remove(key);
                        }
                      });

                      final selectedItems = entries
                          .where((entry) => _selectedKeys.contains(_buildSelectionKey(entry)))
                          .toList(growable: false);
                      widget.onSelectionChanged?.call(selectedItems);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  AngebotSelectionItem? _mapDocToSelectionItem(
    Map<String, dynamic> data,
    String zielgruppe,
  ) {
    final title = _extractOfferTitle(data);
    if (title.isEmpty) return null;

    final category = (data['kategorie'] as String?)?.trim() ?? '';
    final subtitle = _extractOfferSubtitle(data);
    final price = _extractOfferPrice(data, zielgruppe);
    final duration = _extractOfferDuration(data, zielgruppe);

    return AngebotSelectionItem(
      category: category,
      title: title,
      subtitle: subtitle,
      price: price,
      originalPrice: price,
      duration: duration,
    );
  }

  String _buildSelectionKey(AngebotSelectionItem item) {
    return '${item.category}|${item.title}|${item.subtitle}';
  }

  String _extractOfferTitle(Map<String, dynamic> data) {
    final titel = (data['titel'] as String?)?.trim();
    if (titel != null && titel.isNotEmpty) return titel;

    if (data['leistungenSortiert'] is List) {
      final parts = (data['leistungenSortiert'] as List)
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
      if (parts.isNotEmpty) return parts.join(' + ');
    }

    if (data['leistungen'] is List) {
      final parts = (data['leistungen'] as List)
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
      if (parts.isNotEmpty) return parts.join(' + ');
    }

    return '';
  }

  String _extractOfferSubtitle(Map<String, dynamic> data) {
    if (data['varianten'] is List) {
      final parts = (data['varianten'] as List)
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
      if (parts.isNotEmpty) return parts.join(' • ');
    }
    return '';
  }

  double? _extractOfferPrice(Map<String, dynamic> data, String zielgruppe) {
    final direct = <double>[];
    if (data['preis'] is num) {
      direct.add((data['preis'] as num).toDouble());
    }
    final zgMap = data['zielgruppen'];
    if (zgMap is Map && zgMap[zielgruppe] is Map) {
      final value = (zgMap[zielgruppe] as Map)['preis'];
      if (value is num) direct.add(value.toDouble());
    }
    final positive = direct.where((entry) => entry > 0).toList(growable: false);
    if (positive.isEmpty) return null;
    positive.sort();
    return positive.first;
  }

  int? _extractOfferDuration(Map<String, dynamic> data, String zielgruppe) {
    final direct = <int>[];
    if (data['dauer'] is num) {
      direct.add((data['dauer'] as num).toInt());
    }
    final zgMap = data['zielgruppen'];
    if (zgMap is Map && zgMap[zielgruppe] is Map) {
      final value = (zgMap[zielgruppe] as Map)['dauer'];
      if (value is num) direct.add(value.toInt());
    }
    final positive = direct.where((entry) => entry > 0).toList(growable: false);
    if (positive.isEmpty) return null;
    positive.sort();
    return positive.first;
  }

  String _formatEuro(double value) {
    final asString = value.toStringAsFixed(2).replaceAll('.', ',');
    return '$asString €';
  }
}
