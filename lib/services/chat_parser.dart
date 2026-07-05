import '../models/chat.dart';

final _lrm = '\u200E';

final _timestampRe = RegExp(
  r'^\u200E?\s*\[(\d{1,2}/\d{1,2}/\d{2}),\s*(\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?)\]?\s*([^:]+):\s*(.*)$',
  caseSensitive: false,
);

// Fallback regex for Android exports that may have slight variations (no space after ], different spacing, etc.)
final _timestampReFallback = RegExp(
  r'^\u200E?\s*\[(\d{1,2}/\d{1,2}/\d{2}),\s*(\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?)\]?\s*([^:]+):\s*(.*)$',
  caseSensitive: false,
);

// Android "dash" format without brackets: DD/MM/YY, h:mm pm - [Sender: ] text
// Supports system lines without sender (e.g. "date, time - You were added")
final _timestampReDash = RegExp(
  r'^(\d{1,2}/\d{1,2}/\d{2}),\s*(\d{1,2}:\d{2}(?::\d{2})?\s*[ap]m?)\s*-\s*(?:(.+?):\s*)?(.*)$',
  caseSensitive: false,
);

// Matches WhatsApp's deleted message markers (with optional LRM prefix):
//   "You deleted this message."
//   "This message was deleted."
final _deletedMessageRe = RegExp(
  r'^\s*(?:You deleted this message|This message was deleted)\.?\s*$',
  caseSensitive: false,
);

/// Helper to extract media filename if <attached: ...> is present in the line (anywhere).
/// Returns the media name and the text with the tag removed (caption remains).
({String? media, String cleanedText}) _parseAttached(String lineText) {
  // Strip LRM (and any direction marks) that WhatsApp inserts before attachments in some exports.
  // This ensures pure media messages have truly empty .text so buildPreview shows "sent a photo" etc.
  lineText = lineText.replaceAll(_lrm, '');
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



/// Parses raw WhatsApp chat log content into messages (supports both iOS and Android export formats).
/// [myAliases] are used only for caller-side isSelf computation (parser stays neutral).
List<ChatMessage> parseChat(String rawContent, {List<String> myAliases = const []}) {
  // Normalize line endings (the txt from zip may have \r\n on some systems)
  final normalized = rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final messages = <ChatMessage>[];

  ChatMessage? current;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    // Try bracket format first, then fallback, then Android dash format (no brackets)
    var match = _timestampRe.firstMatch(line);
    match ??= _timestampReFallback.firstMatch(line);
    match ??= _timestampReDash.firstMatch(line);

    if (match != null) {
      final datePart = match.group(1)!;
      final timePart = match.group(2)!;
      String sender = (match.group(3) ?? '').trim();
      String text = (match.group(4) ?? '').replaceAll(_lrm, '');

      // For dash format without sender (system lines like "date, time - You were added")
      bool isDashNoSender = false;
      if (sender.isEmpty && text.isNotEmpty) {
        if (match.group(3) == null) {
          sender = 'System';
          isDashNoSender = true;
        }
      }

      // Always initialize. The many formats below support Android (24h, direct filenames) + iOS (12h, <attached:>).
      // If no format matches we fall back so parsing doesn't crash on a weird line.
      // Robust manual parsing that handles both Android (24h) and iOS (12h) formats,
      // with or without seconds, and DD/MM or MM/DD date order.
      DateTime ts = DateTime.now();
      try {
        final dateParts = datePart.split('/');
        int d = int.parse(dateParts[0]);
        int m = int.parse(dateParts[1]);
        int y = 2000 + int.parse(dateParts[2]);

        // Handle possible MM/DD/YY (swap if month > 12)
        if (m > 12 && d <= 12) {
          final tmp = d; d = m; m = tmp;
        }

        String t = timePart.replaceAll('\u202f', ' ').trim();
        bool isPM = false;
        bool hasAmPm = t.toUpperCase().endsWith('PM') || t.toUpperCase().endsWith('AM');
        if (t.toUpperCase().endsWith('PM')) {
          isPM = true;
          t = t.substring(0, t.length - 2).trim();
        } else if (t.toUpperCase().endsWith('AM')) {
          t = t.substring(0, t.length - 2).trim();
        }

        final timeParts = t.split(':');
        int h = int.parse(timeParts[0]);
        int min = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
        int sec = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;

        if (isPM && h < 12) h += 12;
        if (!isPM && h == 12 && hasAmPm) h = 0; // 12 AM only if AM/PM was present

        ts = DateTime(y, m, d, h, min, sec);
      } catch (_) {
        // keep the fallback DateTime.now()
      }

      // Check for attachment on this line (using robust helper)
      final attachedInfo = _parseAttached(text);
      String? media = attachedInfo.media;
      MessageType type = MessageType.text;
      String finalText = attachedInfo.cleanedText;

      if (media != null) {
        type = getMediaTypeFromFilename(media);
      } else {
        final potentialMedia = finalText.trim();
        // Android WhatsApp export often references media directly as the "text" part
        // e.g. "IMG-20250616-WA0001.jpg" instead of "<attached: IMG-...>"
        // Also catches other filename-only media lines
        // Must NOT contain spaces (real filenames from WA exports don't have spaces;
        // sentences like "You deleted this message." would otherwise match).
        if (!potentialMedia.contains(' ') &&
            potentialMedia.contains('.') &&
            potentialMedia.split('.').last.length <= 5 && // plausible extension
            potentialMedia.length > 4 &&
            potentialMedia.length < 120) {
          // Android style: the line content is just the media filename (no <attached: tag)
          media = potentialMedia;
          type = getMediaTypeFromFilename(media);
          finalText = '';
        } else if (sender.toLowerCase().contains('end-to-end') || text.toLowerCase().contains('encrypted')) {
          type = MessageType.system;
        } else if (_deletedMessageRe.hasMatch(finalText)) {
          type = MessageType.system;
        }
      }

      if (isDashNoSender) {
        type = MessageType.system;
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
      final cont = line.trim().replaceAll(_lrm, '');
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
          // Regular text continuation, or Android direct media filename on next line
          final potential = cont.trim();
          if (potential.contains('.') &&
              potential.split('.').last.length <= 5 &&
              potential.length > 4 &&
              potential.length < 120) {
            // Android: filename on continuation line
            final newMedia = potential;
            final newType = getMediaTypeFromFilename(newMedia);
            current = ChatMessage(
              timestamp: current.timestamp,
              sender: current.sender,
              text: current.text,
              mediaPath: newMedia,
              type: newType,
              isEdited: current.isEdited,
            );
          } else {
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
      }
    } else {
      // Orphan line before first message
      final stripped = _stripEditedMarker(line.trim().replaceAll(_lrm, ''));
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
    // Treat LRM-only or whitespace-only as "no caption" so we get nice "sent a photo"
    final visibleCaption = last.text.replaceAll(_lrm, '').replaceAll('\n', ' ').trim();
    if (visibleCaption.isNotEmpty) {
      final p = visibleCaption.length > 50 ? '${visibleCaption.substring(0, 47)}...' : visibleCaption;
      return '${last.sender}: $p';
    }
    String label;
    if (isSticker(last)) {
      label = 'sticker';
    } else if (last.type.displayName.isNotEmpty) {
      label = last.type.displayName;
    } else {
      label = 'file';
    }
    final article = (label == 'photo' || label == 'audio') ? 'an' : 'a';
    return '${last.sender} sent $article $label';
  }

  final txt = last.text.replaceAll(_lrm, '').replaceAll('\n', ' ').trim();
  final preview = txt.length > 60 ? '${txt.substring(0, 57)}...' : txt;
  return '${last.sender}: $preview';
}

/// Parses the contact or group name from a standard WhatsApp export zip filename.
///
/// Supports both common Android and iOS export formats:
///   "WhatsApp Chat - <Name>.zip"
///   "WhatsApp Chat with <Name>.zip"
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

  // Match either " - " or " with " after "WhatsApp Chat" (case insensitive)
  final prefixMatch = RegExp(r'^WhatsApp Chat (?:- |with )', caseSensitive: false).firstMatch(name);

  if (prefixMatch == null) {
    throw Exception(
      'Invalid zip filename format.\n'
      'WhatsApp chat exports must be named like one of:\n'
      '  "WhatsApp Chat - Rashmi Arya.zip"\n'
      '  "WhatsApp Chat with Congob KYC Techops.zip"\n\n'
      'Got: "$name.zip"',
    );
  }

  final title = name.substring(prefixMatch.end).trim();

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

/// Returns true if the message represents a sticker.
/// Heuristic: image type + .webp (common for WA stickers) or filename contains 'sticker'.
bool isSticker(ChatMessage msg) {
  if (msg.type != MessageType.image || msg.mediaPath == null) return false;
  final p = msg.mediaPath!.toLowerCase();
  if (p.endsWith('.webp')) return true;
  if (p.contains('sticker')) return true;
  return false;
}
