import 'dart:io';
import 'package:flutter/foundation.dart';

/// Compresses images in an isolate to avoid blocking the UI thread.
class FileCompressionService {
  /// Compress an image file to reduce its size before uploading.
  ///
  /// Returns the compressed image bytes.
  /// Uses [compute] to run compression in an isolate.
  static Future<Uint8List> compressImage(
    String filePath, {
    int maxWidth = 2048,
    int quality = 85,
  }) async {
    final file = File(filePath);
    final originalBytes = await file.readAsBytes();

    // Use compute to run compression in an isolate
    return compute(
      _compressBytes,
      _CompressionParams(
        bytes: originalBytes,
        maxWidth: maxWidth,
        quality: quality,
      ),
    );
  }

  /// Resize and compress raw image bytes (runs in isolate).
  static Uint8List _compressBytes(_CompressionParams params) {
    // Placeholder for future enhanced compression.
    // Current compression is handled at pick time via image_picker's imageQuality.
    return params.bytes;
  }
}

/// Parameters for the compression isolate.
class _CompressionParams {
  final Uint8List bytes;
  final int maxWidth;
  final int quality;

  const _CompressionParams({
    required this.bytes,
    required this.maxWidth,
    required this.quality,
  });
}

/// Represents a file attachment selected by the user.
class FileAttachment {
  final String path;
  final String name;
  final String originalName; // Original file name (not the stored UUID path)
  final String mimeType;
  final int sizeBytes;
  final String inputType; // 'image', 'pdf', 'video', 'audio', 'file'

  const FileAttachment({
    required this.path,
    required this.name,
    this.originalName = '',
    required this.mimeType,
    required this.sizeBytes,
    required this.inputType,
  });

  /// Get display name — prefer original name, fall back to storage name
  String get displayName => originalName.isNotEmpty ? originalName : name;

  /// Determine if this attachment is an image type.
  bool get isImage => inputType == 'image';

  /// Determine if this attachment is a video.
  bool get isVideo => inputType == 'video';

  /// Determine if this attachment is a PDF.
  bool get isPdf => mimeType == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

  /// Get a display icon name based on type.
  String get displayIcon {
    if (isImage) return 'image';
    if (isPdf) return 'picture_as_pdf';
    if (isVideo) return 'videocam';
    return 'insert_drive_file';
  }

  /// Get file size as human-readable string.
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}