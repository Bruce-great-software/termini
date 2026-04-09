import 'package:shared_preferences/shared_preferences.dart';

class UnreadCountRepository {
  UnreadCountRepository._();

  static final UnreadCountRepository instance = UnreadCountRepository._();

  static const String _countKey = 'notification_unread_count';
  static const String _sequenceKey = 'notification_id_sequence';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    final existing = _prefs;
    if (existing != null) return existing;
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    return prefs;
  }

  Future<int> getUnreadCount() async {
    final prefs = await _ensurePrefs();
    return prefs.getInt(_countKey) ?? 0;
  }

  Future<int> setUnreadCount(int count) async {
    final prefs = await _ensurePrefs();
    final sanitized = count < 0 ? 0 : count;
    await prefs.setInt(_countKey, sanitized);
    return sanitized;
  }

  Future<int> incrementUnreadCount([int by = 1]) async {
    final current = await getUnreadCount();
    return setUnreadCount(current + (by < 1 ? 1 : by));
  }

  Future<int> decrementUnreadCount([int by = 1]) async {
    final current = await getUnreadCount();
    return setUnreadCount(current - (by < 1 ? 1 : by));
  }

  Future<int> nextNotificationSequence() async {
    final prefs = await _ensurePrefs();
    final current = prefs.getInt(_sequenceKey) ?? 0;
    final next = current >= 2147483646 ? 1 : current + 1;
    await prefs.setInt(_sequenceKey, next);
    return next;
  }
}
