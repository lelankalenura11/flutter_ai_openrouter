import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_ai_chat_app_openrouter/screens/media_viewer_screen.dart';

/// Displays a file attachment preview inside a chat bubble.
/// Supports images (thumbnail), PDFs (icon + name), and other files.
class AttachmentBubble extends StatelessWidget {
  final String attachmentPath;
  final String inputType;
  final bool isUser;

  const AttachmentBubble({
    super.key,
    required this.attachmentPath,
    required this.inputType,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = File(attachmentPath);

    if (!file.existsSync()) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file,
                size: 16, color: theme.colorScheme.error),
            const SizedBox(width: 4),
            Text(
              'File not found',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      );
    }

    final fileName = attachmentPath.split('/').last;
    final fileSize = file.lengthSync();

    // Image thumbnail
    if (inputType == 'image') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => _openMediaViewer(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: 240,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildFallbackIcon(theme, fileName, fileSize);
              },
            ),
          ),
        ),
      );
    }

    // PDF
    if (inputType == 'pdf') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => _openMediaViewer(context),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isUser
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.surfaceContainerLow)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf,
                  color: Colors.red.shade400,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isUser
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatSize(fileSize),
                      style: TextStyle(
                        fontSize: 10,
                        color: (isUser
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface)
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Other file types
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _openMediaViewer(context),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (isUser
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.surfaceContainerLow)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isUser
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatSize(fileSize),
                    style: TextStyle(
                      fontSize: 10,
                      color: (isUser
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface)
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMediaViewer(BuildContext context) {
    if (inputType == 'image') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
            filePath: attachmentPath,
            title: 'Image',
          ),
        ),
      );
    }
  }

  Widget _buildFallbackIcon(ThemeData theme, String fileName, int fileSize) {
    return Container(
      width: 240,
      height: 180,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, size: 32, color: theme.colorScheme.error),
            const SizedBox(height: 4),
            Text(
              fileName,
              style: const TextStyle(fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}