import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:termini/checkmytime/pages/create_event_page.dart';
import 'package:termini/checkmytime/pages/event_detail_page.dart';
import 'package:termini/checkmytime/pages/user_page.dart';
import 'package:termini/checkmytime/services/notification_dispatch_service.dart';

class ContactThreadPage extends StatefulWidget {
  final String contactId;
  final String contactName;
  final String phoneNumber;

  const ContactThreadPage({
    super.key,
    required this.contactId,
    required this.contactName,
    required this.phoneNumber,
  });

  @override
  State<ContactThreadPage> createState() => _ContactThreadPageState();
}

class _ContactThreadPageState extends State<ContactThreadPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final Set<String> _updatingEventIds = <String>{};
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSubscription;
  Timer? _recordingTimer;
  Timer? _typingClearTimer;
  bool _isCurrentlyTyping = false;
  DateTime? _lastTypingPingAt;

  late final TabController _tabController;

  String _resolvedContactName = '';
  String _resolvedPhoneNumber = '';
  String _profileImageUrl = '';

  bool _isSendingMessage = false;
  bool _isUploadingAudio = false;
  bool _isRecordingAudio = false;
  bool _isMarkingIncomingMessagesAsRead = false;

  // Badge state
  bool _hasUnreadChat = false;
  bool _hasUnreadPlan = false;
  StreamSubscription<DocumentSnapshot>? _chatBadgeSubscription;
  StreamSubscription<QuerySnapshot>? _planBadgeSubscription;
  int _lastRenderedMessageCount = -1;
  double _lastKeyboardHeight = 0;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  String? _activeAudioMessageId;
  bool _isActiveAudioPlaying = false;

  String get _threadId {
    final ids = [FirebaseAuth.instance.currentUser?.uid ?? '', widget.contactId]
      ..sort();
    return '${ids[0]}_${ids[1]}';
  }

  @override
  void didChangeMetrics() {
    final keyboardHeight =
        WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
    if (keyboardHeight > _lastKeyboardHeight && _tabController.index == 1) {
      _scheduleScrollToBottom();
    }
    _lastKeyboardHeight = keyboardHeight;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0)
      ..addListener(_handleTabChanged);
    _resolvedContactName = widget.contactName.trim();
    _resolvedPhoneNumber = widget.phoneNumber.trim();
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing;
      if (state.processingState == ProcessingState.completed ||
          (!playing && state.processingState == ProcessingState.idle)) {
        setState(() {
          _activeAudioMessageId = null;
          _isActiveAudioPlaying = false;
        });
        return;
      }
      setState(() {
        _isActiveAudioPlaying = playing;
      });
    });
    _messageController.addListener(_handleTypingChanged);
    _loadContactProfile();
    _markThreadAsRead();
    _markIncomingMessagesAsRead();
    _markIncomingEventsAsRead();
    _startBadgeListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _messageController.removeListener(_handleTypingChanged);
    _typingClearTimer?.cancel();
    unawaited(_setTypingState(false, force: true));
    _messageController.dispose();
    _messagesScrollController.dispose();
    _recordingTimer?.cancel();
    _playerStateSubscription?.cancel();
    _chatBadgeSubscription?.cancel();
    _planBadgeSubscription?.cancel();
    unawaited(_audioRecorder.dispose());
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;

    if (_tabController.index == 1) {
      _markIncomingMessagesAsRead();
      _scheduleScrollToBottom();
      if (_hasUnreadChat) setState(() => _hasUnreadChat = false);
    } else {
      _typingClearTimer?.cancel();
      unawaited(_setTypingState(false, force: true));
      if (_tabController.index == 2) {
        _markIncomingEventsAsRead();
        if (_hasUnreadPlan) setState(() => _hasUnreadPlan = false);
      }
    }
  }

  void _handleTypingChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    _typingClearTimer?.cancel();

    if (!hasText) {
      unawaited(_setTypingState(false));
      return;
    }

    final now = DateTime.now();
    final shouldPing = _lastTypingPingAt == null ||
        now.difference(_lastTypingPingAt!) >= const Duration(seconds: 2);

    if (shouldPing) {
      _lastTypingPingAt = now;
      unawaited(_setTypingState(true));
    }

    _typingClearTimer = Timer(const Duration(seconds: 4), () {
      unawaited(_setTypingState(false));
    });
  }

  Future<void> _setTypingState(bool isTyping, {bool force = false}) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || widget.contactId.isEmpty) return;
    if (!force && _isCurrentlyTyping == isTyping) return;

    _isCurrentlyTyping = isTyping;
    try {
      await FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(_threadId)
          .set({
        'typingBy': isTyping ? currentUserId : '',
        'typingUserId': isTyping ? currentUserId : '',
        'typingAt': FieldValue.serverTimestamp(),
        'typingUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }


  Future<void> _loadContactProfile() async {
    if (widget.contactId.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.contactId)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;

      setState(() {
        final firestoreName =
        (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final firestorePhone = (data['phoneNumber'] ?? '').toString().trim();
        final firestoreImage =
        (data['profileImageUrl'] ?? '').toString().trim();

        if (firestoreName.isNotEmpty) {
          _resolvedContactName = firestoreName;
        }
        if (firestorePhone.isNotEmpty) {
          _resolvedPhoneNumber = firestorePhone;
        }
        _profileImageUrl = firestoreImage;
      });
    } catch (_) {}
  }

  Future<void> _markThreadAsRead() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || widget.contactId.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(_threadId)
          .set({
        'unreadCountFor_$currentUserId': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _markIncomingMessagesAsRead() async {
    if (_isMarkingIncomingMessagesAsRead) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || widget.contactId.isEmpty) return;

    _isMarkingIncomingMessagesAsRead = true;

    try {
      final unreadSnapshot = await FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(_threadId)
          .collection('messages')
          .where('receiverId', isEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      if (unreadSnapshot.docs.isEmpty) {
        await FirebaseFirestore.instance
            .collection('contact_threads')
            .doc(_threadId)
            .set({
          'unreadCountFor_$currentUserId': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      final batch = FirebaseFirestore.instance.batch();

      for (final doc in unreadSnapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      batch.set(
        FirebaseFirestore.instance.collection('contact_threads').doc(_threadId),
        {
          'unreadCountFor_$currentUserId': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (_) {
      // ignore, will retry on next rebuild or tab switch
    } finally {
      _isMarkingIncomingMessagesAsRead = false;
    }
  }

  void _startBadgeListeners() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // Chat-Badge: unreadCountFor_<uid> im Thread-Dokument beobachten
    _chatBadgeSubscription = FirebaseFirestore.instance
        .collection('contact_threads')
        .doc(_threadId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      final count =
          (data?['unreadCountFor_$currentUserId'] as num?)?.toInt() ?? 0;
      final isOnChatTab = _tabController.index == 1;
      final hasUnread = count > 0 && !isOnChatTab;
      if (hasUnread != _hasUnreadChat) {
        setState(() => _hasUnreadChat = hasUnread);
      }
    });

    // Planungen-Badge: Einladungen (isReadByRecipient=false) ODER
    // Reaktionen die der Ersteller noch nicht gesehen hat (seenResponseBy_<uid>=false)
    _planBadgeSubscription = FirebaseFirestore.instance
        .collection('events')
        .where('memberIds', arrayContains: currentUserId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final hasUnread = snap.docs.any((doc) {
        final data = doc.data();
        final memberIds =
        List<String>.from(data['memberIds'] ?? const []);
        final createdBy = (data['createdBy'] ?? '').toString();
        if (!memberIds.contains(widget.contactId)) return false;

        // Einladung noch nicht gelesen (ich bin Empfänger)
        if (createdBy == widget.contactId &&
            data['isReadByRecipient'] != true) {
          return true;
        }

        // Reaktion des Kontakts noch nicht gesehen (ich bin Ersteller)
        if (createdBy == currentUserId &&
            data['seenResponseBy_$currentUserId'] == false) {
          return true;
        }

        return false;
      });
      final isOnPlanTab = _tabController.index == 2;
      final showBadge = hasUnread && !isOnPlanTab;
      if (showBadge != _hasUnreadPlan) {
        setState(() => _hasUnreadPlan = showBadge);
      }
    });
  }

  Future<void> _markIncomingEventsAsRead() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .where('memberIds', arrayContains: currentUserId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      var hasUpdates = false;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final memberIds = List<String>.from(data['memberIds'] ?? const []);
        final createdBy = (data['createdBy'] ?? '').toString();
        final isReadByRecipient = data['isReadByRecipient'] == true;
        final seenResponseKey = 'seenResponseBy_$currentUserId';
        final seenResponse = data[seenResponseKey] != false; // null = gesehen

        if (!memberIds.contains(widget.contactId)) continue;

        final Map<String, dynamic> updates = {
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Einladung als gelesen markieren (ich bin Empfänger)
        if (createdBy == widget.contactId && !isReadByRecipient) {
          updates['isReadByRecipient'] = true;
          hasUpdates = true;
        }

        // Reaktion des Kontakts als gesehen markieren (ich bin Ersteller)
        if (createdBy == currentUserId && !seenResponse) {
          updates[seenResponseKey] = true;
          hasUpdates = true;
        }

        if (updates.length > 1) {
          batch.update(doc.reference, updates);
        }
      }

      if (hasUpdates) {
        await batch.commit();
      }
    } catch (_) {}
  }

  Future<void> _openCreateEventPage(String safeName) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateEventPage(
          initialContactId: widget.contactId,
          initialContactName: safeName,
        ),
      ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_messagesScrollController.hasClients) return;
    final maxExtent = _messagesScrollController.position.maxScrollExtent;
    if (animated) {
      _messagesScrollController.animateTo(
        maxExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _messagesScrollController.jumpTo(maxExtent);
    }
  }

  void _scheduleScrollToBottom({bool animated = true}) {
    // Double-postFrameCallback: first frame triggers layout changes
    // (e.g. TextField shrink after clear), second frame has settled layout
    // with correct maxScrollExtent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(animated: animated);
      });
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime? _eventDateFromData(Map<String, dynamic> data) {
    final ts = data['scheduledAt'] ?? data['eventDate'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  String _normalizeKind(String raw) {
    const valid = {'appointment', 'activity', 'service'};
    final t = raw.trim();
    return valid.contains(t) ? t : 'open';
  }

  String _kindLabel(String? raw) {
    switch (_normalizeKind(raw ?? '')) {
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

  Color _kindColor(ColorScheme colorScheme, String? raw) {
    switch (_normalizeKind(raw ?? '')) {
      case 'appointment':
        return colorScheme.primary;
      case 'activity':
        return Colors.orange;
      case 'service':
        return Colors.teal;
      case 'open':
      default:
        return Colors.purple;
    }
  }

  String _normalizeResponseStatus(String raw) {
    switch (raw.trim()) {
      case 'accepted':
      case 'confirmed':
        return 'accepted';
      case 'declined':
      case 'cancelled':
        return 'declined';
      case 'maybe':
        return 'maybe';
      case 'done':
        return 'done';
      case 'open':
        return 'open';
      case 'pending':
      default:
        return 'pending';
    }
  }

  String _statusLabel(String raw) {
    switch (_normalizeResponseStatus(raw)) {
      case 'accepted':
        return 'Bestätigt';
      case 'declined':
        return 'Abgelehnt';
      case 'maybe':
        return 'Vielleicht';
      case 'done':
        return 'Erledigt';
      case 'open':
        return 'Offen';
      case 'pending':
      default:
        return 'Ausstehend';
    }
  }

  Color _statusColor(ColorScheme colorScheme, String raw) {
    switch (_normalizeResponseStatus(raw)) {
      case 'accepted':
        return Colors.green;
      case 'declined':
        return colorScheme.error;
      case 'maybe':
        return Colors.orange;
      case 'done':
        return Colors.teal;
      case 'open':
        return Colors.purple;
      case 'pending':
      default:
        return colorScheme.primary;
    }
  }

  String _personalStatus(
      Map<String, dynamic> data,
      String currentUserId,
      bool isCreatedByMe,
      ) {
    final responseMap = Map<String, dynamic>.from(
      data['responseMap'] ?? const <String, dynamic>{},
    );
    final responseValue = responseMap[currentUserId]?.toString().trim() ?? '';
    if (!isCreatedByMe && responseValue.isNotEmpty) {
      return _normalizeResponseStatus(responseValue);
    }

    final status = (data['status'] ?? '').toString().trim();
    if (status.isNotEmpty) {
      return _normalizeResponseStatus(status);
    }

    return 'pending';
  }

  String _formatDateHeader(DateTime? date) {
    if (date == null) return 'Kein Datum';
    return DateFormat('EEEE, d. MMMM', 'de_DE').format(date);
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '--:--';
    return DateFormat('HH:mm', 'de_DE').format(date);
  }

  String _formatMessageBubbleTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    return DateFormat('HH:mm', 'de_DE').format(timestamp.toDate());
  }

  String _formatMessageDayChip(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(date.year, date.month, date.day);

    if (target == today) return 'Heute';
    if (target == yesterday) return 'Gestern';
    return DateFormat('EEEE, d. MMMM', 'de_DE').format(date);
  }

  Future<void> _updateEventStatus({
    required String eventId,
    required String newStatus,
    required String title,
  }) async {
    if (_updatingEventIds.contains(eventId)) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    setState(() {
      _updatingEventIds.add(eventId);
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final eventRef = firestore.collection('events').doc(eventId);
      final eventDoc = await eventRef.get();
      final data = eventDoc.data() ?? <String, dynamic>{};
      final batch = firestore.batch();

      final participantIds = <String>{
        ...List<String>.from(data['participantIds'] ?? const []),
      };
      final acceptedUserIds = <String>{
        ...List<String>.from(data['acceptedUserIds'] ?? const []),
      };
      final maybeUserIds = <String>{
        ...List<String>.from(data['maybeUserIds'] ?? const []),
      };
      final declinedUserIds = <String>{
        ...List<String>.from(data['declinedUserIds'] ?? const []),
      };
      final responseMap = Map<String, dynamic>.from(
        data['responseMap'] ?? const <String, dynamic>{},
      );

      responseMap[currentUserId] = newStatus;
      maybeUserIds.remove(currentUserId);
      declinedUserIds.remove(currentUserId);
      acceptedUserIds.remove(currentUserId);
      participantIds.remove(currentUserId);

      if (newStatus == 'accepted') {
        participantIds.add(currentUserId);
        acceptedUserIds.add(currentUserId);
      } else if (newStatus == 'declined') {
        declinedUserIds.add(currentUserId);
      } else if (newStatus == 'maybe') {
        maybeUserIds.add(currentUserId);
      }

      batch.update(eventRef, {
        'responseMap': responseMap,
        'participantIds': participantIds.toList(),
        'acceptedUserIds': acceptedUserIds.toList(),
        'maybeUserIds': maybeUserIds.toList(),
        'declinedUserIds': declinedUserIds.toList(),
        'isReadByRecipient': true,
        // Ersteller soll sehen, dass jemand reagiert hat
        'seenResponseBy_${data['createdBy']}': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(
        firestore.collection('contact_threads').doc(_threadId),
        {
          'lastStatus': newStatus,
          'lastEventTitle': title,
          'lastInteractionType': 'event',
          'lastInteractionAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'unreadCountFor_$currentUserId': 0,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;
      _showMessage(
        newStatus == 'accepted'
            ? 'Planung wurde angenommen.'
            : newStatus == 'maybe'
            ? 'Status auf "Vielleicht" gesetzt.'
            : 'Planung wurde abgelehnt.',
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('Status konnte nicht aktualisiert werden.');
    } finally {
      if (mounted) {
        setState(() {
          _updatingEventIds.remove(eventId);
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startAudioRecording() async {
    if (_isRecordingAudio || _isUploadingAudio || _isSendingMessage) return;

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showMessage('Bitte Mikrofonzugriff für Sprachnachrichten erlauben.');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/cmt_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _recordingTimer?.cancel();
      setState(() {
        _isRecordingAudio = true;
        _recordingPath = path;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecordingAudio) return;
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      });
    } catch (_) {
      _recordingTimer?.cancel();
      if (!mounted) return;
      _showMessage('Sprachnachricht konnte nicht gestartet werden.');
    }
  }

  Future<String?> _stopAudioRecording({bool cancel = false}) async {
    if (!_isRecordingAudio) return null;

    _recordingTimer?.cancel();

    try {
      final path = await _audioRecorder.stop();
      final finalPath = path ?? _recordingPath;

      if (cancel && finalPath != null) {
        final file = File(finalPath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      if (!mounted) return cancel ? null : finalPath;
      setState(() {
        _isRecordingAudio = false;
        if (cancel) {
          _recordingPath = null;
          _recordingDuration = Duration.zero;
        }
      });

      return cancel ? null : finalPath;
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRecordingAudio = false;
          _recordingPath = null;
          _recordingDuration = Duration.zero;
        });
      }
      return null;
    }
  }

  Future<void> _cancelAudioRecording() async {
    await _stopAudioRecording(cancel: true);
  }

  Future<void> _sendRecordedAudio() async {
    if (!_isRecordingAudio || _isUploadingAudio || _isSendingMessage) return;

    final recordedDuration = _recordingDuration;
    final recordedPath = await _stopAudioRecording();
    if (recordedPath == null || recordedPath.isEmpty) {
      if (mounted) {
        _showMessage('Sprachnachricht konnte nicht gespeichert werden.');
      }
      return;
    }

    final file = File(recordedPath);
    if (!await file.exists()) {
      if (mounted) {
        _showMessage('Sprachnachricht konnte nicht gefunden werden.');
      }
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid;
    if (currentUserId == null || widget.contactId.isEmpty) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    if (mounted) FocusScope.of(context).unfocus();

    setState(() {
      _isUploadingAudio = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final storage = FirebaseStorage.instance;
      final participants = [currentUserId, widget.contactId]..sort();

      final currentUserDoc = await firestore.collection('users').doc(currentUserId).get();
      final contactUserDoc = await firestore.collection('users').doc(widget.contactId).get();
      final threadRef = firestore.collection('contact_threads').doc(_threadId);
      final existingThread = await threadRef.get();
      final messageRef = threadRef.collection('messages').doc();

      final storageRef = storage
          .ref()
          .child('checkmytime')
          .child('contact_threads')
          .child(_threadId)
          .child('audio')
          .child('${messageRef.id}.m4a');

      await storageRef.putFile(file, SettableMetadata(contentType: 'audio/mp4'));
      final audioUrl = await storageRef.getDownloadURL();
      final fileSize = await file.length();

      final currentUserData = currentUserDoc.data() ?? <String, dynamic>{};
      final contactUserData = contactUserDoc.data() ?? <String, dynamic>{};

      final currentUserName =
      (currentUserData['displayName'] ?? currentUserData['name'] ?? 'Ich')
          .toString()
          .trim();
      final currentUserPhone =
      (currentUserData['phoneNumber'] ?? '').toString().trim();
      final contactName =
      (contactUserData['displayName'] ?? contactUserData['name'] ?? widget.contactName)
          .toString()
          .trim();
      final contactPhone =
      (contactUserData['phoneNumber'] ?? '').toString().trim();

      final batch = firestore.batch();

      batch.set(messageRef, {
        'threadId': _threadId,
        'type': 'audio',
        'audioUrl': audioUrl,
        'audioDurationMs': recordedDuration.inMilliseconds,
        'fileSize': fileSize,
        'senderId': currentUserId,
        'receiverId': widget.contactId,
        'participants': participants,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final threadData = <String, dynamic>{
        'participants': participants,
        'participantMap': {for (final id in participants) id: true},
        'contactNames': {
          currentUserId: currentUserName.isEmpty ? 'Ich' : currentUserName,
          widget.contactId: contactName.isEmpty ? widget.contactName : contactName,
        },
        'contactPhones': {
          currentUserId: currentUserPhone,
          widget.contactId: contactPhone,
        },
        'lastMessageText': '🎤 Sprachnachricht',
        'lastInteractionType': 'audio',
        'lastInteractionAt': FieldValue.serverTimestamp(),
        'lastCreatedBy': currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
        'hiddenFor_$currentUserId': false,
        'hiddenFor_${widget.contactId}': false,
        'unreadCountFor_$currentUserId': 0,
        'unreadCountFor_${widget.contactId}': FieldValue.increment(1),
      };

      if (!existingThread.exists) {
        threadData['createdAt'] = FieldValue.serverTimestamp();
      }

      batch.set(threadRef, threadData, SetOptions(merge: true));

      await batch.commit();

      try {
        await NotificationDispatchService.instance.queueChatMessageNotification(
          recipientUserId: widget.contactId,
          senderId: currentUserId,
          senderName: currentUserName.isEmpty ? 'Ich' : currentUserName,
          senderPhoneNumber: currentUserPhone,
          messageText: '🎤 Sprachnachricht',
        );
      } catch (_) {}

      _recordingPath = null;
      _recordingDuration = Duration.zero;
      _scheduleScrollToBottom();
    } catch (_) {
      if (mounted) {
        _showMessage('Sprachnachricht konnte nicht gesendet werden.');
      }
    } finally {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isUploadingAudio = false;
          _recordingPath = null;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  Future<void> _toggleAudioPlayback({
    required String messageId,
    required String audioUrl,
  }) async {
    try {
      if (_activeAudioMessageId == messageId && _isActiveAudioPlaying) {
        await _audioPlayer.pause();
        if (!mounted) return;
        setState(() {
          _isActiveAudioPlaying = false;
        });
        return;
      }

      if (_activeAudioMessageId != messageId) {
        await _audioPlayer.stop();
        await _audioPlayer.setUrl(audioUrl);
        if (!mounted) return;
        setState(() {
          _activeAudioMessageId = messageId;
        });
      }

      await _audioPlayer.play();
      if (!mounted) return;
      setState(() {
        _activeAudioMessageId = messageId;
        _isActiveAudioPlaying = true;
      });
    } catch (_) {
      if (!mounted) return;
      _showMessage('Sprachnachricht konnte nicht abgespielt werden.');
    }
  }


  Future<void> _showDeleteMessageSheet({
    required String messageId,
    required bool isMe,
    required bool isDeletedForEveryone,
  }) async {
    if (isDeletedForEveryone) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Für mich löschen'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _deleteMessageForMe(messageId: messageId, userId: currentUserId);
                },
              ),
              if (isMe)
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_rounded,
                    color: colorScheme.error,
                  ),
                  title: Text(
                    'Für alle löschen',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _deleteMessageForEveryone(messageId: messageId);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMessageForMe({
    required String messageId,
    required String userId,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(_threadId)
          .collection('messages')
          .doc(messageId)
          .set({
        'deletedForUserIds': FieldValue.arrayUnion([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      if (!mounted) return;
      _showMessage('Nachricht konnte nicht gelöscht werden.');
    }
  }

  Future<void> _deleteMessageForEveryone({
    required String messageId,
  }) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final messageRef = FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(_threadId)
          .collection('messages')
          .doc(messageId);

      final snapshot = await messageRef.get();
      final data = snapshot.data();
      if (data == null) return;
      final senderId = (data['senderId'] ?? '').toString();
      if (senderId != currentUserId) {
        if (!mounted) return;
        _showMessage('Du kannst nur eigene Nachrichten für alle löschen.');
        return;
      }

      await messageRef.set({
        'type': 'deleted',
        'text': '',
        'audioUrl': '',
        'audioDurationMs': 0,
        'deletedForEveryone': true,
        'deletedBy': currentUserId,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      if (!mounted) return;
      _showMessage('Nachricht konnte nicht für alle gelöscht werden.');
    }
  }

  Future<void> _confirmClearChat() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chat leeren'),
        content: const Text(
          'Alle Nachrichten werden nur für dich aus diesem Chat entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leeren'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _clearChatForMe(userId: currentUserId);
  }

  Future<void> _clearChatForMe({
    required String userId,
  }) async {
    try {
      final messagesRef = FirebaseFirestore.instance
          .collection('contact_threads')
          .doc(_threadId)
          .collection('messages');

      DocumentSnapshot<Map<String, dynamic>>? lastDoc;
      var updatedCount = 0;

      while (true) {
        Query<Map<String, dynamic>> query = messagesRef
            .orderBy('createdAt', descending: false)
            .limit(400);

        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snapshot.docs) {
          batch.set(
            doc.reference,
            {
              'deletedForUserIds': FieldValue.arrayUnion([userId]),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          updatedCount++;
        }

        await batch.commit();
        lastDoc = snapshot.docs.last;

        if (snapshot.docs.length < 400) break;
      }

      if (!mounted) return;
      _showMessage(
        updatedCount == 0
            ? 'Der Chat ist bereits leer.'
            : 'Der Chat wurde für dich geleert.',
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('Der Chat konnte nicht geleert werden.');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSendingMessage || _isUploadingAudio || _isRecordingAudio) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid;
    if (currentUserId == null || widget.contactId.isEmpty) {
      _showMessage('Du bist aktuell nicht eingeloggt.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSendingMessage = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final participants = [currentUserId, widget.contactId]..sort();

      final currentUserDoc =
      await firestore.collection('users').doc(currentUserId).get();
      final contactUserDoc =
      await firestore.collection('users').doc(widget.contactId).get();
      final threadRef = firestore.collection('contact_threads').doc(_threadId);
      final existingThread = await threadRef.get();
      final messageRef = threadRef.collection('messages').doc();

      final currentUserData = currentUserDoc.data() ?? <String, dynamic>{};
      final contactUserData = contactUserDoc.data() ?? <String, dynamic>{};

      final currentUserName =
      (currentUserData['displayName'] ?? currentUserData['name'] ?? 'Ich')
          .toString()
          .trim();
      final currentUserPhone =
      (currentUserData['phoneNumber'] ?? '').toString().trim();
      final contactName =
      (contactUserData['displayName'] ??
          contactUserData['name'] ??
          widget.contactName)
          .toString()
          .trim();
      final contactPhone =
      (contactUserData['phoneNumber'] ?? '').toString().trim();

      final batch = firestore.batch();

      batch.set(messageRef, {
        'threadId': _threadId,
        'text': text,
        'type': 'text',
        'senderId': currentUserId,
        'receiverId': widget.contactId,
        'participants': participants,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final threadData = <String, dynamic>{
        'participants': participants,
        'participantMap': {for (final id in participants) id: true},
        'contactNames': {
          currentUserId: currentUserName.isEmpty ? 'Ich' : currentUserName,
          widget.contactId: contactName.isEmpty ? widget.contactName : contactName,
        },
        'contactPhones': {
          currentUserId: currentUserPhone,
          widget.contactId: contactPhone,
        },
        'lastMessageText': text,
        'lastInteractionType': 'message',
        'lastInteractionAt': FieldValue.serverTimestamp(),
        'lastCreatedBy': currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
        'hiddenFor_$currentUserId': false,
        'hiddenFor_${widget.contactId}': false,
        'unreadCountFor_$currentUserId': 0,
        'unreadCountFor_${widget.contactId}': FieldValue.increment(1),
      };

      if (!existingThread.exists) {
        threadData['createdAt'] = FieldValue.serverTimestamp();
      }

      batch.set(threadRef, threadData, SetOptions(merge: true));

      await batch.commit();

      try {
        await NotificationDispatchService.instance.queueChatMessageNotification(
          recipientUserId: widget.contactId,
          senderId: currentUserId,
          senderName: currentUserName.isEmpty ? 'Ich' : currentUserName,
          senderPhoneNumber: currentUserPhone,
          messageText: text,
        );
      } catch (_) {}

      _messageController.clear();
      _typingClearTimer?.cancel();
      await _setTypingState(false, force: true);
      _scheduleScrollToBottom();
    } catch (_) {
      if (!mounted) return;
      _showMessage('Nachricht konnte nicht gesendet werden.');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  bool _isContactOnline(Map<String, dynamic>? userData) {
    if (userData == null || userData['isOnline'] != true) {
      return false;
    }

    final lastSeen = userData['lastSeenAt'];
    if (lastSeen is! Timestamp) return true;

    return DateTime.now().difference(lastSeen.toDate()) <=
        const Duration(minutes: 3);
  }

  bool _isContactTyping(
      Map<String, dynamic>? threadData,
      String currentUserId,
      ) {
    if (threadData == null || currentUserId.trim().isEmpty) {
      return false;
    }

    final typingTimestamp =
        threadData['typingAt'] as Timestamp? ??
            threadData['typingUpdatedAt'] as Timestamp? ??
            threadData['currentlyTypingAt'] as Timestamp?;

    final isTypingFresh = typingTimestamp != null &&
        DateTime.now().difference(typingTimestamp.toDate()) <=
            const Duration(seconds: 8);

    final typingBy = (threadData['typingBy'] ??
        threadData['typingUserId'] ??
        threadData['typingUid'] ??
        threadData['currentlyTypingUserId'] ??
        '')
        .toString()
        .trim();

    if (typingBy.isNotEmpty) {
      return typingBy == widget.contactId &&
          typingBy != currentUserId &&
          isTypingFresh;
    }

    final typingIds = List<String>.from(
      threadData['typingUserIds'] ??
          threadData['currentlyTypingUserIds'] ??
          const [],
    );

    return typingIds.contains(widget.contactId) &&
        !typingIds.contains(currentUserId) &&
        isTypingFresh;
  }

  String _formatLastSeenLabel(Timestamp? timestamp) {
    if (timestamp == null) return 'Zuletzt online unbekannt';

    final now = DateTime.now();
    final lastSeen = timestamp.toDate();
    final diff = now.difference(lastSeen);

    if (diff.inSeconds < 60) {
      return 'Zuletzt online gerade eben';
    }
    if (diff.inMinutes < 60) {
      return 'Zuletzt online vor ${diff.inMinutes} Min.';
    }
    if (diff.inHours < 24) {
      return 'Zuletzt online vor ${diff.inHours} Std.';
    }

    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (lastDay == yesterday) {
      return 'Zuletzt online gestern um ${DateFormat('HH:mm', 'de_DE').format(lastSeen)}';
    }

    return 'Zuletzt online ${DateFormat('dd.MM. • HH:mm', 'de_DE').format(lastSeen)}';
  }

  String _buildPresenceText({
    required bool isTyping,
    required Map<String, dynamic>? userData,
  }) {
    if (isTyping) return 'Schreibt gerade…';
    if (_isContactOnline(userData)) return 'Online';
    final lastSeen = userData?['lastSeenAt'];
    return _formatLastSeenLabel(lastSeen is Timestamp ? lastSeen : null);
  }

  Widget _buildHeaderAvatar(
      ColorScheme colorScheme,
      String safeName, {
        required bool isOnline,
      }) {
    final avatar = _profileImageUrl.isNotEmpty
        ? CircleAvatar(
      radius: 18,
      backgroundImage: NetworkImage(_profileImageUrl),
    )
        : CircleAvatar(
      radius: 18,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      child: Text(
        safeName.characters.first.toUpperCase(),
        style: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (!isOnline) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF19B35E),
          ),
          child: avatar,
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF19B35E),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactAvatar(ThemeData theme, String safeName) {
    if (_profileImageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(_profileImageUrl),
      );
    }

    return CircleAvatar(
      radius: 22,
      child: Text(
        safeName.characters.first.toUpperCase(),
        style: theme.textTheme.labelLarge,
      ),
    );
  }

  Widget _buildBadge({
    required ThemeData theme,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPlansEmptyState({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
          child: Text(
            'Hier siehst du gemeinsame Events mit $safeName – zum Beispiel Typen wie Termin, Treffen oder Dienstleistung.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 28),
        Icon(
          Icons.event_note_outlined,
          size: 72,
          color: colorScheme.primary.withValues(alpha: 0.70),
        ),
        const SizedBox(height: 18),
        Text(
          'Noch keine gemeinsamen Planungen',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Sobald du mit $safeName etwas planst, erscheint es hier in einem gemeinsamen Verlauf.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
    required String title,
    required String description,
    required String kind,
    required String status,
    required DateTime? scheduledAt,
    required bool isCreatedByMe,
    required bool isUpdating,
    required bool isUnread,
    required VoidCallback? onTap,
    required VoidCallback? onAccept,
    required VoidCallback? onDecline,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isUnread
                ? colorScheme.primaryContainer.withValues(alpha: 0.18)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isUnread
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : colorScheme.outlineVariant,
              width: isUnread ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatDateHeader(scheduledAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.schedule_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatTime(scheduledAt),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isUnread) ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildContactAvatar(theme, safeName),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                safeName,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Text(
                                isCreatedByMe
                                    ? 'Von dir vorgeschlagen'
                                    : 'Von $safeName vorgeschlagen',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildBadge(
                              theme: theme,
                              color: _kindColor(colorScheme, kind),
                              label: _kindLabel(kind),
                            ),
                            const SizedBox(height: 8),
                            _buildBadge(
                              theme: theme,
                              color: _statusColor(colorScheme, status),
                              label: _statusLabel(status),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (!isCreatedByMe &&
                        (status == 'pending' || status == 'open')) ...[
                      const SizedBox(height: 14),
                      if (isUpdating)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: onDecline,
                                child: const Text('Ablehnen'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: onAccept,
                                child: const Text('Annehmen'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlansTab({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
    required String currentUserId,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('memberIds', arrayContains: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Fehler beim Laden der Planungen.',
              style: theme.textTheme.bodyLarge,
            ),
          );
        }

        final docs = [...snapshot.data?.docs ?? []]
            .where((doc) {
              final data = doc.data();
              final memberIds = List<String>.from(data['memberIds'] ?? const []);
              return memberIds.contains(widget.contactId);
            })
            .toList();

        docs.sort((a, b) {
          final aDate = _eventDateFromData(a.data()) ??
              (a.data()['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = _eventDateFromData(b.data()) ??
              (b.data()['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return aDate.compareTo(bDate);
        });

        if (docs.isEmpty) {
          return _buildPlansEmptyState(
            theme: theme,
            colorScheme: colorScheme,
            safeName: safeName,
          );
        }

        final now = DateTime.now();
        final invitations = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final active = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final past = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        for (final doc in docs) {
          final data = doc.data();
          final createdBy = (data['createdBy'] ?? '').toString();
          final status = _personalStatus(data, currentUserId, createdBy == currentUserId);
          final scheduledAt = _eventDateFromData(data);

          if (createdBy != currentUserId &&
              (status == 'pending' || status == 'open')) {
            invitations.add(doc);
            continue;
          }

          if (scheduledAt != null && scheduledAt.isBefore(now)) {
            past.add(doc);
          } else {
            active.add(doc);
          }
        }

        List<Widget> buildSection(
          String sectionTitle,
          List<QueryDocumentSnapshot<Map<String, dynamic>>> sectionDocs,
        ) {
          if (sectionDocs.isEmpty) return const <Widget>[];

          return [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                sectionTitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...sectionDocs.map((doc) {
              final data = doc.data();
              final createdBy = (data['createdBy'] ?? '').toString();
              final eventTitle = (data['title'] ?? 'Event').toString().trim();
              final description =
                  (data['description'] ?? '').toString().trim();
              final kind = (data['kind'] ?? data['type'] ?? 'open').toString();
              final isCreatedByMe = createdBy == currentUserId;
              final status = _personalStatus(data, currentUserId, isCreatedByMe);
              final scheduledAt = _eventDateFromData(data);
              final isUpdating = _updatingEventIds.contains(doc.id);
              final resolvedTitle = eventTitle.isEmpty ? 'Event' : eventTitle;

              final isUnread =
                  (!isCreatedByMe && data['isReadByRecipient'] != true) ||
                      (isCreatedByMe &&
                          data['seenResponseBy_$currentUserId'] == false);

              return _buildPlanCard(
                theme: theme,
                colorScheme: colorScheme,
                safeName: safeName,
                title: resolvedTitle,
                description: description,
                kind: kind,
                status: status,
                scheduledAt: scheduledAt,
                isCreatedByMe: isCreatedByMe,
                isUpdating: isUpdating,
                isUnread: isUnread,
                onTap: () async {
                  if (isUnread) {
                    final updates = <String, dynamic>{
                      'updatedAt': FieldValue.serverTimestamp(),
                    };
                    if (!isCreatedByMe) updates['isReadByRecipient'] = true;
                    if (isCreatedByMe) {
                      updates['seenResponseBy_$currentUserId'] = true;
                    }
                    FirebaseFirestore.instance
                        .collection('events')
                        .doc(doc.id)
                        .update(updates)
                        .catchError((_) {});
                  }
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EventDetailPage(
                        eventId: doc.id,
                        view: isCreatedByMe
                            ? EventDetailView.myEvent
                            : EventDetailView.invitation,
                      ),
                    ),
                  );
                },
                onAccept: (!isCreatedByMe &&
                        (status == 'pending' || status == 'open'))
                    ? () => _updateEventStatus(
                          eventId: doc.id,
                          newStatus: 'accepted',
                          title: resolvedTitle,
                        )
                    : null,
                onDecline: (!isCreatedByMe &&
                        (status == 'pending' || status == 'open'))
                    ? () => _updateEventStatus(
                          eventId: doc.id,
                          newStatus: 'declined',
                          title: resolvedTitle,
                        )
                    : null,
              );
            }),
          ];
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            ...buildSection('Einladungen', invitations),
            if (invitations.isNotEmpty && (active.isNotEmpty || past.isNotEmpty))
              const SizedBox(height: 6),
            ...buildSection('Aktiv & offen', active),
            if (active.isNotEmpty && past.isNotEmpty) const SizedBox(height: 6),
            ...buildSection('Vergangen', past),
          ],
        );
      },
    );
  }

  Widget _buildTabLabel(
      String text, bool hasUnread, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (hasUnread) ...[
          const SizedBox(width: 6),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateChip({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String label,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String messageId,
    required String text,
    required bool isMe,
    required Timestamp? createdAt,
    required bool isRead,
    required bool isDeletedForEveryone,
  }) {
    final bubbleColor =
    isMe ? colorScheme.primary.withValues(alpha: 0.14) : colorScheme.surface;
    final bubbleAlignment =
    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final rowAlignment = isMe ? MainAxisAlignment.end : MainAxisAlignment.start;
    final timeColor = isMe
        ? colorScheme.primary.withValues(alpha: 0.85)
        : colorScheme.onSurfaceVariant;

    return Row(
      mainAxisAlignment: rowAlignment,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: GestureDetector(
            onLongPress: () => _showDeleteMessageSheet(
              messageId: messageId,
              isMe: isMe,
              isDeletedForEveryone: isDeletedForEveryone,
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: Border.all(
                  color: isMe
                      ? colorScheme.primary.withValues(alpha: 0.18)
                      : colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: bubbleAlignment,
                children: [
                  Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.35,
                      fontStyle: isDeletedForEveryone ? FontStyle.italic : null,
                      color: isDeletedForEveryone
                          ? colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatMessageBubbleTime(createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: timeColor,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Icon(
                          isRead ? Icons.done_all : Icons.done,
                          size: 15,
                          color: timeColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioMessageBubble({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String messageId,
    required String audioUrl,
    required Duration audioDuration,
    required bool isMe,
    required Timestamp? createdAt,
    required bool isRead,
    required bool isDeletedForEveryone,
  }) {
    final bubbleColor =
    isMe ? colorScheme.primary.withValues(alpha: 0.14) : colorScheme.surface;
    final bubbleAlignment =
    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final rowAlignment = isMe ? MainAxisAlignment.end : MainAxisAlignment.start;
    final timeColor = isMe
        ? colorScheme.primary.withValues(alpha: 0.85)
        : colorScheme.onSurfaceVariant;
    final isActive = _activeAudioMessageId == messageId;
    final isPlaying = isActive && _isActiveAudioPlaying;

    return Row(
      mainAxisAlignment: rowAlignment,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: GestureDetector(
            onLongPress: () => _showDeleteMessageSheet(
              messageId: messageId,
              isMe: isMe,
              isDeletedForEveryone: isDeletedForEveryone,
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: Border.all(
                  color: isMe
                      ? colorScheme.primary.withValues(alpha: 0.18)
                      : colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: bubbleAlignment,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _toggleAudioPlayback(
                          messageId: messageId,
                          audioUrl: audioUrl,
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sprachnachricht',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDuration(audioDuration),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatMessageBubbleTime(createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: timeColor,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Icon(
                          isRead ? Icons.done_all : Icons.done,
                          size: 15,
                          color: timeColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessagesEmptyState({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(
          Icons.chat_bubble_outline_rounded,
          size: 68,
          color: colorScheme.primary.withValues(alpha: 0.72),
        ),
        const SizedBox(height: 18),
        Text(
          'Noch keine Nachrichten',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Starte den Chat mit $safeName oder plane direkt etwas über das Kalender-Symbol oben rechts.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildMessagesTab({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String safeName,
    required String currentUserId,
  }) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('contact_threads')
                .doc(_threadId)
                .collection('messages')
                .orderBy('createdAt')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Fehler beim Laden der Nachrichten.',
                    style: theme.textTheme.bodyLarge,
                  ),
                );
              }

              final docs = [...snapshot.data?.docs ?? []]
                ..sort((a, b) {
                  final aTs = a.data()['createdAt'] as Timestamp?;
                  final bTs = b.data()['createdAt'] as Timestamp?;
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  return aTs.compareTo(bTs);
                });

              if (_tabController.index == 1) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markIncomingMessagesAsRead();
                });
              }

              if (_lastRenderedMessageCount != docs.length) {
                _lastRenderedMessageCount = docs.length;
                _scheduleScrollToBottom(animated: docs.length > 1);
              }

              if (docs.isEmpty) {
                return _buildMessagesEmptyState(
                  theme: theme,
                  colorScheme: colorScheme,
                  safeName: safeName,
                );
              }

              final children = <Widget>[];
              DateTime? lastDate;

              for (final doc in docs) {
                final data = doc.data();
                final type = (data['type'] ?? 'text').toString().trim();
                final text = (data['text'] ?? '').toString().trim();
                final audioUrl = (data['audioUrl'] ?? '').toString().trim();
                final senderId = (data['senderId'] ?? '').toString();
                final isMe = senderId == currentUserId;
                final createdAt = data['createdAt'] as Timestamp?;
                final isRead = data['isRead'] == true;
                final deletedForEveryone = data['deletedForEveryone'] == true || type == 'deleted';
                final deletedForUserIds = List<String>.from(data['deletedForUserIds'] ?? const []);
                final isDeletedForMe = deletedForUserIds.contains(currentUserId);
                final messageDate =
                    createdAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

                if (isDeletedForMe) continue;

                final hasRenderablePayload = deletedForEveryone ||
                    (type == 'audio' && audioUrl.isNotEmpty) ||
                    (type != 'audio' && text.isNotEmpty);
                if (!hasRenderablePayload) continue;

                if (lastDate == null || !_isSameDay(lastDate, messageDate)) {
                  children.add(
                    _buildDateChip(
                      theme: theme,
                      colorScheme: colorScheme,
                      label: _formatMessageDayChip(messageDate),
                    ),
                  );
                  lastDate = messageDate;
                }

                if (deletedForEveryone) {
                  children.add(
                    _buildMessageBubble(
                      theme: theme,
                      colorScheme: colorScheme,
                      messageId: doc.id,
                      text: 'Diese Nachricht wurde gelöscht.',
                      isMe: isMe,
                      createdAt: createdAt,
                      isRead: isRead,
                      isDeletedForEveryone: true,
                    ),
                  );
                } else if (type == 'audio' && audioUrl.isNotEmpty) {
                  final audioDurationMs = (data['audioDurationMs'] as num?)?.toInt() ?? 0;
                  children.add(
                    _buildAudioMessageBubble(
                      theme: theme,
                      colorScheme: colorScheme,
                      messageId: doc.id,
                      audioUrl: audioUrl,
                      audioDuration: Duration(milliseconds: audioDurationMs),
                      isMe: isMe,
                      createdAt: createdAt,
                      isRead: isRead,
                      isDeletedForEveryone: false,
                    ),
                  );
                } else {
                  children.add(
                    _buildMessageBubble(
                      theme: theme,
                      colorScheme: colorScheme,
                      messageId: doc.id,
                      text: text,
                      isMe: isMe,
                      createdAt: createdAt,
                      isRead: isRead,
                      isDeletedForEveryone: false,
                    ),
                  );
                }
              }

              return ListView(
                controller: _messagesScrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: children,
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: _isRecordingAudio
                ? Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mic_rounded,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aufnahme läuft · ${_formatDuration(_recordingDuration)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _cancelAudioRecording,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: const Icon(Icons.close_rounded),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isUploadingAudio ? null : _sendRecordedAudio,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: _isUploadingAudio
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.send_rounded),
                  ),
                ),
              ],
            )
                : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    enabled: !_isUploadingAudio,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Nachricht schreiben',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _messageController,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    return SizedBox(
                      width: 48,
                      height: 48,
                      child: FilledButton(
                        onPressed: _isUploadingAudio
                            ? null
                            : (hasText ? _sendMessage : _startAudioRecording),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                        ),
                        child: _isSendingMessage || _isUploadingAudio
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : Icon(
                          hasText
                              ? Icons.send_rounded
                              : Icons.mic_rounded,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final rawName = _resolvedContactName.trim().isEmpty
        ? widget.contactName.trim()
        : _resolvedContactName.trim();
    final safeName = rawName.isEmpty ? 'Unbekannt' : rawName;

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final currentUserId = authSnapshot.data?.uid;

        return Scaffold(
          appBar: AppBar(
            leadingWidth: 32,
            titleSpacing: 8,
            title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: widget.contactId.isEmpty
                  ? null
                  : FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.contactId)
                  .snapshots(),
              builder: (context, userSnapshot) {
                final contactUserData = userSnapshot.data?.data();
                final isOnline = _isContactOnline(contactUserData);

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: currentUserId == null
                      ? null
                      : FirebaseFirestore.instance
                      .collection('contact_threads')
                      .doc(_threadId)
                      .snapshots(),
                  builder: (context, threadSnapshot) {
                    final threadData = threadSnapshot.data?.data();
                    final isTyping =
                        _isContactTyping(threadData, currentUserId ?? '');
                    final presenceText = _buildPresenceText(
                      isTyping: isTyping,
                      userData: contactUserData,
                    );

                    return Row(
                      children: [
                        _buildHeaderAvatar(
                          colorScheme,
                          safeName,
                          isOnline: isOnline,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                safeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                presenceText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isTyping
                                      ? colorScheme.primary
                                      : isOnline
                                      ? const Color(0xFF19B35E)
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: (isTyping || isOnline)
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            actions: [
              IconButton(
                tooltip: 'Plan erstellen',
                onPressed: () => _openCreateEventPage(safeName),
                icon: const Icon(Icons.calendar_month_outlined),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'clear_chat') {
                    await _confirmClearChat();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'clear_chat',
                    child: Text('Chat leeren'),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: currentUserId == null
                ? Center(
              child: Text(
                'Du bist aktuell nicht eingeloggt.',
                style: theme.textTheme.bodyLarge,
              ),
            )
                : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      labelColor: colorScheme.primary,
                      unselectedLabelColor: colorScheme.onSurfaceVariant,
                      labelStyle: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      tabs: [
                        const Tab(text: 'Profil'),
                        Tab(
                          child: _buildTabLabel(
                              'Chat', _hasUnreadChat, colorScheme),
                        ),
                        Tab(
                          child: _buildTabLabel(
                              'Planungen', _hasUnreadPlan, colorScheme),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      UserPage(
                        userId: widget.contactId,
                        initialName: safeName,
                        initialImageUrl: _profileImageUrl,
                        embedded: true,
                        hideTopIdentitySection: true,
                        onMessageTap: () => _tabController.animateTo(1),
                      ),
                      _buildMessagesTab(
                        theme: theme,
                        colorScheme: colorScheme,
                        safeName: safeName,
                        currentUserId: currentUserId,
                      ),
                      _buildPlansTab(
                        theme: theme,
                        colorScheme: colorScheme,
                        safeName: safeName,
                        currentUserId: currentUserId,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}