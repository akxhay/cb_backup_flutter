import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class VideoThumbnailService {
  static const _channel = MethodChannel('com.xharma.cbbackup/thumbnail');

  static final Map<String, String> _thumbnailCache = {};

  static Future<String?> getThumbnail(String videoPath) async {
    if (_thumbnailCache.containsKey(videoPath)) {
      return _thumbnailCache[videoPath];
    }

    try {
      final file = File(videoPath);
      if (!file.existsSync()) return null;

      final tempDir = await getTemporaryDirectory();
      final videoName = p.basenameWithoutExtension(videoPath);
      final thumbPath = p.join(tempDir.path, 'thumb_${videoName}_${file.lengthSync()}.jpg');

      final thumbFile = File(thumbPath);
      if (thumbFile.existsSync()) {
        _thumbnailCache[videoPath] = thumbPath;
        return thumbPath;
      }

      final result = await _channel.invokeMethod<String>('getVideoThumbnail', {
        'videoPath': videoPath,
        'thumbnailPath': thumbPath,
      });

      if (result != null && File(result).existsSync()) {
        _thumbnailCache[videoPath] = result;
        return result;
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
