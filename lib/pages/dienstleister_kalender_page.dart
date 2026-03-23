import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  const _MitarbeiterOption({
    required this.id,
    required this.name,
  });
}

class _DienstleisterKalenderPageState extends State<DienstleisterKalenderPage> {
  static const double _calendarSidebarWidth = 188;
  static const double _timeColumnWidth = 72;
  static const double _hourRowHeight = 72;
  static const double _terminHorizontalPadding = 6;
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
          const Expanded(child: SizedBox()),
        ],
      ),
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

    return StreamBuilder<List<_TerminEntry>>(
      stream: _loadWeekTermine(),
      builder: (context, snapshot) {
        final termine = snapshot.data ?? const <_TerminEntry>[];
        final loadError = snapshot.hasError
            ? 'Termine konnten nicht geladen werden.'
            : null;

        return Column(
          children: [
            _buildWeekHeader(theme, weekDates),
            const Divider(height: 1, color: Color(0xFFE4E7EC)),
            if (loadError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTimeColumn(theme),
                      Expanded(
                        child: _buildWeekGrid(termine: termine, theme: theme),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
    required double dayColumnWidth,
    required ThemeData theme,
  }) {
    final startOfWeek = _startOfWeek(_referenceDate);
    final blockWidth = (dayColumnWidth - (_terminHorizontalPadding * 2))
        .clamp(40.0, dayColumnWidth)
        .toDouble();

    return termine.map((termin) {
      final minutesFromMidnight =
          (termin.startAt.hour * 60) + termin.startAt.minute;
      final durationMinutes = termin.endAt.difference(termin.startAt).inMinutes;
      final top = (minutesFromMidnight / 60) * _hourRowHeight;
      final height = ((durationMinutes / 60) * _hourRowHeight)
          .clamp(32.0, _hourRowHeight * 24)
          .toDouble();
      final dayIndex = termin.startAt.difference(startOfWeek).inDays;

      if (dayIndex < 0 || dayIndex > 6) {
        return const SizedBox.shrink();
      }

      return Positioned(
        top: top + 2,
        left: (dayIndex * dayColumnWidth) + _terminHorizontalPadding,
        width: blockWidth,
        height: height - 4,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showEditAppointmentDialog(termin),
            child: Ink(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB2CCFF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12101828),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    termin.titel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF175CD3),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (height >= 54) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${termin.startZeit} - ${termin.endZeit}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF175CD3),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Future<void> _showCreateAppointmentDialog() async {
    await _showAppointmentDialog();
  }

  Future<void> _showEditAppointmentDialog(_TerminEntry termin) async {
    await _showAppointmentDialog(initialTermin: termin);
  }

  Future<void> _showAppointmentDialog({
    _TerminEntry? initialTermin,
  }) async {
    final titleController = TextEditingController();
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
    _MitarbeiterOption? selectedMitarbeiter =
        _buildInitialMitarbeiterOption(initialTermin);
    String? validationMessage;
    bool isSaving = false;
    bool isDeleting = false;
    bool isLoadingMitarbeiter = true;
    bool hasMitarbeiter = false;
    titleController.text = initialTermin?.titel ?? '';

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
              final titel = titleController.text.trim();
              final startAt = _combineDateAndTime(selectedDate, fromTime);
              final endAt = _combineDateAndTime(selectedDate, toTime);
              final mitarbeiter = selectedMitarbeiter;

              if (titel.isEmpty) {
                setDialogState(() {
                  validationMessage = 'Bitte gib einen Titel ein.';
                });
                _showSnackBar('Titel darf nicht leer sein.');
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

              final saveResult = isEditMode
                  ? await _updateTermin(
                      terminId: initialTermin!.id,
                      titel: titel,
                      datum: selectedDate,
                      fromTime: fromTime,
                      toTime: toTime,
                      mitarbeiter: mitarbeiter,
                    )
                  : await _saveTermin(
                      titel: titel,
                      datum: selectedDate,
                      fromTime: fromTime,
                      toTime: toTime,
                      mitarbeiter: mitarbeiter,
                    );

              if (!mounted) {
                return;
              }

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

              if (!mounted) {
                return;
              }

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

            return AlertDialog(
              title: Text(
                isEditMode ? 'Termin bearbeiten' : 'Termin eintragen',
              ),
              content: SizedBox(
                width: 420,
                child: FutureBuilder<List<_MitarbeiterOption>>(
                  future: mitarbeiterFuture,
                  builder: (context, mitarbeiterSnapshot) {
                    final mitarbeiter =
                        mitarbeiterSnapshot.data ?? const <_MitarbeiterOption>[];
                    hasMitarbeiter = mitarbeiter.isNotEmpty;
                    isLoadingMitarbeiter =
                        mitarbeiterSnapshot.connectionState == ConnectionState.waiting;
                    final mitarbeiterError = mitarbeiterSnapshot.hasError
                        ? 'Mitarbeiter konnten nicht geladen werden.'
                        : null;
                    final ausgewahlterMitarbeiter = _resolveSelectedMitarbeiter(
                      mitarbeiter: mitarbeiter,
                      selectedMitarbeiter: selectedMitarbeiter,
                    );

                    if (selectedMitarbeiter?.id != ausgewahlterMitarbeiter?.id) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) {
                          return;
                        }
                        setDialogState(() {
                          selectedMitarbeiter = ausgewahlterMitarbeiter;
                        });
                      });
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: titleController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Titel *',
                            border: OutlineInputBorder(),
                          ),
                        ),
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
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text('Mitarbeiter werden geladen...'),
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
                                      selectedMitarbeiter = _findMitarbeiterById(
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

    titleController.dispose();
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

            return _MitarbeiterOption(id: doc.id, name: name);
          })
          .whereType<_MitarbeiterOption>()
          .toList(growable: false);

      mitarbeiter.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
    );
  }

  _MitarbeiterOption? _resolveSelectedMitarbeiter({
    required List<_MitarbeiterOption> mitarbeiter,
    required _MitarbeiterOption? selectedMitarbeiter,
  }) {
    final selectedId = selectedMitarbeiter?.id.trim();
    if (selectedId == null || selectedId.isEmpty) {
      return null;
    }

    return _findMitarbeiterById(mitarbeiter, selectedId);
  }

  Future<String?> _saveTermin({
    required String titel,
    required DateTime datum,
    required TimeOfDay fromTime,
    required TimeOfDay toTime,
    required _MitarbeiterOption mitarbeiter,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return 'Du bist nicht angemeldet.';
      }

      final dienstleisterId = widget.dienstleisterId.trim();
      if (dienstleisterId.isEmpty) {
        return 'Dienstleister-ID konnte nicht ermittelt werden.';
      }

      final startAt = _combineDateAndTime(datum, fromTime);
      final endAt = _combineDateAndTime(datum, toTime);
      final now = Timestamp.now();

      await FirebaseFirestore.instance.collection('termine').add({
        'dienstleisterId': dienstleisterId,
        'mitarbeiterId': mitarbeiter.id,
        'mitarbeiterName': mitarbeiter.name,
        'titel': titel,
        'datum': _formatDate(datum),
        'startZeit': _formatTime(fromTime),
        'endZeit': _formatTime(toTime),
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
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
  }) async {
    try {
      final cleanedTerminId = terminId.trim();
      if (cleanedTerminId.isEmpty) {
        return 'Termin konnte nicht aktualisiert werden.';
      }

      final startAt = _combineDateAndTime(datum, fromTime);
      final endAt = _combineDateAndTime(datum, toTime);

      await FirebaseFirestore.instance
          .collection('termine')
          .doc(cleanedTerminId)
          .update({
        'mitarbeiterId': mitarbeiter.id,
        'mitarbeiterName': mitarbeiter.name,
        'titel': titel,
        'datum': _formatDate(datum),
        'startZeit': _formatTime(fromTime),
        'endZeit': _formatTime(toTime),
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
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
          .where((termin) =>
      !termin.startAt.isBefore(startOfWeek) &&
          termin.startAt.isBefore(endOfWeek))
          .toList(growable: false);

      return List<_TerminEntry>.from(termine)
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
    });
  }

  _TerminEntry? _parseTermin(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      return null;
    }

    final titel = (data['titel'] as String?)?.trim();
    if (titel == null || titel.isEmpty) {
      return null;
    }

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
    );
  }

  DateTime? _parseTerminDateTime({
    required dynamic dateValue,
    required dynamic timeValue,
    required dynamic timestampValue,
  }) {
    if (timestampValue is Timestamp) {
      return timestampValue.toDate();
    }

    final parsedDate = _parseStoredDate(dateValue);
    final parsedTime = _parseStoredTime(timeValue);

    if (parsedDate == null || parsedTime == null) {
      return null;
    }

    return DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      parsedTime.hour,
      parsedTime.minute,
    );
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
    if (!mounted) {
      return;
    }

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

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String _formatMonthYear(DateTime date) {
    return '${_monthLabels[date.month - 1]} ${date.year}';
  }

  String _formatDate(DateTime date) {
    final normalizedDate = _dateOnly(date);
    final year = normalizedDate.year.toString().padLeft(4, '0');
    final month = normalizedDate.month.toString().padLeft(2, '0');
    final day = normalizedDate.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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

  const _TerminEntry({
    required this.id,
    required this.titel,
    required this.startAt,
    required this.endAt,
    required this.mitarbeiterId,
    required this.mitarbeiterName,
    required this.startZeit,
    required this.endZeit,
  });
}
