import 'package:intl/intl.dart';

import '../models/chat.dart';

final _timestampRe = RegExp(
  r'^\u200e?\[(\d{2}/\d{2}/\d{2}),\s*(\d{1,2}:\d{2}:\d{2}\s*[AP]M)\]\s*(.+?):\s*(.*)$',
  caseSensitive: false,
);

final _attachedRe = RegExp(r'^[\u200e\s]*<attached:\s*([^>]+)>', caseSensitive: false);

final _dateFormat = DateFormat('dd/MM/yy, h:mm:ss a');

/// Parses raw WhatsApp _chat.txt content into messages.
/// [myAliases] are used only for caller-side isSelf computation (parser stays neutral).
List<ChatMessage> parseChat(String rawContent, {List<String> myAliases = const []}) {
  final lines = rawContent.split('\n');
  final messages = <ChatMessage>[];

  ChatMessage? current;

  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;

    final match = _timestampRe.firstMatch(line);
    if (match != null) {
      // Finish previous accumulated message
      if (current != null) {
        messages.add(current);
      }

      final datePart = match.group(1)!;
      final timePart = match.group(2)!;
      final sender = match.group(3)!.trim();
      String text = match.group(4) ?? '';

      DateTime ts;
      try {
        ts = _dateFormat.parse('$datePart, $timePart', true).toLocal();
      } catch (_) {
        // Fallback: try with different spacing or unicode
        final cleaned = '$datePart, ${timePart.replaceAll('\u202f', ' ')}';
        try {
          ts = _dateFormat.parse(cleaned, true).toLocal();
        } catch (_) {
          ts = DateTime.now();
        }
      }

      // Check for attachment on this line
      final attachMatch = _attachedRe.firstMatch(text);
      String? media;
      MessageType type = MessageType.text;

      if (attachMatch != null) {
        media = attachMatch.group(1)!.trim();
        type = getMediaTypeFromFilename(media);
        text = ''; // attachment line has no other text
      } else if (sender.toLowerCase().contains('end-to-end') || text.toLowerCase().contains('encrypted')) {
        type = MessageType.system;
      }

      current = ChatMessage(
        timestamp: ts,
        sender: sender,
        text: text.trim(),
        mediaPath: media,
        type: type,
      );
      continue;
    }

    // Continuation of previous message (multi-line)
    if (current != null) {
      final cont = line.trim();
      if (cont.isNotEmpty) {
        if (current.text.isEmpty) {
          current = ChatMessage(
            timestamp: current.timestamp,
            sender: current.sender,
            text: cont,
            mediaPath: current.mediaPath,
            type: current.type,
          );
        } else {
          current = ChatMessage(
            timestamp: current.timestamp,
            sender: current.sender,
            text: '${current.text}\n$cont',
            mediaPath: current.mediaPath,
            type: current.type,
          );
        }
      }
    } else {
      // Orphan line before first message; treat as system if relevant
      messages.add(ChatMessage(
        timestamp: DateTime.now(),
        sender: 'System',
        text: line.trim(),
        type: MessageType.system,
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
