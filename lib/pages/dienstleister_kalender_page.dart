import 'package:flutter/material.dart';

class DienstleisterKalenderPage extends StatefulWidget {
  const DienstleisterKalenderPage({super.key});

  @override
  State<DienstleisterKalenderPage> createState() =>
      _DienstleisterKalenderPageState();
}

enum _KalenderViewMode { tag, woche, monat }

class _DienstleisterKalenderPageState extends State<DienstleisterKalenderPage> {
  static const double _timeColumnWidth = 72;
  static const double _hourRowHeight = 72;
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

  late DateTime _referenceDate;
  _KalenderViewMode _viewMode = _KalenderViewMode.woche;

  @override
  void initState() {
    super.initState();
    _referenceDate = _dateOnly(DateTime.now());
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
          child: Column(
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
          ),
        ),
      ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
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

    return Column(
      children: [
        _buildWeekHeader(theme, weekDates),
        const Divider(height: 1, color: Color(0xFFE4E7EC)),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTimeColumn(theme),
                    Expanded(child: _buildWeekGrid()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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

  Widget _buildWeekGrid() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFFE4E7EC)),
        ),
      ),
      child: Row(
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

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String _formatMonthYear(DateTime date) {
    return '${_monthLabels[date.month - 1]} ${date.year}';
  }
}
