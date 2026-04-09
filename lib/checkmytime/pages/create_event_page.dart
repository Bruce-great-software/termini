import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/widgets/checkmytime_ui.dart';

class CreateEventPage extends StatefulWidget {
  final String? eventId;

  const CreateEventPage({super.key, this.eventId});

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
        _selectedDate = (data['eventDate'] as Timestamp?)?.toDate();
        _selectedUsers = loadedUsers;
        _eventType =
            (data['type'] ?? 'open').toString().trim().isEmpty
                ? 'open'
                : (data['type'] ?? 'open').toString().trim();
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
      final invitedUserIds = _selectedUsers.map((u) => u.id).toList();

      if (_isEditMode) {
        final eventId = widget.eventId!;
        final existingDoc =
            await firestore.collection('events').doc(eventId).get();
        final existingData = existingDoc.data() ?? <String, dynamic>{};
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
                .toList();
        final cleanedMaybe =
            maybeUserIds.where(invitedUserIds.contains).toList();
        final cleanedDeclined =
            declinedUserIds.where(invitedUserIds.contains).toList();

        await firestore.collection('events').doc(eventId).update({
          'title': title,
          'description': description,
          'eventDate': Timestamp.fromDate(_selectedDate!),
          'eventDateText': _formattedDate(),
          'invitedUserIds': invitedUserIds,
          'acceptedUserIds': cleanedAccepted,
          'maybeUserIds': cleanedMaybe,
          'declinedUserIds': cleanedDeclined,
          'participantIds': [currentUser.uid],
          'type': _eventType,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final userDoc =
            await firestore.collection('users').doc(currentUser.uid).get();
        final userData = userDoc.data() ?? <String, dynamic>{};
        final creatorName =
            (userData['displayName'] ?? userData['name'] ?? 'Unbekannt')
                .toString()
                .trim();

        await firestore.collection('events').add({
          'title': title,
          'description': description,
          'eventDate': Timestamp.fromDate(_selectedDate!),
          'eventDateText': _formattedDate(),
          'type': 'open',
          'status': 'open',
          'createdBy': currentUser.uid,
          'createdByName': creatorName.isEmpty ? 'Unbekannt' : creatorName,
          'participantIds': [currentUser.uid],
          'invitedUserIds': invitedUserIds,
          'acceptedUserIds': <String>[currentUser.uid],
          'maybeUserIds': <String>[],
          'declinedUserIds': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                            _isEditMode ? 'Bestehendes Event' : 'Neues Event',
                        title:
                            _isEditMode
                                ? 'Dein Event aktualisieren'
                                : 'Offenes Event starten',
                        description:
                            _isEditMode
                                ? 'Hier kannst du Titel, Beschreibung, Datum und eingeladene Personen anpassen.'
                                : 'Fuer den ersten Schritt erstellen wir ein einfaches offenes Event. Spaeter kommen Einladungen, Teilnehmer und Zusagen dazu.',
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
                                : Icons.celebration_outlined,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      CheckMyTimeSectionCard(
                        child: Column(
                          children: [
                            TextField(
                              controller: _titleController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Titel',
                                hintText: 'z. B. Billard spielen',
                                prefixIcon: Icon(Icons.title_rounded),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _descriptionController,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'Beschreibung',
                                hintText: 'z. B. Wer hat am Wochenende Lust?',
                                prefixIcon: Icon(Icons.notes_rounded),
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
                            _buildSelectedUsers(
                              Theme.of(context).colorScheme,
                              theme,
                            ),
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
                                              : Icons.celebration_outlined,
                                        ),
                                label: Text(
                                  _isSubmitting
                                      ? (_isEditMode
                                          ? 'Wird gespeichert...'
                                          : 'Wird erstellt...')
                                      : (_isEditMode
                                          ? 'Aenderungen speichern'
                                          : 'Event erstellen'),
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
