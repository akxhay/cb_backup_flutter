import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/chat.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isSelf;
  final String? mediaFullPath;
  final bool showSenderName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    this.mediaFullPath,
    this.showSenderName = false,
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

    // Material Design 3 consistent colors
    final Color bubbleColor = isSelf
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;

    final Color textColor = isSelf
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    final Color timeColor = isSelf
        ? theme.colorScheme.onPrimaryContainer.withOpacity(0.7)
        : theme.colorScheme.onSurfaceVariant;

    final align = isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isSelf ? 20 : 5),
      bottomRight: Radius.circular(isSelf ? 5 : 20),
    );

    Widget content;

    final hasMedia = message.mediaPath != null && mediaFullPath != null;

    if (message.type == MessageType.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: timeColor,
              fontWeight: FontWeight.w500,
            ),
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
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    message.text,
                    style: TextStyle(color: textColor, fontSize: 14, height: 1.25),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  file,
                  width: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 220,
                    height: 140,
                    color: theme.colorScheme.surfaceContainerHigh,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image, size: 40),
                  ),
                ),
              ),
            ],
          ),
        );
      } else if (message.type == MessageType.video) {
        // Videos show icon + filename (no thumbnail)
        final filename = message.mediaPath!.split(RegExp(r'[/\\]')).last;
        content = GestureDetector(
          onTap: () => _openMedia(context),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelf 
                  ? theme.colorScheme.onPrimaryContainer.withOpacity(0.12)
                  : theme.colorScheme.onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getMediaIcon(message.type),
                  color: textColor.withOpacity(0.9),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.text.isNotEmpty)
                        Text(
                          message.text,
                          style: TextStyle(color: textColor, fontSize: 14, height: 1.25),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (message.text.isNotEmpty) const SizedBox(height: 2),
                      Text(
                        filename,
                        style: TextStyle(
                          color: textColor.withOpacity(0.75),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Audio, Document, etc. (may have caption in .text)
        final filename = message.mediaPath!.split(RegExp(r'[/\\]')).last;
        content = GestureDetector(
          onTap: () => _openMedia(context),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelf 
                  ? theme.colorScheme.onPrimaryContainer.withOpacity(0.12)
                  : theme.colorScheme.onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getMediaIcon(message.type),
                  color: textColor.withOpacity(0.9),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.text.isNotEmpty)
                        Text(
                          message.text,
                          style: TextStyle(color: textColor, fontSize: 14, height: 1.25),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (message.text.isNotEmpty) const SizedBox(height: 2),
                      Text(
                        filename,
                        style: TextStyle(
                          color: textColor.withOpacity(0.75),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      content = Text(
        message.text,
        style: TextStyle(color: textColor, height: 1.35, fontSize: 15),
      );
    }

    // WhatsApp style: content + timestamp row
    final bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        const SizedBox(height: 3),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.formattedTime,
                style: TextStyle(
                  color: timeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (message.isEdited)
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Text(
                    'edited',
                    style: TextStyle(
                      color: timeColor.withOpacity(0.85),
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isSelf && showSenderName)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                message.sender,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.1),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: bubbleContent,
          ),
        ],
      ),
    );
  }

}
