import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/chat_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/message_bubble.dart';
import 'package:flutter_ai_chat_app_openrouter/screens/settings_screen.dart';
import 'package:flutter_ai_chat_app_openrouter/screens/skills_screen.dart';
import 'package:flutter_ai_chat_app_openrouter/services/file_compression_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/audio_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/video_service.dart';

/// Helper to show a top-of-screen notification banner
void _showTopSnackBar(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
      left: 16,
      right: 16,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.inverseSurface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 2), () => entry.remove());
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _showScrollToBottom = false;

  // Search state
  bool _isSearching = false;
  List<int> _searchMatchIndices = [];
  int _currentSearchIndex = -1;
  final _searchFocusNode = FocusNode();

  // Inline attachment bar (stays above keyboard, no bottom sheet)
  bool _showAttachmentBar = false;

  // Drawer search
  final _drawerSearchController = TextEditingController();
  String _drawerSearchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadChats();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _drawerSearchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final threshold = 200.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final isNearBottom = (maxScroll - currentScroll) < threshold;
    if (isNearBottom != !_showScrollToBottom) {
      setState(() {
        _showScrollToBottom = !isNearBottom;
      });
    }
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

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchMatchIndices = [];
        _currentSearchIndex = -1;
      } else {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _onSearchChanged(String query) {
    final chatProvider = context.read<ChatProvider>();
    final messages = chatProvider.messages;
    if (query.isEmpty || messages.isEmpty) {
      setState(() {
        _searchMatchIndices = [];
        _currentSearchIndex = -1;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    final indices = <int>[];
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].content.toLowerCase().contains(lowerQuery)) {
        indices.add(i);
      }
    }

    setState(() {
      _searchMatchIndices = indices;
      _currentSearchIndex = indices.isNotEmpty ? 0 : -1;
    });

    if (indices.isNotEmpty) {
      _scrollToMessage(indices[0]);
    }
  }

  void _scrollToMessage(int messageIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final offset = messageIndex * 80.0; // approximate item height
        _scrollController.animateTo(
          offset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _nextSearchMatch() {
    if (_searchMatchIndices.isEmpty) return;
    final nextIndex = (_currentSearchIndex + 1) % _searchMatchIndices.length;
    setState(() => _currentSearchIndex = nextIndex);
    _scrollToMessage(_searchMatchIndices[nextIndex]);
  }

  void _prevSearchMatch() {
    if (_searchMatchIndices.isEmpty) return;
    final prevIndex = (_currentSearchIndex - 1 + _searchMatchIndices.length) %
        _searchMatchIndices.length;
    setState(() => _currentSearchIndex = prevIndex);
    _scrollToMessage(_searchMatchIndices[prevIndex]);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chatProvider = context.read<ChatProvider>();
    _messageController.clear();

    await chatProvider.sendMessage(text);
    _scrollToBottom();
  }

  // ========================================================================
  // Attachment handling
  // ========================================================================

  /// Toggle the inline attachment bar above the keyboard.
  void _toggleAttachmentBar() {
    setState(() {
      _showAttachmentBar = !_showAttachmentBar;
    });
  }

  /// Pick an image from the camera.
  /// ImagePicker handles the native camera permission dialog automatically.
  Future<void> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (xfile == null) return;

      final file = File(xfile.path);
      final attachment = FileAttachment(
        path: xfile.path,
        name: xfile.name,
        mimeType: 'image/jpeg',
        sizeBytes: await file.length(),
        inputType: 'image',
      );
      if (!mounted) return;
      context.read<ChatProvider>().setPendingAttachment(attachment);
    } catch (e) {
      if (mounted) {
        _showTopSnackBar(context, 'Could not open camera. Check camera permissions in Settings.');
      }
    }
  }

  /// Pick an image from the gallery.
  /// ImagePicker handles the native gallery permission dialog automatically.
  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (xfile == null) return;

      final file = File(xfile.path);
      final attachment = FileAttachment(
        path: xfile.path,
        name: xfile.name,
        mimeType: 'image/jpeg',
        sizeBytes: await file.length(),
        inputType: 'image',
      );
      if (!mounted) return;
      context.read<ChatProvider>().setPendingAttachment(attachment);
    } catch (e) {
      if (mounted) {
        _showTopSnackBar(context, 'Could not open gallery. Check storage permissions in Settings.');
      }
    }
  }

  /// Pick a video from the gallery, check duration, and set as pending attachment.
  /// Frame extraction happens at send time in ChatProvider.
  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickVideo(
        source: ImageSource.gallery,
      );
      if (xfile == null) return;

      final file = File(xfile.path);
      final fileSize = await file.length();

      // Check duration exceeds 60s
      final durationExceeded = await VideoService.checkDuration(xfile.path);
      if (durationExceeded != null) {
        if (mounted) {
          _showTopSnackBar(
            context,
            'Video too long ($durationExceeded.formattedDuration). Maximum is $maxVideoDurationSeconds seconds.',
          );
        }
        return;
      }

      if (!mounted) return;
      final chatProvider = context.read<ChatProvider>();
      chatProvider.setPendingAttachment(
        FileAttachment(
          path: xfile.path,
          name: xfile.name,
          originalName: xfile.name,
          mimeType: 'video/mp4',
          sizeBytes: fileSize,
          inputType: 'video',
        ),
      );
    } catch (e) {
      if (mounted) {
        _showTopSnackBar(context, 'Could not pick video: $e');
      }
    }
  }

  /// Pick a PDF file.
  /// Uses FilePicker with allowedExtensions: ['pdf'] per PLAN.md.
  /// The native OS file picker handles permissions — no runtime permission needed.
  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      final attachment = FileAttachment(
        path: file.path!,
        name: file.name,
        originalName: file.name,
        mimeType: 'application/pdf',
        sizeBytes: file.size,
        inputType: 'pdf',
      );
      if (!mounted) return;
      context.read<ChatProvider>().setPendingAttachment(attachment);
    } catch (e) {
      if (mounted) {
        _showTopSnackBar(context, 'Could not pick PDF file');
      }
    }
  }

  // ========================================================================
  // Audio recording
  // ========================================================================

  /// Show the recording bottom sheet.
  void _showRecordingSheet() {
    final audioService = AudioRecorderService();
    bool isRecording = false;
    Duration recordedDuration = Duration.zero;

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // Use StatefulBuilder so we can update the UI from callbacks
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Mic icon
                    Icon(
                      isRecording ? Icons.mic : Icons.mic_none,
                      size: 56,
                      color: isRecording
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),

                    // Timer display
                    Text(
                      '${recordedDuration.inMinutes.toString().padLeft(2, '0')}:${(recordedDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isRecording ? Colors.red : null,
                          ),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      isRecording ? 'Recording...' : 'Tap to start recording',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Record / Stop button
                    FloatingActionButton.large(
                      heroTag: 'recordButton',
                      backgroundColor: isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
                      onPressed: () async {
                          if (isRecording) {
                            // Stop recording
                            final navigator = Navigator.of(ctx);
                            final path = await audioService.stopRecording();
                            setSheetState(() {
                              isRecording = false;
                            });

                            if (path != null && mounted) {
                              // Show transcribing state
                              navigator.pop(); // close recording sheet
                              _transcribeAndPopulate(path);
                            }
                        } else {
                          // Start recording
                          try {
                            await audioService.startRecording();
                            setSheetState(() {
                              isRecording = true;
                              recordedDuration = Duration.zero;
                            });

                            // Listen to duration
                            audioService.onDurationChanged.listen((duration) {
                              if (mounted) {
                                setSheetState(() {
                                  recordedDuration = duration;
                                });
                              }
                            });
                          } catch (e) {
                            setSheetState(() {
                              isRecording = false;
                            });
                            if (mounted) {
                              _showTopSnackBar(this.context, 'Could not start recording: $e');
                            }
                          }
                        }
                      },
                      child: Icon(
                        isRecording ? Icons.stop : Icons.mic,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Cancel button (only visible when not recording)
                    if (!isRecording)
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Cleanup if the sheet is dismissed while recording
      if (isRecording) {
        audioService.cancelRecording();
      }
      audioService.dispose();
    });
  }

  /// Transcribe an audio file and populate the text field with the result.
  Future<void> _transcribeAndPopulate(String filePath) async {
    // Show a loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Transcribing audio...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final chatProvider = context.read<ChatProvider>();
      final transcribedText = await chatProvider.transcribeAudio(filePath);

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading dialog

      if (transcribedText != null && transcribedText.isNotEmpty) {
        _messageController.text = transcribedText;
        // Move cursor to end
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: transcribedText.length),
        );
        _showTopSnackBar(context, 'Transcription complete');
      } else {
        _showTopSnackBar(context, 'Transcription failed. Check your API key and try again.');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading dialog
      _showTopSnackBar(context, 'Transcription failed: ${e.toString()}');
    } finally {
      // Delete the temporary audio file
      try {
        final file = File(filePath);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: _isSearching ? _buildSearchAppBar(theme) : _buildNormalAppBar(theme),
      drawer: _buildChatListDrawer(context),
      body: Stack(
        children: [
          Column(
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

                    final itemCount = messages.length;
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isFailed = msg.status == 'failed';
                        final isSearchHighlight = _isSearching &&
                            _searchMatchIndices.contains(index) &&
                            _searchMatchIndices[_currentSearchIndex.clamp(0, _searchMatchIndices.length - 1)] == index;
                        return RepaintBoundary(
                          key: ValueKey('bubble_${msg.id}'),
                          child: MessageBubble(
                            key: ValueKey(msg.id),
                            message: msg,
                            isStarred: chatProvider.isMessageStarred(msg.id),
                            showRetry: isFailed && msg.role == 'user',
                            highlight: isSearchHighlight,
                            searchQuery: _isSearching ? _searchController.text : null,
                            onCopy: () {
                              Clipboard.setData(ClipboardData(text: msg.content));
                              _showTopSnackBar(context, 'Message copied');
                            },
                            onStar: () => chatProvider.toggleStar(msg.id),
                            onRetry: isFailed
                                ? () => chatProvider.retryMessage(msg.id)
                                : null,
                            onFork: (msg.role == 'user' || msg.role == 'assistant')
                                ? () => _forkChat(chatProvider, msg.id)
                                : null,
                          ),
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
                          onTap: () => chatProvider.clearError(),
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
          // Jump-to-bottom FAB
          if (_showScrollToBottom)
            Positioned(
              right: 16,
              bottom: 80,
              child: FloatingActionButton.small(
                heroTag: 'scrollToBottom',
                onPressed: _scrollToBottom,
                child: const Icon(Icons.arrow_downward),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(ThemeData theme) {
    return AppBar(
      title: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          if (chatProvider.currentChatId == null) {
            return const Text('AI Chat');
          }
          final chat = chatProvider.currentChat;
          return Text(chat?.title ?? 'Chat');
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: _toggleSearch,
        ),
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
    );
  }

  PreferredSizeWidget _buildSearchAppBar(ThemeData theme) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _toggleSearch,
      ),
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search messages...',
          border: InputBorder.none,
          fillColor: theme.colorScheme.surfaceContainerHighest,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onChanged: _onSearchChanged,
      ),
      actions: [
        if (_searchMatchIndices.isNotEmpty) ...[
          Center(
            child: Text(
              '${_currentSearchIndex + 1} of ${_searchMatchIndices.length}',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            onPressed: _prevSearchMatch,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward),
            onPressed: _nextSearchMatch,
          ),
        ],
      ],
    );
  }

  Future<void> _forkChat(ChatProvider chatProvider, String messageId) async {
    final newChatId = await chatProvider.forkChat(messageId);
    if (newChatId != null && mounted) {
      _showTopSnackBar(context, 'Chat forked');
    }
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

  /// Build an icon-only button for the inline attachment bar (no text, no overflow).
  Widget _buildAttachmentIcon(IconData icon, String tooltip, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Icon(icon, size: 22, color: theme.colorScheme.primary),
        ),
      ),
    );
  }

  /// Build the gallery icon button with a popup for Photo/Video choice.
  Widget _buildGalleryButton(ThemeData theme) {
    return Tooltip(
      message: 'Gallery',
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'photo') {
            _pickFromGallery();
          } else if (value == 'video') {
            _pickVideo();
          }
        },
        offset: const Offset(0, -80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'photo', child: Text('Photo')),
          const PopupMenuItem(value: 'video', child: Text('Video')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Icon(Icons.photo_library, size: 22, color: theme.colorScheme.primary),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attachment preview chip
            Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                final attachment = chatProvider.pendingAttachment;
                if (attachment == null) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        attachment.isImage
                            ? Icons.image
                            : attachment.isPdf
                                ? Icons.picture_as_pdf
                                : Icons.insert_drive_file,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          attachment.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        attachment.formattedSize,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => chatProvider.clearPendingAttachment(),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            // Inline attachment bar (above keyboard, no dismiss)
            if (_showAttachmentBar)
              Container(
                height: 48,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildAttachmentIcon(Icons.camera_alt, 'Camera', _pickFromCamera),
                    _buildGalleryButton(theme),
                    _buildAttachmentIcon(Icons.picture_as_pdf, 'PDF', _pickPdf),
                    _buildAttachmentIcon(Icons.mic, 'Record', _showRecordingSheet),
                  ],
                ),
              ),
            // Text input + buttons
            Row(
              children: [
                // Attachment button — toggles inline bar above keyboard
                Consumer<ChatProvider>(
                  builder: (context, chatProvider, _) {
                    return IconButton(
                      icon: Icon(
                        _showAttachmentBar
                            ? Icons.close
                            : Icons.attach_file,
                        color: _showAttachmentBar
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      tooltip: 'Attach file',
                      onPressed: chatProvider.isSending
                          ? null
                          : _toggleAttachmentBar,
                    );
                  },
                ),
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
                    // Show stop button when sending in THIS chat, send button otherwise
                    final isSendingHere = chatProvider.isSending &&
                        chatProvider.currentChatId == chatProvider.streamingChatId;
                    return FloatingActionButton(
                      mini: true,
                      onPressed: isSendingHere
                          ? () => chatProvider.cancelResponse()
                          : _sendMessage,
                      child: isSendingHere
                          ? const Icon(Icons.stop, size: 18)
                          : const Icon(Icons.send),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Drawer with folders, starred messages, and chat list
  // ========================================================================

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
              // Drawer search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  controller: _drawerSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search chats...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _drawerSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _drawerSearchController.clear();
                              setState(() => _drawerSearchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _drawerSearchQuery = value),
                ),
              ),
              // New Chat
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New Chat'),
                onTap: () {
                  Navigator.pop(context);
                  chatProvider.createChat();
                },
              ),
              // Drawer content: search results or normal structure
              if (_drawerSearchQuery.isNotEmpty)
                ..._buildDrawerSearchResults(chatProvider)
              else ...[
                // Starred messages
                ListTile(
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: const Text('Starred'),
                  trailing: chatProvider.starredMessages.isNotEmpty
                      ? Chip(
                          label: Text(
                            '${chatProvider.starredMessages.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          visualDensity: VisualDensity.compact,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _showStarredMessages(context);
                  },
                ),
                // Folders section (collapsible parent)
                ExpansionTile(
                  leading: const Icon(Icons.folder),
                  title: Text('Folders${chatProvider.folders.isNotEmpty ? ' (${chatProvider.folders.length})' : ''}'),
                  initiallyExpanded: false,
                  children: [
                    // Individual folders
                    ...chatProvider.folders.map((folder) {
                      final folderChatCount = chatProvider.getChatsByFolder(folder.id).length;
                      return ExpansionTile(
                          leading: const Icon(Icons.folder_open, size: 20),
                          title: Text('${folder.name} ($folderChatCount)'),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18),
                            onSelected: (value) {
                              if (value == 'rename') {
                                _showRenameFolderDialog(context, folder.id, folder.name);
                              } else if (value == 'delete') {
                                chatProvider.deleteFolder(folder.id);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'rename', child: Text('Rename')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                          initiallyExpanded: false,
                          children: chatProvider
                              .getChatsByFolder(folder.id)
                              .map((chat) => _buildChatTile(chatProvider, chat))
                              .toList(),
                        );
                    }),
                    // New Folder button inside collapsible section
                    ListTile(
                      leading: const Icon(Icons.create_new_folder_outlined),
                      title: const Text('New Folder'),
                      onTap: () {
                        _showCreateFolderDialog(context);
                      },
                    ),
                  ],
                ),
                // Root folder (no folder) — only show if there are unfiled chats
                if (chatProvider.getChatsByFolder(null).isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'Unfiled',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  ...chatProvider
                      .getChatsByFolder(null)
                      .map((chat) => _buildChatTile(chatProvider, chat)),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  /// Build search results list when user types in the drawer search bar.
  List<Widget> _buildDrawerSearchResults(ChatProvider chatProvider) {
    final query = _drawerSearchQuery.toLowerCase().trim();
    if (query.isEmpty) return [];

    final matchingChats = chatProvider.chats
        .where((c) => c.title.toLowerCase().contains(query))
        .toList();

    if (matchingChats.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: Text(
              'No chats found',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          '${matchingChats.length} result${matchingChats.length == 1 ? '' : 's'}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
      ),
      ...matchingChats.map((chat) => _buildChatTile(chatProvider, chat)),
    ];
  }

  Widget _buildChatTile(ChatProvider chatProvider, ChatsTableData chat) {
    final isGenerating = chatProvider.isChatGenerating(chat.id);
    return ListTile(
      dense: true,
      leading: isGenerating
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chat_bubble_outline, size: 18),
      title: Text(
        chat.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isGenerating
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
      ),
      selected: chat.id == chatProvider.currentChatId,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 16),
        onSelected: (value) {
          if (value == 'rename') {
            _showRenameChatDialog(context, chat.id, chat.title);
          } else if (value == 'move') {
            _showMoveChatDialog(context, chat.id, chat.folderId);
          } else if (value == 'delete') {
            if (chat.id == chatProvider.currentChatId) {
              Navigator.pop(context);
            }
            chatProvider.deleteChat(chat.id);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'move', child: Text('Move to folder')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () {
        Navigator.pop(context);
        chatProvider.selectChat(chat.id);
      },
    );
  }

  // ========================================================================
  // Starred messages — WhatsApp style
  // ========================================================================

  void _showStarredMessages(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          final starredList = chatProvider.starredWithChatInfo;
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Starred Messages', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    Text(
                      '${starredList.length} messages',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: starredList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.star_border, size: 48,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                              const SizedBox(height: 12),
                              Text(
                                'No starred messages yet',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: starredList.length,
                          itemBuilder: (context, index) {
                            final info = starredList[index];
                            final msg = info.message;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: msg.role == 'user'
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.primaryContainer,
                                  child: Icon(
                                    msg.role == 'user' ? Icons.person : Icons.smart_toy_outlined,
                                    size: 18,
                                    color: msg.role == 'user'
                                        ? theme.colorScheme.onPrimary
                                        : theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                title: Text(
                                  msg.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                subtitle: Text(
                                  '${msg.role == 'user' ? 'You' : 'AI'} · ${info.chatTitle}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.open_in_new, size: 18),
                                      tooltip: 'Go to chat',
                                      onPressed: () {
                                        Navigator.pop(context); // close starred
                                        chatProvider.selectChat(msg.chatId);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.star, color: Colors.amber),
                                      onPressed: () => chatProvider.toggleStar(msg.id),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ========================================================================
  // Dialogs
  // ========================================================================

  void _showCreateFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              context.read<ChatProvider>().createFolder(value.trim());
              Navigator.pop(dialogContext);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<ChatProvider>().createFolder(controller.text.trim());
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameFolderDialog(BuildContext context, String id, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              context.read<ChatProvider>().renameFolder(id, value.trim());
              Navigator.pop(dialogContext);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<ChatProvider>().renameFolder(id, controller.text.trim());
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showRenameChatDialog(BuildContext context, String chatId, String currentTitle) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename Chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Chat title',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              context.read<ChatProvider>().renameChat(chatId, value.trim());
              Navigator.pop(dialogContext);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<ChatProvider>().renameChat(chatId, controller.text.trim());
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showMoveChatDialog(BuildContext context, String chatId, String? currentFolderId) {
    final chatProvider = context.read<ChatProvider>();
    final selectedFolderId = ValueNotifier<String?>(currentFolderId);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to folder'),
        content: ValueListenableBuilder<String?>(
          valueListenable: selectedFolderId,
          builder: (context, value, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioGroup<String?>(
                  groupValue: value,
                  onChanged: (v) => selectedFolderId.value = v,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String?>(
                        title: const Text('No folder'),
                        value: null,
                      ),
                      ...chatProvider.folders.map(
                        (folder) => RadioListTile<String?>(
                          title: Text(folder.name),
                          value: folder.id,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: FilledButton(
                    onPressed: () {
                      chatProvider.moveChatToFolder(chatId, selectedFolderId.value);
                      Navigator.pop(dialogContext);
                    },
                    child: const Text('Move'),
                  ),
                ),
              ],
            );
          },
        ),
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