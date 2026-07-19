import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/code_block_widget.dart';

class RichContent extends StatelessWidget {
  final String content;
  final TextStyle? textStyle;
  final Color? mathColor;
  final TextAlign textAlign;
  final String? searchQuery;
  final int? activeMatchStart;
  final int? activeMatchEnd;
  final GlobalKey? activeMatchKey;
  /// Optional custom markdown style overrides (merged with defaults).
  final MarkdownStyleSheet? markdownStyleSheet;

  const RichContent({
    super.key,
    required this.content,
    this.textStyle,
    this.mathColor,
    this.textAlign = TextAlign.start,
    this.searchQuery,
    this.activeMatchStart,
    this.activeMatchEnd,
    this.activeMatchKey,
    this.markdownStyleSheet,
  });

  List<InlineSpan> _highlightSpans(
    String text,
    TextStyle style,
    String query,
    int segmentRawStart,
  ) {
    if (query.isEmpty) {
      return [TextSpan(text: text, style: style)];
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <InlineSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: style));
        }
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }

      final matchText = text.substring(index, index + query.length);
      final rawStart = segmentRawStart + index;
      final rawEnd = rawStart + query.length;

      final isActive = activeMatchStart != null &&
          activeMatchEnd != null &&
          rawStart == activeMatchStart &&
          rawEnd == activeMatchEnd;

      if (isActive) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              key: activeMatchKey,
              padding: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                matchText,
                style: style.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: matchText,
            style: style.copyWith(
              background: Paint()..color = Colors.yellow.withValues(alpha: 0.4),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }

      start = index + query.length;
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = textStyle ?? DefaultTextStyle.of(context).style;
    final color = mathColor ?? theme.colorScheme.primary;
    final segments = _parseContent(content);

    if (segments.isEmpty) {
      return Text(content, style: style, textAlign: textAlign);
    }

    if (segments.length == 1 && segments.first is TextSegment) {
      final text = (segments.first as TextSegment).text;
      if (searchQuery != null && searchQuery!.isNotEmpty) {
        final segment = segments.first as TextSegment;
        final spans = _highlightSpans(text, style, searchQuery!, segment.rawStart);
        return SelectableText.rich(
          TextSpan(children: spans),
          textAlign: textAlign,
        );
      }
      return _buildMarkdown(text, style);
    }

    if (!segments.any((s) => s is DisplayMathSegment)) {
      final children = <Widget>[];
      for (final segment in segments) {
        if (segment is TextSegment) {
          if (searchQuery != null && searchQuery!.isNotEmpty) {
            final spans = _highlightSpans(segment.text, style, searchQuery!, segment.rawStart);
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText.rich(
                  TextSpan(children: spans),
                  textAlign: textAlign,
                ),
              ),
            );
          } else {
            children.add(_buildMarkdown(segment.text, style));
          }
        } else if (segment is InlineMathSegment) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _MathScrollable(
                child: Math.tex(
                  segment.tex,
                  textStyle: style.copyWith(color: color),
                  mathStyle: MathStyle.text,
                  onErrorFallback: (err) => Text(r'$' + segment.tex + r'$', style: style),
                ),
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

    return _buildMixedLayout(segments, style, color);
  }

  Widget _buildMarkdown(String text, TextStyle style) {
    // If custom markdown style sheet provided, merge it with defaults
    return MarkdownBody(
      data: text,
      selectable: true,
      builders: {
        'code': CodeElementBuilder(),
      },
      styleSheet: markdownStyleSheet ?? MarkdownStyleSheet(
        p: style,
        h1: style.copyWith(
          fontSize: (style.fontSize ?? 14.0) * 1.5,
          fontWeight: FontWeight.bold,
        ),
        h2: style.copyWith(
          fontSize: (style.fontSize ?? 14.0) * 1.3,
          fontWeight: FontWeight.bold,
        ),
        h3: style.copyWith(
          fontSize: (style.fontSize ?? 14.0) * 1.15,
          fontWeight: FontWeight.bold,
        ),
        listBullet: style,
        code: style.copyWith(
          backgroundColor: Colors.grey.withValues(alpha: 0.2),
          fontFamily: 'monospace',
          fontSize: (style.fontSize ?? 14.0) * 0.9,
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
        if (searchQuery != null && searchQuery!.isNotEmpty) {
          final spans = _highlightSpans(segment.text, style, searchQuery!, segment.rawStart);
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText.rich(
                TextSpan(children: spans),
                textAlign: textAlign,
              ),
            ),
          );
        } else {
          children.add(_buildMarkdown(segment.text, style));
        }
      } else if (segment is InlineMathSegment) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _MathScrollable(
              child: Math.tex(
                segment.tex,
                textStyle: style.copyWith(color: mathColor),
                mathStyle: MathStyle.text,
                onErrorFallback: (err) => Text(r'$' + segment.tex + r'$', style: style),
              ),
            ),
          ),
        );
      } else if (segment is DisplayMathSegment) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: _MathScrollable(
              child: Math.tex(
                segment.tex,
                textStyle: style.copyWith(
                  color: mathColor,
                  fontSize: (style.fontSize ?? 14.0) * 1.1,
                ),
                mathStyle: MathStyle.display,
                onErrorFallback: (err) => Text(r'$$' + segment.tex + r'$$', style: style),
              ),
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

  List<ContentSegment> _parseContent(String text) {
    final segments = <ContentSegment>[];
    final regex = RegExp(r'\$\$(.+?)\$\$|\$(.+?)\$', dotAll: true);

    int lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        segments.add(TextSegment(text.substring(lastEnd, match.start), lastEnd));
      }

      final displayMath = match.group(1);
      final inlineMath = match.group(2);

      if (displayMath != null) {
        segments.add(DisplayMathSegment(displayMath.trim()));
      } else if (inlineMath != null) {
        segments.add(InlineMathSegment(inlineMath.trim()));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      segments.add(TextSegment(text.substring(lastEnd), lastEnd));
    }

    return segments;
  }
}

class _MathScrollable extends StatelessWidget {
  final Widget child;
  const _MathScrollable({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: child,
      ),
    );
  }
}

sealed class ContentSegment {}

class TextSegment extends ContentSegment {
  final String text;
  final int rawStart;
  TextSegment(this.text, this.rawStart);
}

class InlineMathSegment extends ContentSegment {
  final String tex;
  InlineMathSegment(this.tex);
}

class DisplayMathSegment extends ContentSegment {
  final String tex;
  DisplayMathSegment(this.tex);
}