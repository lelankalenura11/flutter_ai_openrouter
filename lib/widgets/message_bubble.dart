import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/rich_content.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/attachment_bubble.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/search_provider.dart';

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
        final offset =
            -8.0 * (0.5 - 0.5 * (1.0 - animValue) * (1.0 - animValue));
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
  final bool highlight;
  final String? searchQuery;
  final ChatSearchNotifier? searchNotifier;

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
    this.highlight = false,
    this.searchQuery,
    this.searchNotifier,
  });

  /// Compute the max bubble width once instead of calling MediaQuery per frame.
  static double _maxBubbleWidth(BuildContext context) {
    return MediaQuery.of(context).size.width * 0.75;
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
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: _maxBubbleWidth(context),
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: highlight
                        ? Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reasoning section (collapsible)
                      if (isAssistant &&
                          message.reasoning != null &&
                          message.reasoning!.isNotEmpty)
                        _ReasoningToggle(reasoning: message.reasoning!),
                      // Attachment preview (image, PDF, file)
                      if (hasAttachment)
                        AttachmentBubble(
                          attachmentPath: message.attachmentPath!,
                          inputType: message.inputType,
                          isUser: isUser,
                        ),
                      // Streaming three dots (when content empty and generating)
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
                      // Content text — always visible during streaming even if empty
                      if (isStreaming || message.content.isNotEmpty)
                        RichContent(
                          content:
                              message.content + (isStreaming ? ' ▎' : ''),
                          textStyle: TextStyle(
                            color: isUser
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                          mathColor: isUser
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.primary,
                          searchQuery: searchQuery,
                        ),
                      // Failed state
                      if (showRetry)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 14,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Failed to send',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (onRetry != null)
                                TextButton.icon(
                                  onPressed: onRetry,
                                  icon: const Icon(Icons.refresh, size: 14),
                                  label: const Text('Retry',
                                      style: TextStyle(fontSize: 11)),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      // Token count
                      if (showTokenCount &&
                          isAssistant &&
                          (message.inputTokens != null ||
                              message.outputTokens != null))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '⬆${message.inputTokens ?? 0} ⬇${message.outputTokens ?? 0} tokens',
                            style: TextStyle(
                              fontSize: 10,
                              color: (isUser
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface)
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onCopy != null)
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Copy message',
                        onPressed: onCopy,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    if (onFork != null)
                      IconButton(
                        icon: const Icon(Icons.call_split, size: 16),
                        tooltip: 'Fork chat from this message',
                        onPressed: onFork,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    if (onStar != null)
                      IconButton(
                        icon: Icon(
                          isStarred ? Icons.star : Icons.star_border,
                          size: 16,
                          color: isStarred ? Colors.amber : null,
                        ),
                        onPressed: onStar,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                  ],
                ),
              ],
            ),
          ),
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

    // On desktop, wrap with right-click context menu
    if (isDesktop) {
      return GestureDetector(
        onSecondaryTap: () => _showContextMenu(context),
        child: bubbleContent,
      );
    }

    return bubbleContent;
  }

  /// Show a right-click context menu with clipboard and action options.
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
        const PopupMenuItem(
            value: 'copy_code', child: Text('Copy as code block')),
        if (message.attachmentPath != null && message.inputType == 'image')
          const PopupMenuItem(
              value: 'copy_image', child: Text('Copy image path')),
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
            Clipboard.setData(
                ClipboardData(text: message.attachmentPath!));
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

class _ReasoningToggle extends StatefulWidget {
  final String reasoning;
  const _ReasoningToggle({required this.reasoning});

  @override
  State<_ReasoningToggle> createState() => _ReasoningToggleState();
}

class _ReasoningToggleState extends State<_ReasoningToggle> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                _expanded ? 'Hide reasoning' : 'Show reasoning',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              widget.reasoning,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}