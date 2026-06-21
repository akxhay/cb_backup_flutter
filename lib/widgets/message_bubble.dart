import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/chat.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isSelf;
  final String? mediaFullPath;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    this.mediaFullPath,
  });

  Future<void> _openMedia(BuildContext context) async {
    if (mediaFullPath == null) return;

    final result = await OpenFilex.open(mediaFullPath!);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: ${result.message}')),
      );
    }
  }

  IconData _getMediaIcon(MessageType type) {
    switch (type) {
      case MessageType.image:
        return Icons.image;
      case MessageType.video:
        return Icons.videocam;
      case MessageType.audio:
        return Icons.audiotrack;
      case MessageType.document:
        return Icons.insert_drive_file;
      default:
        return Icons.attach_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = isSelf
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isSelf
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final align = isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isSelf ? 16 : 4),
      bottomRight: Radius.circular(isSelf ? 4 : 16),
    );

    Widget content;

    final hasMedia = message.mediaPath != null && mediaFullPath != null;

    if (message.type == MessageType.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.text,
            style: theme.textTheme.bodySmall?.copyWith(color: textColor),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (hasMedia) {
      if (message.type == MessageType.image) {
        final file = File(mediaFullPath!);
        content = GestureDetector(
          onTap: () => _openMedia(context),
          child: Column(
            crossAxisAlignment: align,
            children: [
              if (message.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(message.text, style: TextStyle(color: textColor)),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  file,
                  width: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 220,
                    height: 120,
                    color: Colors.grey.shade300,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        // Non-image media: video, audio, document, etc.
        final filename = message.mediaPath!.split(RegExp(r'[/\\]')).last;
        content = GestureDetector(
          onTap: () => _openMedia(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getMediaIcon(message.type),
                color: textColor.withOpacity(0.85),
                size: 28,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          message.text,
                          style: TextStyle(color: textColor, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Text(
                      filename,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Tap to open in default app',
                      style: TextStyle(
                        color: textColor.withOpacity(0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    } else {
      content = Text(
        message.text,
        style: TextStyle(color: textColor, height: 1.25),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isSelf)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                message.sender,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: radius,
              boxShadow: [
                if (!isSelf)
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 4),
                Text(
                  message.formattedTime,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textColor.withOpacity(0.65),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
