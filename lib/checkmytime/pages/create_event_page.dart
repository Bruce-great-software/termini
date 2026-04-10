import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/services/notification_dispatch_service.dart';
import 'package:termini/checkmytime/widgets/checkmytime_ui.dart';

class CreateEventPage extends StatefulWidget {
  final String? eventId;
  final String? initialContactId;
  final String? initialContactName;

  const CreateEventPage({
    super.key,
    this.eventId,
    this.initialContactId,
    this.initialContactName,
  });

  bool get isEditMode => eventId != null && eventId!.trim().isNotEmpty;

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _isSubmitting = false;
  bool _isInitialLoading = false;
  DateTime? _selectedDate;
  List<_SelectableUser> _selectedUsers = [];
  String _eventType = 'open';

  bool get _isEditMode => widget.isEditMode;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _loadExistingEvent();
    } else {
      _seedInitialSelectedUser();
    }
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

  Future<void> _seedInitialSelectedUser() async {
    final contactId = (widget.initialContactId ?? '').trim();
    if (contactId.isEmpty) return;
    if (_selectedUsers.any((user) => user.id == contactId)) return;

    final fallbackName = (widget.initialContactName ?? '').trim();

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(contactId).get();
      final data = doc.data() ?? <String, dynamic>{};
      final resolvedName =
      (data['displayName'] ?? data['name'] ?? fallbackName).toString().trim();
      final phone = (data['phoneNumber'] ?? '').toString().trim();
      final imageUrl = (data['profileImageUrl'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _selectedUsers = [
          ..._selectedUsers.where((user) => user.id != contactId),
          _SelectableUser(
            id: contactId,
            name: resolvedName.isEmpty
                ? (fallbackName.isEmpty ? 'Unbekannt' : fallbackName)
                : resolvedName,
            phone: phone,
            imageUrl: imageUrl,
            selected: true,
          ),
        ];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedUsers = [
          ..._selectedUsers.where((user) => user.id != contactId),
          _SelectableUser(
            id: contactId,
            name: fallbackName.isEmpty ? 'Unbekannt' : fallbackName,
            phone: '',
            imageUrl: '',
            selected: true,
          ),
        ];
      });
    }
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
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final createdBy = (data['createdBy'] ?? '').toString().trim();
      if (createdBy != currentUser.uid) {
        _showMessage('Du kannst nur eigene Events bearbeiten.');
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final invitedUserIds = List<String>.from(data['invitedUserIds'] ?? const []);
      final loadedUsers = await _loadUsersByIds(invitedUserIds);

      DateTime? parsedDate;
      final scheduledAt = data['scheduledAt'];
      final eventDate = data['eventDate'];
      if (scheduledAt is Timestamp) {
        parsedDate = scheduledAt.toDate();
      } else if (eventDate is Timestamp) {
        parsedDate = eventDate.toDate();
      }

      final loadedType = (data['kind'] ?? data['type'] ?? 'open').toString().trim();

      if (!mounted) return;
      setState(() {
        _titleController.text = (data['title'] ?? '').toString();
        _descriptionController.text = (data['description'] ?? '').toString();
        _selectedDate = parsedDate;
        _selectedUsers = loadedUsers;
        _eventType = loadedType.isEmpty ? 'open' : loadedType;
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
        (data['displayName'] ?? data['name'] ?? 'Unbekannt').toString().trim();
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
          const _SelectableUser(
            id: '',
            name: 'Unbekannt',
            phone: '',
            imageUrl: '',
            selected: true,
          ).copyWith(id: userId),
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
    final allUsers = snapshot.docs
        .where((doc) => doc.id != currentUser.uid)
        .map((doc) {
      final data = doc.data();
      return _SelectableUser(
        id: doc.id,
        name: (data['displayName'] ?? data['name'] ?? 'Unbekannt')
            .toString()
            .trim(),
        phone: (data['phoneNumber'] ?? '').toString().trim(),
        imageUrl: (data['profileImageUrl'] ?? '').toString().trim(),
        selected: _selectedUsers.any((u) => u.id == doc.id),
      );
    })
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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

  Future<void> _submit() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty) {
      _showMessage('Bitte gib einen Titel ein.');
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
      final invitedUserIds = _selectedUsers.map((u) => u.id).toList();
      final memberIds = <String>{currentUser.uid, ...invitedUserIds}.toList();
      final userDoc = await firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final creatorName =
      (userData['displayName'] ?? userData['name'] ?? 'Unbekannt')
          .toString()
          .trim();

      final responseMap = <String, String>{currentUser.uid: 'accepted'};
      for (final userId in invitedUserIds) {
        responseMap[userId] = 'pending';
      }

      final basePayload = <String, dynamic>{
        'title': title,
        'description': description,
        'eventDate': Timestamp.fromDate(_selectedDate!),
        'eventDateText': _formattedDate(),
        'scheduledAt': Timestamp.fromDate(_selectedDate!),
        'type': _eventType,
        'kind': _eventType,
        'status': _defaultStatusForType(_eventType),
        'visibility': _defaultVisibilityForType(_eventType),
        'invitedUserIds': invitedUserIds,
        'memberIds': memberIds,
        'participantIds': <String>[currentUser.uid],
        'responseMap': responseMap,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEditMode) {
        final eventId = widget.eventId!;
        final existingDoc = await firestore.collection('events').doc(eventId).get();
        final existingData = existingDoc.data() ?? <String, dynamic>{};
        final previousInvitedUserIds =
        List<String>.from(existingData['invitedUserIds'] ?? const []);

        final previousResponseMap = Map<String, dynamic>.from(
          existingData['responseMap'] ?? const <String, dynamic>{},
        );
        final mergedResponseMap = <String, String>{currentUser.uid: 'accepted'};
        for (final userId in invitedUserIds) {
          final existingResponse =
          (previousResponseMap[userId] ?? 'pending').toString().trim();
          mergedResponseMap[userId] = existingResponse.isEmpty ? 'pending' : existingResponse;
        }

        final cleanedAccepted = mergedResponseMap.entries
            .where((entry) => entry.value == 'accepted')
            .map((entry) => entry.key)
            .toList();
        final cleanedMaybe = mergedResponseMap.entries
            .where((entry) => entry.value == 'maybe')
            .map((entry) => entry.key)
            .toList();
        final cleanedDeclined = mergedResponseMap.entries
            .where((entry) => entry.value == 'declined')
            .map((entry) => entry.key)
            .toList();

        await firestore.collection('events').doc(eventId).update({
          ...basePayload,
          'acceptedUserIds': cleanedAccepted,
          'maybeUserIds': cleanedMaybe,
          'declinedUserIds': cleanedDeclined,
          'responseMap': mergedResponseMap,
        });

        final newlyInvitedUserIds =
        invitedUserIds.where((id) => !previousInvitedUserIds.contains(id)).toList();

        if (newlyInvitedUserIds.isNotEmpty) {
          try {
            await NotificationDispatchService.instance.queueEventInviteNotifications(
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

        await eventRef.set({
          ...basePayload,
          'createdBy': currentUser.uid,
          'createdByName': creatorName.isEmpty ? 'Unbekannt' : creatorName,
          'acceptedUserIds': <String>[currentUser.uid],
          'maybeUserIds': <String>[],
          'declinedUserIds': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (invitedUserIds.isNotEmpty) {
          try {
            await NotificationDispatchService.instance.queueEventInviteNotifications(
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

  String _typeLabel(String type) {
    switch (type) {
      case 'appointment':
        return 'Termin';
      case 'activity':
        return 'Treffen';
      case 'service':
        return 'Dienstleistung';
      case 'open':
      default:
        return 'Event';
    }
  }

  String _heroEyebrow() {
    if (_isEditMode) return 'Bestehendes ${_typeLabel(_eventType)}';
    return _typeLabel(_eventType);
  }

  String _heroTitle() {
    if (_isEditMode) {
      switch (_eventType) {
        case 'appointment':
          return 'Deinen Termin bearbeiten';
        case 'activity':
          return 'Dein Treffen anpassen';
        case 'service':
          return 'Deine Dienstleistung aktualisieren';
        case 'open':
        default:
          return 'Dein Event aktualisieren';
      }
    }

    switch (_eventType) {
      case 'appointment':
        return 'Termin erstellen';
      case 'activity':
        return 'Treffen planen';
      case 'service':
        return 'Dienstleistung planen';
      case 'open':
      default:
        return 'Offenes Event starten';
    }
  }

  String _heroDescription() {
    if (_isEditMode) {
      return 'Hier kannst du Typ, Titel, Beschreibung, Datum und eingeladene Personen anpassen.';
    }

    switch (_eventType) {
      case 'appointment':
        return 'Plane einen festen Termin mit einer oder mehreren Personen.';
      case 'activity':
        return 'Plane ein gemeinsames Treffen wie Kaffee, Billard oder Kino.';
      case 'service':
        return 'Plane eine private Dienstleistung wie Haare schneiden oder Hilfe vor Ort.';
      case 'open':
      default:
        return 'Plane eine offene Unternehmung, die spaeter auch fuer weitere Personen sichtbar sein kann.';
    }
  }

  IconData _heroIcon() {
    if (_isEditMode) return Icons.edit_calendar_rounded;
    switch (_eventType) {
      case 'appointment':
        return Icons.calendar_month_rounded;
      case 'activity':
        return Icons.groups_rounded;
      case 'service':
        return Icons.content_cut_rounded;
      case 'open':
      default:
        return Icons.celebration_outlined;
    }
  }

  String _titleHint() {
    switch (_eventType) {
      case 'appointment':
        return 'z. B. Friseurtermin';
      case 'activity':
        return 'z. B. Billard spielen';
      case 'service':
        return 'z. B. Haare schneiden';
      case 'open':
      default:
        return 'z. B. Offenes Event';
    }
  }

  String _descriptionHint() {
    switch (_eventType) {
      case 'appointment':
        return 'z. B. Lass uns Freitag um 18 Uhr treffen.';
      case 'activity':
        return 'z. B. Wer hat am Wochenende Lust?';
      case 'service':
        return 'z. B. Bei Izet zuhause, ca. 30 Minuten.';
      case 'open':
      default:
        return 'z. B. Wer moechte teilnehmen?';
    }
  }

  String _submitLabel() {
    if (_isSubmitting) {
      return _isEditMode ? 'Wird gespeichert...' : 'Wird erstellt...';
    }
    if (_isEditMode) return 'Aenderungen speichern';

    switch (_eventType) {
      case 'appointment':
        return 'Termin erstellen';
      case 'activity':
        return 'Treffen erstellen';
      case 'service':
        return 'Dienstleistung erstellen';
      case 'open':
      default:
        return 'Event erstellen';
    }
  }

  String _defaultStatusForType(String type) {
    switch (type) {
      case 'appointment':
      case 'service':
        return 'pending';
      case 'activity':
      case 'open':
      default:
        return 'open';
    }
  }

  String _defaultVisibilityForType(String type) {
    switch (type) {
      case 'open':
        return 'open';
      case 'appointment':
      case 'activity':
      case 'service':
      default:
        return 'private';
    }
  }

  Widget _buildTypePicker(ThemeData theme) {
    final options = const [
      _EventTypeOption('open', 'Event', Icons.celebration_outlined),
      _EventTypeOption('appointment', 'Termin', Icons.calendar_month_rounded),
      _EventTypeOption('activity', 'Treffen', Icons.groups_rounded),
      _EventTypeOption('service', 'Dienstleistung', Icons.content_cut_rounded),
    ];

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
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: options.map((option) {
              final selected = _eventType == option.value;
              return ChoiceChip(
                selected: selected,
                onSelected: (_) => setState(() => _eventType = option.value),
                avatar: Icon(
                  option.icon,
                  size: 18,
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                ),
                label: Text(option.label),
                selectedColor: theme.colorScheme.primary,
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                backgroundColor: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                showCheckmark: false,
              );
            }).toList(),
          ),
        ],
      ),
    );
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
      children: _selectedUsers.map((user) {
        return InputChip(
          avatar: user.imageUrl.isNotEmpty
              ? CircleAvatar(backgroundImage: NetworkImage(user.imageUrl))
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Event bearbeiten' : 'Event erstellen'),
      ),
      body: CheckMyTimeGradientBackground(
        child: SafeArea(
          child: _isInitialLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              CheckMyTimeHeroCard(
                eyebrow: _heroEyebrow(),
                title: _heroTitle(),
                description: _heroDescription(),
                trailing: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _heroIcon(),
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildTypePicker(theme),
              const SizedBox(height: 16),
              CheckMyTimeSectionCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Titel',
                        hintText: _titleHint(),
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
                        hintText: _descriptionHint(),
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
                          suffixIcon: Icon(Icons.calendar_today_outlined),
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
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openUserPicker,
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Auswaehlen'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildSelectedUsers(
                      Theme.of(context).colorScheme,
                      theme,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : Icon(_isEditMode ? Icons.save_outlined : _heroIcon()),
                        label: Text(_submitLabel()),
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

class _EventTypeOption {
  final String value;
  final String label;
  final IconData icon;

  const _EventTypeOption(this.value, this.label, this.icon);
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

  _SelectableUser copyWith({
    String? id,
    String? name,
    String? phone,
    String? imageUrl,
    bool? selected,
  }) {
    return _SelectableUser(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      imageUrl: imageUrl ?? this.imageUrl,
      selected: selected ?? this.selected,
    );
  }
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
    final filtered = _users.where((user) {
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
                child: filtered.isEmpty
                    ? const Center(child: Text('Keine Personen gefunden.'))
                    : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    final originalIndex =
                    _users.indexWhere((item) => item.id == user.id);

                    return CheckboxListTile(
                      value: user.selected,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      secondary: user.imageUrl.isNotEmpty
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
