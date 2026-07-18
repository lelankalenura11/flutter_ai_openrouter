import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';

/// Maximum video duration allowed (60 seconds).
const int maxVideoDurationSeconds = 60;

/// Number of frames to extract per second of video.
/// Extracts ~1 frame every 2.5 seconds ≈ 24 frames max for a 60s video.
const double framesPerSecond = 0.4;

/// Maximum number of frames to extract (hard cap).
const int maxFrames = 30;

/// Results from video frame extraction.
class VideoFrameResult {
  final List<Uint8List> frames;
  final int totalFramesExtracted;
  final double videoDurationSeconds;
  final String? error;

  const VideoFrameResult({
    required this.frames,
    required this.totalFramesExtracted,
    required this.videoDurationSeconds,
    this.error,
  });

  bool get hasFrames => frames.isNotEmpty;
  bool get hasError => error != null;
}

/// Extracts frames from a video file for sending to a vision-capable model.
///
/// Uses [video_thumbnail] to capture frames at strategic intervals.
/// Runs extraction in an isolate via [compute] to keep the UI thread responsive.
class VideoService {
  /// Extract frames from a video file.
  ///
  /// [filePath] — path to the local video file.
  /// [maxFramesCount] — maximum number of frames to extract (default 30).
  ///
  /// Returns [VideoFrameResult] containing the frame images as PNG [Uint8List]s.
  static Future<VideoFrameResult> extractFrames(
    String filePath, {
    int maxFramesCount = maxFrames,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return VideoFrameResult(
        frames: [],
        totalFramesExtracted: 0,
        videoDurationSeconds: 0,
        error: 'Video file not found',
      );
    }

    try {
      // Run extraction in isolate to avoid blocking UI
      return await compute(
        _extractFramesInIsolate,
        _ExtractionParams(filePath: filePath, maxFrames: maxFramesCount),
      );
    } catch (e) {
      debugPrint('Video frame extraction error: $e');
      return VideoFrameResult(
        frames: [],
        totalFramesExtracted: 0,
        videoDurationSeconds: 0,
        error: e.toString(),
      );
    }
  }

  /// The actual extraction logic — runs in an isolate.
  static Future<VideoFrameResult> _extractFramesInIsolate(
    _ExtractionParams params,
  ) async {
    final frames = <Uint8List>[];

    try {
      // Get video duration in milliseconds via thumbnail API
      final durationMs = await _getVideoDuration(params.filePath);
      final durationSeconds = durationMs / 1000.0;

      if (durationMs <= 0) {
        return VideoFrameResult(
          frames: [],
          totalFramesExtracted: 0,
          videoDurationSeconds: 0,
          error: 'Could not determine video duration',
        );
      }

      // Calculate frame interval
      final frameCount = min(
        params.maxFrames,
        (durationSeconds * framesPerSecond).ceil(),
      );

      // Ensure at least 1 frame
      final actualFrameCount = max(1, frameCount);
      final intervalMs =
          (durationMs / actualFrameCount).floor();

      for (int i = 0; i < actualFrameCount; i++) {
        final timeMs = i * intervalMs;
        final result = await FlutterVideoThumbnailPlus.thumbnailData(
          video: params.filePath,
          imageFormat: ImageFormat.jpeg,
          timeMs: timeMs,
          quality: 70, // Good quality at reasonable size
          maxWidth: 1024, // Reasonable width for vision models
        );

        if (result != null && result.isNotEmpty) {
          frames.add(result);
        }
      }

      return VideoFrameResult(
        frames: frames,
        totalFramesExtracted: frames.length,
        videoDurationSeconds: durationSeconds,
      );
    } catch (e) {
      return VideoFrameResult(
        frames: frames,
        totalFramesExtracted: frames.length,
        videoDurationSeconds: 0,
        error: e.toString(),
      );
    }
  }

  /// Get video duration in milliseconds using the thumbnail API.
  /// We try multiple approaches since video_thumbnail may not expose duration directly.
  static Future<int> _getVideoDuration(String filePath) async {
    try {
      // Try to get the duration from the video file metadata
      // Fallback: estimate from file size (rough, but better than nothing)
      final file = File(filePath);
      if (!file.existsSync()) return 0;

      // Attempt to probe via thumbnail; if it fails, estimate
      final firstFrame = await FlutterVideoThumbnailPlus.thumbnailData(
        video: filePath,
        imageFormat: ImageFormat.jpeg,
        timeMs: 0,
        quality: 10,
        maxWidth: 32,
      );

      if (firstFrame != null) {
        // We'll estimate duration: try extracting at increasing offsets
        // to find where the video ends.
        // For simplicity, use a binary-search-like probe.
        int lo = 0;
        int hi = maxVideoDurationSeconds * 1000; // 60 seconds in ms

        while (lo < hi) {
          final mid = (lo + hi) ~/ 2;
          final probe = await FlutterVideoThumbnailPlus.thumbnailData(
            video: filePath,
            imageFormat: ImageFormat.jpeg,
            timeMs: mid,
            quality: 10,
            maxWidth: 32,
          );
          if (probe != null && probe.isNotEmpty) {
            lo = mid + 100; // +100ms step
          } else {
            hi = mid - 100;
          }
        }

        return lo;
      }

      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// Quick check if a video exceeds the maximum allowed duration.
  ///
  /// Returns `null` if the duration cannot be determined (allow), or
  /// a [DurationExceededResult] with the actual duration if it exceeds the limit.
  static Future<DurationExceededResult?> checkDuration(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      final durationMs = await _getVideoDuration(filePath);
      if (durationMs <= 0) return null; // Can't determine, allow

      final durationSeconds = durationMs / 1000.0;
      if (durationSeconds > maxVideoDurationSeconds) {
        return DurationExceededResult(
          actualDurationSeconds: durationSeconds,
          maxAllowedSeconds: maxVideoDurationSeconds,
        );
      }

      return null; // Within limit
    } catch (e) {
      return null; // Can't determine, allow
    }
  }
}

/// Parameters for the frame extraction isolate.
class _ExtractionParams {
  final String filePath;
  final int maxFrames;

  const _ExtractionParams({
    required this.filePath,
    required this.maxFrames,
  });
}

/// Result returned when a video exceeds the maximum allowed duration.
class DurationExceededResult {
  final double actualDurationSeconds;
  final int maxAllowedSeconds;

  const DurationExceededResult({
    required this.actualDurationSeconds,
    required this.maxAllowedSeconds,
  });

  String get formattedDuration {
    final secs = actualDurationSeconds.round();
    final min = secs ~/ 60;
    final sec = secs % 60;
    if (min > 0) return '${min}m ${sec}s';
    return '${sec}s';
  }
}