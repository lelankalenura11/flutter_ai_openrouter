import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

class CodeBlockWidget extends StatelessWidget {
  final String code;
  final String language;

  const CodeBlockWidget({super.key, required this.code, required this.language});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with language label + copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
              border: Border(
                bottom:
                    BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    language.isEmpty ? 'code' : language,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.robotoMono(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copied!'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 14, color: Colors.grey[600]),
                      if (!Platform.isAndroid) ...[
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Code content
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                code,
                style: GoogleFonts.robotoMono(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Builder that creates [CodeBlockWidget] for fenced code blocks in markdown.
class CodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    String language = '';
    if (element.attributes['class'] != null) {
      final cls = element.attributes['class']!;
      if (cls.startsWith('language-')) {
        language = cls.substring(9);
      }
    }

    // Extract raw text content
    final code = element.textContent.trim();

    return CodeBlockWidget(code: code, language: language);
  }
}