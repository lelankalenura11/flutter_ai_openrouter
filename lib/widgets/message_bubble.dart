import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/rich_content.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/attachment_bubble.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/message_action_button.dart';

/// A simple animated streaming dot for the three-dot thinking indicator.
class _StreamingDot extends StatefulWidget {
  final double delay;
  const _StreamingDot({required this.delay});

  @override
  State<_StreamingDot> createState() => _StreamingDotState();
}

class _StreamingDotState extends State<_StreamingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          widget.delay,
          widget.delay + 0.5,
          curve: Curves.easeInOut,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final theme = Theme.of(context);
        final animValue = _animation.value;
        final offset = -8.0 * (0.5 - 0.5 * (1.0 - animValue) * (1.0 - animValue));
        return Transform.translate(
          offset: Offset(0, offset),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

class MessageBubble extends StatelessWidget {
  final MessagesTableData message;
  final bool showTokenCount;
  final VoidCallback? onCopy;
  final VoidCallback? onStar;
  final bool isStarred;
  final bool showRetry;
  final VoidCallback? onRetry;
  final VoidCallback? onFork;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEdit;
  final bool highlight;
  final String? searchQuery;
  final int? activeMatchStart;
  final int? activeMatchEnd;
  final GlobalKey? activeMatchKey;

  const MessageBubble({
    super.key,
    required this.message,
    this.showTokenCount = true,
    this.onCopy,
    this.onStar,
    this.isStarred = false,
    this.showRetry = false,
    this.onRetry,
    this.onFork,
    this.onRegenerate,
    this.onEdit,
    this.highlight = false,
    this.searchQuery,
    this.activeMatchStart,
    this.activeMatchEnd,
    this.activeMatchKey,
  });

  /// The text style used for body content — Inter with comfortable line height.
  /// On Android, use system font to avoid the Google Fonts network download.
  static TextStyle _bodyTextStyle(ThemeData theme, {required bool isUser}) {
    final isAndroid = Platform.isAndroid;
    return (isAndroid ? TextStyle(
      fontSize: 15,
      height: 1.6,
      color: isUser
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurface,
    ) : GoogleFonts.inter(
      fontSize: 15,
      height: 1.6,
      color: isUser
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurface,
    ));
  }

  /// Base markdown style sheet shared by both user and AI messages.
  static MarkdownStyleSheet _markdownStyle(ThemeData theme, TextStyle body) {
    final isDark = theme.brightness == Brightness.dark;
    final isAndroid = Platform.isAndroid;
    return MarkdownStyleSheet(
      p: body,
      h1: body.copyWith(fontSize: 24, fontWeight: FontWeight.bold, height: 1.8),
      h2: body.copyWith(fontSize: 20, fontWeight: FontWeight.w600, height: 1.7),
      h3: body.copyWith(fontSize: 17, fontWeight: FontWeight.w600, height: 1.6),
      listBullet: body,
      code: isAndroid ? TextStyle(
        fontSize: 13,
        backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        fontFamily: 'monospace',
      ) : GoogleFonts.firaCode(
        fontSize: 13,
        backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isAssistant = message.role == 'assistant';
    final theme = Theme.of(context);
    final hasAttachment =
        message.attachmentPath != null && message.inputType != 'text';
    final isStreaming = message.status == 'sending' && isAssistant;
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    final bodyStyle = _bodyTextStyle(theme, isUser: isUser);
    final mdStyle = _markdownStyle(theme, bodyStyle);

    // User messages keep the classic right-aligned bubble.
    // AI messages are clean, left-aligned, with no visible bubble.
    final contentColumn = Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width *
                (isUser ? 0.75 : 0.85),
          ),
          child: isUser ? _buildUserContent(theme, hasAttachment, isStreaming, bodyStyle, mdStyle)
                         : _buildAiContent(theme, isStreaming, bodyStyle, mdStyle),
        ),
        // Action buttons — subtle inline style
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (onCopy != null)
              MessageActionButton(
                icon: Icons.content_copy,
                label: 'Copy',
                showLabel: !Platform.isAndroid,
                onPressed: onCopy!,
              ),
            if (onFork != null)
              MessageActionButton(
                icon: Icons.call_split,
                label: 'Fork',
                showLabel: !Platform.isAndroid,
                onPressed: onFork!,
              ),
            if (onStar != null)
              MessageActionButton(
                icon: isStarred ? Icons.star : Icons.star_border,
                label: isStarred ? 'Starred' : 'Star',
                showLabel: !Platform.isAndroid,
                onPressed: onStar!,
              ),
            if (onRegenerate != null && isAssistant)
              MessageActionButton(
                icon: Icons.refresh,
                label: 'Try again',
                showLabel: !Platform.isAndroid,
                onPressed: onRegenerate!,
              ),
            if (onEdit != null && isUser)
              MessageActionButton(
                icon: Icons.edit_outlined,
                label: 'Edit & Retry',
                showLabel: !Platform.isAndroid,
                onPressed: onEdit!,
              ),
            // Token counter — inline in action row (Android only)
            if (Platform.isAndroid && showTokenCount &&
                (message.inputTokens != null || message.outputTokens != null))
              MessageActionButton(
                icon: Icons.token_outlined,
                label: '${message.inputTokens ?? 0}↓${message.outputTokens ?? 0}',
                showLabel: true,
                onPressed: () {},
              ),
          ],
        ),
      ],
    );

    final bubbleContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.smart_toy_outlined,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: contentColumn),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary,
              child: Icon(
                Icons.person,
                size: 18,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ],
      ),
    );

    if (isDesktop) {
      return GestureDetector(
        onSecondaryTap: () => _showContextMenu(context),
        child: bubbleContent,
      );
    }

    return bubbleContent;
  }

  /// Build the user message bubble (classic right-aligned, colored background).
  Widget _buildUserContent(
    ThemeData theme,
    bool hasAttachment,
    bool isStreaming,
    TextStyle bodyStyle,
    MarkdownStyleSheet mdStyle,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(4),
        ),
        border: highlight
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasAttachment)
            AttachmentBubble(
              attachmentPath: message.attachmentPath!,
              inputType: message.inputType,
              isUser: true,
            ),
          if (isStreaming && message.content.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StreamingDot(delay: 0.0),
                  SizedBox(width: 4),
                  _StreamingDot(delay: 0.2),
                  SizedBox(width: 4),
                  _StreamingDot(delay: 0.4),
                ],
              ),
            ),
          if (isStreaming || message.content.isNotEmpty)
            RichContent(
              content: message.content + (isStreaming ? ' ▎' : ''),
              textStyle: bodyStyle,
              markdownStyleSheet: mdStyle,
              mathColor: theme.colorScheme.onPrimary,
              searchQuery: searchQuery,
              activeMatchStart: activeMatchStart,
              activeMatchEnd: activeMatchEnd,
              activeMatchKey: activeMatchKey,
            ),
          if (showRetry) _buildRetryRow(theme),
        ],
      ),
    );
  }

  /// Build the AI message content (clean, no visible bubble).
  Widget _buildAiContent(
    ThemeData theme,
    bool isStreaming,
    TextStyle bodyStyle,
    MarkdownStyleSheet mdStyle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reasoning block (styled container with ExpansionTile)
        if (message.reasoning != null && message.reasoning!.isNotEmpty)
          _AiReasoningTile(reasoning: message.reasoning!),

        // Attachment preview (image, PDF, file)
        if (message.attachmentPath != null && message.inputType != 'text')
          AttachmentBubble(
            attachmentPath: message.attachmentPath!,
            inputType: message.inputType,
            isUser: false,
          ),

        // Streaming three dots
        if (isStreaming && message.content.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StreamingDot(delay: 0.0),
                SizedBox(width: 4),
                _StreamingDot(delay: 0.2),
                SizedBox(width: 4),
                _StreamingDot(delay: 0.4),
              ],
            ),
          ),

        // Main content
        if (isStreaming || message.content.isNotEmpty)
          RichContent(
            content: message.content + (isStreaming ? ' ▎' : ''),
            textStyle: bodyStyle,
            markdownStyleSheet: mdStyle,
            mathColor: theme.colorScheme.primary,
            searchQuery: searchQuery,
            activeMatchStart: activeMatchStart,
            activeMatchEnd: activeMatchEnd,
            activeMatchKey: activeMatchKey,
          ),

        const SizedBox(height: 12),

        // Token counter chip at bottom-right (desktop only; Android shows inline)
        if (!Platform.isAndroid &&
            showTokenCount &&
            (message.inputTokens != null || message.outputTokens != null))
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.token_outlined,
                    size: 12,
                    color: theme.iconTheme.color?.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${message.inputTokens ?? 0} ↓ ${message.outputTokens ?? 0} tokens',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.iconTheme.color?.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Retry row used in user messages on failure.
  Widget _buildRetryRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 14, color: theme.colorScheme.error),
          const SizedBox(width: 4),
          Text(
            'Failed to send',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
          ),
          const SizedBox(width: 8),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Retry', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + renderBox.size.width / 2,
        offset.dy,
        offset.dx + renderBox.size.width,
        offset.dy + renderBox.size.height,
      ),
      items: [
        const PopupMenuItem(value: 'copy_text', child: Text('Copy text')),
        const PopupMenuItem(value: 'copy_code', child: Text('Copy as code block')),
        if (message.attachmentPath != null && message.inputType == 'image')
          const PopupMenuItem(value: 'copy_image', child: Text('Copy image path')),
        const PopupMenuDivider(),
        if (onStar != null)
          PopupMenuItem(
            value: 'star',
            child: Text(isStarred ? 'Unstar message' : 'Star message'),
          ),
        if (onRetry != null)
          const PopupMenuItem(value: 'retry', child: Text('Retry')),
        if (onFork != null)
          const PopupMenuItem(value: 'fork', child: Text('Fork chat')),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'copy_text':
          Clipboard.setData(ClipboardData(text: message.content));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Message copied')),
            );
          }
          break;
        case 'copy_code':
          Clipboard.setData(ClipboardData(
            text: '```\n${message.content}\n```',
          ));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied as code block')),
            );
          }
          break;
        case 'copy_image':
          if (message.attachmentPath != null) {
            Clipboard.setData(ClipboardData(text: message.attachmentPath!));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Image path copied')),
              );
            }
          }
          break;
        case 'star':
          onStar?.call();
          break;
        case 'retry':
          onRetry?.call();
          break;
        case 'fork':
          onFork?.call();
          break;
      }
    });
  }
}

/// Styled reasoning toggle using ExpansionTile inside a subtle container.
class _AiReasoningTile extends StatefulWidget {
  final String reasoning;
  const _AiReasoningTile({required this.reasoning});

  @override
  State<_AiReasoningTile> createState() => _AiReasoningTileState();
}

class _AiReasoningTileState extends State<_AiReasoningTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        title: Text(
          'Show reasoning',
          style: Platform.isAndroid ? TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.primary,
          ) : GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.primary,
          ),
        ),
          trailing: Icon(
            _expanded ? Icons.remove : Icons.add,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          onExpansionChanged: (val) => setState(() => _expanded = val),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                widget.reasoning,
                style: Platform.isAndroid ? TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontStyle: FontStyle.italic,
                ) : GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}