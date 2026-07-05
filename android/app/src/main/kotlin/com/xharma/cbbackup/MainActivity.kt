package com.xharma.cbbackup

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.xharma.cbbackup/thumbnail"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getVideoThumbnail") {
                val videoPath = call.argument<String>("videoPath")
                val thumbnailPath = call.argument<String>("thumbnailPath")
                if (videoPath != null && thumbnailPath != null) {
                    try {
                        val retriever = MediaMetadataRetriever()
                        retriever.setDataSource(videoPath)
                        val bitmap = retriever.getFrameAtTime(1, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        retriever.release()

                        if (bitmap != null) {
                            val file = File(thumbnailPath)
                            val out = FileOutputStream(file)
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 75, out)
                            out.flush()
                            out.close()
                            result.success(thumbnailPath)
                        } else {
                            result.error("GEN_ERROR", "Failed to retrieve frame from video", null)
                        }
                    } catch (e: Exception) {
                        result.error("EXCEPTION", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Missing videoPath or thumbnailPath", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}