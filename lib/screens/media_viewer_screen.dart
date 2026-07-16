import 'dart:io';
import 'package:flutter/material.dart';

/// Full-screen media viewer with pinch-to-zoom and swipe-to-dismiss.
/// Opens when tapping on an image attachment in the chat.
class MediaViewerScreen extends StatelessWidget {
  final String filePath;
  final String title;

  const MediaViewerScreen({
    super.key,
    required this.filePath,
    this.title = 'Media',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = File(filePath);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () {
              // TODO: Implement share functionality in phase 6 (export/import)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share coming soon')),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: file.existsSync()
            ? InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildErrorState(theme);
                  },
                ),
              )
            : _buildErrorState(theme),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.broken_image,
          size: 64,
          color: Colors.grey.shade600,
        ),
        const SizedBox(height: 16),
        Text(
          'Could not load image',
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}