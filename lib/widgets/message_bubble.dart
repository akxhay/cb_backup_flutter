import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/chat.dart';
import '../services/chat_parser.dart';
import '../services/video_thumbnail_service.dart';
import '../theme/chat_theme.dart';
import 'full_screen_image_viewer.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isSelf;
  final String? mediaFullPath;
  final bool showSenderName;
  final bool groupedAbove;
  final bool groupedBelow;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    this.mediaFullPath,
    this.showSenderName = false,
    this.groupedAbove = false,
    this.groupedBelow = false,
  });

  Future<void> _openMedia(BuildContext context) async {
    if (mediaFullPath == null) return;

    if (message.type == MessageType.image) {
      await FullScreenImageViewer.show(
        context,
        imagePath: mediaFullPath!,
        caption: message.text.isNotEmpty ? message.text : null,
      );
      return;
    }

    final result = await OpenFilex.open(mediaFullPath!);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: ${result.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.type == MessageType.system) {
      return _buildSystemMessage(context);
    }

    final isStickerMsg =
        message.type == MessageType.image && isSticker(message);

    if (isStickerMsg && mediaFullPath != null) {
      return _buildSticker(context);
    }

    final bubbleColor = isSelf
        ? ChatTheme.sentBubbleColor(context)
        : ChatTheme.receivedBubbleColor(context);
    final textColor = isSelf
        ? ChatTheme.sentTextColor(context)
        : ChatTheme.receivedTextColor(context);
    final timeColor =
        ChatTheme.timestampColor(context, isSelf: isSelf);
    final align = isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final hasMedia = message.mediaPath != null && mediaFullPath != null;

    final isMediaOnly = hasMedia &&
        (message.type == MessageType.image || message.type == MessageType.video) &&
        message.text.isEmpty;

    final showName = !isSelf && showSenderName && !groupedAbove;

    Widget innerContent;
    if (hasMedia) {
      if (message.type == MessageType.image) {
        innerContent = _buildImageContent(context, textColor, align, timeColor);
      } else if (message.type == MessageType.video) {
        innerContent = _buildVideoContent(context, textColor, align, timeColor);
      } else if (message.type == MessageType.audio) {
        innerContent = _buildAudioContent(context, textColor, timeColor);
      } else {
        innerContent = _buildFileContent(context, textColor, timeColor);
      }
    } else {
      innerContent = _buildTextContent(context, textColor, timeColor);
    }

    if (isMediaOnly) {
      return Container(
        margin: ChatTheme.bubbleMargin(
          isSelf: isSelf,
          groupedAbove: groupedAbove,
          groupedBelow: groupedBelow,
          showSenderName: showName,
        ),
        child: Column(
          crossAxisAlignment: align,
          children: [
            if (showName)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 3),
                child: Text(
                  message.sender,
                  style: TextStyle(
                    color: ChatTheme.senderNameColor(message.sender),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: innerContent,
            ),
          ],
        ),
      );
    }

    final hasTail = !groupedAbove;
    final horizontalPadding = isSelf
        ? EdgeInsets.only(left: 10, right: hasTail ? 18 : 10)
        : EdgeInsets.only(left: hasTail ? 18 : 10, right: 10);

    return Container(
      margin: ChatTheme.bubbleMargin(
        isSelf: isSelf,
        groupedAbove: groupedAbove,
        groupedBelow: groupedBelow,
        showSenderName: showName,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(
                message.sender,
                style: TextStyle(
                  color: ChatTheme.senderNameColor(message.sender),
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          PhysicalShape(
            clipper: BubbleClipper(isSelf: isSelf, hasTail: hasTail),
            elevation: 1.0,
            color: bubbleColor,
            shadowColor: Colors.black.withValues(alpha: 0.08),
            child: Padding(
              padding: horizontalPadding.copyWith(top: 6, bottom: 6),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: ChatTheme.bubbleMaxWidth(context),
                ),
                child: innerContent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ChatTheme.systemPillColor(context),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 2,
            ),
          ],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: ChatTheme.datePillTextColor(context),
            fontSize: 12,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildSticker(BuildContext context) {
    return Container(
      margin: ChatTheme.bubbleMargin(
        isSelf: isSelf,
        groupedAbove: groupedAbove,
        groupedBelow: groupedBelow,
        showSenderName: false,
      ),
      alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _openMedia(context),
        child: Stack(
          children: [
            Image.file(
              File(mediaFullPath!),
              width: 140,
              height: 140,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
            ),
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  message.formattedTime,
                  style: const TextStyle(color: Colors.white, fontSize: 9.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextContent(BuildContext context, Color textColor, Color timeColor) {
    final textStyle = TextStyle(color: textColor, height: 1.38, fontSize: 15.5);
    final double spacerWidth = message.isEdited ? 75.0 : 45.0;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: message.text, style: textStyle),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: SizedBox(width: spacerWidth, height: 10),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: _TimestampRow(
            time: message.formattedTime,
            isEdited: message.isEdited,
            color: timeColor,
          ),
        ),
      ],
    );
  }

  String _getFileSize(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes < 1024) return '$bytes B';
        if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    } catch (_) {}
    return '';
  }

  Widget _buildImageContent(
    BuildContext context,
    Color textColor,
    CrossAxisAlignment align,
    Color timeColor,
  ) {
    final double maxW = (ChatTheme.bubbleMaxWidth(context) - 16).clamp(180.0, 262.0);
    final double maxH = 220.0;
    final isGif = message.mediaPath?.toLowerCase().endsWith('.gif') ?? false;

    final imageWidget = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Image.file(
            File(mediaFullPath!),
            width: maxW,
            height: maxH,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: maxW,
              height: maxH,
              color: Colors.black12,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined, size: 40),
            ),
          ),
          if (isGif)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: const Text(
                  'GIF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (message.text.isEmpty) {
      return GestureDetector(
        onTap: () => _openMedia(context),
        child: Stack(
          children: [
            imageWidget,
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _TimestampRow(
                  time: message.formattedTime,
                  isEdited: message.isEdited,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return GestureDetector(
        onTap: () => _openMedia(context),
        child: Column(
          crossAxisAlignment: align,
          children: [
            imageWidget,
            const SizedBox(height: 6),
            _buildTextContent(context, textColor, timeColor),
          ],
        ),
      );
    }
  }

  Widget _buildVideoContent(
    BuildContext context,
    Color textColor,
    CrossAxisAlignment align,
    Color timeColor,
  ) {
    final double maxW = (ChatTheme.bubbleMaxWidth(context) - 16).clamp(180.0, 262.0);
    final double maxH = 220.0;
    final sizeLabel = _getFileSize(mediaFullPath!);

    return FutureBuilder<String?>(
      future: VideoThumbnailService.getThumbnail(mediaFullPath!),
      builder: (context, snapshot) {
        final thumbPath = snapshot.data;
        final hasThumb = thumbPath != null && File(thumbPath).existsSync();

        final videoPreviewWidget = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (hasThumb)
                Image.file(
                  File(thumbPath),
                  width: maxW,
                  height: maxH,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: maxW,
                    height: maxH,
                    color: Colors.black.withValues(alpha: 0.12),
                    child: Icon(
                      Icons.videocam_rounded,
                      size: 44,
                      color: textColor.withValues(alpha: 0.4),
                    ),
                  ),
                )
              else
                Container(
                  width: maxW,
                  height: maxH,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.04),
                        Colors.black.withValues(alpha: 0.25),
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.videocam_rounded,
                    size: 44,
                    color: textColor.withValues(alpha: 0.4),
                  ),
                ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
              ),
              if (sizeLabel.isNotEmpty)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_rounded, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          sizeLabel,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );

        if (message.text.isEmpty) {
          return GestureDetector(
            onTap: () => _openMedia(context),
            child: Stack(
              children: [
                videoPreviewWidget,
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _TimestampRow(
                      time: message.formattedTime,
                      isEdited: message.isEdited,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          return GestureDetector(
            onTap: () => _openMedia(context),
            child: Column(
              crossAxisAlignment: align,
              children: [
                videoPreviewWidget,
                const SizedBox(height: 6),
                _buildTextContent(context, textColor, timeColor),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildAudioContent(BuildContext context, Color textColor, Color timeColor) {
    final accent = const Color(0xFF53BDEB); // voice note blue
    
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.play_arrow_rounded,
            color: isSelf ? textColor : accent,
            size: 32,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoiceWaveform(color: isSelf ? textColor.withValues(alpha: 0.5) : accent),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "0:00",
                      style: TextStyle(color: timeColor, fontSize: 11),
                    ),
                    _TimestampRow(
                      time: message.formattedTime,
                      isEdited: message.isEdited,
                      color: timeColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: isSelf 
                    ? textColor.withValues(alpha: 0.12) 
                    : accent.withValues(alpha: 0.12),
                child: Icon(
                  Icons.person,
                  color: isSelf ? textColor.withValues(alpha: 0.5) : accent,
                  size: 18,
                ),
              ),
              const Icon(Icons.mic_rounded, color: Color(0xFF53BDEB), size: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileContent(BuildContext context, Color textColor, Color timeColor) {
    final filename = message.mediaPath!.split(RegExp(r'[/\\]')).last;
    final ext = filename.contains('.') ? filename.split('.').last.toUpperCase() : 'FILE';
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF15C5C),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  ext.substring(0, (ext.length).clamp(0, 4)),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ext,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (message.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message.text,
              style: TextStyle(color: textColor, fontSize: 14.5),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _TimestampRow(
              time: message.formattedTime,
              isEdited: message.isEdited,
              color: timeColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimestampRow extends StatelessWidget {
  final String time;
  final bool isEdited;
  final Color color;

  const _TimestampRow({
    required this.time,
    required this.isEdited,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w400),
        ),
        if (isEdited)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'edited',
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}

class _VoiceWaveform extends StatelessWidget {
  final Color color;

  const _VoiceWaveform({required this.color});

  @override
  Widget build(BuildContext context) {
    const heights = [6.0, 12.0, 8.0, 16.0, 10.0, 14.0, 7.0, 18.0, 9.0, 13.0, 6.0, 11.0];
    return Row(
      children: [
        for (final h in heights)
          Container(
            width: 3,
            height: h,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

class BubbleClipper extends CustomClipper<Path> {
  final bool isSelf;
  final bool hasTail;

  BubbleClipper({required this.isSelf, required this.hasTail});

  @override
  Path getClip(Size size) {
    final path = Path();
    const double r = 12.0; // border radius

    if (isSelf) {
      if (hasTail) {
        // Top right tail pointing outwards
        path.moveTo(r, 0);
        path.lineTo(size.width - 10, 0);
        // Drawing tail
        path.quadraticBezierTo(size.width - 2, 0, size.width, 0);
        path.quadraticBezierTo(size.width - 3, 5, size.width - 10, 9);
        path.lineTo(size.width - 10, size.height - r);
        path.quadraticBezierTo(size.width - 10, size.height, size.width - 10 - r, size.height);
        path.lineTo(r, size.height);
        path.quadraticBezierTo(0, size.height, 0, size.height - r);
        path.lineTo(0, r);
        path.quadraticBezierTo(0, 0, r, 0);
      } else {
        path.addRRect(RRect.fromLTRBR(0, 0, size.width, size.height, const Radius.circular(r)));
      }
    } else {
      if (hasTail) {
        // Top left tail pointing outwards
        path.moveTo(10 + r, 0);
        path.lineTo(size.width - r, 0);
        path.quadraticBezierTo(size.width, 0, size.width, r);
        path.lineTo(size.width, size.height - r);
        path.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
        path.lineTo(10 + r, size.height);
        path.quadraticBezierTo(10, size.height, 10, size.height - r);
        path.lineTo(10, 9);
        path.quadraticBezierTo(3, 5, 0, 0);
        path.quadraticBezierTo(2, 0, 10, 0);
      } else {
        path.addRRect(RRect.fromLTRBR(0, 0, size.width, size.height, const Radius.circular(r)));
      }
    }
    return path;
  }

  @override
  bool shouldReclip(covariant BubbleClipper oldClipper) {
    return oldClipper.isSelf != isSelf || oldClipper.hasTail != hasTail;
  }
}