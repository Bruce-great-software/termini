import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/angebote_view.dart';

class DienstleisterKalenderPage extends StatefulWidget {
  final String dienstleisterId;

  const DienstleisterKalenderPage({
    super.key,
    required this.dienstleisterId,
  });

  @override
  State<DienstleisterKalenderPage> createState() =>
      _DienstleisterKalenderPageState();
}

enum _KalenderViewMode { tag, woche, monat }

class _MitarbeiterOption {
  final String id;
  final String name;
  final int kalenderFarbeValue;

  const _MitarbeiterOption({
    required this.id,
    required this.name,
    required this.kalenderFarbeValue,
  });
}

class _LeistungsPosition {
  final String category;
  final String title;
  final String subtitle;
  final double? price;
  final double? originalPrice;
  final int? duration;

  const _LeistungsPosition({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.originalPrice,
    required this.duration,
  });
}

class _KundenSuggestion {
  final String id;
  final String name;
  final String email;
  final String phone;

  const _KundenSuggestion({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
  });
}

class _DienstleisterKalenderPageState extends State<DienstleisterKalenderPage> {
  static const double _calendarSidebarWidth = 188;
  static const double _timeColumnWidth = 72;
  static const double _hourRowHeight = 72;
  static const double _terminHorizontalPadding = 6;
  static const double _terminColumnGap = 4;
  static const int _defaultKalenderFarbeValue = 0xFF4285F4;

  static const List<String> _weekdayLabels = [
    'Mo',
    'Di',
    'Mi',
    'Do',
    'Fr',
    'Sa',
    'So',
  ];

  static const List<String> _monthLabels = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  final ScrollController _weekScrollController = ScrollController();

  late DateTime _referenceDate;
  _KalenderViewMode _viewMode = _KalenderViewMode.woche;
  bool _alleMitarbeiterAnzeigen = true;
  final Set<String> _selectedMitarbeiterIds = <String>{};

  @override
  void initState() {
    super.initState();
    _referenceDate = _dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _weekScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: const Color(0xFFF6F7FB),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWideLayout = constraints.maxWidth >= 980;

              if (isWideLayout) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCalendarSidebar(theme),
                    const SizedBox(width: 16),
                    Expanded(child: _buildCalendarContent(theme)),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCreateButton(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildCalendarContent(theme)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarSidebar(ThemeData theme) {
    return Container(
      width: _calendarSidebarWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCreateButton(),
          const SizedBox(height: 12),
          Expanded(
            child: _buildMitarbeiterFilterSection(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildMitarbeiterFilterSection(ThemeData theme) {
    return StreamBuilder<List<_MitarbeiterOption>>(
      stream: _watchActiveMitarbeiter(),
      builder: (context, snapshot) {
        final mitarbeiter = snapshot.data ?? const <_MitarbeiterOption>[];
        final allIds = mitarbeiter.map((item) => item.id).toSet();
        final hasError = snapshot.hasError;

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mitarbeiter',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF344054),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                value: _alleMitarbeiterAnzeigen,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Alle anzeigen',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
                onChanged: mitarbeiter.isEmpty
                    ? null
                    : (value) {
                  if (value == null) return;
                  setState(() {
                    _alleMitarbeiterAnzeigen = value;
                    if (value) {
                      _selectedMitarbeiterIds.clear();
                    } else if (_selectedMitarbeiterIds.isEmpty) {
                      _selectedMitarbeiterIds
                        ..clear()
                        ..addAll(allIds);
                    }
                  });
                },
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 6),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  mitarbeiter.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Mitarbeiter konnten nicht geladen werden.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB42318),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (mitarbeiter.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Keine aktiven Mitarbeiter',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: mitarbeiter.length,
                      itemBuilder: (context, index) {
                        final item = mitarbeiter[index];
                        final isChecked = _alleMitarbeiterAnzeigen
                            ? true
                            : _selectedMitarbeiterIds.contains(item.id);

                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          visualDensity:
                          const VisualDensity(horizontal: -4, vertical: -4),
                          dense: true,
                          value: isChecked,
                          controlAffinity: ListTileControlAffinity.leading,
                          secondary: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Color(item.kalenderFarbeValue),
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF101828),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            _handleMitarbeiterSelectionChanged(
                              mitarbeiter: mitarbeiter,
                              mitarbeiterId: item.id,
                              isSelected: value,
                            );
                          },
                        );
                      },
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCreateButton() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      shadowColor: const Color(0x14000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _showCreateAppointmentDialog,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, color: Color(0xFF101828), size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Eintragen',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF101828),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarContent(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE4E7EC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A101828),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: _buildWeekView(theme),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 780;

        final navigation = Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _jumpToToday,
              style: OutlinedButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                side: const BorderSide(color: Color(0xFFD0D5DD)),
                foregroundColor: const Color(0xFF344054),
                backgroundColor: Colors.white,
              ),
              child: const Text('Heute'),
            ),
            _buildIconButton(
              icon: Icons.chevron_left,
              onPressed: _navigateBackward,
            ),
            _buildIconButton(
              icon: Icons.chevron_right,
              onPressed: _navigateForward,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                _formatMonthYear(_referenceDate),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF101828),
                ),
              ),
            ),
          ],
        );

        final viewModeToggle = SegmentedButton<_KalenderViewMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<_KalenderViewMode>(
              value: _KalenderViewMode.tag,
              label: Text('Tag'),
            ),
            ButtonSegment<_KalenderViewMode>(
              value: _KalenderViewMode.woche,
              label: Text('Woche'),
            ),
            ButtonSegment<_KalenderViewMode>(
              value: _KalenderViewMode.monat,
              label: Text('Monat'),
            ),
          ],
          selected: {_viewMode},
          onSelectionChanged: (selection) {
            final nextMode = selection.first;
            setState(() {
              _viewMode = nextMode;
            });
          },
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFFEEF2FF);
              }
              return Colors.white;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF344054);
              }
              return const Color(0xFF667085);
            }),
            side: WidgetStateProperty.all(
              const BorderSide(color: Color(0xFFD0D5DD)),
            ),
            textStyle: WidgetStateProperty.all(
              theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              navigation,
              const SizedBox(height: 12),
              viewModeToggle,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: navigation),
            const SizedBox(width: 16),
            viewModeToggle,
          ],
        );
      },
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD0D5DD)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: const Color(0xFF344054)),
        ),
      ),
    );
  }

  Widget _buildWeekView(ThemeData theme) {
    final weekDates = _weekDates;

    return StreamBuilder<List<_MitarbeiterOption>>(
      stream: _watchActiveMitarbeiter(),
      builder: (context, snapshot) {
        final mitarbeiter = snapshot.data ?? const <_MitarbeiterOption>[];
        final mitarbeiterFarben = <String, int>{
          for (final item in mitarbeiter) item.id: item.kalenderFarbeValue,
        };
        final mitarbeiterLoadError = snapshot.hasError
            ? 'Mitarbeiter konnten nicht geladen werden.'
            : null;

        return StreamBuilder<List<_TerminEntry>>(
          stream: _loadWeekTermine(),
          builder: (context, terminSnapshot) {
            final termine = terminSnapshot.data ?? const <_TerminEntry>[];
            final gefilterteTermine = _applyMitarbeiterFilter(termine);
            final terminLoadError = terminSnapshot.hasError
                ? 'Termine konnten nicht geladen werden.'
                : null;
            final loadError = mitarbeiterLoadError ?? terminLoadError;

            return Column(
              children: [
                _buildWeekHeader(theme, weekDates),
                const Divider(height: 1, color: Color(0xFFE4E7EC)),
                if (loadError != null)
                  Container(
                    width: double.infinity,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: const Color(0xFFFFF4ED),
                    child: Text(
                      loadError,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFB42318),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final gridWidth = constraints.maxWidth - _timeColumnWidth;

                      return Scrollbar(
                        controller: _weekScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _weekScrollController,
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTimeColumn(theme),
                              SizedBox(
                                width: gridWidth > 0 ? gridWidth : 0,
                                child: _buildWeekGrid(
                                  termine: gefilterteTermine,
                                  mitarbeiterFarben: mitarbeiterFarben,
                                  theme: theme,
                                ),
                              ),
                            ],
                          ),
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

  Widget _buildWeekHeader(ThemeData theme, List<DateTime> weekDates) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
      child: Row(
        children: [
          const SizedBox(width: _timeColumnWidth),
          Expanded(
            child: Row(
              children: [
                for (var index = 0; index < weekDates.length; index++)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: index == 0
                                ? Colors.transparent
                                : const Color(0xFFE4E7EC),
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _weekdayLabels[index],
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: const Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${weekDates[index].day}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF101828),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeColumn(ThemeData theme) {
    return SizedBox(
      width: _timeColumnWidth,
      child: Column(
        children: List.generate(24, (index) {
          return SizedBox(
            height: _hourRowHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: const Offset(0, -10),
                child: Text(
                  '${index.toString().padLeft(2, '0')}:00',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF98A2B3),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWeekGrid({
    required List<_TerminEntry> termine,
    required Map<String, int> mitarbeiterFarben,
    required ThemeData theme,
  }) {
    final totalHeight = _hourRowHeight * 24;

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFFE4E7EC)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dayColumnWidth = constraints.maxWidth / 7;

          return SizedBox(
            height: totalHeight,
            child: Stack(
              children: [
                Row(
                  children: List.generate(7, (dayIndex) {
                    return Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: dayIndex == 0
                                ? BorderSide.none
                                : const BorderSide(color: Color(0xFFE4E7EC)),
                          ),
                        ),
                        child: Column(
                          children: List.generate(24, (hourIndex) {
                            return Container(
                              height: _hourRowHeight,
                              decoration: BoxDecoration(
                                color: hourIndex.isEven
                                    ? const Color(0xFFFDFDFE)
                                    : const Color(0xFFFAFBFC),
                                border: const Border(
                                  top: BorderSide(color: Color(0xFFF2F4F7)),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  }),
                ),
                ..._buildTerminBlocks(
                  termine: termine,
                  mitarbeiterFarben: mitarbeiterFarben,
                  dayColumnWidth: dayColumnWidth,
                  theme: theme,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildTerminBlocks({
    required List<_TerminEntry> termine,
    required Map<String, int> mitarbeiterFarben,
    required double dayColumnWidth,
    required ThemeData theme,
  }) {
    final startOfWeek = _startOfWeek(_referenceDate);
    final perDay = List.generate(7, (_) => <_TerminEntry>[]);

    for (final termin in termine) {
      final dayIndex = termin.startAt.difference(startOfWeek).inDays;
      if (dayIndex >= 0 && dayIndex < 7) {
        perDay[dayIndex].add(termin);
      }
    }

    final widgets = <Widget>[];

    for (var dayIndex = 0; dayIndex < perDay.length; dayIndex++) {
      final dayTermine = perDay[dayIndex]..sort(_compareTerminEntries);
      final clusters = _buildOverlapClusters(dayTermine);

      for (final cluster in clusters) {
        final positionedEvents = _layoutCluster(cluster);

        for (final item in positionedEvents) {
          final termin = item.termin;
          final minutesFromMidnight =
              (termin.startAt.hour * 60) + termin.startAt.minute;
          final durationMinutes =
              termin.endAt.difference(termin.startAt).inMinutes;
          final top = (minutesFromMidnight / 60) * _hourRowHeight;
          final height = ((durationMinutes / 60) * _hourRowHeight)
              .clamp(32.0, _hourRowHeight * 24)
              .toDouble();

          final blockHeight =
          (height - 4).clamp(40.0, _hourRowHeight * 24).toDouble();

          final availableWidth = (dayColumnWidth - (_terminHorizontalPadding * 2))
              .clamp(40.0, dayColumnWidth);
          final totalGap = (item.totalColumns - 1) * _terminColumnGap;
          final columnWidth = ((availableWidth - totalGap) / item.totalColumns)
              .clamp(28.0, availableWidth)
              .toDouble();

          final left = (dayIndex * dayColumnWidth) +
              _terminHorizontalPadding +
              (item.columnIndex * (columnWidth + _terminColumnGap));

          final displayName =
          (termin.mitarbeiterName?.trim().isNotEmpty ?? false)
              ? termin.mitarbeiterName!.trim()
              : termin.titel;
          final timeLabel = '${termin.startZeit} bis ${termin.endZeit}';
          final terminColorValue = _resolveTerminFarbe(
            termin: termin,
            mitarbeiterFarben: mitarbeiterFarben,
          );
          final baseColor = Color(terminColorValue);

// Hintergrund (kräftig, aber nicht komplett 100%)
          final blockFillColor = baseColor.withOpacity(0.85);

// 🔥 Rahmen deutlich dunkler machen
          final hsl = HSLColor.fromColor(baseColor);
          final blockBorderColor = hsl
              .withLightness((hsl.lightness - 0.4).clamp(0.0, 1.0))
              .toColor();

// Text weiß
          final blockTextColor = Colors.white;

          widgets.add(
            Positioned(
              top: top + 2,
              left: left,
              width: columnWidth,
              height: blockHeight,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showTerminPreviewDialog(termin),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: blockFillColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: blockBorderColor,
                        width: 1.4,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12101828),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, blockConstraints) {
                        final innerHeight = blockConstraints.maxHeight;
                        final showNothing = innerHeight < 22;
                        final showHeaderAndBody = innerHeight >= 44;

                        if (showNothing) {
                          return const SizedBox.shrink();
                        }

                        final headerColor = hsl
                            .withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0))
                            .toColor();

                        final bodyColor = blockFillColor;

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: showHeaderAndBody
                              ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 22,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                alignment: Alignment.centerLeft,
                                color: headerColor,
                                child: Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  color: bodyColor,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    timeLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                              : Container(
                            color: headerColor,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                height: 1.0,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

          );
        }
      }
    }

    return widgets;
  }

  int _compareTerminEntries(_TerminEntry a, _TerminEntry b) {
    final startCompare = a.startAt.compareTo(b.startAt);
    if (startCompare != 0) return startCompare;

    final endCompare = a.endAt.compareTo(b.endAt);
    if (endCompare != 0) return endCompare;

    return a.id.compareTo(b.id);
  }

  List<List<_TerminEntry>> _buildOverlapClusters(List<_TerminEntry> termine) {
    if (termine.isEmpty) return const [];

    final clusters = <List<_TerminEntry>>[];
    var currentCluster = <_TerminEntry>[];
    DateTime? clusterEnd;

    for (final termin in termine) {
      if (currentCluster.isEmpty) {
        currentCluster = [termin];
        clusterEnd = termin.endAt;
        continue;
      }

      final overlapsCurrentCluster =
          clusterEnd != null && termin.startAt.isBefore(clusterEnd);
      if (overlapsCurrentCluster) {
        currentCluster.add(termin);
        if (termin.endAt.isAfter(clusterEnd)) {
          clusterEnd = termin.endAt;
        }
      } else {
        clusters.add(currentCluster);
        currentCluster = [termin];
        clusterEnd = termin.endAt;
      }
    }

    if (currentCluster.isNotEmpty) {
      clusters.add(currentCluster);
    }

    return clusters;
  }

  List<_PositionedTermin> _layoutCluster(List<_TerminEntry> cluster) {
    if (cluster.isEmpty) return const [];

    final columnEndTimes = <DateTime>[];
    final items = <_PositionedTermin>[];

    for (final termin in cluster) {
      var assignedColumn = -1;

      for (var index = 0; index < columnEndTimes.length; index++) {
        final columnEnd = columnEndTimes[index];
        if (!termin.startAt.isBefore(columnEnd)) {
          assignedColumn = index;
          columnEndTimes[index] = termin.endAt;
          break;
        }
      }

      if (assignedColumn == -1) {
        assignedColumn = columnEndTimes.length;
        columnEndTimes.add(termin.endAt);
      }

      items.add(
        _PositionedTermin(
          termin: termin,
          columnIndex: assignedColumn,
          totalColumns: 0,
        ),
      );
    }

    final totalColumns = columnEndTimes.length;
    return items
        .map(
          (item) => _PositionedTermin(
        termin: item.termin,
        columnIndex: item.columnIndex,
        totalColumns: totalColumns,
      ),
    )
        .toList(growable: false);
  }

  Future<void> _showCreateAppointmentDialog() async {
    await _showAppointmentDialog();
  }

  Future<void> _showEditAppointmentDialog(_TerminEntry termin) async {
    await _showAppointmentDialog(initialTermin: termin);
  }

  Future<void> _showTerminPreviewDialog(_TerminEntry termin) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final fullDateText = _formatPreviewDate(termin.startAt);
        final timeText = '${termin.startZeit} bis ${termin.endZeit}';
        final statusText = _formatStatus(termin.status);

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 560,
              maxHeight: 760,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          termin.mitarbeiterName?.trim().isNotEmpty == true
                              ? termin.mitarbeiterName!.trim()
                              : termin.titel,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF101828),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await _showEditAppointmentDialog(termin);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Bearbeiten',
                      ),
                      IconButton(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await _deleteTerminWithFeedback(termin.id);
                        },
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Löschen',
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Schließen',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$fullDateText · $timeText',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF475467),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _statusBackgroundColor(termin.status),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusText,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: _statusTextColor(termin.status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPreviewInfoCard(
                            context: dialogContext,
                            title: 'Terminübersicht',
                            children: [
                              _buildPreviewRow(
                                label: 'Mitarbeiter',
                                value:
                                termin.mitarbeiterName?.trim().isNotEmpty ==
                                    true
                                    ? termin.mitarbeiterName!.trim()
                                    : 'Nicht gesetzt',
                              ),
                              _buildPreviewRow(
                                label: 'Datum',
                                value: fullDateText,
                              ),
                              _buildPreviewRow(
                                label: 'Uhrzeit',
                                value: timeText,
                              ),
                              _buildPreviewRow(
                                label: 'Status',
                                value: statusText,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildPreviewInfoCard(
                            context: dialogContext,
                            title: 'Kunde',
                            children: [
                              FutureBuilder<String?>(
                                future: _loadKundeGeschlecht(termin.kundeId),
                                builder: (context, snapshot) {
                                  return _buildPreviewRow(
                                    label: 'Anrede',
                                    value: _anredeAusGeschlecht(snapshot.data),
                                  );
                                },
                              ),
                              _buildPreviewRow(
                                label: 'Name',
                                value: termin.kundeName?.trim().isNotEmpty ==
                                    true
                                    ? termin.kundeName!.trim()
                                    : 'Nicht hinterlegt',
                              ),
                              _buildPreviewRow(
                                label: 'Telefon',
                                value:
                                termin.kundePhone?.trim().isNotEmpty == true
                                    ? _formatPhoneDisplay(
                                  termin.kundePhone!.trim(),
                                )
                                    : 'Nicht hinterlegt',
                              ),
                              _buildPreviewRow(
                                label: 'E-Mail',
                                value:
                                termin.kundeEmail?.trim().isNotEmpty == true
                                    ? termin.kundeEmail!.trim()
                                    : 'Nicht hinterlegt',
                              ),
                            ],
                          ),
                          if (termin.leistungsPositionen.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _buildPreviewLeistungenCard(
                              context: dialogContext,
                              termin: termin,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewInfoCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildPreviewRow({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewLeistungenCard({
    required BuildContext context,
    required _TerminEntry termin,
  }) {
    final grouped = <String, List<_LeistungsPosition>>{};
    for (final item in termin.leistungsPositionen) {
      final key =
      item.category.trim().isNotEmpty ? item.category.trim() : 'Leistungen';
      grouped.putIfAbsent(key, () => <_LeistungsPosition>[]).add(item);
    }

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gebuchte Leistungen',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          for (final category in sortedKeys) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: Colors.black,
              child: Text(
                category,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...grouped[category]!.map((item) {
              final subtitle = item.subtitle.trim();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  border: const Border(
                    left: BorderSide(color: Color(0xFFE4E7EC)),
                    right: BorderSide(color: Color(0xFFE4E7EC)),
                    bottom: BorderSide(color: Color(0xFFE4E7EC)),
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF101828),
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (item.duration != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${item.duration} Min',
                              style: const TextStyle(
                                color: Color(0xFF101828),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      item.price != null ? _formatEuro(item.price!) : '–',
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          _buildPreviewRow(
            label: 'Gesamtdauer',
            value: termin.dauerGesamt != null
                ? '${termin.dauerGesamt} Min'
                : 'Nicht hinterlegt',
          ),
          _buildPreviewRow(
            label: 'Gesamtpreis',
            value: termin.preisGesamt != null
                ? _formatEuro(termin.preisGesamt!)
                : 'Nicht hinterlegt',
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTerminWithFeedback(String terminId) async {
    final deleteResult = await _deleteTermin(terminId);
    if (!mounted) return;

    if (deleteResult == null) {
      _showSnackBar('Termin erfolgreich gelöscht.');
      return;
    }

    _showSnackBar(deleteResult);
  }

  String _formatPreviewDate(DateTime date) {
    const weekdays = [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ];

    const months = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];

    return '${weekdays[date.weekday - 1]}, ${date.day}. ${months[date.month - 1]} ${date.year}';
  }

  String _formatStatus(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    switch (normalized) {
      case 'bestaetigt':
        return 'Bestätigt';
      case 'abgesagt':
        return 'Abgesagt';
      case 'offen':
        return 'Offen';
      default:
        if (normalized.isEmpty) return 'Unbekannt';
        return rawStatus[0].toUpperCase() + rawStatus.substring(1);
    }
  }

  Color _statusBackgroundColor(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    switch (normalized) {
      case 'abgesagt':
        return const Color(0xFFFEE4E2);
      case 'bestaetigt':
        return const Color(0xFFDFF6DB);
      default:
        return const Color(0xFFF2F4F7);
    }
  }

  Color _statusTextColor(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    switch (normalized) {
      case 'abgesagt':
        return const Color(0xFFB42318);
      case 'bestaetigt':
        return const Color(0xFF2B9745);
      default:
        return const Color(0xFF344054);
    }
  }

  String _formatEuro(double value) {
    final asString = value.toStringAsFixed(2).replaceAll('.', ',');
    return '$asString €';
  }

  String _anredeAusGeschlecht(String? geschlechtRaw) {
    final geschlecht = geschlechtRaw?.trim().toLowerCase();
    if (geschlecht == 'herr') return 'Herr';
    if (geschlecht == 'frau') return 'Frau';
    return 'Nicht hinterlegt';
  }

  String? _zielgruppeAusGeschlecht(String? geschlechtRaw) {
    final geschlecht = geschlechtRaw?.trim().toLowerCase();
    if (geschlecht == 'herr') return 'Herren';
    if (geschlecht == 'frau') return 'Damen';
    return null;
  }

  Future<String?> _loadKundeGeschlecht(String? kundeId) async {
    final cleanedId = kundeId?.trim() ?? '';
    if (cleanedId.isEmpty) return null;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(cleanedId)
          .get();
      final data = doc.data();
      return (data?['geschlecht'] as String?)?.trim().toLowerCase();
    } catch (_) {
      return null;
    }
  }

  Future<String> _loadDienstleisterName() async {
    final cleanedId = widget.dienstleisterId.trim();
    if (cleanedId.isEmpty) {
      return 'Dienstleister';
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(cleanedId)
          .get();

      final data = doc.data();
      final name = (data?['name'] as String?)?.trim();

      if (name != null && name.isNotEmpty) {
        return name;
      }

      return 'Dienstleister';
    } catch (_) {
      return 'Dienstleister';
    }
  }

  Future<void> _showAppointmentDialog({
    _TerminEntry? initialTermin,
  }) async {
    final kundeNameController = TextEditingController();
    final kundePhoneController = TextEditingController();
    final kundeEmailController = TextEditingController();
    final mitarbeiterFuture = _loadActiveMitarbeiter();

    final isEditMode = initialTermin != null;
    var selectedDate =
    initialTermin != null ? _dateOnly(initialTermin.startAt) : _referenceDate;
    var fromTime = initialTermin != null
        ? TimeOfDay.fromDateTime(initialTermin.startAt)
        : const TimeOfDay(hour: 9, minute: 0);
    var toTime = initialTermin != null
        ? TimeOfDay.fromDateTime(initialTermin.endAt)
        : const TimeOfDay(hour: 10, minute: 0);

    _MitarbeiterOption? selectedMitarbeiter;
    String? validationMessage;
    bool isSaving = false;
    bool isDeleting = false;
    bool isLoadingMitarbeiter = true;
    bool hasMitarbeiter = false;
    var selectedLeistungen = List<_LeistungsPosition>.from(
      initialTermin?.leistungsPositionen ?? const <_LeistungsPosition>[],
    );

    List<_KundenSuggestion> emailSuggestions = <_KundenSuggestion>[];
    List<_KundenSuggestion> phoneSuggestions = <_KundenSuggestion>[];
    bool isLoadingEmailSuggestions = false;
    bool isLoadingPhoneSuggestions = false;
    String? selectedKundeId = initialTermin?.kundeId;
    int emailRequestCounter = 0;
    int phoneRequestCounter = 0;
    String emailSearchQuery = '';
    String phoneSearchQuery = '';

    kundeNameController.text = initialTermin?.kundeName ?? '';
    kundePhoneController.text = initialTermin?.kundePhone != null
        ? _formatPhoneDisplay(initialTermin!.kundePhone!)
        : '';
    kundeEmailController.text = initialTermin?.kundeEmail ?? '';

    int berechneGesamtDauer(List<_LeistungsPosition> items) {
      var total = 0;
      for (final item in items) {
        final duration = item.duration;
        if (duration != null && duration > 0) {
          total += duration;
        }
      }
      return total;
    }

    double berechneGesamtPreis(List<_LeistungsPosition> items) {
      var total = 0.0;
      for (final item in items) {
        final price = item.price;
        if (price != null && price > 0) {
          total += price;
        }
      }
      return total;
    }

    Future<void> loadEmailSuggestions(
        String rawValue,
        void Function(void Function()) setDialogState,
        ) async {
      final query = rawValue.trim().toLowerCase();

      if (query.isEmpty) {
        setDialogState(() {
          emailSearchQuery = '';
          emailSuggestions = <_KundenSuggestion>[];
          isLoadingEmailSuggestions = false;
        });
        return;
      }

      final currentRequest = ++emailRequestCounter;

      setDialogState(() {
        emailSearchQuery = rawValue.trim();
        isLoadingEmailSuggestions = true;
      });

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('rolle', isEqualTo: 'kunde')
            .get();

        if (!mounted || currentRequest != emailRequestCounter) {
          return;
        }

        final suggestions = snapshot.docs
            .map((doc) {
          final data = doc.data();

          final email = _readFirstNonEmptyString([
            data['emailLc'],
            data['email'],
            data['kundeEmail'],
          ]);

          if (email.isEmpty || !email.toLowerCase().contains(query)) {
            return null;
          }

          final name = _readFirstNonEmptyString([
            data['name'],
            data['kundeName'],
            data['anzeigeName'],
          ]);

          final phone = _readFirstNonEmptyString([
            data['phoneNumber'],
            data['phone'],
            data['telefon'],
            data['kundePhone'],
            data['handynummer'],
          ]);

          return _KundenSuggestion(
            id: doc.id,
            name: name,
            email: email,
            phone: phone,
          );
        })
            .whereType<_KundenSuggestion>()
            .toList();

        suggestions.sort(
              (a, b) => a.email.toLowerCase().compareTo(b.email.toLowerCase()),
        );

        setDialogState(() {
          emailSuggestions = suggestions.take(6).toList();
          isLoadingEmailSuggestions = false;
        });
      } catch (_) {
        if (!mounted || currentRequest != emailRequestCounter) {
          return;
        }

        setDialogState(() {
          emailSuggestions = <_KundenSuggestion>[];
          isLoadingEmailSuggestions = false;
        });
      }
    }

    Future<void> loadPhoneSuggestions(
        String rawValue,
        void Function(void Function()) setDialogState,
        ) async {
      final query = rawValue.trim();

      if (query.isEmpty) {
        setDialogState(() {
          phoneSearchQuery = '';
          phoneSuggestions = <_KundenSuggestion>[];
          isLoadingPhoneSuggestions = false;
        });
        return;
      }

      final currentRequest = ++phoneRequestCounter;

      setDialogState(() {
        phoneSearchQuery = rawValue.trim();
        isLoadingPhoneSuggestions = true;
      });

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('rolle', isEqualTo: 'kunde')
            .get();

        if (!mounted || currentRequest != phoneRequestCounter) {
          return;
        }

        final suggestions = snapshot.docs
            .map((doc) {
          final data = doc.data();

          final phone = _readFirstNonEmptyString([
            data['phoneNumber'],
            data['phone'],
            data['telefon'],
            data['kundePhone'],
            data['handynummer'],
          ]);

          if (phone.isEmpty || !_phoneMatches(phone, query)) {
            return null;
          }

          final email = _readFirstNonEmptyString([
            data['emailLc'],
            data['email'],
            data['kundeEmail'],
          ]);

          final name = _readFirstNonEmptyString([
            data['name'],
            data['kundeName'],
            data['anzeigeName'],
          ]);

          return _KundenSuggestion(
            id: doc.id,
            name: name,
            email: email,
            phone: phone,
          );
        })
            .whereType<_KundenSuggestion>()
            .toList();

        suggestions.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        setDialogState(() {
          phoneSuggestions = suggestions.take(6).toList();
          isLoadingPhoneSuggestions = false;
        });
      } catch (_) {
        if (!mounted || currentRequest != phoneRequestCounter) {
          return;
        }

        setDialogState(() {
          phoneSuggestions = <_KundenSuggestion>[];
          isLoadingPhoneSuggestions = false;
        });
      }
    }

    void applyCustomerSuggestion(
        _KundenSuggestion suggestion,
        void Function(void Function()) setDialogState,
        ) {
      setDialogState(() {
        selectedKundeId = suggestion.id;

        if (suggestion.name.isNotEmpty) {
          kundeNameController.text = suggestion.name;
        }
        if (suggestion.phone.isNotEmpty) {
          kundePhoneController.text = _formatPhoneDisplay(suggestion.phone);
        }
        if (suggestion.email.isNotEmpty) {
          kundeEmailController.text = suggestion.email;
        }

        phoneSuggestions = <_KundenSuggestion>[];
        emailSuggestions = <_KundenSuggestion>[];
        phoneSearchQuery = '';
        emailSearchQuery = '';
        validationMessage = null;
      });
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickDate() async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );

              if (pickedDate != null) {
                setDialogState(() {
                  selectedDate = _dateOnly(pickedDate);
                  validationMessage = null;
                });
              }
            }

            Future<void> pickTime({required bool isStartTime}) async {
              final pickedTime = await showTimePicker(
                context: context,
                initialTime: isStartTime ? fromTime : toTime,
              );

              if (pickedTime != null) {
                setDialogState(() {
                  if (isStartTime) {
                    fromTime = pickedTime;
                  } else {
                    toTime = pickedTime;
                  }
                  validationMessage = null;
                });
              }
            }

            Future<void> handleSave() async {
              final kundeName = kundeNameController.text.trim();
              final kundePhone = kundePhoneController.text.trim();
              final kundeEmail = kundeEmailController.text.trim();
              final startAt = _combineDateAndTime(selectedDate, fromTime);
              final endAt = _combineDateAndTime(selectedDate, toTime);
              final mitarbeiter = selectedMitarbeiter;
              final preisGesamt = berechneGesamtPreis(selectedLeistungen);
              final dauerGesamt = berechneGesamtDauer(selectedLeistungen);

              if (kundeName.isEmpty) {
                setDialogState(() {
                  validationMessage = 'Bitte gib einen Kundennamen ein.';
                });
                _showSnackBar('Kundenname darf nicht leer sein.');
                return;
              }

              if (isLoadingMitarbeiter) {
                setDialogState(() {
                  validationMessage = 'Mitarbeiter werden noch geladen.';
                });
                _showSnackBar('Bitte warte, bis die Mitarbeiter geladen sind.');
                return;
              }

              if (!hasMitarbeiter) {
                setDialogState(() {
                  validationMessage = 'Keine aktiven Mitarbeiter verfügbar.';
                });
                _showSnackBar('Keine aktiven Mitarbeiter verfügbar.');
                return;
              }

              if (mitarbeiter == null) {
                setDialogState(() {
                  validationMessage = 'Bitte wähle einen Mitarbeiter aus.';
                });
                _showSnackBar('Bitte wähle einen Mitarbeiter aus.');
                return;
              }

              if (!endAt.isAfter(startAt)) {
                setDialogState(() {
                  validationMessage =
                  'Die Endzeit muss nach der Startzeit liegen.';
                });
                _showSnackBar('Bis muss nach Von liegen.');
                return;
              }

              setDialogState(() {
                isSaving = true;
                validationMessage = null;
              });

              final titel = _buildAutomaticTerminTitle(
                kundeName: kundeName,
                initialTermin: initialTermin,
              );

              final saveResult = isEditMode
                  ? await _updateTermin(
                terminId: initialTermin!.id,
                titel: titel,
                datum: selectedDate,
                fromTime: fromTime,
                toTime: toTime,
                mitarbeiter: mitarbeiter,
                kundeId: selectedKundeId,
                kundeName: kundeName,
                kundePhone: kundePhone,
                kundeEmail: kundeEmail,
                leistungsPositionen: selectedLeistungen,
                preisGesamt: preisGesamt > 0 ? preisGesamt : null,
                dauerGesamt: dauerGesamt > 0 ? dauerGesamt : null,
              )
                  : await _saveTermin(
                titel: titel,
                datum: selectedDate,
                fromTime: fromTime,
                toTime: toTime,
                mitarbeiter: mitarbeiter,
                kundeId: selectedKundeId,
                kundeName: kundeName,
                kundePhone: kundePhone,
                kundeEmail: kundeEmail,
                leistungsPositionen: selectedLeistungen,
                preisGesamt: preisGesamt > 0 ? preisGesamt : null,
                dauerGesamt: dauerGesamt > 0 ? dauerGesamt : null,
              );

              if (!mounted) return;

              if (saveResult == null) {
                Navigator.of(dialogContext).pop();
                _showSnackBar(
                  isEditMode
                      ? 'Termin erfolgreich aktualisiert.'
                      : 'Termin erfolgreich gespeichert.',
                );
                return;
              }

              setDialogState(() {
                isSaving = false;
                validationMessage = saveResult;
              });
              _showSnackBar(saveResult);
            }

            Future<void> handleDelete() async {
              if (!isEditMode || isDeleting || isSaving) {
                return;
              }

              setDialogState(() {
                isDeleting = true;
                validationMessage = null;
              });

              final deleteResult = await _deleteTermin(initialTermin!.id);

              if (!mounted) return;

              if (deleteResult == null) {
                Navigator.of(dialogContext).pop();
                _showSnackBar('Termin erfolgreich gelöscht.');
                return;
              }

              setDialogState(() {
                isDeleting = false;
                validationMessage = deleteResult;
              });
              _showSnackBar(deleteResult);
            }

            final customerLinked = selectedKundeId != null;
            final hasAnySuggestions =
                emailSuggestions.isNotEmpty || phoneSuggestions.isNotEmpty;

            return AlertDialog(
              title: Text(
                isEditMode ? 'Termin bearbeiten' : 'Termin eintragen',
              ),
              content: SizedBox(
                width: 440,
                child: FutureBuilder<List<_MitarbeiterOption>>(
                  future: mitarbeiterFuture,
                  builder: (context, mitarbeiterSnapshot) {
                    final mitarbeiter =
                        mitarbeiterSnapshot.data ?? const <_MitarbeiterOption>[];
                    hasMitarbeiter = mitarbeiter.isNotEmpty;
                    isLoadingMitarbeiter =
                        mitarbeiterSnapshot.connectionState ==
                            ConnectionState.waiting;

                    final mitarbeiterError = mitarbeiterSnapshot.hasError
                        ? 'Mitarbeiter konnten nicht geladen werden.'
                        : null;

                    final ausgewahlterMitarbeiter = _resolveSelectedMitarbeiter(
                      mitarbeiter: mitarbeiter,
                      selectedMitarbeiter: selectedMitarbeiter,
                      initialTermin: initialTermin,
                    );

                    if (selectedMitarbeiter?.id !=
                        ausgewahlterMitarbeiter?.id) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setDialogState(() {
                          selectedMitarbeiter = ausgewahlterMitarbeiter;
                        });
                      });
                    }

                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: kundeNameController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Kundenname *',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) {
                              if (selectedKundeId != null) {
                                setDialogState(() {
                                  selectedKundeId = null;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: kundePhoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Handynummer',
                              border: const OutlineInputBorder(),
                              suffixIcon: isLoadingPhoneSuggestions
                                  ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                                  : customerLinked
                                  ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                                  : null,
                            ),
                            onChanged: (value) async {
                              if (selectedKundeId != null) {
                                setDialogState(() {
                                  selectedKundeId = null;
                                });
                              }
                              await loadPhoneSuggestions(value, setDialogState);
                            },
                          ),
                          if (phoneSuggestions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildSuggestionList(
                              suggestions: phoneSuggestions,
                              query: phoneSearchQuery,
                              matchBuilder: (suggestion) =>
                                  _formatPhoneDisplay(suggestion.phone),
                              onTap: (suggestion) => applyCustomerSuggestion(
                                suggestion,
                                setDialogState,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextField(
                            controller: kundeEmailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'E-Mail',
                              border: const OutlineInputBorder(),
                              suffixIcon: isLoadingEmailSuggestions
                                  ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                                  : customerLinked
                                  ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                                  : null,
                            ),
                            onChanged: (value) async {
                              if (selectedKundeId != null) {
                                setDialogState(() {
                                  selectedKundeId = null;
                                });
                              }
                              await loadEmailSuggestions(value, setDialogState);
                            },
                          ),
                          if (emailSuggestions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildSuggestionList(
                              suggestions: emailSuggestions,
                              query: emailSearchQuery,
                              matchBuilder: (suggestion) => suggestion.email,
                              onTap: (suggestion) => applyCustomerSuggestion(
                                suggestion,
                                setDialogState,
                              ),
                            ),
                          ],
                          if (kundeEmailController.text.isNotEmpty ||
                              kundePhoneController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (customerLinked) ...[
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Kunde erkannt',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ] else if (hasAnySuggestions) ...[
                                  const Icon(
                                    Icons.info_outline,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Vorschläge gefunden',
                                    style: TextStyle(color: Colors.blue),
                                  ),
                                ] else ...[
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Kein registrierter Kunde',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          _buildDialogPickerField(
                            label: 'Datum',
                            value: _formatDate(selectedDate),
                            icon: Icons.calendar_today_outlined,
                            onTap: pickDate,
                          ),
                          const SizedBox(height: 16),
                          if (isLoadingMitarbeiter)
                            const InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Mitarbeiter *',
                                border: OutlineInputBorder(),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child:
                                    Text('Mitarbeiter werden geladen...'),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            DropdownButtonFormField<String>(
                              value: ausgewahlterMitarbeiter?.id,
                              decoration: const InputDecoration(
                                labelText: 'Mitarbeiter *',
                                border: OutlineInputBorder(),
                              ),
                              isExpanded: true,
                              items: mitarbeiter
                                  .map(
                                    (item) => DropdownMenuItem<String>(
                                  value: item.id,
                                  child: Text(item.name),
                                ),
                              )
                                  .toList(growable: false),
                              onChanged: hasMitarbeiter && !isSaving && !isDeleting
                                  ? (value) {
                                setDialogState(() {
                                  selectedMitarbeiter =
                                      _findMitarbeiterById(
                                        mitarbeiter,
                                        value,
                                      );
                                  validationMessage = null;
                                });
                              }
                                  : null,
                            ),
                            if (mitarbeiterError != null || !hasMitarbeiter) ...[
                              const SizedBox(height: 8),
                              Text(
                                mitarbeiterError ??
                                    'Keine aktiven Mitarbeiter verfügbar.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                  color: const Color(0xFFB42318),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 12),
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Gebuchte Leistungen',
                              border: OutlineInputBorder(),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: isSaving || isDeleting
                                      ? null
                                      : () async {
                                    final geschlecht = await _loadKundeGeschlecht(
                                      selectedKundeId,
                                    );
                                    final initialZielgruppe =
                                    _zielgruppeAusGeschlecht(geschlecht);
                                    final ausgewaehlt =
                                    await _showLeistungAuswahlSheet(
                                      context: context,
                                      initialSelected: selectedLeistungen,
                                      initialZielgruppe: initialZielgruppe,
                                    );
                                    if (ausgewaehlt == null) return;

                                    setDialogState(() {
                                      selectedLeistungen = ausgewaehlt;
                                      validationMessage = null;
                                    });
                                  },
                                  icon: const Icon(Icons.add),
                                  label: const Text('+ Leistung auswählen'),
                                ),
                                if (selectedLeistungen.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  ...selectedLeistungen.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final item = entry.value;
                                    final subtitleParts = <String>[
                                      if (item.subtitle.trim().isNotEmpty)
                                        item.subtitle.trim(),
                                      if (item.duration != null && item.duration! > 0)
                                        '${item.duration} Min',
                                      if (item.price != null && item.price! > 0)
                                        _formatEuro(item.price!),
                                    ];

                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom: index == selectedLeistungen.length - 1 ? 0 : 8,
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.category.trim().isNotEmpty
                                                      ? item.category.trim()
                                                      : 'Leistungen',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                    color: const Color(0xFF667085),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.title,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                    color: const Color(0xFF101828),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (subtitleParts.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    subtitleParts.join(' • '),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                      color: const Color(0xFF667085),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Leistung entfernen',
                                            onPressed: isSaving || isDeleting
                                                ? null
                                                : () {
                                              setDialogState(() {
                                                selectedLeistungen.removeAt(index);
                                              });
                                            },
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const Divider(height: 18),
                                  Text(
                                    'Gesamtdauer: ${berechneGesamtDauer(selectedLeistungen)} Min',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF344054),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Gesamtpreis: ${_formatEuro(berechneGesamtPreis(selectedLeistungen))}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF344054),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDialogPickerField(
                                  label: 'Von *',
                                  value: _formatTime(fromTime),
                                  icon: Icons.schedule,
                                  onTap: () => pickTime(isStartTime: true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildDialogPickerField(
                                  label: 'Bis *',
                                  value: _formatTime(toTime),
                                  icon: Icons.schedule_outlined,
                                  onTap: () => pickTime(isStartTime: false),
                                ),
                              ),
                            ],
                          ),
                          if (validationMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              validationMessage!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                color: const Color(0xFFB42318),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              actions: [
                if (isEditMode)
                  TextButton(
                    onPressed: isSaving || isDeleting ? null : handleDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB42318),
                    ),
                    child: isDeleting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Löschen'),
                  ),
                TextButton(
                  onPressed: isSaving || isDeleting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: isSaving || isDeleting ? null : handleSave,
                  child: isSaving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    kundeNameController.dispose();
    kundePhoneController.dispose();
    kundeEmailController.dispose();
  }

  Future<List<_LeistungsPosition>?> _showLeistungAuswahlSheet({
    required BuildContext context,
    required List<_LeistungsPosition> initialSelected,
    String? initialZielgruppe,
  }) async {
    var selectedItems = initialSelected
        .map(
          (item) => AngebotSelectionItem(
        category: item.category,
        title: item.title,
        subtitle: item.subtitle,
        price: item.price,
        originalPrice: item.originalPrice,
        duration: item.duration,
      ),
    )
        .toList(growable: false);

    return showModalBottomSheet<List<_LeistungsPosition>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Leistungen auswählen',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: AngeboteView.selection(
                          dienstleisterId: widget.dienstleisterId,
                          initialSelection: selectedItems,
                          initialZielgruppe: initialZielgruppe ?? 'Damen',
                          onSelectionChanged: (items) {
                            setSheetState(() {
                              selectedItems = items;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Abbrechen'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final selected = selectedItems
                                    .map(
                                      (item) => _LeistungsPosition(
                                    category: item.category,
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    price: item.price,
                                    originalPrice: item.originalPrice,
                                    duration: item.duration,
                                  ),
                                )
                                    .toList(growable: false);
                                Navigator.of(sheetContext).pop(selected);
                              },
                              child: const Text('Übernehmen'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSuggestionList({
    required List<_KundenSuggestion> suggestions,
    required String query,
    required String Function(_KundenSuggestion suggestion) matchBuilder,
    required ValueChanged<_KundenSuggestion> onTap,
  }) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD0D5DD)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          final displayPhone = suggestion.phone.isNotEmpty
              ? _formatPhoneDisplay(suggestion.phone)
              : 'Keine Nummer';
          final displayEmail =
          suggestion.email.isNotEmpty ? suggestion.email : 'Keine E-Mail';
          final displayName =
          suggestion.name.isNotEmpty ? suggestion.name : 'Unbekannt';
          final matchText = matchBuilder(suggestion);

          return InkWell(
            onTap: () => onTap(suggestion),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFF2F4F7),
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName.characters.first.toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Color(0xFF344054),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(
                              color: Color(0xFF101828),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            children: _buildHighlightedTextSpans(
                              displayName,
                              query,
                              highlightStyle: const TextStyle(
                                color: Color(0xFF175CD3),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            children: _buildHighlightedTextSpans(
                              matchText,
                              query,
                              highlightStyle: const TextStyle(
                                color: Color(0xFF175CD3),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          matchText == displayEmail
                              ? displayPhone
                              : displayEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 13,
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
      ),
    );
  }

  List<TextSpan> _buildHighlightedTextSpans(
      String text,
      String query, {
        TextStyle? baseStyle,
        TextStyle? highlightStyle,
      }) {
    final resolvedBaseStyle = baseStyle ?? const TextStyle();
    final resolvedHighlightStyle =
        highlightStyle ?? resolvedBaseStyle.copyWith(fontWeight: FontWeight.w700);

    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return [TextSpan(text: text, style: resolvedBaseStyle)];
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = trimmedQuery.toLowerCase();
    final spans = <TextSpan>[];

    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        if (start < text.length) {
          spans.add(
            TextSpan(
              text: text.substring(start),
              style: resolvedBaseStyle,
            ),
          );
        }
        break;
      }

      if (index > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, index),
            style: resolvedBaseStyle,
          ),
        );
      }

      final end = index + trimmedQuery.length;
      spans.add(
        TextSpan(
          text: text.substring(index, end),
          style: resolvedHighlightStyle,
        ),
      );

      start = end;
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: resolvedBaseStyle));
    }

    return spans;
  }

  String _buildAutomaticTerminTitle({
    required String kundeName,
    _TerminEntry? initialTermin,
  }) {
    if (initialTermin != null &&
        initialTermin.quelle.trim().toLowerCase() == 'kunde' &&
        initialTermin.titel.trim().isNotEmpty) {
      return initialTermin.titel.trim();
    }

    final trimmedName = kundeName.trim();
    if (trimmedName.isNotEmpty) {
      return trimmedName;
    }

    return 'Termin';
  }

  String _readFirstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  String _normalizePhone(String input) {
    var value = input.trim();

    value = value
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('/', '')
        .replaceAll('(', '')
        .replaceAll(')', '');

    if (value.startsWith('00')) {
      value = '+${value.substring(2)}';
    }

    if (value.startsWith('0') && !value.startsWith('+')) {
      value = '+49${value.substring(1)}';
    }

    return value;
  }

  bool _phoneMatches(String a, String b) {
    final normalizedA = _normalizePhone(a);
    final normalizedB = _normalizePhone(b);

    if (normalizedA.isEmpty || normalizedB.isEmpty) return false;

    return normalizedA.contains(normalizedB) || normalizedB.contains(normalizedA);
  }

  String _formatPhoneDisplay(String phone) {
    final cleaned = phone.replaceAll(' ', '').trim();

    if (cleaned.startsWith('+49')) {
      return '0${cleaned.substring(3)}';
    }

    if (cleaned.startsWith('49')) {
      return '0${cleaned.substring(2)}';
    }

    return cleaned;
  }

  Widget _buildDialogPickerField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: Icon(icon),
        ),
        child: Text(value),
      ),
    );
  }

  int _resolveKalenderFarbeValue(dynamic rawValue) {
    if (rawValue is int) {
      return rawValue;
    }

    if (rawValue is String) {
      final parsed = int.tryParse(rawValue.trim());
      if (parsed != null) {
        return parsed;
      }
    }

    return _defaultKalenderFarbeValue;
  }

  Stream<List<_MitarbeiterOption>> _watchActiveMitarbeiter() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final dienstleisterId = currentUser?.uid.trim().isNotEmpty == true
        ? currentUser!.uid.trim()
        : widget.dienstleisterId.trim();

    if (dienstleisterId.isEmpty) {
      return Stream<List<_MitarbeiterOption>>.value(const <_MitarbeiterOption>[]);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .where('rolle', isEqualTo: 'mitarbeiter')
        .where('dienstleisterId', isEqualTo: dienstleisterId)
        .where('aktiv', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final mitarbeiter = snapshot.docs
          .map((doc) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim();
        if (name == null || name.isEmpty) {
          return null;
        }

        return _MitarbeiterOption(
          id: doc.id,
          name: name,
          kalenderFarbeValue: _resolveKalenderFarbeValue(data['kalenderFarbe']),
        );
      })
          .whereType<_MitarbeiterOption>()
          .toList(growable: false);

      mitarbeiter.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      final activeIds = mitarbeiter.map((item) => item.id).toSet();
      if (!_alleMitarbeiterAnzeigen) {
        final idsToRemove = _selectedMitarbeiterIds
            .where((id) => !activeIds.contains(id))
            .toList(growable: false);

        if (idsToRemove.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _selectedMitarbeiterIds.removeAll(idsToRemove);
            });
          });
        }
      }

      return mitarbeiter;
    });
  }

  void _handleMitarbeiterSelectionChanged({
    required List<_MitarbeiterOption> mitarbeiter,
    required String mitarbeiterId,
    required bool isSelected,
  }) {
    final allIds = mitarbeiter.map((item) => item.id).toSet();

    setState(() {
      if (_alleMitarbeiterAnzeigen) {
        if (!isSelected) {
          _alleMitarbeiterAnzeigen = false;
          _selectedMitarbeiterIds
            ..clear()
            ..addAll(allIds)
            ..remove(mitarbeiterId);
        }
        return;
      }

      if (isSelected) {
        _selectedMitarbeiterIds.add(mitarbeiterId);
      } else {
        _selectedMitarbeiterIds.remove(mitarbeiterId);
      }

      if (_selectedMitarbeiterIds.length >= allIds.length && allIds.isNotEmpty) {
        _alleMitarbeiterAnzeigen = true;
        _selectedMitarbeiterIds.clear();
      }
    });
  }

  List<_TerminEntry> _applyMitarbeiterFilter(List<_TerminEntry> termine) {
    if (_alleMitarbeiterAnzeigen) {
      return termine;
    }

    if (_selectedMitarbeiterIds.isEmpty) {
      return const <_TerminEntry>[];
    }

    return termine.where((termin) {
      final mitarbeiterId = termin.mitarbeiterId?.trim();
      if (mitarbeiterId == null || mitarbeiterId.isEmpty) {
        return false;
      }
      return _selectedMitarbeiterIds.contains(mitarbeiterId);
    }).toList(growable: false);
  }

  int _resolveTerminFarbe({
    required _TerminEntry termin,
    required Map<String, int> mitarbeiterFarben,
  }) {
    final mitarbeiterId = termin.mitarbeiterId?.trim();
    if (mitarbeiterId != null && mitarbeiterId.isNotEmpty) {
      final mitarbeiterFarbe = mitarbeiterFarben[mitarbeiterId];
      if (mitarbeiterFarbe != null) {
        return mitarbeiterFarbe;
      }
    }

    return _defaultKalenderFarbeValue;
  }

  Future<List<_MitarbeiterOption>> _loadActiveMitarbeiter() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final dienstleisterId = currentUser?.uid.trim().isNotEmpty == true
        ? currentUser!.uid.trim()
        : widget.dienstleisterId.trim();

    if (dienstleisterId.isEmpty) {
      return const <_MitarbeiterOption>[];
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('rolle', isEqualTo: 'mitarbeiter')
          .where('dienstleisterId', isEqualTo: dienstleisterId)
          .where('aktiv', isEqualTo: true)
          .get();

      final mitarbeiter = snapshot.docs
          .map((doc) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim();
        if (name == null || name.isEmpty) {
          return null;
        }

        return _MitarbeiterOption(
          id: doc.id,
          name: name,
          kalenderFarbeValue: _resolveKalenderFarbeValue(data['kalenderFarbe']),
        );
      })
          .whereType<_MitarbeiterOption>()
          .toList(growable: false);

      mitarbeiter.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return mitarbeiter;
    } on FirebaseException {
      return const <_MitarbeiterOption>[];
    } catch (_) {
      return const <_MitarbeiterOption>[];
    }
  }

  _MitarbeiterOption? _findMitarbeiterById(
      List<_MitarbeiterOption> mitarbeiter,
      String? id,
      ) {
    if (id == null || id.trim().isEmpty) {
      return null;
    }

    for (final item in mitarbeiter) {
      if (item.id == id) {
        return item;
      }
    }

    return null;
  }

  _MitarbeiterOption? _buildInitialMitarbeiterOption(_TerminEntry? termin) {
    final mitarbeiterId = termin?.mitarbeiterId?.trim();
    if (mitarbeiterId == null || mitarbeiterId.isEmpty) {
      return null;
    }

    final mitarbeiterName = termin?.mitarbeiterName?.trim();
    return _MitarbeiterOption(
      id: mitarbeiterId,
      name: mitarbeiterName != null && mitarbeiterName.isNotEmpty
          ? mitarbeiterName
          : 'Unbekannter Mitarbeiter',
      kalenderFarbeValue: _defaultKalenderFarbeValue,
    );
  }

  _MitarbeiterOption? _resolveSelectedMitarbeiter({
    required List<_MitarbeiterOption> mitarbeiter,
    required _MitarbeiterOption? selectedMitarbeiter,
    _TerminEntry? initialTermin,
  }) {
    if (mitarbeiter.isEmpty) {
      return null;
    }

    final selectedId = selectedMitarbeiter?.id.trim() ?? '';
    if (selectedId.isNotEmpty) {
      final bySelectedId = _findMitarbeiterById(mitarbeiter, selectedId);
      if (bySelectedId != null) {
        return bySelectedId;
      }
    }

    final selectedName = selectedMitarbeiter?.name.trim().toLowerCase() ?? '';
    if (selectedName.isNotEmpty) {
      for (final item in mitarbeiter) {
        if (item.name.trim().toLowerCase() == selectedName) {
          return item;
        }
      }
    }

    final initialId = initialTermin?.mitarbeiterId?.trim() ?? '';
    if (initialId.isNotEmpty) {
      final byInitialId = _findMitarbeiterById(mitarbeiter, initialId);
      if (byInitialId != null) {
        return byInitialId;
      }
    }

    final initialName = initialTermin?.mitarbeiterName?.trim().toLowerCase() ?? '';
    if (initialName.isNotEmpty) {
      for (final item in mitarbeiter) {
        if (item.name.trim().toLowerCase() == initialName) {
          return item;
        }
      }
    }

    return null;
  }

  Future<String?> _saveTermin({
    required String titel,
    required DateTime datum,
    required TimeOfDay fromTime,
    required TimeOfDay toTime,
    required _MitarbeiterOption mitarbeiter,
    required String? kundeId,
    required String kundeName,
    required String kundePhone,
    required String kundeEmail,
    required List<_LeistungsPosition> leistungsPositionen,
    required double? preisGesamt,
    required int? dauerGesamt,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return 'Du bist nicht angemeldet.';
      }

      final dienstleisterName = await _loadDienstleisterName();

      final dienstleisterId = widget.dienstleisterId.trim();
      if (dienstleisterId.isEmpty) {
        return 'Dienstleister-ID konnte nicht ermittelt werden.';
      }

      final startAt = _combineDateAndTime(datum, fromTime);
      final endAt = _combineDateAndTime(datum, toTime);
      final now = Timestamp.now();
      final leistungen = leistungsPositionen
          .map((item) => item.title.trim())
          .where((title) => title.isNotEmpty)
          .toList(growable: false);
      final leistungenPayload = leistungsPositionen
          .map((item) => <String, dynamic>{
        'category': item.category,
        'title': item.title,
        'subtitle': item.subtitle,
        'price': item.price,
        'originalPrice': item.originalPrice,
        'duration': item.duration,
      })
          .toList(growable: false);

      await FirebaseFirestore.instance.collection('termine').add({
        'dienstleisterId': dienstleisterId,
        'dienstleisterName': dienstleisterName,
        'mitarbeiterId': mitarbeiter.id,
        'mitarbeiterName': mitarbeiter.name,
        'titel': titel,
        'kundeId': kundeId,
        'kundeName': kundeName,
        'kundePhone': kundePhone,
        'kundeEmail': kundeEmail,
        'datum': _formatDate(datum),
        'startZeit': _formatTime(fromTime),
        'endZeit': _formatTime(toTime),
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
        'leistungen': leistungen,
        'leistungsPositionen': leistungenPayload,
        'preisGesamt': preisGesamt,
        'dauerGesamt': dauerGesamt,
        'status': 'bestaetigt',
        'quelle': 'dienstleister',
        'createdAt': now,
        'updatedAt': now,
      });

      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Termin konnte nicht gespeichert werden.';
    } catch (_) {
      return 'Termin konnte nicht gespeichert werden.';
    }
  }

  Future<String?> _updateTermin({
    required String terminId,
    required String titel,
    required DateTime datum,
    required TimeOfDay fromTime,
    required TimeOfDay toTime,
    required _MitarbeiterOption mitarbeiter,
    required String? kundeId,
    required String kundeName,
    required String kundePhone,
    required String kundeEmail,
    required List<_LeistungsPosition> leistungsPositionen,
    required double? preisGesamt,
    required int? dauerGesamt,
  }) async {
    try {
      final cleanedTerminId = terminId.trim();
      if (cleanedTerminId.isEmpty) {
        return 'Termin konnte nicht aktualisiert werden.';
      }

      final dienstleisterName = await _loadDienstleisterName();

      final startAt = _combineDateAndTime(datum, fromTime);
      final endAt = _combineDateAndTime(datum, toTime);
      final leistungen = leistungsPositionen
          .map((item) => item.title.trim())
          .where((title) => title.isNotEmpty)
          .toList(growable: false);
      final leistungenPayload = leistungsPositionen
          .map((item) => <String, dynamic>{
        'category': item.category,
        'title': item.title,
        'subtitle': item.subtitle,
        'price': item.price,
        'originalPrice': item.originalPrice,
        'duration': item.duration,
      })
          .toList(growable: false);

      await FirebaseFirestore.instance
          .collection('termine')
          .doc(cleanedTerminId)
          .update({
        'dienstleisterName': dienstleisterName,
        'mitarbeiterId': mitarbeiter.id,
        'mitarbeiterName': mitarbeiter.name,
        'titel': titel,
        'kundeId': kundeId,
        'kundeName': kundeName,
        'kundePhone': kundePhone,
        'kundeEmail': kundeEmail,
        'datum': _formatDate(datum),
        'startZeit': _formatTime(fromTime),
        'endZeit': _formatTime(toTime),
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
        'leistungen': leistungen,
        'leistungsPositionen': leistungenPayload,
        'preisGesamt': preisGesamt,
        'dauerGesamt': dauerGesamt,
        'updatedAt': Timestamp.now(),
      });

      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Termin konnte nicht aktualisiert werden.';
    } catch (_) {
      return 'Termin konnte nicht aktualisiert werden.';
    }
  }

  Future<String?> _deleteTermin(String terminId) async {
    try {
      final cleanedTerminId = terminId.trim();
      if (cleanedTerminId.isEmpty) {
        return 'Termin konnte nicht gelöscht werden.';
      }

      await FirebaseFirestore.instance
          .collection('termine')
          .doc(cleanedTerminId)
          .delete();

      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Termin konnte nicht gelöscht werden.';
    } catch (_) {
      return 'Termin konnte nicht gelöscht werden.';
    }
  }

  Stream<List<_TerminEntry>> _loadWeekTermine() {
    final dienstleisterId = widget.dienstleisterId.trim();
    if (dienstleisterId.isEmpty) {
      return Stream<List<_TerminEntry>>.value(const <_TerminEntry>[]);
    }

    final startOfWeek = _startOfWeek(_referenceDate);
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    return FirebaseFirestore.instance
        .collection('termine')
        .where('dienstleisterId', isEqualTo: dienstleisterId)
        .snapshots()
        .map((snapshot) {
      final termine = snapshot.docs
          .map(_parseTermin)
          .whereType<_TerminEntry>()
          .where(
            (termin) =>
        !termin.startAt.isBefore(startOfWeek) &&
            termin.startAt.isBefore(endOfWeek),
      )
          .toList(growable: false);

      return List<_TerminEntry>.from(termine)
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
    });
  }

  _TerminEntry? _parseTermin(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;

    final titel = (data['titel'] as String?)?.trim();
    if (titel == null || titel.isEmpty) return null;

    final startZeit = (data['startZeit'] as String?)?.trim();
    final endZeit = (data['endZeit'] as String?)?.trim();
    final startAt = _parseTerminDateTime(
      dateValue: data['datum'],
      timeValue: startZeit,
      timestampValue: data['startAt'],
    );
    final endAt = _parseTerminDateTime(
      dateValue: data['datum'],
      timeValue: endZeit,
      timestampValue: data['endAt'],
    );

    if (startAt == null || endAt == null || !endAt.isAfter(startAt)) {
      return null;
    }

    final status = (data['status'] as String?)?.trim() ?? 'bestaetigt';
    final quelle = (data['quelle'] as String?)?.trim() ?? '';
    final kundeId = (data['kundeId'] as String?)?.trim();
    final kundeName = (data['kundeName'] as String?)?.trim();
    final kundePhone = (data['kundePhone'] as String?)?.trim();
    final kundeEmail = (data['kundeEmail'] as String?)?.trim();
    final preisGesamt = _readDouble(data['preisGesamt']);
    final dauerGesamt = _readInt(data['dauerGesamt']);
    final leistungsPositionen =
    _parseLeistungsPositionen(data['leistungsPositionen']);

    return _TerminEntry(
      id: doc.id,
      titel: titel,
      startAt: startAt,
      endAt: endAt,
      mitarbeiterId: (data['mitarbeiterId'] as String?)?.trim(),
      mitarbeiterName: (data['mitarbeiterName'] as String?)?.trim(),
      startZeit: startZeit?.isNotEmpty == true
          ? startZeit!
          : _formatTime(TimeOfDay.fromDateTime(startAt)),
      endZeit: endZeit?.isNotEmpty == true
          ? endZeit!
          : _formatTime(TimeOfDay.fromDateTime(endAt)),
      status: status,
      quelle: quelle,
      kundeId: kundeId,
      kundeName: kundeName,
      kundePhone: kundePhone,
      kundeEmail: kundeEmail,
      preisGesamt: preisGesamt,
      dauerGesamt: dauerGesamt,
      leistungsPositionen: leistungsPositionen,
    );
  }

  List<_LeistungsPosition> _parseLeistungsPositionen(dynamic value) {
    if (value is! List) return const <_LeistungsPosition>[];

    return value
        .map((item) {
      if (item is! Map) return null;
      final map = Map<String, dynamic>.from(item);
      return _LeistungsPosition(
        category: (map['category'] as String?)?.trim() ?? '',
        title: (map['title'] as String?)?.trim() ?? '',
        subtitle: (map['subtitle'] as String?)?.trim() ?? '',
        price: _readDouble(map['price']),
        originalPrice: _readDouble(map['originalPrice']),
        duration: _readInt(map['duration']),
      );
    })
        .whereType<_LeistungsPosition>()
        .toList(growable: false);
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value.trim().replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  DateTime? _parseTerminDateTime({
    required dynamic dateValue,
    required dynamic timeValue,
    required dynamic timestampValue,
  }) {
    final parsedDate = _parseStoredDate(dateValue);
    final parsedTime = _parseStoredTime(timeValue);

    if (parsedDate != null && parsedTime != null) {
      return DateTime(
        parsedDate.year,
        parsedDate.month,
        parsedDate.day,
        parsedTime.hour,
        parsedTime.minute,
      );
    }

    if (timestampValue is Timestamp) {
      return timestampValue.toDate();
    }
    if (timestampValue is DateTime) {
      return timestampValue;
    }
    if (timestampValue is String) {
      final normalized = timestampValue.trim();
      if (normalized.isNotEmpty) {
        return DateTime.tryParse(normalized);
      }
    }
    return null;
  }

  DateTime? _parseStoredDate(dynamic value) {
    if (value is Timestamp) {
      return _dateOnly(value.toDate());
    }

    if (value is DateTime) {
      return _dateOnly(value);
    }

    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) {
        return null;
      }

      final parsed = DateTime.tryParse(normalized);
      if (parsed != null) {
        return _dateOnly(parsed);
      }

      final parts = normalized.split(RegExp(r'[-./]'));
      if (parts.length == 3) {
        final first = int.tryParse(parts[0]);
        final second = int.tryParse(parts[1]);
        final third = int.tryParse(parts[2]);

        if (first != null && second != null && third != null) {
          if (parts[0].length == 4) {
            return DateTime(first, second, third);
          }
          return DateTime(third, second, first);
        }
      }
    }

    return null;
  }

  TimeOfDay? _parseStoredTime(dynamic value) {
    if (value is Timestamp) {
      return TimeOfDay.fromDateTime(value.toDate());
    }

    if (value is DateTime) {
      return TimeOfDay.fromDateTime(value);
    }

    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) {
        return null;
      }

      final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(normalized);
      if (match != null) {
        final hour = int.tryParse(match.group(1)!);
        final minute = int.tryParse(match.group(2)!);
        if (hour != null && minute != null) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    }

    return null;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _jumpToToday() {
    setState(() {
      _referenceDate = _dateOnly(DateTime.now());
    });
  }

  void _navigateBackward() {
    setState(() {
      switch (_viewMode) {
        case _KalenderViewMode.tag:
          _referenceDate = _referenceDate.subtract(const Duration(days: 1));
          break;
        case _KalenderViewMode.woche:
          _referenceDate = _referenceDate.subtract(const Duration(days: 7));
          break;
        case _KalenderViewMode.monat:
          _referenceDate = DateTime(
            _referenceDate.year,
            _referenceDate.month - 1,
            _referenceDate.day,
          );
          break;
      }
    });
  }

  void _navigateForward() {
    setState(() {
      switch (_viewMode) {
        case _KalenderViewMode.tag:
          _referenceDate = _referenceDate.add(const Duration(days: 1));
          break;
        case _KalenderViewMode.woche:
          _referenceDate = _referenceDate.add(const Duration(days: 7));
          break;
        case _KalenderViewMode.monat:
          _referenceDate = DateTime(
            _referenceDate.year,
            _referenceDate.month + 1,
            _referenceDate.day,
          );
          break;
      }
    });
  }

  List<DateTime> get _weekDates {
    final startOfWeek = _startOfWeek(_referenceDate);
    return List.generate(
      7,
          (index) => startOfWeek.add(Duration(days: index)),
    );
  }

  DateTime _startOfWeek(DateTime date) {
    final normalizedDate = _dateOnly(date);
    final daysFromMonday = normalizedDate.weekday - DateTime.monday;
    return normalizedDate.subtract(Duration(days: daysFromMonday));
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _formatMonthYear(DateTime date) {
    return '${_monthLabels[date.month - 1]} ${date.year}';
  }

  String _formatDate(DateTime date) {
    final normalizedDate = _dateOnly(date);
    final day = normalizedDate.day.toString().padLeft(2, '0');
    final month = normalizedDate.month.toString().padLeft(2, '0');
    final year = normalizedDate.year.toString();
    return '$day.$month.$year';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }
}

class _TerminEntry {
  final String id;
  final String titel;
  final DateTime startAt;
  final DateTime endAt;
  final String? mitarbeiterId;
  final String? mitarbeiterName;
  final String startZeit;
  final String endZeit;
  final String status;
  final String quelle;
  final String? kundeId;
  final String? kundeName;
  final String? kundePhone;
  final String? kundeEmail;
  final double? preisGesamt;
  final int? dauerGesamt;
  final List<_LeistungsPosition> leistungsPositionen;

  const _TerminEntry({
    required this.id,
    required this.titel,
    required this.startAt,
    required this.endAt,
    required this.mitarbeiterId,
    required this.mitarbeiterName,
    required this.startZeit,
    required this.endZeit,
    required this.status,
    required this.quelle,
    required this.kundeId,
    required this.kundeName,
    required this.kundePhone,
    required this.kundeEmail,
    required this.preisGesamt,
    required this.dauerGesamt,
    required this.leistungsPositionen,
  });
}

class _PositionedTermin {
  final _TerminEntry termin;
  final int columnIndex;
  final int totalColumns;

  const _PositionedTermin({
    required this.termin,
    required this.columnIndex,
    required this.totalColumns,
  });
}