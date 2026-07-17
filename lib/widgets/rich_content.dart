import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// A widget that renders a message string with LaTeX math and Markdown support.
///
/// Detects:
/// - `$$...$$` for display math (block)
/// - `$...$` for inline math
/// - Everything else rendered as Markdown
///
/// When [searchQuery] is non-null, matching text is highlighted with a yellow background.
class RichContent extends StatelessWidget {
  final String content;
  final TextStyle? textStyle;
  final Color? mathColor;
  final TextAlign textAlign;
  final String? searchQuery;

  const RichContent({
    super.key,
    required this.content,
    this.textStyle,
    this.mathColor,
    this.textAlign = TextAlign.start,
    this.searchQuery,
  });

  /// Returns a list of InlineSpan for text, splitting by [query] and wrapping
  /// matches with a yellow background highlight.
  List<InlineSpan> _highlightSpans(String text, TextStyle style, String query) {
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
        // No more matches — add remaining text
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: style));
        }
        break;
      }

      // Text before the match
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }

      // The highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: style.copyWith(
          background: Paint()..color = Colors.yellow.withValues(alpha: 0.4),
          fontWeight: FontWeight.w600,
        ),
      ));

      start = index + query.length;
    }

    return spans;
  }

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
      final text = (segments.first as TextSegment).text;
      // If searching, show highlighted plain text instead of markdown
      if (searchQuery != null && searchQuery!.isNotEmpty) {
        final spans = _highlightSpans(text, style, searchQuery!);
        return SelectableText.rich(
          TextSpan(children: spans),
          textAlign: textAlign,
        );
      }
      return _buildMarkdown(text, style);
    }

    // If no display math, use RichText with inline spans for selectability
    if (!segments.any((s) => s is DisplayMathSegment)) {
      final inlineChildren = <InlineSpan>[];
      for (final segment in segments) {
        if (segment is TextSegment) {
          if (searchQuery != null && searchQuery!.isNotEmpty) {
            inlineChildren.addAll(_highlightSpans(segment.text, style, searchQuery!));
          } else {
            inlineChildren.add(TextSpan(text: segment.text, style: style));
          }
        } else if (segment is InlineMathSegment) {
          inlineChildren.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
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
        if (searchQuery != null && searchQuery!.isNotEmpty) {
          final spans = _highlightSpans(segment.text, style, searchQuery!);
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
                textStyle: style.copyWith(color: mathColor, fontSize: (style.fontSize ?? 14.0) * 1.1),
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

/// A stateful widget that wraps a child in a horizontally-scrollable container
/// with a [Scrollbar] that only shows when the content actually overflows.
///
/// Each instance owns its own [ScrollController] to avoid "no ScrollPosition
/// attached" assertions that occur when using [PrimaryScrollController] with
/// non-scrolling content.
class _MathScrollable extends StatefulWidget {
  final Widget child;

  const _MathScrollable({required this.child});

  @override
  State<_MathScrollable> createState() => _MathScrollableState();
}

class _MathScrollableState extends State<_MathScrollable> {
  final ScrollController _scrollController = ScrollController();
  bool _hasOverflow = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
    // Check overflow right after the first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkOverflow() {
    if (!_scrollController.hasClients) return;
    setState(() {
      _hasOverflow = _scrollController.position.maxScrollExtent > 0;
    });
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final newOverflow = _scrollController.position.maxScrollExtent > 0;
    if (newOverflow != _hasOverflow) {
      setState(() {
        _hasOverflow = newOverflow;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: _hasOverflow,
      thickness: 4.0,
      radius: const Radius.circular(4),
      child: Padding(
        // Reserve space at the bottom so the scrollbar doesn't overlap the equation
        padding: const EdgeInsets.only(bottom: 6.0),
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: LayoutBuilder(
            builder: (context, constraints) => FittedBox(
              fit: BoxFit.scaleDown,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
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