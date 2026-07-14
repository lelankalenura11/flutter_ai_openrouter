import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/chat_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/message_bubble.dart';
import 'package:flutter_ai_chat_app_openrouter/screens/settings_screen.dart';
import 'package:flutter_ai_chat_app_openrouter/screens/skills_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadChats();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chatProvider = context.read<ChatProvider>();
    _messageController.clear();

    if (chatProvider.currentChatId == null) {
      final id = await chatProvider.createChat(
        skillId: chatProvider.activeSkillId,
      );
      if (id == null) return;
    }

    await chatProvider.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Consumer<ChatProvider>(
          builder: (context, chatProvider, _) {
            if (chatProvider.currentChatId == null) {
              return const Text('AI Chat');
            }
            final chat = chatProvider.chats
                .where((c) => c.id == chatProvider.currentChatId)
                .firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chat?.title ?? 'Chat'),
                if (chat != null)
                  Text(
                    '⬆${chat.totalInputTokens} ⬇${chat.totalOutputTokens} tokens',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_outlined),
            tooltip: 'Skills',
            onPressed: () => _showSkillsDrawer(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      drawer: _buildChatListDrawer(context),
      body: Column(
        children: [
          // Skill indicator
          Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              if (chatProvider.activeSkillPrompt == null) {
                return const SizedBox.shrink();
              }
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                color: theme.colorScheme.primaryContainer,
                child: Row(
                  children: [
                    Icon(Icons.psychology,
                        size: 14, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      'Using skill: ${chatProvider.activeSkillId?.replaceAll('builtin_', '').replaceAll('_', ' ') ?? 'Custom'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => chatProvider.setSkill(null, null),
                      child: Icon(Icons.close,
                          size: 14,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ],
                ),
              );
            },
          ),
          // Messages
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                if (chatProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (chatProvider.currentChatId == null) {
                  return _buildWelcomeMessage(context);
                }

                final messages = chatProvider.messages;
                if (messages.isEmpty) {
                  return const Center(child: Text('Start a conversation!'));
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return MessageBubble(
                      message: msg,
                      onCopy: () {
                        Clipboard.setData(ClipboardData(text: msg.content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Message copied'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                      onStar: () async {
                        await chatProvider._toggleStar(msg.id);
                      },
                    );
                  },
                );
              },
            ),
          ),
          // Error banner
          Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              if (chatProvider.error == null) {
                return const SizedBox.shrink();
              }
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: theme.colorScheme.errorContainer,
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chatProvider.error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => chatProvider._clearError(),
                      child: Icon(Icons.close,
                          size: 14,
                          color: theme.colorScheme.onErrorContainer),
                    ),
                  ],
                ),
              );
            },
          ),
          // Input area
          _buildInputArea(context),
        ],
      ),
    );
  }

  Widget _buildWelcomeMessage(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'AI Chat',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Type a message to start a conversation\nor select a chat from the menu.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                textInputAction: TextInputAction.send,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                return FloatingActionButton(
                  mini: true,
                  onPressed: chatProvider.isSending ? null : _sendMessage,
                  child: chatProvider.isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatListDrawer(BuildContext context) {
    return Drawer(
      child: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'AI Chat',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${chatProvider.chats.length} chats',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New Chat'),
                onTap: () {
                  Navigator.pop(context);
                  chatProvider.createChat();
                },
              ),
              const Divider(),
              ...chatProvider.chats.map((chat) => ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: chat.id == chatProvider.currentChatId,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => chatProvider.deleteChat(chat.id),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      chatProvider.selectChat(chat.id);
                    },
                  )),
            ],
          );
        },
      ),
    );
  }

  void _showSkillsDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SkillsSheet(),
    );
  }
}

extension ChatProviderPrivate on ChatProvider {
  Future<void> _toggleStar(String messageId) => toggleStar(messageId);
  void _clearError() => clearError();
}
