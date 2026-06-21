import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

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
    final isDark = theme.brightness == Brightness.dark;

    // WhatsApp-like colors
    final Color bubbleColor = isSelf
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6))
        : (isDark ? const Color(0xFF1F2C34) : Colors.white);

    final Color textColor = isSelf
        ? (isDark ? Colors.white : Colors.black87)
        : (isDark ? Colors.white : Colors.black87);

    final Color timeColor = isSelf
        ? (isDark ? Colors.white70 : Colors.black54)
        : (isDark ? Colors.white70 : Colors.black54);

    final align = isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isSelf ? 18 : 4),
      bottomRight: Radius.circular(isSelf ? 4 : 18),
    );

    Widget content;

    final hasMedia = message.mediaPath != null && mediaFullPath != null;

    if (message.type == MessageType.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2C34) : Colors.white70,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.text,
            style: theme.textTheme.bodySmall?.copyWith(color: timeColor),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              file,
              width: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 220,
                height: 140,
                color: Colors.grey.shade300,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image, size: 40),
              ),
            ),
          ),
        );
      } else if (message.type == MessageType.video) {
        content = GestureDetector(
          onTap: () => _openMedia(context),
          child: VideoThumbnailWidget(
            path: mediaFullPath!,
            width: 220,
            height: 140,
          ),
        );
      } else {
        // Audio, Document, etc.
        final filename = message.mediaPath!.split(RegExp(r'[/\\]')).last;
        content = GestureDetector(
          onTap: () => _openMedia(context),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelf ? Colors.black12 : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(8),
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
                          style: TextStyle(color: textColor, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        filename,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
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
        style: TextStyle(color: textColor, height: 1.3, fontSize: 15),
      );
    }

    // WhatsApp style: content + timestamp row
    final bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.text.isNotEmpty && hasMedia)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(message.text, style: TextStyle(color: textColor, fontSize: 14)),
          ),
        content,
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            message.formattedTime,
            style: TextStyle(
              color: timeColor,
              fontSize: 10,
            ),
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
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 1,
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

/// Stateful video thumbnail widget.
/// The thumbnail is generated only when this widget is built (i.e. comes on-screen
/// in a ListView or GridView). The bitmap is released in dispose() when the
/// widget is scrolled off-screen. This keeps memory and CPU usage low for long chats.
class VideoThumbnailWidget extends StatefulWidget {
  final String path;
  final double width;
  final double height;

  const VideoThumbnailWidget({
    required this.path,
    required this.width,
    required this.height,
  });

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnailWidget> {
  Uint8List? _thumbnailBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: widget.width.toInt(),
        quality: 55,
      );
      if (mounted) {
        setState(() {
          _thumbnailBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Release reference so GC can reclaim memory when off-screen
    _thumbnailBytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget thumbnailWidget;

    if (_isLoading) {
      thumbnailWidget = Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black26,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ),
      );
    } else if (_thumbnailBytes != null) {
      thumbnailWidget = Image.memory(
        _thumbnailBytes!,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
      );
    } else {
      thumbnailWidget = Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black26,
        child: const Center(
          child: Icon(Icons.videocam, size: 42, color: Colors.white70),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: thumbnailWidget,
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(10),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      ],
    );
  }
}
