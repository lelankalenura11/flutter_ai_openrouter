import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// A widget that renders a message string with LaTeX math and Markdown support.
///
/// Detects:
/// - `$$...$$` for display math (block)
/// - `$...$` for inline math
/// - Everything else rendered as Markdown
class RichContent extends StatelessWidget {
  final String content;
  final TextStyle? textStyle;
  final Color? mathColor;
  final TextAlign textAlign;

  const RichContent({
    super.key,
    required this.content,
    this.textStyle,
    this.mathColor,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = textStyle ?? DefaultTextStyle.of(context).style;
    final color = mathColor ?? theme.colorScheme.primary;

    // Parse content into segments (text blocks and LaTeX blocks)
    final segments = _parseContent(content);

    if (segments.isEmpty) {
      return Text(content, style: style, textAlign: textAlign);
    }

    // If there's only one text segment with no math, render as markdown
    if (segments.length == 1 && segments.first is TextSegment) {
      return _buildMarkdown((segments.first as TextSegment).text, style);
    }

    // If no display math, use RichText with inline spans for selectability
    if (!segments.any((s) => s is DisplayMathSegment)) {
      final inlineChildren = <InlineSpan>[];
      for (final segment in segments) {
        if (segment is TextSegment) {
          inlineChildren.add(TextSpan(text: segment.text, style: style));
        } else if (segment is InlineMathSegment) {
          inlineChildren.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Math.tex(
                segment.tex,
                textStyle: style.copyWith(color: color),
                mathStyle: MathStyle.text,
                onErrorFallback: (err) => Text(r'$' + segment.tex + r'$', style: style),
              ),
            ),
          );
        }
      }
      return SelectableText.rich(
        TextSpan(children: inlineChildren),
        textAlign: textAlign,
      );
    }

    // Mixed with display math: use a Column layout
    return _buildMixedLayout(segments, style, color);
  }

  Widget _buildMarkdown(String text, TextStyle style) {
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: style,
        h1: style.copyWith(fontSize: (style.fontSize ?? 14.0) * 1.5, fontWeight: FontWeight.bold),
        h2: style.copyWith(fontSize: (style.fontSize ?? 14.0) * 1.3, fontWeight: FontWeight.bold),
        h3: style.copyWith(fontSize: (style.fontSize ?? 14.0) * 1.15, fontWeight: FontWeight.bold),
        listBullet: style,
        code: style.copyWith(
          backgroundColor: Colors.grey.withValues(alpha: 0.2),
          fontFamily: 'monospace',
          fontSize: (style.fontSize ?? 14.0) * 0.9,
        ),
        codeblockDecoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Colors.grey.withValues(alpha: 0.5),
              width: 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMixedLayout(List<ContentSegment> segments, TextStyle style, Color mathColor) {
    final children = <Widget>[];
    for (final segment in segments) {
      if (segment is TextSegment) {
        children.add(_buildMarkdown(segment.text, style));
      } else if (segment is InlineMathSegment) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Math.tex(
              segment.tex,
              textStyle: style.copyWith(color: mathColor),
              mathStyle: MathStyle.text,
              onErrorFallback: (err) => Text(r'$' + segment.tex + r'$', style: style),
            ),
          ),
        );
      } else if (segment is DisplayMathSegment) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Math.tex(
              segment.tex,
              textStyle: style.copyWith(color: mathColor, fontSize: (style.fontSize ?? 14.0) * 1.1),
              mathStyle: MathStyle.display,
              onErrorFallback: (err) => Text(r'$$' + segment.tex + r'$$', style: style),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// Parse text into segments, detecting LaTeX math delimiters.
  List<ContentSegment> _parseContent(String text) {
    final segments = <ContentSegment>[];
    final regex = RegExp(
      r'\$\$(.+?)\$\$|\$(.+?)\$',
      dotAll: true,
    );

    int lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      // Text before this match
      if (match.start > lastEnd) {
        segments.add(TextSegment(text.substring(lastEnd, match.start)));
      }

      // Determine which group matched
      final displayMath = match.group(1);
      final inlineMath = match.group(2);

      if (displayMath != null) {
        segments.add(DisplayMathSegment(displayMath.trim()));
      } else if (inlineMath != null) {
        segments.add(InlineMathSegment(inlineMath.trim()));
      }

      lastEnd = match.end;
    }

    // Remaining text after last match
    if (lastEnd < text.length) {
      segments.add(TextSegment(text.substring(lastEnd)));
    }

    return segments;
  }
}

/// Base class for content segments.
sealed class ContentSegment {}

/// Plain text (not LaTeX).
class TextSegment extends ContentSegment {
  final String text;
  TextSegment(this.text);
}

/// Inline LaTeX math: `$...$`
class InlineMathSegment extends ContentSegment {
  final String tex;
  InlineMathSegment(this.tex);
}

/// Display LaTeX math: `$$...$$`
class DisplayMathSegment extends ContentSegment {
  final String tex;
  DisplayMathSegment(this.tex);
}