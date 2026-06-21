import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    final dir = Directory(p.join(docs.path, 'cbbackup', 'chats'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
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
    if (!await metaFile.exists()) return;

    try {
      final content = await metaFile.readAsString();
      final list = (jsonDecode(content) as List).cast<Map<String, dynamic>>();
      _chats.addAll(list.map(Chat.fromJson));
      notifyListeners();
    } catch (e) {
      // ignore corrupt meta for MVP
      debugPrint('Failed to load chats meta: $e');
      // Try to delete corrupt file so next import can start fresh
      try { await metaFile.delete(); } catch (_) {}
    }
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
  /// `parseChatTitleFromZipFilename` (e.g. "WhatsApp Chat - <Name>.zip").
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
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final outPath = p.join(chatDir.path, file.name);
      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    // Locate chat txt (case-insensitive search)
    String? chatTxtPath;
    await for (final entity in chatDir.list(recursive: true, followLinks: false)) {
      if (entity is File && p.basename(entity.path).toLowerCase() == '_chat.txt') {
        chatTxtPath = entity.path;
        break;
      }
    }
    if (chatTxtPath == null) {
      // cleanup
      await chatDir.delete(recursive: true);
      throw Exception('No _chat.txt found in the zip.');
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
    final temp = await Directory.systemTemp.createTemp('cbbackup_merge_');
    try {
      // Extract new zip to temp
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        final outPath = p.join(temp.path, f.name);
        if (f.isFile) {
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(f.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }

      // Find _chat.txt in temp
      String? txtPath;
      await for (final entity in temp.list(recursive: true, followLinks: false)) {
        if (entity is File && p.basename(entity.path).toLowerCase() == '_chat.txt') {
          txtPath = entity.path;
          break;
        }
      }
      if (txtPath == null) {
        throw Exception('No _chat.txt found in the zip for merge.');
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
          if (base.toLowerCase() == '_chat.txt') continue;
          final rel = p.relative(entity.path, from: temp.path);
          final destPath = p.join(target.extractedDir, rel);
          final destFile = File(destPath);
          await destFile.parent.create(recursive: true);
          await entity.copy(destPath);
        }
      }

      // Overwrite messages.json with merged
      final msgFile = File(p.join(target.extractedDir, 'messages.json'));
      await _writeFileAtomically(msgFile, jsonEncode(merged.map((m) => m.toJson()).toList()));

      // Update the in-memory chat metadata
      final idx = _chats.indexWhere((c) => c.id == target.id);
      if (idx != -1) {
        final old = _chats[idx];
        final updated = Chat(
          id: old.id,
          title: old.title,
          isGroup: old.isGroup,
          participants: old.participants,
          importDate: DateTime.now(),
          extractedDir: old.extractedDir,
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
      // fallback: reparse _chat.txt
      final txt = File(p.join(chat.extractedDir, '_chat.txt'));
      if (await txt.exists()) {
        final raw = await txt.readAsString();
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
      return data.map((j) => ChatMessage.fromJson((j as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      // If json corrupt, fallback to txt
      final txt = File(p.join(chat.extractedDir, '_chat.txt'));
      if (await txt.exists()) {
        final raw = await txt.readAsString();
        final msgs = parseChat(raw);
        try {
          await _writeFileAtomically(messagesFile, jsonEncode(msgs.map((m) => m.toJson()).toList()));
        } catch (_) {}
        return msgs;
      }
      return [];
    }
  }

  Future<void> deleteChat(Chat chat) async {
    _chats.removeWhere((c) => c.id == chat.id);
    await _persist();
    notifyListeners();

    final dir = Directory(chat.extractedDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Returns full absolute path for a media file belonging to a chat.
  String resolveMediaPath(Chat chat, String relativeMedia) {
    return p.join(chat.extractedDir, relativeMedia);
  }
}
