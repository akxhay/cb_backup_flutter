import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the user's known names (in priority order) so the app can identify "me" in chats.
/// The order in the list determines default perspective: earlier matches have higher priority.
/// Also supports per-chat overrides for changing perspective in specific chats.
class SelfIdentityService extends ChangeNotifier {
  static const _myUsernamesKey = 'my_usernames';
  static const _chatSelfKey = 'chat_self_names';

  List<String> _myUsernames = [];
  Map<String, String> _chatSelfNames = {};

  List<String> get myUsernames => List.unmodifiable(_myUsernames);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _myUsernames = prefs.getStringList(_myUsernamesKey) ?? [];
    final jsonStr = prefs.getString(_chatSelfKey) ?? '{}';
    try {
      final decoded = jsonDecode(jsonStr) as Map;
      _chatSelfNames = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      _chatSelfNames = {};
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_myUsernamesKey, _myUsernames);
    await prefs.setString(_chatSelfKey, jsonEncode(_chatSelfNames));
  }

  Future<void> addMyUsername(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    String clean(String str) => str
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '')
        .toLowerCase()
        .trim();
    final cleaned = clean(trimmed);

    if (!_myUsernames.any((a) => clean(a) == cleaned)) {
      _myUsernames.add(trimmed);
      await save();
      notifyListeners();
    }
  }

  Future<void> removeMyUsername(String name) async {
    String clean(String str) => str
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '')
        .toLowerCase()
        .trim();
    final cleaned = clean(name);
    _myUsernames.removeWhere((a) => clean(a) == cleaned);
    await save();
    notifyListeners();
  }

  Future<void> setMyUsernames(List<String> names) async {
    _myUsernames = names.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await save();
    notifyListeners();
  }

  Future<void> setSelfForChat(String chatId, String selfName, {bool addToConfig = true}) async {
    final trimmed = selfName.trim();
    if (trimmed.isEmpty) return;
    if (addToConfig) {
      await addMyUsername(trimmed); // Automatically add chosen name to usernames config
    }
    _chatSelfNames[chatId] = trimmed;
    await save();
    notifyListeners();
  }

  String? getSelfForChat(String chatId) => _chatSelfNames[chatId];

  Future<void> clearSelfForChat(String chatId) async {
    _chatSelfNames.remove(chatId);
    await save();
    notifyListeners();
  }

  /// Returns true if the given sender is "me".
  /// If chatId is provided, prefers the per-chat override.
  bool isSelf(String sender, {String? chatId}) {
    String clean(String str) => str
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '')
        .toLowerCase()
        .trim();

    final s = clean(sender);
    if (chatId != null) {
      final perChat = _chatSelfNames[chatId];
      if (perChat != null && clean(perChat) == s) {
        return true;
      }
    }
    return _myUsernames.any((a) => clean(a) == s);
  }

  /// Resolves the best "me" for this chat using:
  /// 1. Per-chat override (if any)
  /// 2. Best priority match from myUsernames list (earlier = higher priority)
  /// 3. For individual chats, fallback to "the other person" based on chat title (common in WA exports)
  String? resolveSelfForChat(List<String> senders, {String? chatTitle, String? chatId}) {
    if (senders.isEmpty) return null;

    String clean(String str) => str
        .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '')
        .toLowerCase()
        .trim();

    // 1. Per-chat override
    if (chatId != null) {
      final per = _chatSelfNames[chatId];
      if (per != null) {
        final cleanPer = clean(per);
        final found = senders.firstWhere(
          (s) => clean(s) == cleanPer,
          orElse: () => '',
        );
        if (found.isNotEmpty) return found;
      }
    }

    // 2. Priority match from configured my usernames
    String? bestMatch;
    int bestIdx = 999999;
    for (final sender in senders) {
      final cleanSender = clean(sender);
      final idx = _myUsernames.indexWhere((u) => clean(u) == cleanSender);
      if (idx != -1 && idx < bestIdx) {
        bestIdx = idx;
        bestMatch = sender;
      }
    }
    if (bestMatch != null) return bestMatch;

    // 3. 1:1 title-based default (filename usually names the other party)
    if (senders.length == 2 && chatTitle != null && chatTitle.trim().isNotEmpty) {
      final cleanTitle = clean(chatTitle);
      for (final s in senders) {
        if (clean(s) == cleanTitle) {
          return senders.firstWhere((o) => clean(o) != cleanTitle, orElse: () => senders[0]);
        }
      }
    }

    return null;
  }

  /// Suggests a default "me" to pre-select in the chooser dialog (for 1:1 title logic etc.)
  String? suggestDefaultSelf(List<String> senders, {String? chatTitle}) {
    return resolveSelfForChat(senders, chatTitle: chatTitle);
  }
}
