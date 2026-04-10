import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/services/notification_dispatch_service.dart';
import 'package:termini/checkmytime/widgets/checkmytime_ui.dart';

class CreateEventPage extends StatefulWidget {
  final String? eventId;
  final String? initialSelectedUserId;
  final String? initialSelectedUserName;
  final String? initialSelectedUserPhone;
  final String? initialSelectedUserImageUrl;

  const CreateEventPage({
    super.key,
    this.eventId,
    this.initialSelectedUserId,
    this.initialSelectedUserName,
    this.initialSelectedUserPhone,
    this.initialSelectedUserImageUrl,
  });

  bool get isEditMode => eventId != null && eventId!.trim().isNotEmpty;

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  static const List<_EventKindOption> _eventKindOptions = [
    _EventKindOption(
      id: 'open',
      label: 'Event',
      eyebrow: 'Offenes Event',
      heroTitle: 'Offenes Event starten',
      heroDescription:
      'Plane eine offene Unternehmung, die spaeter auch fuer weitere Personen sichtbar sein kann.',
      titleHint: 'z. B. Spieleabend im Park',
      descriptionHint: 'z. B. Wer hat am Wochenende Lust?',
      buttonLabel: 'Event erstellen',
      icon: Icons.celebration_outlined,
    ),
    _EventKindOption(
      id: 'appointment',
      label: 'Termin',
      eyebrow: 'Fester Termin',
      heroTitle: 'Termin planen',
      heroDescription:
      'Plane eine klare Verabredung mit Datum und Personen, zum Beispiel ein Treffen oder einen festen Vorschlag.',
      titleHint: 'z. B. Kaffee trinken',
      descriptionHint: 'z. B. Lass uns Freitag um 18 Uhr treffen.',
      buttonLabel: 'Termin erstellen',
      icon: Icons.event_available_rounded,
    ),
    _EventKindOption(
      id: 'activity',
      label: 'Treffen',
      eyebrow: 'Gemeinsam unterwegs',
      heroTitle: 'Treffen planen',
      heroDescription:
      'Plane gemeinsame Freizeitaktivitaeten mit mehreren Personen, zum Beispiel Billard, Kino oder Cafe.',
      titleHint: 'z. B. Billard am Samstag',
      descriptionHint: 'z. B. Wer hat Samstagabend Lust auf Billard?',
      buttonLabel: 'Treffen erstellen',
      icon: Icons.groups_2_outlined,
    ),
    _EventKindOption(
      id: 'service',
      label: 'Dienstleistung',
      eyebrow: 'Privater Service',
      heroTitle: 'Dienstleistung planen',
      heroDescription:
      'Nutze CheckMyTime auch fuer private Services, zum Beispiel Haare schneiden, Hilfe oder kleine Auftraege unter Bekannten.',
      titleHint: 'z. B. Haare schneiden bei Izet',
      descriptionHint: 'z. B. Freitag nach Feierabend bei Izet zuhause.',
      buttonLabel: 'Dienstleistung erstellen',
      icon: Icons.content_cut_rounded,
    ),
  ];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _isSubmitting = false;
  bool _isInitialLoading = false;
  DateTime? _selectedDate;
  List<_SelectableUser> _selectedUsers = [];
  String _eventKind = 'open';

  bool get _isEditMode => widget.isEditMode;

  _EventKindOption get _selectedKindOption {
    return _eventKindOptions.firstWhere(
          (option) => option.id == _eventKind,
      orElse: () => _eventKindOptions.first,
    );
  }

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _loadExistingEvent();
    } else {
      _applyInitialSelectedUser();
    }
  }

  void _applyInitialSelectedUser() {
    final userId = (widget.initialSelectedUserId ?? '').trim();
    if (userId.isEmpty) return;

    final userName = (widget.initialSelectedUserName ?? '').trim();
    final userPhone = (widget.initialSelectedUserPhone ?? '').trim();
    final userImageUrl = (widget.initialSelectedUserImageUrl ?? '').trim();

    _selectedUsers = <_SelectableUser>[
      _SelectableUser(
        id: userId,
        name: userName.isEmpty ? 'Unbekannt' : userName,
        phone: userPhone,
        imageUrl: userImageUrl,
        selected: true,
      ),
    ];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  String _normalizeEventKind(String? rawValue) {
    final raw = (rawValue ?? '').trim();
    const supported = {'open', 'appointment', 'activity', 'service'};
    if (supported.contains(raw)) return raw;
    return 'open';
  }

  Future<void> _loadExistingEvent() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final eventId = widget.eventId;

    if (currentUser == null || eventId == null) return;

    setState(() {
      _isInitialLoading = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final eventDoc = await firestore.collection('events').doc(eventId).get();
      final data = eventDoc.data();

      if (data == null) {
        _showMessage('Das Event wurde nicht gefunden.');
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      if (createdBy != currentUser.uid) {
        _showMessage('Du kannst nur eigene Events bearbeiten.');
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      final invitedUserIds = List<String>.from(
        data['invitedUserIds'] ?? const [],
      );
      final loadedUsers = await _loadUsersByIds(invitedUserIds);

      if (!mounted) return;
      setState(() {
        _titleController.text = (data['title'] ?? '').toString();
        _descriptionController.text = (data['description'] ?? '').toString();
        _selectedDate =
            (data['scheduledAt'] as Timestamp?)?.toDate() ??
                (data['eventDate'] as Timestamp?)?.toDate();
        _selectedUsers = loadedUsers;
        _eventKind = _normalizeEventKind(
          (data['kind'] ?? data['type']).toString(),
        );
      });
    } catch (_) {
      _showMessage('Das Event konnte nicht geladen werden.');
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  Future<List<_SelectableUser>> _loadUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    final firestore = FirebaseFirestore.instance;
    final result = <_SelectableUser>[];

    for (final userId in userIds) {
      try {
        final doc = await firestore.collection('users').doc(userId).get();
        final data = doc.data() ?? <String, dynamic>{};
        final name =
        (data['displayName'] ?? data['name'] ?? 'Unbekannt')
            .toString()
            .trim();
        final phone = (data['phoneNumber'] ?? '').toString().trim();
        final imageUrl = (data['profileImageUrl'] ?? '').toString().trim();

        result.add(
          _SelectableUser(
            id: userId,
            name: name.isEmpty ? 'Unbekannt' : name,
            phone: phone,
            imageUrl: imageUrl,
            selected: true,
          ),
        );
      } catch (_) {
        result.add(
          _SelectableUser(
            id: userId,
            name: 'Unbekannt',
            phone: '',
            imageUrl: '',
            selected: true,
          ),
        );
      }
    }

    return result;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  String _formattedDate() {
    if (_selectedDate == null) return 'Datum auswaehlen';
    return DateFormat('dd.MM.yyyy', 'de_DE').format(_selectedDate!);
  }

  Future<void> _openUserPicker() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final allUsers =
    snapshot.docs.where((doc) => doc.id != currentUser.uid).map((doc) {
      final data = doc.data();
      return _SelectableUser(
        id: doc.id,
        name:
        (data['displayName'] ?? data['name'] ?? 'Unbekannt')
            .toString()
            .trim(),
        phone: (data['phoneNumber'] ?? '').toString().trim(),
        imageUrl: (data['profileImageUrl'] ?? '').toString().trim(),
        selected: _selectedUsers.any((u) => u.id == doc.id),
      );
    }).toList()
      ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

    if (!mounted) return;

    final result = await showModalBottomSheet<List<_SelectableUser>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _UserPickerSheet(initialUsers: allUsers);
      },
    );

    if (result != null) {
      setState(() {
        _selectedUsers = result.where((u) => u.selected).toList();
      });
    }
  }

  Map<String, String> _buildResponseMap({
    required String currentUserId,
    required List<String> invitedUserIds,
    List<String> acceptedUserIds = const [],
    List<String> maybeUserIds = const [],
    List<String> declinedUserIds = const [],
  }) {
    final responseMap = <String, String>{currentUserId: 'accepted'};

    for (final userId in invitedUserIds) {
      responseMap[userId] = 'pending';
    }
    for (final userId in acceptedUserIds) {
      responseMap[userId] = 'accepted';
    }
    for (final userId in maybeUserIds) {
      responseMap[userId] = 'maybe';
    }
    for (final userId in declinedUserIds) {
      responseMap[userId] = 'declined';
    }

    return responseMap;
  }

  String _visibilityForCurrentKind(List<String> invitedUserIds) {
    if (_eventKind == 'open') return 'open';
    return invitedUserIds.isEmpty ? 'private' : 'invited';
  }

  String _statusForCurrentKind() {
    return _eventKind == 'open' ? 'open' : 'pending';
  }

  Future<void> _submit() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty) {
      _showMessage('Bitte gib einen Titel fuer das Event ein.');
      return;
    }

    if (_selectedDate == null) {
      _showMessage('Bitte waehle ein Datum aus.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final invitedUserIds = _selectedUsers.map((u) => u.id).toSet().toList();
      final scheduledTimestamp = Timestamp.fromDate(_selectedDate!);
      final eventDateText = _formattedDate();
      final visibility = _visibilityForCurrentKind(invitedUserIds);
      final status = _statusForCurrentKind();

      final userDoc =
      await firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final creatorName =
      (userData['displayName'] ?? userData['name'] ?? 'Unbekannt')
          .toString()
          .trim();

      if (_isEditMode) {
        final eventId = widget.eventId!;
        final existingDoc =
        await firestore.collection('events').doc(eventId).get();
        final existingData = existingDoc.data() ?? <String, dynamic>{};
        final previousInvitedUserIds = List<String>.from(
          existingData['invitedUserIds'] ?? const [],
        );
        final acceptedUserIds = List<String>.from(
          existingData['acceptedUserIds'] ?? const [],
        );
        final maybeUserIds = List<String>.from(
          existingData['maybeUserIds'] ?? const [],
        );
        final declinedUserIds = List<String>.from(
          existingData['declinedUserIds'] ?? const [],
        );

        final cleanedAccepted =
        acceptedUserIds
            .where(
              (id) => id == currentUser.uid || invitedUserIds.contains(id),
        )
            .toSet()
            .toList();
        final cleanedMaybe =
        maybeUserIds.where(invitedUserIds.contains).toSet().toList();
        final cleanedDeclined =
        declinedUserIds.where(invitedUserIds.contains).toSet().toList();
        final memberIds = <String>{currentUser.uid, ...invitedUserIds}.toList();
        final participantIds = <String>{...cleanedAccepted}.toList();
        if (!participantIds.contains(currentUser.uid)) {
          participantIds.add(currentUser.uid);
        }

        await firestore.collection('events').doc(eventId).update({
          'title': title,
          'description': description,
          'eventDate': scheduledTimestamp,
          'scheduledAt': scheduledTimestamp,
          'eventDateText': eventDateText,
          'scheduledDateText': eventDateText,
          'invitedUserIds': invitedUserIds,
          'acceptedUserIds': cleanedAccepted,
          'maybeUserIds': cleanedMaybe,
          'declinedUserIds': cleanedDeclined,
          'participantIds': participantIds,
          'memberIds': memberIds,
          'responseMap': _buildResponseMap(
            currentUserId: currentUser.uid,
            invitedUserIds: invitedUserIds,
            acceptedUserIds: cleanedAccepted,
            maybeUserIds: cleanedMaybe,
            declinedUserIds: cleanedDeclined,
          ),
          'type': _eventKind,
          'kind': _eventKind,
          'visibility': visibility,
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final newlyInvitedUserIds =
        invitedUserIds
            .where((id) => !previousInvitedUserIds.contains(id))
            .toList();

        if (newlyInvitedUserIds.isNotEmpty) {
          try {
            await NotificationDispatchService.instance
                .queueEventInviteNotifications(
              recipientUserIds: newlyInvitedUserIds,
              senderId: currentUser.uid,
              senderName: creatorName.isEmpty ? 'Unbekannt' : creatorName,
              eventId: eventId,
              eventTitle: title,
            );
          } catch (_) {}
        }
      } else {
        final eventRef = firestore.collection('events').doc();
        final memberIds = <String>{currentUser.uid, ...invitedUserIds}.toList();

        await eventRef.set({
          'title': title,
          'description': description,
          'eventDate': scheduledTimestamp,
          'scheduledAt': scheduledTimestamp,
          'eventDateText': eventDateText,
          'scheduledDateText': eventDateText,
          'type': _eventKind,
          'kind': _eventKind,
          'status': status,
          'visibility': visibility,
          'createdBy': currentUser.uid,
          'createdByName': creatorName.isEmpty ? 'Unbekannt' : creatorName,
          'participantIds': <String>[currentUser.uid],
          'memberIds': memberIds,
          'invitedUserIds': invitedUserIds,
          'acceptedUserIds': <String>[currentUser.uid],
          'maybeUserIds': <String>[],
          'declinedUserIds': <String>[],
          'responseMap': _buildResponseMap(
            currentUserId: currentUser.uid,
            invitedUserIds: invitedUserIds,
          ),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (invitedUserIds.isNotEmpty) {
          try {
            await NotificationDispatchService.instance
                .queueEventInviteNotifications(
              recipientUserIds: invitedUserIds,
              senderId: currentUser.uid,
              senderName: creatorName.isEmpty ? 'Unbekannt' : creatorName,
              eventId: eventRef.id,
              eventTitle: title,
            );
          } catch (_) {}
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      _showMessage(
        _isEditMode
            ? 'Event konnte nicht aktualisiert werden.'
            : 'Event konnte nicht erstellt werden.',
      );
    }
  }

  Widget _buildSelectedUsers(ColorScheme colorScheme, ThemeData theme) {
    if (_selectedUsers.isEmpty) {
      return CheckMyTimeSectionCard(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Noch keine Personen hinzugefuegt.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
      _selectedUsers.map((user) {
        return InputChip(
          avatar:
          user.imageUrl.isNotEmpty
              ? CircleAvatar(
            backgroundImage: NetworkImage(user.imageUrl),
          )
              : CircleAvatar(
            child: Text(
              user.name.isNotEmpty
                  ? user.name.characters.first.toUpperCase()
                  : '?',
            ),
          ),
          label: Text(user.name),
          onDeleted: () {
            setState(() {
              _selectedUsers.removeWhere((u) => u.id == user.id);
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildEventKindSelector(ThemeData theme, ColorScheme colorScheme) {
    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Typ auswaehlen',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Lege fest, ob du einen Termin, ein Treffen, eine Dienstleistung oder ein offenes Event planst.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children:
            _eventKindOptions.map((option) {
              final isSelected = option.id == _eventKind;
              return ChoiceChip(
                selected: isSelected,
                label: Text(option.label),
                avatar: Icon(
                  option.icon,
                  size: 18,
                  color:
                  isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.primary,
                ),
                onSelected: (_) {
                  setState(() {
                    _eventKind = option.id;
                  });
                },
                selectedColor: colorScheme.primary,
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color:
                  isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(color: colorScheme.outlineVariant),
                backgroundColor: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedKind = _selectedKindOption;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Event bearbeiten' : 'Event erstellen'),
      ),
      body: CheckMyTimeGradientBackground(
        child: SafeArea(
          child:
          _isInitialLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              CheckMyTimeHeroCard(
                eyebrow:
                _isEditMode
                    ? 'Bestehendes ${selectedKind.label}'
                    : selectedKind.eyebrow,
                title:
                _isEditMode
                    ? '${selectedKind.label} aktualisieren'
                    : selectedKind.heroTitle,
                description:
                _isEditMode
                    ? 'Hier kannst du Typ, Titel, Beschreibung, Datum und eingeladene Personen anpassen.'
                    : selectedKind.heroDescription,
                trailing: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _isEditMode
                        ? Icons.edit_calendar_rounded
                        : selectedKind.icon,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildEventKindSelector(theme, colorScheme),
              const SizedBox(height: 16),
              CheckMyTimeSectionCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Titel',
                        hintText: selectedKind.titleHint,
                        prefixIcon: const Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Beschreibung',
                        hintText: selectedKind.descriptionHint,
                        prefixIcon: const Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(16),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Datum',
                          suffixIcon: Icon(
                            Icons.calendar_today_outlined,
                          ),
                        ),
                        child: Text(_formattedDate()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CheckMyTimeSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Personen hinzufuegen',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openUserPicker,
                          icon: const Icon(
                            Icons.person_add_alt_1_outlined,
                          ),
                          label: const Text('Auswaehlen'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildSelectedUsers(colorScheme, theme),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon:
                        _isSubmitting
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : Icon(
                          _isEditMode
                              ? Icons.save_outlined
                              : selectedKind.icon,
                        ),
                        label: Text(
                          _isSubmitting
                              ? (_isEditMode
                              ? 'Wird gespeichert...'
                              : 'Wird erstellt...')
                              : (_isEditMode
                              ? 'Aenderungen speichern'
                              : selectedKind.buttonLabel),
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
    );
  }
}

class _SelectableUser {
  final String id;
  final String name;
  final String phone;
  final String imageUrl;
  final bool selected;

  const _SelectableUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.imageUrl,
    required this.selected,
  });

  _SelectableUser copyWith({bool? selected}) {
    return _SelectableUser(
      id: id,
      name: name,
      phone: phone,
      imageUrl: imageUrl,
      selected: selected ?? this.selected,
    );
  }
}

class _EventKindOption {
  final String id;
  final String label;
  final String eyebrow;
  final String heroTitle;
  final String heroDescription;
  final String titleHint;
  final String descriptionHint;
  final String buttonLabel;
  final IconData icon;

  const _EventKindOption({
    required this.id,
    required this.label,
    required this.eyebrow,
    required this.heroTitle,
    required this.heroDescription,
    required this.titleHint,
    required this.descriptionHint,
    required this.buttonLabel,
    required this.icon,
  });
}

class _UserPickerSheet extends StatefulWidget {
  final List<_SelectableUser> initialUsers;

  const _UserPickerSheet({required this.initialUsers});

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  late List<_SelectableUser> _users;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _users = widget.initialUsers;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final filtered =
    _users.where((user) {
      return user.name.toLowerCase().contains(query) ||
          user.phone.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SizedBox(
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Personen auswaehlen',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Nach Name oder Nummer suchen',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child:
                filtered.isEmpty
                    ? const Center(child: Text('Keine Personen gefunden.'))
                    : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    final originalIndex = _users.indexWhere(
                          (item) => item.id == user.id,
                    );

                    return CheckboxListTile(
                      value: user.selected,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      secondary:
                      user.imageUrl.isNotEmpty
                          ? CircleAvatar(
                        backgroundImage: NetworkImage(
                          user.imageUrl,
                        ),
                      )
                          : CircleAvatar(
                        child: Text(
                          user.name.isNotEmpty
                              ? user.name.characters.first
                              .toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(user.name),
                      subtitle: Text(
                        user.phone.isNotEmpty
                            ? user.phone
                            : 'Keine Nummer vorhanden',
                      ),
                      onChanged: (value) {
                        setState(() {
                          final updated = _users[originalIndex]
                              .copyWith(selected: value ?? false);
                          _users[originalIndex] = updated;
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_users),
                  child: const Text('Uebernehmen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
