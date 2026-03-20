import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/leistung_erstellen_dialog.dart';

class DienstleisterAngebotePage extends StatefulWidget {
  const DienstleisterAngebotePage({
    super.key,
    this.showScaffold = true,
  });

  final bool showScaffold;

  @override
  State<DienstleisterAngebotePage> createState() =>
      _DienstleisterAngebotePageState();
}

class _DienstleisterAngebotePageState extends State<DienstleisterAngebotePage> {
  static const double _desktopDrawerWidth = 380;
  static const double _createButtonBottomSpacing = 16;
  static const double _createButtonReservedHeight = 88;

  String? _selectedDocId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _angeboteStream;
  String? _savingZielgruppeKey;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _angeboteStream = FirebaseFirestore.instance
          .collection('angebote')
          .where('dienstleisterId', isEqualTo: uid)
          .snapshots();
    }
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value
          .replaceAll(RegExp(r'[^0-9,.-]'), '')
          .replaceAll(',', '.');
      return normalized.isEmpty ? null : double.tryParse(normalized);
    }
    return null;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final normalized = value.replaceAll(RegExp(r'[^0-9-]'), '');
      return normalized.isEmpty ? null : int.tryParse(normalized);
    }
    return null;
  }

  (double?, int?) _minPreisUndDauer(Map<String, dynamic> data) {
    double? preis = _toDouble(data['preis']);
    int? dauer = _toInt(data['dauer']);

    if (data['zielgruppen'] is Map) {
      final zielgruppen = Map<String, dynamic>.from(data['zielgruppen']);
      final preise = <double>[];
      final dauern = <int>[];

      for (final entry in zielgruppen.values) {
        if (entry is! Map) continue;

        final entryPreis = _toDouble(entry['preis']);
        final entryDauer = _toInt(entry['dauer']);
        if (entryPreis != null) preise.add(entryPreis);
        if (entryDauer != null) dauern.add(entryDauer);

        if (entry['varianten'] is! Map) continue;

        final varianten = Map<String, dynamic>.from(entry['varianten']);
        for (final variante in varianten.values) {
          if (variante is! Map) continue;
          final variantenPreis = _toDouble(variante['preis']);
          final variantenDauer = _toInt(variante['dauer']);
          if (variantenPreis != null) preise.add(variantenPreis);
          if (variantenDauer != null) dauern.add(variantenDauer);
        }
      }

      if (preise.isNotEmpty) {
        final minPreis = preise.reduce((a, b) => a < b ? a : b);
        preis = preis == null ? minPreis : (minPreis < preis ? minPreis : preis);
      }

      if (dauern.isNotEmpty) {
        final minDauer = dauern.reduce((a, b) => a < b ? a : b);
        dauer = dauer == null ? minDauer : (minDauer < dauer ? minDauer : dauer);
      }
    }

    return (preis, dauer);
  }

  String _preisText(double? preis) {
    if (preis == null) return '–';
    final formatted = preis.toStringAsFixed(2).replaceAll('.', ',');
    return 'ab $formatted €';
  }

  String _dauerText(int? dauer) => dauer == null ? '' : ' • $dauer Min';

  String _fallbackTitel(Map<String, dynamic> data) {
    final kategorie = (data['kategorie'] as String?)?.trim() ?? 'Sonstiges';
    final leistungen = (data['leistungen'] is List)
        ? List<String>.from(data['leistungen'])
        .where((entry) => entry.trim().isNotEmpty)
        .toList()
        : <String>[];

    if (leistungen.isEmpty) return kategorie;
    return '$kategorie – ${leistungen.join(' & ')}';
  }

  Future<void> _updateZielgruppeValues({
    required String docId,
    required String titel,
    required String zielgruppe,
    required Map<String, dynamic> zielgruppenWerte,
    required String preisText,
    required String dauerText,
  }) async {
    final preis = _toDouble(preisText);
    final dauer = _toInt(dauerText);
    final update = <String, dynamic>{
      'zielgruppen.$zielgruppe.preis':
          preis == null ? FieldValue.delete() : preis,
      'zielgruppen.$zielgruppe.dauer':
          dauer == null ? FieldValue.delete() : dauer,
    };

    final hasVarianten = zielgruppenWerte['varianten'] is Map &&
        (zielgruppenWerte['varianten'] as Map).isNotEmpty;
    if (preis == null && dauer == null && !hasVarianten) {
      update['zielgruppen.$zielgruppe'] = FieldValue.delete();
    }

    final savingKey = '$docId::$zielgruppe';
    setState(() => _savingZielgruppeKey = savingKey);

    try {
      await FirebaseFirestore.instance
          .collection('angebote')
          .doc(docId)
          .update(update);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('„$titel“ für $zielgruppe gespeichert.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Preis und Dauer für $zielgruppe konnten nicht gespeichert werden.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingZielgruppeKey = null);
      }
    }
  }

  Future<void> _updateVariantenValues({
    required String docId,
    required String titel,
    required String zielgruppe,
    required String variante,
    required String preisText,
    required String dauerText,
  }) async {
    final preis = _toDouble(preisText);
    final dauer = _toInt(dauerText);
    final variantPath = 'zielgruppen.$zielgruppe.varianten.$variante';
    final update = <String, dynamic>{
      '$variantPath.preis': preis == null ? FieldValue.delete() : preis,
      '$variantPath.dauer': dauer == null ? FieldValue.delete() : dauer,
    };

    if (preis == null && dauer == null) {
      update[variantPath] = FieldValue.delete();
    }

    final savingKey = '$docId::$zielgruppe::$variante';
    setState(() => _savingZielgruppeKey = savingKey);

    try {
      await FirebaseFirestore.instance
          .collection('angebote')
          .doc(docId)
          .update(update);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('„$titel“ – $zielgruppe / $variante gespeichert.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Preis und Dauer für $zielgruppe / $variante konnten nicht gespeichert werden.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingZielgruppeKey = null);
      }
    }
  }

  Widget _buildHeaderListView(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.only(bottom: _createButtonReservedHeight),
      children: [
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Meine Leistungen',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }

  Widget _buildCreateLeistungButton({required double rightInset}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: rightInset,
          bottom: _createButtonBottomSpacing,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Material(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const LeistungErstellenDialog(),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'Leistungen erstellen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_DetailBlock> _detailBlocksForZielgruppen(Map<String, dynamic> data) {
    if (data['zielgruppen'] is! Map) return const [];

    final zielgruppen = Map<String, dynamic>.from(data['zielgruppen']);
    final blocks = <_DetailBlock>[];

    for (final entry in zielgruppen.entries) {
      if (entry.value is! Map) continue;
      final values = Map<String, dynamic>.from(entry.value);
      final varianten = <_VarianteBlock>[];

      if (values['varianten'] is Map) {
        final variantenMap = Map<String, dynamic>.from(values['varianten']);
        for (final variante in variantenMap.entries) {
          if (variante.value is! Map) continue;
          varianten.add(
            _VarianteBlock(
              title: variante.key,
              values: Map<String, dynamic>.from(variante.value),
            ),
          );
        }
      }

      blocks.add(
        _DetailBlock(
          title: entry.key,
          values: values,
          varianten: varianten,
        ),
      );
    }

    return blocks;
  }

  Widget _buildDesktopDrawer(_SelectedLeistung selection) {
    final data = selection.data;
    final kategorie = (data['kategorie'] as String?)?.trim() ?? 'Ohne Kategorie';
    final leistungen = (data['leistungen'] is List)
        ? List<String>.from(data['leistungen'])
        .where((entry) => entry.trim().isNotEmpty)
        .toList()
        : <String>[];
    final methoden = (data['varianten'] is List)
        ? List<String>.from(data['varianten'])
        .where((entry) => entry.trim().isNotEmpty)
        .toList()
        : <String>[];
    final zielgruppenBlocks = _detailBlocksForZielgruppen(data);
    final hasEditableZielgruppen = zielgruppenBlocks.isNotEmpty;

    return Material(
      color: Colors.white,
      elevation: 14,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selection.titel,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          selection.subtitle,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
                    onPressed: () => setState(() => _selectedDocId = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailSection(
                      title: 'Kategorie',
                      child: Text(kategorie),
                    ),
                    if (leistungen.isNotEmpty)
                      _DetailSection(
                        title: 'Leistungen',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: leistungen
                              .map(
                                (entry) => Chip(
                              label: Text(entry),
                              backgroundColor: const Color(0xFFF3F4F8),
                            ),
                          )
                              .toList(),
                        ),
                      ),
                    if (methoden.isNotEmpty)
                      _DetailSection(
                        title: 'Varianten',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: methoden
                              .map(
                                (entry) => Chip(
                              label: Text(entry),
                              backgroundColor: const Color(0xFFEFF4FF),
                            ),
                          )
                              .toList(),
                        ),
                      ),
                    if (zielgruppenBlocks.isNotEmpty)
                      _DetailSection(
                        title: hasEditableZielgruppen
                            ? 'Zielgruppen (Preis & Dauer bearbeitbar)'
                            : 'Zielgruppen',
                        child: Column(
                          children: zielgruppenBlocks
                              .map(
                                (block) => Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE6E9F0),
                                ),
                              ),
                              child: _EditableZielgruppeCard(
                                key: ValueKey(
                                  '${selection.docId}-${block.title}-${block.values['preis']}-${block.values['dauer']}-${block.varianten.length}',
                                ),
                                title: block.title,
                                initialPreis: _toDouble(block.values['preis']),
                                initialDauer: _toInt(block.values['dauer']),
                                varianten: block.varianten,
                                isSaving:
                                    _savingZielgruppeKey ==
                                    '${selection.docId}::${block.title}',
                                onSave: (preisText, dauerText) =>
                                    _updateZielgruppeValues(
                                  docId: selection.docId,
                                  titel: selection.titel,
                                  zielgruppe: block.title,
                                  zielgruppenWerte: block.values,
                                  preisText: preisText,
                                  dauerText: dauerText,
                                ),
                                isVariantSaving: (variantenTitel) =>
                                    _savingZielgruppeKey ==
                                    '${selection.docId}::${block.title}::$variantenTitel',
                                onVariantSave:
                                    (variantenTitel, preisText, dauerText) =>
                                    _updateVariantenValues(
                                  docId: selection.docId,
                                  titel: selection.titel,
                                  zielgruppe: block.title,
                                  variante: variantenTitel,
                                  preisText: preisText,
                                  dauerText: dauerText,
                                ),
                              ),
                            ),
                          )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopContent({
    required Widget listContent,
    required _SelectedLeistung? selection,
  }) {
    final drawerVisible = selection != null;

    return Row(
      children: [
        Expanded(child: listContent),
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: drawerVisible ? _desktopDrawerWidth : 0,
          child: drawerVisible
              ? DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(0xFFE5E5E5)),
              ),
            ),
            child: _buildDesktopDrawer(selection!),
          )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      const fallback = Center(child: Text('Nicht eingeloggt'));
      if (!widget.showScaffold) return fallback;
      return const Scaffold(body: Center(child: Text('Nicht eingeloggt')));
    }

    final isDesktopLayout = MediaQuery.sizeOf(context).width >= 1100;

    final content = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _angeboteStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          final emptyContent = _buildHeaderListView(
            const [
              SizedBox(height: 32),
              Center(child: Text('Noch keine Leistungen erstellt.')),
            ],
          );

          return Stack(
            children: [
              Positioned.fill(child: emptyContent),
              _buildCreateLeistungButton(rightInset: 16),
            ],
          );
        }

        final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        _SelectedLeistung? selectedLeistung;

        for (final doc in snapshot.data!.docs) {
          final data = doc.data();
          final kategorie = (data['kategorie'] as String?)?.trim();
          final key = (kategorie == null || kategorie.isEmpty)
              ? 'Sonstiges'
              : kategorie;
          grouped.putIfAbsent(key, () => []).add(doc);

          if (_selectedDocId == doc.id) {
            final titel = (data['titel'] as String?) ?? _fallbackTitel(data);
            final (minPreis, minDauer) = _minPreisUndDauer(data);
            selectedLeistung = _SelectedLeistung(
              docId: doc.id,
              titel: titel,
              subtitle: '${_preisText(minPreis)}${_dauerText(minDauer)}',
              data: data,
            );
          }
        }

        if (_selectedDocId != null && selectedLeistung == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedDocId = null);
            }
          });
        }

        final kategorien = grouped.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        final children = <Widget>[];

        for (final kategorie in kategorien) {
          final docs = grouped[kategorie]!
            ..sort((a, b) {
              final at =
                  (a.data()['titel'] as String?) ?? _fallbackTitel(a.data());
              final bt =
                  (b.data()['titel'] as String?) ?? _fallbackTitel(b.data());
              return at.toLowerCase().compareTo(bt.toLowerCase());
            });

          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  kategorie,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          );

          for (final doc in docs) {
            final data = doc.data();
            final titel = (data['titel'] as String?) ?? _fallbackTitel(data);
            final (minPreis, minDauer) = _minPreisUndDauer(data);
            final subtitle = '${_preisText(minPreis)}${_dauerText(minDauer)}';
            final isSelected = doc.id == _selectedDocId;

            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: isSelected
                      ? const Color(0xFFF5F8FF)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: isDesktopLayout
                        ? () => setState(() => _selectedDocId = doc.id)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE5E5E5)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titel,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.black38,
                            ),
                            onPressed: () => _showMehrSheetForDoc(
                              context: context,
                              docId: doc.id,
                              data: data,
                              titel: titel,
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

          children.add(const SizedBox(height: 8));
        }

        final listContent = _buildHeaderListView(children);
        final drawerVisible = isDesktopLayout && selectedLeistung != null;
        final contentView = isDesktopLayout
            ? _buildDesktopContent(
          listContent: listContent,
          selection: selectedLeistung,
        )
            : listContent;

        return Stack(
          children: [
            Positioned.fill(child: contentView),
            _buildCreateLeistungButton(
              rightInset: drawerVisible ? _desktopDrawerWidth + 16 : 16,
            ),
          ],
        );
      },
    );

    if (!widget.showScaffold) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Leistungen'),
        centerTitle: true,
      ),
      body: content,
    );
  }

  void _showMehrSheetForDoc({
    required BuildContext context,
    required String docId,
    required Map<String, dynamic> data,
    required String titel,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Bearbeiten'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => LeistungErstellenDialog(
                    angebotId: docId,
                    initialData: data,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Löschen',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FirebaseFirestore.instance
                    .collection('angebote')
                    .doc(docId)
                    .delete();
                if (context.mounted) {
                  if (_selectedDocId == docId) {
                    setState(() => _selectedDocId = null);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('„$titel“ gelöscht')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Abbrechen'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _VarianteBlock {
  const _VarianteBlock({
    required this.title,
    required this.values,
  });

  final String title;
  final Map<String, dynamic> values;
}

class _DetailBlock {
  const _DetailBlock({
    required this.title,
    required this.values,
    required this.varianten,
  });

  final String title;
  final Map<String, dynamic> values;
  final List<_VarianteBlock> varianten;
}

class _EditablePreisDauerFields extends StatefulWidget {
  const _EditablePreisDauerFields({
    super.key,
    required this.initialPreis,
    required this.initialDauer,
    required this.isSaving,
    required this.onSave,
  });

  final double? initialPreis;
  final int? initialDauer;
  final bool isSaving;
  final Future<void> Function(String preisText, String dauerText) onSave;

  @override
  State<_EditablePreisDauerFields> createState() =>
      _EditablePreisDauerFieldsState();
}

class _EditablePreisDauerFieldsState extends State<_EditablePreisDauerFields> {
  late final TextEditingController _preisController;
  late final TextEditingController _dauerController;

  String _preisTextForValue(double? preis) {
    if (preis == null) return '';
    final hasDecimals = preis % 1 != 0;
    return (hasDecimals ? preis.toStringAsFixed(2) : preis.toStringAsFixed(0))
        .replaceAll('.', ',');
  }

  String _dauerTextForValue(int? dauer) => dauer?.toString() ?? '';

  bool get _hasPreisChanged =>
      _preisController.text.trim() != _preisTextForValue(widget.initialPreis);

  bool get _hasDauerChanged =>
      _dauerController.text.trim() != _dauerTextForValue(widget.initialDauer);

  Future<void> _save() {
    if (widget.isSaving) return Future.value();
    return widget.onSave(
      _preisController.text,
      _dauerController.text,
    );
  }

  void _handleChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildSaveAction({required bool visible}) {
    if (!visible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: InkWell(
          onTap: widget.isSaving ? null : _save,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: widget.isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.check,
                      size: 32,
                      color: Color(0xFF24C552),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _preisController = TextEditingController();
    _dauerController = TextEditingController();
    _preisController.addListener(_handleChanged);
    _dauerController.addListener(_handleChanged);
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _EditablePreisDauerFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPreis != widget.initialPreis ||
        oldWidget.initialDauer != widget.initialDauer) {
      _syncControllers();
    }
  }

  void _syncControllers() {
    _preisController.text = _preisTextForValue(widget.initialPreis);
    _dauerController.text = _dauerTextForValue(widget.initialDauer);
  }

  @override
  void dispose() {
    _preisController.removeListener(_handleChanged);
    _dauerController.removeListener(_handleChanged);
    _preisController.dispose();
    _dauerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _preisController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'Preis',
                  suffixText: '€',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            _buildSaveAction(visible: _hasPreisChanged),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _dauerController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'Dauer',
                  suffixText: 'Min',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            _buildSaveAction(visible: _hasDauerChanged),
          ],
        ),
      ],
    );
  }
}

class _EditableZielgruppeCard extends StatelessWidget {
  const _EditableZielgruppeCard({
    super.key,
    required this.title,
    required this.initialPreis,
    required this.initialDauer,
    required this.varianten,
    required this.isSaving,
    required this.onSave,
    required this.isVariantSaving,
    required this.onVariantSave,
  });

  final String title;
  final double? initialPreis;
  final int? initialDauer;
  final List<_VarianteBlock> varianten;
  final bool isSaving;
  final Future<void> Function(String preisText, String dauerText) onSave;
  final bool Function(String variantenTitel) isVariantSaving;
  final Future<void> Function(
    String variantenTitel,
    String preisText,
    String dauerText,
  ) onVariantSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _EditablePreisDauerFields(
          initialPreis: initialPreis,
          initialDauer: initialDauer,
          isSaving: isSaving,
          onSave: onSave,
        ),
        if (varianten.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Varianten',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          ...varianten.map(
            (variante) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variante.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _EditablePreisDauerFields(
                    key: ValueKey(
                      '$title-${variante.title}-${variante.values['preis']}-${variante.values['dauer']}',
                    ),
                    initialPreis: variante.values['preis'] is num
                        ? (variante.values['preis'] as num).toDouble()
                        : null,
                    initialDauer: variante.values['dauer'] is num
                        ? (variante.values['dauer'] as num).toInt()
                        : null,
                    isSaving: isVariantSaving(variante.title),
                    onSave: (preisText, dauerText) => onVariantSave(
                      variante.title,
                      preisText,
                      dauerText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SelectedLeistung {
  const _SelectedLeistung({
    required this.docId,
    required this.titel,
    required this.subtitle,
    required this.data,
  });

  final String docId;
  final String titel;
  final String subtitle;
  final Map<String, dynamic> data;
}