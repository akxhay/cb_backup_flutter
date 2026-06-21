import 'package:intl/intl.dart';

import '../models/chat.dart';

final _lrm = '\u200E';

final _timestampRe = RegExp(
  '^' + _lrm + r'?\[(\d{2}/\d{2}/\d{2}),\s*(\d{1,2}:\d{2}:\d{2}\s*[AP]M)\]\s*(.+?):\s*(.*)$',
  caseSensitive: false,
);

/// Helper to extract media filename if <attached: ...> is present in the line (anywhere).
/// Returns the media name and the text with the tag removed (caption remains).
({String? media, String cleanedText}) _parseAttached(String lineText) {
  final lower = lineText.toLowerCase();
  final startIdx = lower.indexOf('<attached:');
  if (startIdx == -1) {
    return (media: null, cleanedText: lineText.trim());
  }
  final contentStart = startIdx + '<attached:'.length;
  final endIdx = lineText.indexOf('>', contentStart);
  if (endIdx == -1) {
    return (media: null, cleanedText: lineText.trim());
  }
  final media = lineText.substring(contentStart, endIdx).trim();
  // remove from startIdx to endIdx+1
  final before = lineText.substring(0, startIdx).trimRight();
  final after = lineText.substring(endIdx + 1).trimLeft();
  final cleaned = [before, after].where((s) => s.isNotEmpty).join(' ').trim();
  return (media: media, cleanedText: cleaned);
}

/// Removes WhatsApp's "This message was edited" marker from the text and returns whether it was edited.
({String text, bool isEdited}) _stripEditedMarker(String text) {
  // Matches variations like: "text ‎<This message was edited>" or "text <This message was edited>"
  final editedRe = RegExp(r'\s*[' + _lrm + r']?\s*<This message was edited>', caseSensitive: false);
  if (editedRe.hasMatch(text)) {
    final cleaned = text.replaceAll(editedRe, '').trim();
    return (text: cleaned, isEdited: true);
  }
  return (text: text.trim(), isEdited: false);
}

final _dateFormat = DateFormat('dd/MM/yy, h:mm:ss a');

/// Parses raw WhatsApp _chat.txt content into messages.
/// [myAliases] are used only for caller-side isSelf computation (parser stays neutral).
List<ChatMessage> parseChat(String rawContent, {List<String> myAliases = const []}) {
  // Normalize line endings (the txt from zip may have \r\n on some systems)
  final normalized = rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final messages = <ChatMessage>[];

  ChatMessage? current;

  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;

    final match = _timestampRe.firstMatch(line);
    if (match != null) {
      final datePart = match.group(1)!;
      final timePart = match.group(2)!;
      final sender = match.group(3)!.trim();
      String text = match.group(4) ?? '';

      DateTime ts;
      try {
        ts = _dateFormat.parse('$datePart, $timePart', true).toLocal();
      } catch (_) {
        final cleaned = '$datePart, ${timePart.replaceAll('\u202f', ' ')}';
        try {
          ts = _dateFormat.parse(cleaned, true).toLocal();
        } catch (_) {
          ts = DateTime.now();
        }
      }

      // Check for attachment on this line (using robust helper)
      final attachedInfo = _parseAttached(text);
      String? media = attachedInfo.media;
      MessageType type = MessageType.text;
      String finalText = attachedInfo.cleanedText;

      if (media != null) {
        type = getMediaTypeFromFilename(media);
      } else if (sender.toLowerCase().contains('end-to-end') || text.toLowerCase().contains('encrypted')) {
        type = MessageType.system;
      }

      // Check if this timestamped line is a caption for a previous media message
      if (current != null &&
          current.mediaPath != null &&
          sender.toLowerCase() == current.sender.toLowerCase() &&
          (ts.difference(current.timestamp).inSeconds.abs() < 120) &&
          media == null) {
        // Append as caption to the existing media message (immutable)
        final combined = current.text.isNotEmpty
            ? '${current.text}\n$finalText'
            : finalText;
        final stripped = _stripEditedMarker(combined);

        current = ChatMessage(
          timestamp: current.timestamp,
          sender: current.sender,
          text: stripped.text,
          mediaPath: current.mediaPath,
          type: current.type,
          isEdited: stripped.isEdited || current.isEdited,
        );
        continue;
      }

      // Normal case: finish previous message
      if (current != null) {
        messages.add(current);
      }

      final stripped = _stripEditedMarker(finalText);
      current = ChatMessage(
        timestamp: ts,
        sender: sender,
        text: stripped.text,
        mediaPath: media,
        type: type,
        isEdited: stripped.isEdited,
      );
      continue;
    }

    // Continuation of previous message (multi-line) -- may contain <attached> tag
    if (current != null) {
      final cont = line.trim();
      if (cont.isNotEmpty) {
        final attachedInfo = _parseAttached(cont);
        if (attachedInfo.media != null) {
          // Media tag found inside a continuation line
          final newMedia = attachedInfo.media!;
          final newType = getMediaTypeFromFilename(newMedia);
          // keep any caption text from the cont (tag already stripped by helper)
          final cleanedCont = attachedInfo.cleanedText;

          final combined = current.text.isNotEmpty && cleanedCont.isNotEmpty
              ? '${current.text}\n$cleanedCont'
              : (cleanedCont.isNotEmpty ? cleanedCont : current.text);
          final stripped = _stripEditedMarker(combined);

          current = ChatMessage(
            timestamp: current.timestamp,
            sender: current.sender,
            text: stripped.text,
            mediaPath: newMedia,
            type: newType,
            isEdited: stripped.isEdited || current.isEdited,
          );
        } else {
          // Regular text continuation
          final combined = current.text.isEmpty
              ? cont
              : '${current.text}\n$cont';
          final stripped = _stripEditedMarker(combined);

          current = ChatMessage(
            timestamp: current.timestamp,
            sender: current.sender,
            text: stripped.text,
            mediaPath: current.mediaPath,
            type: current.type,
            isEdited: stripped.isEdited || current.isEdited,
          );
        }
      }
    } else {
      // Orphan line before first message
      final stripped = _stripEditedMarker(line.trim());
      messages.add(ChatMessage(
        timestamp: DateTime.now(),
        sender: 'System',
        text: stripped.text,
        type: MessageType.system,
        isEdited: stripped.isEdited,
      ));
    }
  }

  if (current != null) {
    messages.add(current);
  }

  return messages;
}

/// Returns all unique senders found in the messages.
Set<String> extractSenders(List<ChatMessage> messages) {
  return messages.map((m) => m.sender).toSet();
}

/// Detect if this is likely a group chat based on number of distinct non-system senders.
bool isLikelyGroupChat(List<ChatMessage> messages) {
  final realSenders = messages
      .where((m) => m.type != MessageType.system)
      .map((m) => m.sender)
      .toSet();
  return realSenders.length > 2;
}

/// Build a short preview for last message (truncated).
String buildPreview(List<ChatMessage> messages) {
  if (messages.isEmpty) return '';
  final last = messages.last;

  if (last.mediaPath != null) {
    if (last.text.isNotEmpty) {
      final txt = last.text.replaceAll('\n', ' ').trim();
      final p = txt.length > 50 ? '${txt.substring(0, 47)}...' : txt;
      return '${last.sender}: $p';
    }
    final label = last.type.displayName.isNotEmpty
        ? last.type.displayName
        : 'file';
    final article = (label == 'photo' || label == 'audio') ? 'an' : 'a';
    return '${last.sender} sent $article $label';
  }

  final txt = last.text.replaceAll('\n', ' ');
  final preview = txt.length > 60 ? '${txt.substring(0, 57)}...' : txt;
  return '${last.sender}: $preview';
}

/// Parses the contact or group name from a standard WhatsApp export zip filename.
/// 
/// Expected format (matching sample "WhatsApp Chat - Rashmi Arya.zip"):
///   "WhatsApp Chat - <Name>.zip"
/// 
/// Returns the extracted name (e.g. "Rashmi Arya" or "Family Group").
/// Throws a descriptive error if the filename does not follow the expected format.
String parseChatTitleFromZipFilename(String filePath) {
  // We only need the basename; import 'path' is not required here for this function.
  // To avoid extra dep in this file, we do simple last-segment extraction.
  String name = filePath.split(RegExp(r'[/\\]')).last;
  if (name.toLowerCase().endsWith('.zip')) {
    name = name.substring(0, name.length - 4);
  }

  const prefix = 'WhatsApp Chat - ';

  if (!name.toLowerCase().startsWith(prefix.toLowerCase())) {
    throw Exception(
      'Invalid zip filename format.\n'
      'WhatsApp chat exports must be named like:\n'
      '  "WhatsApp Chat - Rashmi Arya.zip"\n\n'
      'Got: "$name.zip"',
    );
  }

  final title = name.substring(prefix.length).trim();

  if (title.isEmpty) {
    throw Exception('Could not extract contact or group name from the zip filename.');
  }

  return title;
}

/// Extracts the base title without any numeric label suffix like " (2)".
String extractBaseChatTitle(String title) {
  final match = RegExp(r'^(.*)\s*\(\d+\)$').firstMatch(title);
  return match != null ? match.group(1)!.trim() : title.trim();
}

/// Returns the numeric label if present, e.g. 2 for "Foo (2)", else 1.
int extractLabelNumber(String title) {
  final match = RegExp(r'^(.*)\s*\((\d+)\)$').firstMatch(title);
  if (match != null) {
    return int.tryParse(match.group(2)!) ?? 1;
  }
  return 1;
}

/// Determines the media type based on file extension.
/// Used when parsing <attached: filename> lines from WhatsApp exports.
MessageType getMediaTypeFromFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase().trim();

  const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp'};
  const videoExts = {'mp4', 'mov', 'avi', 'mkv', '3gp', 'm4v'};
  const audioExts = {'mp3', 'm4a', 'opus', 'aac', 'wav', 'ogg', 'amr'};

  if (imageExts.contains(ext)) return MessageType.image;
  if (videoExts.contains(ext)) return MessageType.video;
  if (audioExts.contains(ext)) return MessageType.audio;

  // Everything else (pdf, docx, txt, vcf, zip, unknown, etc.) is treated as document
  return MessageType.document;
}
