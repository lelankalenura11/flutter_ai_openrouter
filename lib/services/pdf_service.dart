import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Processes PDF files for AI consumption.
///
/// Two approaches are attempted in order:
///   1. Render PDF pages as PNG images (for vision-capable models).
///      Uses [Printing.raster] which renders via the platform's native
///      PDF renderer (Android PdfRenderer, iOS/macOS Core Graphics,
///      Windows print subsystem).
///   2. Extract plain text from the PDF (fallback for text-based PDFs).
///      Uses Syncfusion's PDF parser which works on all platforms.
///
/// Page counting is done via Syncfusion's [PdfDocument] (accurate,
/// cross-platform) rather than a brittle regex on raw binary data.
class PdfService {
  static const int maxPagesPerBatch = 20;

  /// Render PDF pages as PNG images with text extraction fallback.
  ///
  /// Returns a [PdfRenderResult] containing either:
  /// - Rendered page images (via platform native renderer), or
  /// - Extracted text from all pages (Syncfusion fallback).
  ///
  /// If the PDF has more than [maxPagesPerBatch] pages, only the first
  /// batch of pages is rendered as images; the text extraction fallback
  /// always covers all pages.
  static Future<PdfRenderResult> renderPdfAsImages(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return PdfRenderResult(images: [], totalPages: 0);
    }

    // Read file bytes once — used by both renderers
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      debugPrint('PdfService: Cannot read file $filePath: $e');
      return PdfRenderResult(images: [], totalPages: 0);
    }

    // Get accurate page count via Syncfusion (works on all platforms).
    final totalPages = _countPdfPages(bytes);
    if (totalPages == 0) {
      debugPrint('PdfService: PDF has 0 pages or is unreadable: $filePath');
      return PdfRenderResult(images: [], totalPages: 0);
    }

    // --- Attempt 1: Render pages as images (Printing.raster) ---
    try {
      final pagesToRender = totalPages > maxPagesPerBatch
          ? maxPagesPerBatch
          : totalPages;

      final images = <Uint8List>[];

      await for (final raster in Printing.raster(
        bytes,
        pages: [for (int i = 0; i < pagesToRender; i++) i],
        dpi: 150,
      )) {
        final pngBytes = await raster.toPng();
        if (pngBytes.isNotEmpty) {
          images.add(pngBytes);
        }
      }

      if (images.isNotEmpty) {
        debugPrint('PdfService: Successfully rendered $pagesToRender pages '
            'as images for $filePath');
        return PdfRenderResult(
          images: images,
          totalPages: totalPages,
        );
      }

      debugPrint('PdfService: Printing.raster returned no images for '
          '$filePath — falling back to text extraction');
    } catch (e) {
      debugPrint('PdfService: Printing.raster failed for $filePath: $e — '
          'falling back to text extraction');
    }

    // --- Attempt 2: Extract text (Syncfusion, works everywhere) ---
    return _extractText(bytes, totalPages, filePath);
  }

  /// Count pages using Syncfusion's PDF parser.
  /// This is reliable on all platforms (Android, iOS, Windows, macOS, Linux).
  static int _countPdfPages(Uint8List bytes) {
    try {
      final document = PdfDocument(inputBytes: bytes);
      final count = document.pages.count;
      document.dispose();
      return count;
    } catch (e) {
      debugPrint('PdfService: Syncfusion page count failed: $e');
      return 0;
    }
  }

  /// Extract plain text from a PDF using Syncfusion's PDF library.
  static PdfRenderResult _extractText(
    Uint8List bytes,
    int totalPages,
    String filePath,
  ) {
    try {
      final document = PdfDocument(inputBytes: bytes);
      final buffer = StringBuffer();

      for (int i = 0; i < totalPages; i++) {
        final text = PdfTextExtractor(document).extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        if (text.trim().isNotEmpty) {
          buffer.writeln('--- Page ${i + 1} ---');
          buffer.writeln(text.trim());
          buffer.writeln();
        }
      }
      document.dispose();

      final extractedText = buffer.toString().trim();
      if (extractedText.isNotEmpty) {
        debugPrint('PdfService: Successfully extracted $totalPages page(s) '
            'of text from $filePath (${extractedText.length} chars)');
        return PdfRenderResult(
          images: [],
          totalPages: totalPages,
          extractedText: extractedText,
        );
      }

      debugPrint('PdfService: No text content found in $filePath');
      return PdfRenderResult(images: [], totalPages: totalPages);
    } catch (e) {
      debugPrint('PdfService: Text extraction error for $filePath: $e');
      return PdfRenderResult(images: [], totalPages: 0);
    }
  }
}

/// Result from PDF processing.
class PdfRenderResult {
  final List<Uint8List> images;
  final int totalPages;
  final String? extractedText;

  const PdfRenderResult({
    required this.images,
    required this.totalPages,
    this.extractedText,
  });

  bool get hasImages => images.isNotEmpty;
  int get renderedCount => images.length;

  int get skippedPages =>
      (totalPages > renderedCount) ? totalPages - renderedCount : 0;
}