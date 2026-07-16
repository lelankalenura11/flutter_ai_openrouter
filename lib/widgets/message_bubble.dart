import 'package:flutter/material.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/rich_content.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/attachment_bubble.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isAssistant = message.role == 'assistant';
    final theme = Theme.of(context);
    final hasAttachment = message.attachmentPath != null && message.inputType != 'text';

    return Padding(
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
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
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
                      // Content text
                      if (message.content.isNotEmpty)
                        RichContent(
                          content: message.content,
                          textStyle: TextStyle(
                            color: isUser
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                          mathColor: isUser
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.primary,
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
                        onPressed: onCopy,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                      ),
                    if (onFork != null)
                      IconButton(
                        icon: const Icon(Icons.call_split, size: 16),
                        tooltip: 'Fork chat from this message',
                        onPressed: onFork,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
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
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
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