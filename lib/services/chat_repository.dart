import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat.dart';
import 'chat_parser.dart';

/// Repository responsible for importing WhatsApp zips, extracting, parsing, and persisting chats.
class ChatRepository extends ChangeNotifier {
  static const _chatsMetaFile = 'chats.json';

  final List<Chat> _chats = [];
  Directory? _baseDir;

  List<Chat> get chats => List.unmodifiable(_chats);

  Future<Directory> _getBaseDir() async {
    if (_baseDir != null) return _baseDir!;
    final docs = await getApplicationDocumentsDirectory();
    var dir = Directory(p.join(docs.path, 'cbbackup', 'chats'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    dir = Directory(dir.resolveSymbolicLinksSync());
    _baseDir = dir;
    return dir;
  }

  Future<File> _getMetaFile() async {
    final base = await _getBaseDir();
    return File(p.join(base.path, _chatsMetaFile));
  }

  Future<void> load() async {
    _chats.clear();
    final metaFile = await _getMetaFile();
    if (await metaFile.exists()) {
      try {
        final content = await metaFile.readAsString();
        final list = (jsonDecode(content) as List).cast<Map<String, dynamic>>();
        final base = await _getBaseDir();
        final healed = list.map(Chat.fromJson).map((c) {
          final dirName = p.basename(c.extractedDir);
          final updatedDir = p.join(base.path, dirName);
          return Chat(
            id: c.id,
            title: c.title,
            isGroup: c.isGroup,
            participants: c.participants,
            importDate: c.importDate,
            extractedDir: updatedDir,
            messageCount: c.messageCount,
            lastMessagePreview: c.lastMessagePreview,
          );
        });
        _chats.addAll(healed);
      } catch (e) {
        // ignore corrupt meta for MVP
        debugPrint('Failed to load chats meta: $e');
        // Try to delete corrupt file so next import can start fresh
        try { await metaFile.delete(); } catch (_) {}
      }
    }

    // Migrate chats from legacy native Android app if they exist
    await _migrateFromAndroidLegacy();

    notifyListeners();
  }

  Future<void> _persist() async {
    final metaFile = await _getMetaFile();
    final jsonStr = jsonEncode(_chats.map((c) => c.toJson()).toList());
    await _writeFileAtomically(metaFile, jsonStr);
  }

  Future<void> _writeFileAtomically(File file, String content) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(content, flush: true);
    await temp.rename(file.path);
  }

  /// Picks a zip via platform picker and imports it.
  /// Returns the created Chat or null if cancelled/error.
  Future<Chat?> importFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) return null;
    return importZip(File(path));
  }


  /// Core import: extract, parse, detect self, save metadata + messages.json, persist list.
  ///
  /// The chat title (display name) is parsed from the zip filename using
  /// `parseChatTitleFromZipFilename` (supports both " - " and " with " formats).
  /// If the filename is not in the correct format an error is thrown.
  Future<Chat?> importZip(File zipFile, {String? forceTitle}) async {
    final base = await _getBaseDir();

    // Determine title early from zip name (or override). This enforces the expected format.
    String chatTitle = forceTitle ?? parseChatTitleFromZipFilename(zipFile.path);
    if (chatTitle.length > 60) chatTitle = chatTitle.substring(0, 57) + '...';

    final ts = DateTime.now().millisecondsSinceEpoch;
    final slug = p.basenameWithoutExtension(zipFile.path).replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final chatDir = Directory(p.join(base.path, '${slug}_$ts'));
    await chatDir.create(recursive: true);

    // Extract
    await extractFileToDisk(zipFile.path, chatDir.path);

    // Locate the chat log .txt file.
    // - iOS usually: _chat.txt
    // - Android often: chat.txt or a file named after the chat (e.g. "WhatsApp Chat with XXX.txt")
    // We prefer known names, otherwise pick the largest .txt file (the chat log is typically the biggest).
    String? chatTxtPath;
    final txtCandidates = <File>[];

    await for (final entity in chatDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final base = p.basename(entity.path).toLowerCase();
        if (base.endsWith('.txt')) {
          txtCandidates.add(entity);
        }
      }
    }

    // Prefer standard names
    for (final f in txtCandidates) {
      final base = p.basename(f.path).toLowerCase();
      if (base == '_chat.txt' || base == 'chat.txt') {
        chatTxtPath = f.path;
        break;
      }
    }

    if (chatTxtPath == null && txtCandidates.isNotEmpty) {
      // Pick the .txt that looks like a real WhatsApp chat log.
      // iOS bracket format: [dd/mm/yy, ...]
      // Android dash format: dd/mm/yy, time - sender: ...
      for (final f in txtCandidates) {
        try {
          // Read only the beginning to detect
          final preview = await f.openRead(0, 4096).transform(utf8.decoder).join();
          if (RegExp(r'\[?\d{1,2}/\d{1,2}/\d{2},?\s').hasMatch(preview)) {
            chatTxtPath = f.path;
            break;
          }
        } catch (_) {}
      }
    }

    // Last fallback: largest .txt
    if (chatTxtPath == null && txtCandidates.isNotEmpty) {
      txtCandidates.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
      chatTxtPath = txtCandidates.first.path;
    }

    if (chatTxtPath == null) {
      // cleanup
      await chatDir.delete(recursive: true);
      throw Exception('No chat log (.txt) file found in the zip.');
    }

    final raw = await File(chatTxtPath).readAsString();
    final messages = parseChat(raw);

    if (messages.isEmpty) {
      await chatDir.delete(recursive: true);
      throw Exception('No messages parsed from chat.');
    }

    // Derive metadata
    final senders = extractSenders(messages).toList();
    final isGroup = isLikelyGroupChat(messages);
    final preview = buildPreview(messages);

    final chat = Chat(
      id: 'chat_$ts',
      title: chatTitle,
      isGroup: isGroup,
      participants: senders,
      importDate: DateTime.now(),
      extractedDir: chatDir.path,
      messageCount: messages.length,
      lastMessagePreview: preview,
    );

    // Persist full messages alongside
    final messagesFile = File(p.join(chatDir.path, 'messages.json'));
    await _writeFileAtomically(messagesFile, jsonEncode(messages.map((m) => m.toJson()).toList()));

    _chats.insert(0, chat);
    await _persist();
    notifyListeners();

    return chat;
  }

  /// Merge messages from a new zip into an existing chat (sorted by date, deduplicated).
  /// Copies any new media files into the target chat's directory.
  Future<void> mergeIntoChat(Chat target, File zipFile) async {
    final tempDir = await getTemporaryDirectory();
    var temp = await tempDir.createTemp('cbbackup_merge_');
    temp = Directory(temp.resolveSymbolicLinksSync());
    
    final base = await _getBaseDir();
    final resolvedTargetDir = p.join(base.path, p.basename(target.extractedDir));
    try {
      // Extract new zip to temp
      await extractFileToDisk(zipFile.path, temp.path);

      // Find chat log .txt in temp (Android may use different filename)
      String? txtPath;
      final txtCandidates = <File>[];

      await for (final entity in temp.list(recursive: true, followLinks: false)) {
        if (entity is File && p.basename(entity.path).toLowerCase().endsWith('.txt')) {
          txtCandidates.add(entity);
        }
      }

      // Prefer standard names
      for (final f in txtCandidates) {
        final base = p.basename(f.path).toLowerCase();
        if (base == '_chat.txt' || base == 'chat.txt') {
          txtPath = f.path;
          break;
        }
      }

      if (txtPath == null && txtCandidates.isNotEmpty) {
        // Pick the one that contains chat timestamp lines
        for (final f in txtCandidates) {
          try {
            final preview = await f.openRead(0, 4096).transform(utf8.decoder).join();
            if (RegExp(r'\[\d{1,2}/\d{1,2}/\d{2}').hasMatch(preview)) {
              txtPath = f.path;
              break;
            }
          } catch (_) {}
        }
      }

      // Last fallback: largest
      if (txtPath == null && txtCandidates.isNotEmpty) {
        txtCandidates.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
        txtPath = txtCandidates.first.path;
      }

      if (txtPath == null) {
        throw Exception('No chat log (.txt) file found in the zip for merge.');
      }

      final raw = await File(txtPath).readAsString();
      final newMessages = parseChat(raw);
      if (newMessages.isEmpty) return;

      final existingMessages = await loadMessages(target);

      // Combine, sort by date, deduplicate
      var combined = [...existingMessages, ...newMessages];
      combined.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final seen = <String>{};
      final merged = <ChatMessage>[];
      for (final m in combined) {
        final key = '${m.timestamp.toIso8601String()}|${m.sender}|${m.text}|${m.mediaPath ?? ''}';
        if (seen.add(key)) {
          merged.add(m);
        }
      }

      // Copy media files from temp to target (preserve structure)
      await for (final entity in temp.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final base = p.basename(entity.path);
          if (base.toLowerCase().endsWith('.txt')) continue;
          final rel = p.relative(entity.path, from: temp.path);
          final destPath = p.join(resolvedTargetDir, rel);
          final destFile = File(destPath);
          await destFile.parent.create(recursive: true);
          await entity.copy(destPath);
        }
      }

      // Overwrite messages.json with merged
      final msgFile = File(p.join(resolvedTargetDir, 'messages.json'));
      await _writeFileAtomically(msgFile, jsonEncode(merged.map((m) => m.toJson()).toList()));

      // Update the in-memory chat metadata
      final idx = _chats.indexWhere((c) => c.id == target.id);
      if (idx != -1) {
        final old = _chats[idx];
        final senders = merged.map((m) => m.sender).toSet().toList();
        senders.remove('System');

        final updated = Chat(
          id: old.id,
          title: old.title,
          isGroup: old.isGroup,
          participants: senders,
          importDate: DateTime.now(),
          extractedDir: resolvedTargetDir,
          messageCount: merged.length,
          lastMessagePreview: buildPreview(merged),
        );
        _chats[idx] = updated;
      }

      await _persist();
      notifyListeners();
    } finally {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  }

  Future<List<ChatMessage>> loadMessages(Chat chat) async {
    final messagesFile = File(p.join(chat.extractedDir, 'messages.json'));
    if (!await messagesFile.exists()) {
      // fallback: reparse the chat log txt (may be named differently on Android)
      final txtPath = _findChatLogFile(chat.extractedDir);
      if (txtPath != null) {
        final raw = await File(txtPath).readAsString();
        final msgs = parseChat(raw);
        // Re-save as json for faster future loads and robustness after rebuilds
        try {
          await _writeFileAtomically(messagesFile, jsonEncode(msgs.map((m) => m.toJson()).toList()));
        } catch (_) {}
        return msgs;
      }
      return [];
    }
    try {
      final content = await messagesFile.readAsString();
      final data = jsonDecode(content) as List;
      final List<ChatMessage> msgs = [];
      bool dirty = false;

      for (final j in data) {
        final msg = ChatMessage.fromJson((j as Map).cast<String, dynamic>());
        // Self-healing / sanitation logic for old invalid document classifications (e.g. "Bta...?")
        if (msg.type == MessageType.document && msg.mediaPath != null) {
          final ext = msg.mediaPath!.split('.').last;
          final hasValidExt = ext.length >= 2 &&
              ext.length <= 5 &&
              RegExp(r'^[a-zA-Z0-9]+$').hasMatch(ext);
          if (!hasValidExt) {
            msgs.add(ChatMessage(
              timestamp: msg.timestamp,
              sender: msg.sender,
              text: msg.mediaPath!, // restore the filename as the message text!
              type: MessageType.text,
              mediaPath: null,
              isEdited: msg.isEdited,
            ));
            dirty = true;
            continue;
          }
        }
        msgs.add(msg);
      }

      if (dirty) {
        // Re-save healed messages to disk
        try {
          await _writeFileAtomically(messagesFile, jsonEncode(msgs.map((m) => m.toJson()).toList()));
        } catch (_) {}

        // Replace the Chat object in memory and persist it to correct the home screen preview
        final chatIdx = _chats.indexWhere((c) => c.id == chat.id);
        if (chatIdx != -1) {
          final oldChat = _chats[chatIdx];
          String? newPreview;
          if (msgs.isNotEmpty) {
            final last = msgs.last;
            newPreview = last.type == MessageType.text ? last.text : '[${last.type.name}]';
          }
          _chats[chatIdx] = Chat(
            id: oldChat.id,
            title: oldChat.title,
            isGroup: oldChat.isGroup,
            participants: oldChat.participants,
            importDate: oldChat.importDate,
            extractedDir: oldChat.extractedDir,
            messageCount: msgs.length,
            lastMessagePreview: newPreview,
          );
          await _persist();
          notifyListeners();
        }
      }

      return msgs;
    } catch (_) {
      // If json corrupt, fallback to txt
      final txtPath = _findChatLogFile(chat.extractedDir);
      if (txtPath != null) {
        final raw = await File(txtPath).readAsString();
        final msgs = parseChat(raw);
        try {
          await _writeFileAtomically(messagesFile, jsonEncode(msgs.map((m) => m.toJson()).toList()));
        } catch (_) {}
        return msgs;
      }
      return [];
    }
  }

  String? _findChatLogFile(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;

    // Prefer _chat.txt if present
    final standard = File(p.join(dirPath, '_chat.txt'));
    if (standard.existsSync()) return standard.path;

    // Find .txt files (Android may use different names like "chat.txt" or "WhatsApp Chat with XXX.txt")
    final txtFiles = <File>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && p.basename(entity.path).toLowerCase().endsWith('.txt')) {
        txtFiles.add(entity);
      }
    }

    if (txtFiles.isEmpty) return null;

    // Prefer one that contains actual chat timestamps (iOS bracket or Android dash format)
    for (final f in txtFiles) {
      try {
        final preview = f.readAsStringSync().substring(0, (4096).clamp(0, f.lengthSync()));
        if (RegExp(r'\[?\d{1,2}/\d{1,2}/\d{2},?\s').hasMatch(preview)) {
          return f.path;
        }
      } catch (_) {}
    }

    // Fallback to largest
    txtFiles.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
    return txtFiles.first.path;
  }

  // In-memory cache for resolved media paths to prevent expensive synchronous filesystem checks on every build frame.
  final Map<String, String> _mediaPathCache = {};

  // Lazily built maps of: chat.id -> (basename -> absolutePath) to avoid redundant directory scanning.
  final Map<String, Map<String, String>> _chatFileIndex = {};

  Future<void> deleteChat(Chat chat) async {
    _chats.removeWhere((c) => c.id == chat.id);
    _mediaPathCache.removeWhere((key, value) => key.startsWith('${chat.id}_'));
    _chatFileIndex.remove(chat.id);
    await _persist();
    notifyListeners();

    final dir = Directory(chat.extractedDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  void _buildFileIndex(Chat chat) {
    if (_chatFileIndex.containsKey(chat.id)) return;

    final index = <String, String>{};
    final dir = Directory(chat.extractedDir);
    if (dir.existsSync()) {
      try {
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is File) {
            final base = p.basename(entity.path).toLowerCase();
            index[base] = entity.path;
          }
        }
      } catch (_) {}
    }
    _chatFileIndex[chat.id] = index;
  }

  /// Returns full absolute path for a media file belonging to a chat.
  /// Tries direct path first, then searches recursively by basename (for cross-platform
  /// zip differences where media might be in subfolders or referenced differently).
  String resolveMediaPath(Chat chat, String relativeMedia) {
    final cacheKey = '${chat.id}_$relativeMedia';
    final cached = _mediaPathCache[cacheKey];
    if (cached != null) return cached;

    // 1. Try direct path first (extremely fast)
    final direct = p.join(chat.extractedDir, relativeMedia);
    if (File(direct).existsSync()) {
      _mediaPathCache[cacheKey] = direct;
      return direct;
    }

    // 2. Build index lazily if recursive search is needed
    _buildFileIndex(chat);

    // 3. Look up in the indexed filenames map
    final base = p.basename(relativeMedia).toLowerCase();
    final indexedPath = _chatFileIndex[chat.id]?[base];
    if (indexedPath != null) {
      _mediaPathCache[cacheKey] = indexedPath;
      return indexedPath;
    }

    _mediaPathCache[cacheKey] = direct;
    return direct; // return original attempt so caller can show error
  }

  Future<void> _migrateFromAndroidLegacy() async {
    // Only migrate on Android
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('android_migration_completed') ?? false) {
          return; // Already migrated!
        }

        // Get default databases path
        final dbFolder = await getDatabasesPath();
        final dbFile = File(p.join(dbFolder, 'SQLiteDatabase.db'));
        if (!await dbFile.exists()) {
          return; // Legacy database doesn't exist
        }

        final db = await openDatabase(dbFile.path, readOnly: true);

        // Fetch all contacts from SAVED_CONTACTS
        final contacts = await db.rawQuery('SELECT * FROM SAVED_CONTACTS');
        if (contacts.isEmpty) {
          await db.close();
          return;
        }

        final baseDir = await _getBaseDir();

        for (final contact in contacts) {
          final String chatName = (contact['CHAT_NAME'] as String? ?? '').trim();
          if (chatName.isEmpty) continue;

          // Check if this chat is already present in _chats
          if (_chats.any((c) => c.title.toLowerCase().trim() == chatName.toLowerCase().trim())) {
            continue;
          }

          final String groupFlag = contact['GROUP_FLAG'] as String? ?? 'N';
          final bool isGroup = groupFlag == 'Y';

          // Fetch all message records for this contact
          final messagesRows = await db.rawQuery(
            'SELECT * FROM CHAT_RECORD WHERE CHAT_NAME = ? ORDER BY ID ASC',
            [chatName],
          );

          if (messagesRows.isEmpty) continue;

          final List<ChatMessage> messages = [];
          final String chatSlug = chatName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
          final int ts = DateTime.now().millisecondsSinceEpoch;
          final chatDir = Directory(p.join(baseDir.path, 'migrated_${chatSlug}_$ts'));
          await chatDir.create(recursive: true);

          for (final row in messagesRows) {
            final String whatsappName = (row['WHATSAPP_NAME'] as String? ?? '').trim();
            final String chatText = row['CHAT_TEXT'] as String? ?? '';
            final String timeStr = row['TIME'] as String? ?? '';
            final String typeStr = (row['TYPE'] as String? ?? 'text').trim().toLowerCase();
            final String absolutePath = row['PATH'] as String? ?? '';
            final String filename = row['FILENAME'] as String? ?? '';

            final bool isSystem = whatsappName == '##420##';
            final String sender = isSystem ? 'System' : whatsappName;

            MessageType type = MessageType.text;
            if (isSystem) {
              type = MessageType.system;
            } else {
              switch (typeStr) {
                case 'image':
                  type = MessageType.image;
                  break;
                case 'video':
                  type = MessageType.video;
                  break;
                case 'audio':
                  type = MessageType.audio;
                  break;
                case 'document':
                  type = MessageType.document;
                  break;
                case 'system':
                  type = MessageType.system;
                  break;
                default:
                  type = MessageType.text;
              }
            }

            // Parse timestamp string
            DateTime timestamp = DateTime.now();
            if (timeStr.isNotEmpty) {
              try {
                // Legacy date formats: "dd/MM/yyyy HH:mm:ss", "dd/MM/yy, h:mm aaa", etc.
                final match = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})(?:,\s*|\s+)(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([a-zA-Z]{2}))?').firstMatch(timeStr.trim());
                if (match != null) {
                  int d = int.parse(match.group(1)!);
                  int m = int.parse(match.group(2)!);
                  int y = int.parse(match.group(3)!);
                  if (y < 100) y += 2000;

                  int h = int.parse(match.group(4)!);
                  int min = int.parse(match.group(5)!);
                  int s = match.group(6) != null ? int.parse(match.group(6)!) : 0;
                  final ampm = match.group(7)?.toUpperCase();

                  if (ampm == 'PM' && h < 12) h += 12;
                  if (ampm == 'AM' && h == 12) h = 0;

                  timestamp = DateTime(y, m, d, h, min, s);
                } else {
                  timestamp = DateTime.parse(timeStr);
                }
              } catch (_) {}
            }

            // Copy media file if it exists
            String? mediaPath;
            if (type != MessageType.text && type != MessageType.system && filename.isNotEmpty) {
              File? mediaFile;
              if (absolutePath.isNotEmpty) {
                mediaFile = File(absolutePath);
              }
              if (mediaFile == null || !await mediaFile.exists()) {
                // Fallback to legacy shared directory
                final fallbackDir = '/storage/emulated/0/ChatBin/.backup/.$chatName/Media';
                mediaFile = File(p.join(fallbackDir, filename));
              }

              if (await mediaFile.exists()) {
                final destPath = p.join(chatDir.path, filename);
                await mediaFile.copy(destPath);
                mediaPath = filename;
              } else {
                mediaPath = filename; // fallback to filename
              }
            }

            messages.add(ChatMessage(
              timestamp: timestamp,
              sender: sender,
              text: chatText,
              type: type,
              mediaPath: mediaPath,
            ));
          }

          if (messages.isEmpty) {
            await chatDir.delete(recursive: true);
            continue;
          }

          // Save messages.json inside chatDir
          final messagesFile = File(p.join(chatDir.path, 'messages.json'));
          await _writeFileAtomically(messagesFile, jsonEncode(messages.map((m) => m.toJson()).toList()));

          // Derive metadata
          final senders = messages
              .map((m) => m.sender)
              .where((s) => s != 'System')
              .toSet()
              .toList();

          String? preview;
          final last = messages.last;
          if (last.type == MessageType.text) {
            preview = last.text;
          } else {
            preview = '[${last.type.name}]';
          }

          final chat = Chat(
            id: 'migrated_${chatSlug}_$ts',
            title: chatName,
            isGroup: isGroup,
            participants: senders,
            importDate: DateTime.now(),
            extractedDir: chatDir.path,
            messageCount: messages.length,
            lastMessagePreview: preview,
          );

          _chats.insert(0, chat);
        }

        await db.close();
        await _persist();
        await prefs.setBool('android_migration_completed', true);
      } catch (e) {
        debugPrint('Legacy Android migration failed: $e');
      }
    }
  }
}
