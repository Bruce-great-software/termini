import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:termini/checkmytime/services/google_places_service.dart';
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
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _maxParticipantsController =
  TextEditingController();
  final TextEditingController _approxLocationController =
  TextEditingController();
  final TextEditingController _exactLocationController = TextEditingController();
  final FocusNode _topicFocusNode = FocusNode();
  final FocusNode _exactLocationFocusNode = FocusNode();

  Timer? _exactLocationDebounce;
  List<GooglePlaceSuggestion> _exactLocationSuggestions = const [];
  GooglePlaceDetails? _selectedExactPlace;

  bool _isExactLocationLoading = false;
  bool _hideExactLocationSuggestions = false;
  String _placesSessionToken = _newPlacesSessionToken();

  bool _isSubmitting = false;
  bool _isInitialLoading = false;

  DateTime? _selectedDate;
  TimeOfDay? _selectedStartTime;
  DateTime? _participationDeadline;

  List<_SelectableUser> _selectedUsers = [];

  String _eventType = 'activity';
  String _category = 'sport';
  String _visibility = 'private';
  String _joinMode = 'invite_only';
  bool _hasParticipantLimit = false;
  String _locationType = 'none';
  String _exactLocationVisibility = 'all';
  String _loadedTopicKey = '';
  bool _hideTopicSuggestions = false;

  bool get _isEditMode => widget.isEditMode;

  static const List<_ChoiceOption> _typeOptions = [
    _ChoiceOption('activity', 'Aktivität', Icons.local_activity_outlined),
    _ChoiceOption('appointment', 'Termin', Icons.calendar_month_rounded),
    _ChoiceOption('service', 'Dienstleistung', Icons.content_cut_rounded),
  ];

  static const List<_ChoiceOption> _categoryOptions = [
    _ChoiceOption('sport', 'Sport', Icons.sports_soccer_outlined),
    _ChoiceOption('freizeit', 'Freizeit', Icons.celebration_outlined),
    _ChoiceOption('essen_trinken', 'Essen & Trinken', Icons.restaurant_outlined),
    _ChoiceOption('nachtleben', 'Nachtleben', Icons.nightlife_outlined),
    _ChoiceOption('dienstleistung', 'Dienstleistung', Icons.design_services_outlined),
    _ChoiceOption('lernen_arbeit', 'Lernen & Arbeit', Icons.school_outlined),
  ];

  static const List<_ChoiceOption> _visibilityOptions = [
    _ChoiceOption('private', 'Privat', Icons.lock_outline_rounded),
    _ChoiceOption('friends', 'Freunde', Icons.people_outline_rounded),
    _ChoiceOption('public', 'Öffentlich', Icons.public_rounded),
  ];

  static const List<_ChoiceOption> _joinOptions = [
    _ChoiceOption('invite_only', 'Nur Einladung', Icons.mail_outline_rounded),
    _ChoiceOption('request', 'Anfrage senden', Icons.pending_actions_outlined),
    _ChoiceOption('direct', 'Direkt beitreten', Icons.login_rounded),
  ];

  static const List<_ChoiceOption> _locationTypeOptions = [
    _ChoiceOption('none', 'Kein Ort', Icons.location_disabled_outlined),
    _ChoiceOption('approximate', 'Ungefährer Ort', Icons.place_outlined),
    _ChoiceOption('exact', 'Genauer Ort', Icons.location_on_outlined),
  ];

  static const List<_ChoiceOption> _exactLocationVisibilityOptions = [
    _ChoiceOption('all', 'Für alle sichtbar', Icons.visibility_outlined),
    _ChoiceOption('participants_only', 'Nur für Teilnehmer', Icons.group_outlined),
  ];

  static String _newPlacesSessionToken() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  @override
  void initState() {
    super.initState();
    _topicFocusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _exactLocationFocusNode.addListener(() {
      if (!mounted) return;
      if (!_exactLocationFocusNode.hasFocus) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (!mounted || _exactLocationFocusNode.hasFocus) return;
          setState(() {
            _hideExactLocationSuggestions = true;
          });
        });
      } else {
        setState(() {
          _hideExactLocationSuggestions = false;
        });
      }
    });
    if (_isEditMode) {
      _loadExistingEvent();
    } else {
      _seedInitialSelectedUser();
      _syncDefaultsForType();
      _syncJoinModeForVisibility();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _topicController.dispose();
    _maxParticipantsController.dispose();
    _approxLocationController.dispose();
    _exactLocationController.dispose();
    _topicFocusNode.dispose();
    _exactLocationFocusNode.dispose();
    _exactLocationDebounce?.cancel();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  void _syncDefaultsForType() {
    if (_eventType == 'service') {
      if (_category == 'sport' || _category == 'freizeit') {
        _category = 'dienstleistung';
      }
      if (_visibility == 'public') {
        _visibility = 'friends';
      }
    }

    if (_eventType == 'appointment' && _joinMode == 'direct') {
      _joinMode = 'request';
    }
  }

  void _syncJoinModeForVisibility() {
    if (_visibility == 'private') {
      _joinMode = 'invite_only';
    }
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

      final loadedType =
      (data['kind'] ?? data['type'] ?? 'activity').toString().trim();
      final normalizedType = loadedType == 'open' ? 'activity' : loadedType;
      final loadedCategory = (data['category'] ?? '').toString().trim();
      final loadedVisibility =
      (data['visibility'] ?? 'private').toString().trim().toLowerCase();
      final loadedJoinMode =
      (data['joinMode'] ?? 'invite_only').toString().trim().toLowerCase();
      final loadedTopic = ((data['topic'] ?? data['title']) ?? '').toString();
      final loadedLocationType =
      (data['locationType'] ?? 'none').toString().trim().toLowerCase();
      final loadedApproxLocation =
      (data['approxLocationText'] ?? '').toString().trim();
      final loadedExactLocation =
      (data['exactLocationText'] ?? data['locationText'] ?? '').toString().trim();
      final loadedExactVisibility =
      (data['exactLocationVisibility'] ?? 'all').toString().trim().toLowerCase();
      final loadedExactPlaceId =
      (data['exactLocationPlaceId'] ?? '').toString().trim();
      final loadedExactPlaceName =
      (data['exactLocationName'] ?? loadedExactLocation).toString().trim();
      final loadedExactAddress =
      (data['exactLocationAddress'] ?? '').toString().trim();
      final loadedExactCity =
      (data['exactLocationCity'] ?? '').toString().trim();
      final loadedExactPostalCode =
      (data['exactLocationPostalCode'] ?? '').toString().trim();
      final loadedExactCountry =
      (data['exactLocationCountry'] ?? '').toString().trim();
      final loadedExactStreet =
      (data['exactLocationStreet'] ?? '').toString().trim();
      final loadedExactStreetNumber =
      (data['exactLocationStreetNumber'] ?? '').toString().trim();
      final loadedExactLat = _parseDouble(data['exactLocationLat']);
      final loadedExactLng = _parseDouble(data['exactLocationLng']);
      final hasParticipantLimit = data['hasParticipantLimit'] == true;
      final maxParticipants = (data['maxParticipants'] ?? '').toString().trim();
      final deadlineAt = data['participationDeadlineAt'];

      if (!mounted) return;
      setState(() {
        _titleController.text = (data['title'] ?? '').toString();
        _descriptionController.text = (data['description'] ?? '').toString();
        _topicController.text = loadedTopic;
        _selectedDate = parsedDate;
        _selectedStartTime = parsedDate == null
            ? null
            : TimeOfDay(hour: parsedDate.hour, minute: parsedDate.minute);
        _participationDeadline =
        deadlineAt is Timestamp ? deadlineAt.toDate() : null;
        _selectedUsers = loadedUsers;
        _eventType = normalizedType.isEmpty ? 'activity' : normalizedType;
        _category = loadedCategory.isEmpty ? _defaultCategoryForType(_eventType) : loadedCategory;
        _visibility = _normalizeVisibility(loadedVisibility);
        _joinMode = _normalizeJoinMode(loadedJoinMode);
        _hasParticipantLimit = hasParticipantLimit;
        _maxParticipantsController.text = maxParticipants;
        _locationType = _normalizeLocationType(loadedLocationType);
        _approxLocationController.text = loadedApproxLocation;
        _exactLocationController.text = loadedExactLocation;
        _selectedExactPlace = loadedExactPlaceId.isEmpty &&
            loadedExactPlaceName.isEmpty &&
            loadedExactAddress.isEmpty &&
            loadedExactLat == null &&
            loadedExactLng == null
            ? null
            : GooglePlaceDetails(
          placeId: loadedExactPlaceId,
          name: loadedExactPlaceName,
          formattedAddress: loadedExactAddress,
          latitude: loadedExactLat,
          longitude: loadedExactLng,
          city: loadedExactCity,
          postalCode: loadedExactPostalCode,
          country: loadedExactCountry,
          street: loadedExactStreet,
          streetNumber: loadedExactStreetNumber,
        );
        _exactLocationVisibility =
        loadedExactVisibility == 'participants_only' ? 'participants_only' : 'all';
        _loadedTopicKey = _normalizeTopicKey(loadedTopic);
      });
      _syncDefaultsForType();
      _syncJoinModeForVisibility();
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

  String _normalizeVisibility(String value) {
    if (value == 'public' || value == 'open') return 'public';
    if (value == 'friends') return 'friends';
    return 'private';
  }

  String _normalizeJoinMode(String value) {
    switch (value) {
      case 'request':
      case 'direct':
      case 'invite_only':
        return value;
      default:
        return 'invite_only';
    }
  }

  String _normalizeLocationType(String value) {
    switch (value) {
      case 'approximate':
      case 'exact':
      case 'none':
        return value;
      default:
        return 'none';
    }
  }

  String _defaultCategoryForType(String type) {
    switch (type) {
      case 'service':
        return 'dienstleistung';
      case 'appointment':
        return 'lernen_arbeit';
      case 'activity':
      default:
        return 'sport';
    }
  }

  List<_EventTopicSuggestion> _filteredTopicSuggestions(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final query = _normalizeTopicKey(_topicController.text);
    if (query.isEmpty) return const [];

    final seen = <String>{};
    final suggestions = docs
        .map(_EventTopicSuggestion.fromDoc)
        .where((topic) => topic.isActive)
        .where((topic) {
      if (topic.nameLc.startsWith(query)) return true;
      if (topic.nameLc.contains(query)) return true;
      return topic.defaultTagsLc.any((tag) => tag.contains(query));
    })
        .where((topic) => seen.add(topic.nameLc))
        .toList();

    suggestions.sort((a, b) {
      final aStarts = a.nameLc.startsWith(query) ? 0 : 1;
      final bStarts = b.nameLc.startsWith(query) ? 0 : 1;
      if (aStarts != bStarts) return aStarts.compareTo(bStarts);

      final usageCompare = b.usageCount.compareTo(a.usageCount);
      if (usageCompare != 0) return usageCompare;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    if (suggestions.length > 6) {
      return suggestions.take(6).toList();
    }
    return suggestions;
  }

  void _applyTopicSuggestion(_EventTopicSuggestion suggestion) {
    final text = suggestion.name;
    setState(() {
      _topicController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _titleController.text = text;
      _hideTopicSuggestions = true;
      if (suggestion.defaultType.isNotEmpty) {
        _eventType = suggestion.defaultType;
      }
      if (suggestion.defaultCategory.isNotEmpty) {
        _category = suggestion.defaultCategory;
      }
      _syncDefaultsForType();
      _syncJoinModeForVisibility();
    });
    FocusScope.of(context).unfocus();
  }

  void _clearTopicInput() {
    setState(() {
      _topicController.clear();
      _titleController.clear();
      _hideTopicSuggestions = false;
    });
    _topicFocusNode.requestFocus();
  }

  Widget _buildHighlightedTopicText({
    required String text,
    required String query,
    required TextStyle? style,
    required TextStyle? highlightStyle,
  }) {
    final normalizedText = text.toLowerCase();
    final normalizedQuery = query.toLowerCase();
    final start = normalizedText.indexOf(normalizedQuery);

    if (start < 0 || normalizedQuery.isEmpty) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final end = start + normalizedQuery.length;
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: highlightStyle,
          ),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }

  Widget _buildTopicSuggestions(ThemeData theme) {
    final query = _normalizeTopicKey(_topicController.text);
    if (!_topicFocusNode.hasFocus || query.isEmpty || _hideTopicSuggestions) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('event_topics')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final suggestions = _filteredTopicSuggestions(docs);

        if (suggestions.isEmpty) {
          return const SizedBox.shrink();
        }

        final borderColor = theme.colorScheme.outlineVariant;
        final itemTextStyle = theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
        final highlightStyle = itemTextStyle?.copyWith(
          fontWeight: FontWeight.w800,
        );

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                for (int i = 0; i < suggestions.length; i++) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _applyTopicSuggestion(suggestions[i]),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.subdirectory_arrow_right_rounded,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildHighlightedTopicText(
                                    text: suggestions[i].name,
                                    query: query,
                                    style: itemTextStyle,
                                    highlightStyle: highlightStyle,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_categoryLabel(suggestions[i].defaultCategory)} • ${_typeLabel(suggestions[i].defaultType)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
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
                  if (i != suggestions.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: borderColor,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _normalizeTopicKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _upsertEventTopic({
    required FirebaseFirestore firestore,
    required String topic,
    required String defaultType,
    required String defaultCategory,
    required List<String> defaultTags,
    required String createdBy,
  }) async {
    final normalized = _normalizeTopicKey(topic);
    if (normalized.isEmpty) return;

    final docId = normalized.replaceAll('/', '_');
    final docRef = firestore.collection('event_topics').doc(docId);
    final docSnap = await docRef.get();

    final cleanedTags = defaultTags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();

    if (docSnap.exists) {
      await docRef.update({
        'name': topic.trim(),
        'nameLc': normalized,
        'defaultType': defaultType,
        'defaultCategory': defaultCategory,
        'defaultTags': cleanedTags,
        'usageCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });
      return;
    }

    await docRef.set({
      'name': topic.trim(),
      'nameLc': normalized,
      'defaultType': defaultType,
      'defaultCategory': defaultCategory,
      'defaultTags': cleanedTags,
      'usageCount': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isActive': true,
      'createdBy': createdBy,
    });
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
        final previous = _selectedDate;
        final hour = _selectedStartTime?.hour ?? previous?.hour ?? 18;
        final minute = _selectedStartTime?.minute ?? previous?.minute ?? 0;
        _selectedDate = DateTime(picked.year, picked.month, picked.day, hour, minute);
      });
    }
  }

  Future<void> _pickStartTime() async {
    final initialTime = _selectedStartTime ??
        (_selectedDate == null
            ? const TimeOfDay(hour: 18, minute: 0)
            : TimeOfDay(hour: _selectedDate!.hour, minute: _selectedDate!.minute));

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      setState(() {
        _selectedStartTime = picked;
        if (_selectedDate != null) {
          _selectedDate = DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
            picked.hour,
            picked.minute,
          );
        }
      });
    }
  }

  Future<void> _pickParticipationDeadline() async {
    final now = DateTime.now();
    final initialDate = _participationDeadline ?? _selectedDate ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );

    if (pickedDate == null || !mounted) return;

    final initialTime = _participationDeadline == null
        ? const TimeOfDay(hour: 16, minute: 0)
        : TimeOfDay(
      hour: _participationDeadline!.hour,
      minute: _participationDeadline!.minute,
    );

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime == null) return;

    setState(() {
      _participationDeadline = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formattedDate() {
    if (_selectedDate == null) return 'Datum auswählen';
    return DateFormat('dd.MM.yyyy', 'de_DE').format(_selectedDate!);
  }

  String _formattedStartTime() {
    if (_selectedStartTime == null) return 'Uhrzeit auswählen';
    final hh = _selectedStartTime!.hour.toString().padLeft(2, '0');
    final mm = _selectedStartTime!.minute.toString().padLeft(2, '0');
    return '$hh:$mm Uhr';
  }

  String _formattedParticipationDeadline() {
    if (_participationDeadline == null) return 'Kein Teilnahmeschluss festgelegt';
    return DateFormat('dd.MM.yyyy • HH:mm', 'de_DE')
        .format(_participationDeadline!);
  }

  double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  void _clearExactLocationSelection({bool keepInput = true}) {
    setState(() {
      _selectedExactPlace = null;
      _exactLocationSuggestions = const [];
      _hideExactLocationSuggestions = false;
      _isExactLocationLoading = false;
      _placesSessionToken = _newPlacesSessionToken();
      if (!keepInput) {
        _exactLocationController.clear();
      }
    });
  }

  void _clearExactLocationInput() {
    _exactLocationDebounce?.cancel();
    _clearExactLocationSelection(keepInput: false);
    _exactLocationFocusNode.requestFocus();
  }

  void _onExactLocationChanged(String value) {
    final query = value.trim();
    _exactLocationDebounce?.cancel();

    setState(() {
      _selectedExactPlace = null;
      _hideExactLocationSuggestions = false;
      if (query.length < 2) {
        _exactLocationSuggestions = const [];
        _isExactLocationLoading = false;
        _placesSessionToken = _newPlacesSessionToken();
      } else {
        _isExactLocationLoading = true;
      }
    });

    if (query.length < 2) {
      return;
    }

    final expectedQuery = query;
    final sessionToken = _placesSessionToken;

    _exactLocationDebounce = Timer(const Duration(milliseconds: 350), () async {
      final suggestions = await GooglePlacesService.instance.fetchAutocomplete(
        input: expectedQuery,
        sessionToken: sessionToken,
      );

      if (!mounted) return;
      if (_exactLocationController.text.trim() != expectedQuery) return;

      setState(() {
        _exactLocationSuggestions = suggestions;
        _isExactLocationLoading = false;
      });
    });
  }

  Future<void> _selectExactLocationSuggestion(
      GooglePlaceSuggestion suggestion,
      ) async {
    _exactLocationDebounce?.cancel();

    setState(() {
      _isExactLocationLoading = true;
      _hideExactLocationSuggestions = true;
    });

    final details = await GooglePlacesService.instance.fetchPlaceDetails(
      placeId: suggestion.placeId,
      sessionToken: _placesSessionToken,
    );

    if (!mounted) return;

    if (details == null) {
      setState(() {
        _isExactLocationLoading = false;
        _hideExactLocationSuggestions = false;
      });
      _showMessage('Die Ortsdetails konnten nicht geladen werden.');
      return;
    }

    final displayText = details.displayText.isEmpty
        ? suggestion.mainText
        : details.displayText;

    setState(() {
      _selectedExactPlace = details;
      _exactLocationController.value = TextEditingValue(
        text: displayText,
        selection: TextSelection.collapsed(offset: displayText.length),
      );
      _exactLocationSuggestions = const [];
      _isExactLocationLoading = false;
      _hideExactLocationSuggestions = true;
      _placesSessionToken = _newPlacesSessionToken();
    });

    FocusScope.of(context).unfocus();
  }

  Widget _buildExactLocationSuggestions(ThemeData theme) {
    final query = _exactLocationController.text.trim();
    if (_locationType != 'exact' ||
        !_exactLocationFocusNode.hasFocus ||
        _hideExactLocationSuggestions ||
        query.length < 2) {
      return const SizedBox.shrink();
    }

    if (_isExactLocationLoading && _exactLocationSuggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Suche Orte ...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_exactLocationSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            for (int i = 0; i < _exactLocationSuggestions.length; i++) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _selectExactLocationSuggestion(
                    _exactLocationSuggestions[i],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _exactLocationSuggestions[i].mainText,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_exactLocationSuggestions[i]
                                  .secondaryText
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _exactLocationSuggestions[i].secondaryText,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (i != _exactLocationSuggestions.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedExactLocationSummary(ThemeData theme) {
    final place = _selectedExactPlace;
    if (place == null) {
      return const SizedBox.shrink();
    }

    final coordinateText = place.latitude == null || place.longitude == null
        ? ''
        : '${place.latitude!.toStringAsFixed(6)}, ${place.longitude!.toStringAsFixed(6)}';
    final locationMeta = <String>[
      if (place.streetLine.isNotEmpty) place.streetLine,
      if (place.city.isNotEmpty) place.city,
      if (place.postalCode.isNotEmpty) place.postalCode,
      if (place.country.isNotEmpty) place.country,
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withOpacity(0.40),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ort bestätigt',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        place.displayText.isEmpty
                            ? 'Ort ausgewählt'
                            : place.displayText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (place.formattedAddress.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                place.formattedAddress,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
            if (locationMeta.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: locationMeta
                    .map(
                      (item) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.70),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      item,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                    .toList(),
              ),
            ],
            if (coordinateText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                coordinateText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _hideExactLocationSuggestions = false;
                  });
                  _exactLocationFocusNode.requestFocus();
                },
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Ort ändern'),
              ),
            ),
          ],
        ),
      ),
    );
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

  DateTime? _combinedStartDateTime() {
    if (_selectedDate == null) return null;
    final hour = _selectedStartTime?.hour ?? _selectedDate!.hour;
    final minute = _selectedStartTime?.minute ?? _selectedDate!.minute;
    return DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      hour,
      minute,
    );
  }

  bool _validateBeforeSubmit() {
    final topic = _topicController.text.trim();
    final combined = _combinedStartDateTime();

    if (topic.isEmpty) {
      _showMessage('Bitte gib an, was du planst.');
      return false;
    }

    if (_category.trim().isEmpty) {
      _showMessage('Bitte wähle eine Kategorie aus.');
      return false;
    }

    if (combined == null) {
      _showMessage('Bitte wähle Datum und Uhrzeit aus.');
      return false;
    }

    if (_hasParticipantLimit) {
      final maxParticipants = int.tryParse(_maxParticipantsController.text.trim());
      if (maxParticipants == null || maxParticipants <= 0) {
        _showMessage('Bitte gib eine gültige Teilnehmerzahl ein.');
        return false;
      }
    }

    if (_participationDeadline != null &&
        !_participationDeadline!.isBefore(combined)) {
      _showMessage('Der Teilnahmeschluss muss vor dem Start liegen.');
      return false;
    }

    if (_locationType == 'approximate' && _approxLocationController.text.trim().isEmpty) {
      _showMessage('Bitte gib einen ungefähren Ort an.');
      return false;
    }

    if (_locationType == 'exact' && _exactLocationController.text.trim().isEmpty) {
      _showMessage('Bitte gib einen genauen Ort an.');
      return false;
    }

    if (_visibility == 'private' && _selectedUsers.isEmpty) {
      _showMessage('Bitte füge mindestens eine Person hinzu.');
      return false;
    }

    return true;
  }

  Future<void> _submit() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    if (!_validateBeforeSubmit()) return;

    final topic = _topicController.text.trim();
    final title = topic.isNotEmpty ? topic : _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final startAt = _combinedStartDateTime()!;

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
        responseMap[userId] = _joinMode == 'direct' ? 'accepted' : 'pending';
      }

      final acceptedUserIds = responseMap.entries
          .where((entry) => entry.value == 'accepted')
          .map((entry) => entry.key)
          .toList();

      final maxParticipants = _hasParticipantLimit
          ? int.tryParse(_maxParticipantsController.text.trim())
          : null;
      final exactLocationInput = _exactLocationController.text.trim();
      final approximateLocationInput = _approxLocationController.text.trim();
      final isExactLocation = _locationType == 'exact';
      final isApproximateLocation = _locationType == 'approximate';

      final locationText = isExactLocation
          ? exactLocationInput
          : isApproximateLocation
          ? approximateLocationInput
          : '';

      final basePayload = <String, dynamic>{
        'title': title,
        'description': description,
        'topic': topic,
        'tags': topic
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(),
        'category': _category,
        'eventDate': Timestamp.fromDate(startAt),
        'eventDateText': DateFormat('dd.MM.yyyy', 'de_DE').format(startAt),
        'scheduledAt': Timestamp.fromDate(startAt),
        'type': _eventType,
        'kind': _eventType,
        'status': _defaultStatusForType(),
        'visibility': _visibility,
        'joinMode': _joinMode,
        'invitedUserIds': invitedUserIds,
        'memberIds': memberIds,
        'participantIds': acceptedUserIds,
        'responseMap': responseMap,
        'hasParticipantLimit': _hasParticipantLimit,
        'maxParticipants': maxParticipants,
        'participationDeadlineAt': _participationDeadline == null
            ? null
            : Timestamp.fromDate(_participationDeadline!),
        'locationType': _locationType,
        'approxLocationText': isApproximateLocation ? approximateLocationInput : '',
        'exactLocationText': isExactLocation ? exactLocationInput : '',
        'exactLocationPlaceId': isExactLocation ? _selectedExactPlace?.placeId : null,
        'exactLocationName': isExactLocation ? _selectedExactPlace?.name : null,
        'exactLocationAddress': isExactLocation ? _selectedExactPlace?.formattedAddress : null,
        'exactLocationLat': isExactLocation ? _selectedExactPlace?.latitude : null,
        'exactLocationLng': isExactLocation ? _selectedExactPlace?.longitude : null,
        'exactLocationCity': isExactLocation ? _selectedExactPlace?.city : null,
        'exactLocationPostalCode': isExactLocation ? _selectedExactPlace?.postalCode : null,
        'exactLocationCountry': isExactLocation ? _selectedExactPlace?.country : null,
        'exactLocationStreet': isExactLocation ? _selectedExactPlace?.street : null,
        'exactLocationStreetNumber': isExactLocation ? _selectedExactPlace?.streetNumber : null,
        'locationText': locationText,
        'exactLocationVisibility': isExactLocation ? _exactLocationVisibility : 'all',
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
          (previousResponseMap[userId] ?? responseMap[userId] ?? 'pending')
              .toString()
              .trim();
          mergedResponseMap[userId] =
          existingResponse.isEmpty ? 'pending' : existingResponse;
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
          'participantIds': cleanedAccepted,
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

        final normalizedTopic = _normalizeTopicKey(topic);
        if (normalizedTopic.isNotEmpty && normalizedTopic != _loadedTopicKey) {
          await _upsertEventTopic(
            firestore: firestore,
            topic: topic,
            defaultType: _eventType,
            defaultCategory: _category,
            defaultTags: topic
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList(),
            createdBy: currentUser.uid,
          );
          _loadedTopicKey = normalizedTopic;
        }
      } else {
        final eventRef = firestore.collection('events').doc();

        await eventRef.set({
          ...basePayload,
          'createdBy': currentUser.uid,
          'createdByName': creatorName.isEmpty ? 'Unbekannt' : creatorName,
          'acceptedUserIds': acceptedUserIds,
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

        if (topic.isNotEmpty) {
          await _upsertEventTopic(
            firestore: firestore,
            topic: topic,
            defaultType: _eventType,
            defaultCategory: _category,
            defaultTags: topic
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList(),
            createdBy: currentUser.uid,
          );
          _loadedTopicKey = _normalizeTopicKey(topic);
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
      case 'service':
        return 'Dienstleistung';
      case 'activity':
      default:
        return 'Aktivität';
    }
  }

  String _categoryLabel(String value) {
    switch (value) {
      case 'sport':
        return 'Sport';
      case 'freizeit':
        return 'Freizeit';
      case 'essen_trinken':
        return 'Essen & Trinken';
      case 'nachtleben':
        return 'Nachtleben';
      case 'dienstleistung':
        return 'Dienstleistung';
      case 'lernen_arbeit':
        return 'Lernen & Arbeit';
      default:
        return value;
    }
  }

  String _heroEyebrow() {
    if (_isEditMode) return 'Bestehendes ${_typeLabel(_eventType)}';
    return _typeLabel(_eventType);
  }

  String _heroTitle() {
    if (_isEditMode) return '${_typeLabel(_eventType)} bearbeiten';
    return 'Event erstellen';
  }

  String _heroDescription() {
    switch (_eventType) {
      case 'appointment':
        return 'Plane eine feste Verabredung mit klarer Zeit, Sichtbarkeit und Teilnahme-Regel.';
      case 'service':
        return 'Plane eine private Dienstleistung mit Thema, Ort und passenden Teilnehmer-Regeln.';
      case 'activity':
      default:
        return 'Plane eine Aktivität wie Cage Soccer, Billard oder Kino mit Kategorie, Sichtbarkeit und Teilnehmerlimit.';
    }
  }

  IconData _heroIcon() {
    switch (_eventType) {
      case 'appointment':
        return Icons.calendar_month_rounded;
      case 'service':
        return Icons.content_cut_rounded;
      case 'activity':
      default:
        return Icons.local_activity_outlined;
    }
  }

  String _topicHint() {
    switch (_eventType) {
      case 'appointment':
        return 'z. B. Arzt, Besprechung, Treffen';
      case 'service':
        return 'z. B. Haare schneiden, Nachhilfe';
      case 'activity':
      default:
        return 'z. B. Cage Soccer, Billard, Kino';
    }
  }

  String _titleHint() {
    switch (_eventType) {
      case 'appointment':
        return 'z. B. Termin am Freitag';
      case 'service':
        return 'z. B. Haare schneiden bei Izet';
      case 'activity':
      default:
        return 'z. B. Cage Soccer Samstag 18:00';
    }
  }

  String _descriptionHint() {
    switch (_eventType) {
      case 'appointment':
        return 'z. B. Wir treffen uns direkt vor Ort um 18 Uhr.';
      case 'service':
        return 'z. B. Privat bei mir, dauert ungefähr 30 Minuten.';
      case 'activity':
      default:
        return 'z. B. Wir suchen noch 2 Leute. Hallenschuhe bitte mitbringen.';
    }
  }

  String _defaultStatusForType() {
    switch (_eventType) {
      case 'appointment':
      case 'service':
        return 'pending';
      case 'activity':
      default:
        return 'open';
    }
  }

  String _submitLabel() {
    if (_isSubmitting) {
      return _isEditMode ? 'Wird gespeichert...' : 'Wird erstellt...';
    }
    if (_isEditMode) return 'Änderungen speichern';
    return 'Event erstellen';
  }

  Widget _buildChoiceChips({
    required ThemeData theme,
    required List<_ChoiceOption> options,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((option) {
        final selected = selectedValue == option.value;
        return ChoiceChip(
          selected: selected,
          onSelected: (_) => onSelected(option.value),
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
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildPlanningPromptSection(ThemeData theme) {
    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            theme,
            'Was planst du?',
            'Beschreibe kurz, was du vorhast. Darauf bauen wir später Vorschläge und automatische Kategorien auf.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _topicController,
            focusNode: _topicFocusNode,
            textInputAction: TextInputAction.next,
            onChanged: (value) {
              setState(() {
                _titleController.text = value.trim();
                _hideTopicSuggestions = false;
              });
            },
            decoration: InputDecoration(
              labelText: 'Was planst du?',
              hintText: _topicHint(),
              prefixIcon: const Icon(Icons.auto_awesome_outlined),
              suffixIcon: _topicController.text.trim().isEmpty
                  ? null
                  : IconButton(
                tooltip: 'Eingabe löschen',
                onPressed: _clearTopicInput,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
          _buildTopicSuggestions(theme),
        ],
      ),
    );
  }

  Widget _buildTypePicker(ThemeData theme) {
    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            theme,
            'Art des Events',
            'Lege fest, ob dein Event eine Aktivität, ein Termin oder eine Dienstleistung ist.',
          ),
          const SizedBox(height: 16),
          _buildChoiceChips(
            theme: theme,
            options: _typeOptions,
            selectedValue: _eventType,
            onSelected: (value) {
              setState(() {
                _eventType = value;
                _syncDefaultsForType();
                _syncJoinModeForVisibility();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPicker(ThemeData theme) {
    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            theme,
            'Kategorie',
            'Die Kategorie ist später wichtig für Suche, Filter und Empfehlungen auf Home.',
          ),
          const SizedBox(height: 16),
          _buildChoiceChips(
            theme: theme,
            options: _categoryOptions,
            selectedValue: _category,
            onSelected: (value) => setState(() => _category = value),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicsSection(ThemeData theme) {
    return CheckMyTimeSectionCard(
      child: Column(
        children: [
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
        ],
      ),
    );
  }

  Widget _buildVisibilitySection(ThemeData theme) {
    final description = _visibility == 'private'
        ? 'Nur eingeladene Personen können dieses Event sehen.'
        : _visibility == 'friends'
        ? 'Nur deine Freunde können dieses Event sehen.'
        : 'Jeder kann dieses Event über Feed, Suche oder in der Nähe sehen.';

    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            theme,
            'Sichtbarkeit',
            'Bestimme, wer das Event überhaupt sehen darf.',
          ),
          const SizedBox(height: 16),
          _buildChoiceChips(
            theme: theme,
            options: _visibilityOptions,
            selectedValue: _visibility,
            onSelected: (value) {
              setState(() {
                _visibility = value;
                _syncJoinModeForVisibility();
              });
            },
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinModeSection(ThemeData theme) {
    final options = _visibility == 'private'
        ? _joinOptions.where((option) => option.value == 'invite_only').toList()
        : _joinOptions.where((option) => option.value != 'invite_only' || _selectedUsers.isNotEmpty).toList();

    final helper = _joinMode == 'invite_only'
        ? 'Nur von dir hinzugefügte Personen können teilnehmen.'
        : _joinMode == 'request'
        ? 'Sichtbare Personen schicken eine Anfrage. Du entscheidest.'
        : 'Sichtbare Personen können direkt beitreten, solange Plätze frei sind.';

    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            theme,
            'Teilnahmeart',
            'Lege fest, wie sichtbare Personen in dein Event reinkommen.',
          ),
          const SizedBox(height: 16),
          _buildChoiceChips(
            theme: theme,
            options: options,
            selectedValue: _joinMode,
            onSelected: (value) => setState(() => _joinMode = value),
          ),
          const SizedBox(height: 12),
          Text(
            helper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsSection(ThemeData theme) {
    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            theme,
            'Teilnehmer',
            'Lege fest, ob dein Event unbegrenzt ist oder eine feste Teilnehmerzahl hat.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                selected: !_hasParticipantLimit,
                onSelected: (_) => setState(() => _hasParticipantLimit = false),
                label: const Text('Unbegrenzt'),
                showCheckmark: false,
              ),
              ChoiceChip(
                selected: _hasParticipantLimit,
                onSelected: (_) => setState(() => _hasParticipantLimit = true),
                label: const Text('Begrenzt'),
                showCheckmark: false,
              ),
            ],
          ),
          if (_hasParticipantLimit) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _maxParticipantsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Maximale Teilnehmerzahl',
                hintText: 'z. B. 10',
                prefixIcon: Icon(Icons.group_add_outlined),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeSection(ThemeData theme) {
    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            theme,
            'Zeit',
            'Lege Beginn und optional einen Teilnahmeschluss fest.',
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
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickStartTime,
            borderRadius: BorderRadius.circular(16),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Beginn',
                suffixIcon: Icon(Icons.schedule_outlined),
              ),
              child: Text(_formattedStartTime()),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Teilnahmeschluss',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: _pickParticipationDeadline,
                child: const Text('Festlegen'),
              ),
              if (_participationDeadline != null)
                TextButton(
                  onPressed: () => setState(() => _participationDeadline = null),
                  child: const Text('Entfernen'),
                ),
            ],
          ),
          Text(
            _formattedParticipationDeadline(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(ThemeData theme) {
    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            theme,
            'Ort / Standort',
            'Lege fest, ob kein Ort, ein ungefährer Ort oder ein genauer Ort angezeigt wird.',
          ),
          const SizedBox(height: 16),
          _buildChoiceChips(
            theme: theme,
            options: _locationTypeOptions,
            selectedValue: _locationType,
            onSelected: (value) {
              setState(() {
                _locationType = value;
                if (value != 'exact') {
                  _hideExactLocationSuggestions = true;
                  _exactLocationSuggestions = const [];
                  _isExactLocationLoading = false;
                }
              });
            },
          ),
          if (_locationType == 'approximate') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _approxLocationController,
              decoration: const InputDecoration(
                labelText: 'Ungefährer Ort',
                hintText: 'z. B. Frankfurt Innenstadt',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
          ],
          if (_locationType == 'exact') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _exactLocationController,
              focusNode: _exactLocationFocusNode,
              textInputAction: TextInputAction.done,
              onChanged: _onExactLocationChanged,
              decoration: InputDecoration(
                labelText: 'Genauer Ort',
                hintText: 'z. B. Cage Soccer Arena Duisburg',
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: _isExactLocationLoading
                    ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : _exactLocationController.text.trim().isEmpty
                    ? null
                    : IconButton(
                  tooltip: 'Ort löschen',
                  onPressed: _clearExactLocationInput,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
            _buildExactLocationSuggestions(theme),
            _buildSelectedExactLocationSummary(theme),
            const SizedBox(height: 16),
            _buildChoiceChips(
              theme: theme,
              options: _exactLocationVisibilityOptions,
              selectedValue: _exactLocationVisibility,
              onSelected: (value) =>
                  setState(() => _exactLocationVisibility = value),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedUsers(ColorScheme colorScheme, ThemeData theme) {
    if (_selectedUsers.isEmpty) {
      return CheckMyTimeSectionCard(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Noch keine Personen hinzugefügt.',
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

  Widget _buildPeopleSection(ThemeData theme) {
    return CheckMyTimeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Personen hinzufügen',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _openUserPicker,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Auswählen'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _visibility == 'private'
                ? 'Bei privaten Events sind Einladungen besonders wichtig.'
                : 'Du kannst auch bei offenen oder Freunde-Events direkt Personen hinzufügen.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _buildSelectedUsers(theme.colorScheme, theme),
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
              _buildPlanningPromptSection(theme),
              const SizedBox(height: 16),
              _buildTypePicker(theme),
              const SizedBox(height: 16),
              _buildCategoryPicker(theme),
              const SizedBox(height: 16),
              _buildBasicsSection(theme),
              const SizedBox(height: 16),
              _buildVisibilitySection(theme),
              const SizedBox(height: 16),
              _buildJoinModeSection(theme),
              const SizedBox(height: 16),
              _buildParticipantsSection(theme),
              const SizedBox(height: 16),
              _buildTimeSection(theme),
              const SizedBox(height: 16),
              _buildLocationSection(theme),
              const SizedBox(height: 16),
              _buildPeopleSection(theme),
            ],
          ),
        ),
      ),
    );
  }
}


class _EventTopicSuggestion {
  final String name;
  final String nameLc;
  final String defaultType;
  final String defaultCategory;
  final List<String> defaultTags;
  final List<String> defaultTagsLc;
  final int usageCount;
  final bool isActive;

  const _EventTopicSuggestion({
    required this.name,
    required this.nameLc,
    required this.defaultType,
    required this.defaultCategory,
    required this.defaultTags,
    required this.defaultTagsLc,
    required this.usageCount,
    required this.isActive,
  });

  factory _EventTopicSuggestion.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();
    final name = (data['name'] ?? '').toString().trim();
    final nameLc = (data['nameLc'] ?? name).toString().trim().toLowerCase();
    final defaultType = (data['defaultType'] ?? 'activity').toString().trim();
    final defaultCategory =
    (data['defaultCategory'] ?? 'sport').toString().trim();
    final defaultTags = List<String>.from(data['defaultTags'] ?? const <String>[]);
    final cleanedTags = defaultTags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();

    return _EventTopicSuggestion(
      name: name.isEmpty ? doc.id : name,
      nameLc: nameLc,
      defaultType: defaultType,
      defaultCategory: defaultCategory,
      defaultTags: cleanedTags,
      defaultTagsLc: cleanedTags.map((tag) => tag.toLowerCase()).toList(),
      usageCount: (data['usageCount'] ?? 0) is int
          ? (data['usageCount'] ?? 0) as int
          : int.tryParse((data['usageCount'] ?? '0').toString()) ?? 0,
      isActive: data['isActive'] != false,
    );
  }
}

class _ChoiceOption {
  final String value;
  final String label;
  final IconData icon;

  const _ChoiceOption(this.value, this.label, this.icon);
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
                'Personen auswählen',
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
                  child: const Text('Übernehmen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
