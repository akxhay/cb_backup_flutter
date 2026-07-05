import 'package:intl/intl.dart';

enum MessageType { text, image, video, audio, document, system }

extension MessageTypeX on MessageType {
  /// Human-friendly label for previews and descriptions.
  /// Pure data label (no UI dependencies).
  String get displayName {
    switch (this) {
      case MessageType.image:
        return 'photo';
      case MessageType.video:
        return 'video';
      case MessageType.audio:
        return 'audio';
      case MessageType.document:
        return 'file';
      default:
        return '';
    }
  }
}

class ChatMessage {
  final DateTime timestamp;
  final String sender;
  final String text;
  final String? mediaPath; // relative filename inside the extracted chat dir
  final MessageType type;
  final bool isEdited;

  const ChatMessage({
    required this.timestamp,
    required this.sender,
    required this.text,
    this.mediaPath,
    this.type = MessageType.text,
    this.isEdited = false,
  });

  bool get isFromSelf => false; // resolved at runtime using aliases

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawText = (json['text'] as String?) ?? '';
    final cleanText = rawText.replaceAll('\u200E', '').trim();
    return ChatMessage(
      timestamp: DateTime.parse(json['timestamp'] as String),
      sender: json['sender'] as String,
      text: cleanText,
      mediaPath: json['mediaPath'] as String?,
      type: MessageType.values.firstWhere(
        (e) => e.name == (json['type'] as String? ?? 'text'),
        orElse: () => MessageType.text,
      ),
      isEdited: json['isEdited'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'sender': sender,
        'text': text,
        if (mediaPath != null) 'mediaPath': mediaPath,
        'type': type.name,
        'isEdited': isEdited,
      };

  String get formattedTime => DateFormat('HH:mm').format(timestamp);
  String get uniqueId => '${timestamp.millisecondsSinceEpoch}_${sender}_${text.hashCode}';
}

class Chat {
  final String id;
  final String title;
  final bool isGroup;
  final List<String> participants;
  final DateTime importDate;
  final String extractedDir; // path to folder containing the extracted files + chat log .txt (name may vary by platform)
  final int messageCount;
  final String? lastMessagePreview;

  const Chat({
    required this.id,
    required this.title,
    required this.isGroup,
    required this.participants,
    required this.importDate,
    required this.extractedDir,
    required this.messageCount,
    this.lastMessagePreview,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as String,
      title: json['title'] as String,
      isGroup: json['isGroup'] as bool? ?? false,
      participants: (json['participants'] as List?)?.cast<String>() ?? const [],
      importDate: DateTime.parse(json['importDate'] as String),
      extractedDir: json['extractedDir'] as String,
      messageCount: json['messageCount'] as int? ?? 0,
      lastMessagePreview: json['lastMessagePreview'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isGroup': isGroup,
        'participants': participants,
        'importDate': importDate.toIso8601String(),
        'extractedDir': extractedDir,
        'messageCount': messageCount,
        if (lastMessagePreview != null) 'lastMessagePreview': lastMessagePreview,
      };
}
