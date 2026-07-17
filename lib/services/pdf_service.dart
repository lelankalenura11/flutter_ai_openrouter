import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

/// Renders PDF pages as PNG images for sending to vision-capable models.
/// Each page becomes one `image_url` content block.
/// Max 20 pages per batch (per PLAN.md: batches of 20 pages).
class PdfService {
  static const int maxPagesPerBatch = 20;

  /// Render PDF pages as PNG images.
  ///
  /// Uses [Printing.raster] which requires the native PDF renderer
  /// (supported on Android/iOS/Windows/macOS).
  ///
  /// If the PDF has more than [maxPagesPerBatch] pages, only the first
  /// batch is rendered to avoid excessive token usage.
  static Future<PdfRenderResult> renderPdfAsImages(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return PdfRenderResult(images: [], totalPages: 0);
    }

    try {
      final bytes = await file.readAsBytes();
      // Count pages first via simple PDF structure scan (runs synchronously)
      final totalPages = _countPdfPages(bytes);

      if (totalPages == 0) {
        return PdfRenderResult(images: [], totalPages: 0);
      }

      final pagesToRender = totalPages > maxPagesPerBatch
          ? maxPagesPerBatch
          : totalPages;

      final images = <Uint8List>[];

      // Render using Printing.raster stream
      await for (final raster in Printing.raster(
        bytes,
        pages: [for (int i = 0; i < pagesToRender; i++) i],
        dpi: 150, // Good quality at reasonable size
      )) {
        final pngBytes = await raster.toPng();
        if (pngBytes.isNotEmpty) {
          images.add(pngBytes);
        }
      }

      return PdfRenderResult(
        images: images,
        totalPages: totalPages,
      );
    } catch (e) {
      debugPrint('PDF rendering error: $e');
      return PdfRenderResult(images: [], totalPages: 0);
    }
  }

  /// Count PDF pages by scanning file content for /Type /Page entries.
  static int _countPdfPages(Uint8List bytes) {
    try {
      final content = String.fromCharCodes(bytes);
      final matches = RegExp(r'/Type\s*/Page[^s]').allMatches(content);
      return matches.length;
    } catch (e) {
      return 0;
    }
  }
}

/// Result from PDF rendering.
class PdfRenderResult {
  final List<Uint8List> images;
  final int totalPages;

  const PdfRenderResult({
    required this.images,
    required this.totalPages,
  });

  bool get hasImages => images.isNotEmpty;
  int get renderedCount => images.length;

  int get skippedPages =>
      (totalPages > renderedCount) ? totalPages - renderedCount : 0;
}