import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/chat_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/services/web_search_service.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/widgets/message_bubble.dart';
import 'package:flutter_ai_chat_app_openrouter/screens/settings_screen.dart';
import 'package:flutter_ai_chat_app_openrouter/screens/skills_screen.dart';
import 'package:flutter_ai_chat_app_openrouter/services/file_compression_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/audio_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/video_service.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/search_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/services/clipboard_service.dart';
import 'package:image/image.dart' as img;

/// Helper to show a top-of-screen notification banner
void showTopSnackBar(BuildContext context, String message) {
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
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();
  final AutoScrollController scrollController = AutoScrollController(
    suggestedRowHeight: 120,
  );

  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();
  final GlobalKey activeMatchKey = GlobalKey();

  bool isSearching = false;
  bool showScrollToBottom = false;
  bool showAttachmentBar = false;
  String drawerSearchQuery = '';
  bool sidebarVisible = true;

  // Drawer search
  final _drawerSearchController = TextEditingController();

  // Web search
  bool _isWebSearchEnabled = false;
  bool _isSearchingWeb = false;

  // @ Mention overlay
  bool _showMentionOverlay = false;
  List<FileAttachment> _filteredAttachments = [];
  final List<_MessageAttachmentRef> _chatAttachments = [];

  /// Populate _chatAttachments from the current chat's messages.
  /// Extracts the original file name from the clip emoji prefix in the content field.
  void _refreshChatAttachments() {
    final provider = context.read<ChatProvider>();
    final msgs = provider.messages;
    _chatAttachments.clear();
    for (final msg in msgs) {
      if (msg.attachmentPath != null && msg.attachmentPath!.isNotEmpty) {
        try {
          final file = File(msg.attachmentPath!);
          if (file.existsSync()) {
            String originalName = msg.attachmentPath!.split('/').last;
            if (msg.content.startsWith('\u{1F4CE}')) {
              final newlineIndex = msg.content.indexOf('\n');
              if (newlineIndex > 2) {
                originalName = msg.content.substring(2, newlineIndex).trim();
              }
            }
            _chatAttachments.add(_MessageAttachmentRef(
              path: msg.attachmentPath!,
              originalName: originalName,
              inputType: msg.inputType,
              sizeBytes: file.lengthSync(),
            ));
          }
        } catch (_) {}
      }
    }
  }

  // Pending edit state: tracks user edits so regeneration uses the edited text, not the DB original
  String? _pendingEditMessageId;
  String? _pendingEditText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadChats();
    });
    scrollController.addListener(onScroll);
    messageController.addListener(_handleMentionDetection);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<ChatProvider>().addListener(_onChatChanged);
  }

  @override
  void dispose() {
    messageController.removeListener(_handleMentionDetection);
    // Provider is still available during dispose for StatefulWidget
    try {
      context.read<ChatProvider>().removeListener(_onChatChanged);
    } catch (_) {}
    messageController.dispose();
    scrollController.removeListener(onScroll);
    scrollController.dispose();
    searchController.dispose();
    searchFocusNode.dispose();
    _drawerSearchController.dispose();
    super.dispose();
  }

  void onScroll() {
    if (!scrollController.hasClients) return;

    final threshold = 200.0;
    final maxScroll = scrollController.position.maxScrollExtent;
    final currentScroll = scrollController.position.pixels;
    final isNearBottom = maxScroll - currentScroll <= threshold;

    if (mounted) {
      setState(() {
        showScrollToBottom = !isNearBottom;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ============================================================================
  // SEARCH
  // ============================================================================

  void toggleSearch() {
    final search = context.read<ChatSearchNotifier>();
    if (!isSearching) {
      search.enterSearch();
      searchFocusNode.requestFocus();
    } else {
      search.exitSearch();
      searchController.clear();
      search.clear();
    }
    setState(() => isSearching = !isSearching);
  }

  void onSearchChanged(String query) {
    final chatProvider = context.read<ChatProvider>();
    final search = context.read<ChatSearchNotifier>();
    search.setQuery(query, chatProvider.messages);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToCurrentMatch();
    });
  }

  bool isFullyVisible(BuildContext target) {
    final renderObject = target.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;

    final scrollableState = Scrollable.maybeOf(target);
    final scrollableRenderObject = scrollableState?.context.findRenderObject();
    if (scrollableState == null || scrollableRenderObject is! RenderBox) {
      return true;
    }

    final topLeft = renderObject.localToGlobal(
      Offset.zero,
      ancestor: scrollableRenderObject,
    );
    final bottomRight = renderObject.localToGlobal(
      renderObject.size.bottomRight(Offset.zero),
      ancestor: scrollableRenderObject,
    );

    return topLeft.dy >= 0 && bottomRight.dy <= scrollableRenderObject.size.height;
  }

  Future<void> scrollToCurrentMatch() async {
    if (!mounted) return;

    final search = context.read<ChatSearchNotifier>();
    final currentMatch = search.currentMatch;
    if (currentMatch == null) return;

    final chatProvider = context.read<ChatProvider>();
    final msgIdx = chatProvider.messages.indexWhere(
      (m) => m.id == currentMatch.messageId,
    );
    if (msgIdx == -1) return;

    await scrollController.scrollToIndex(
      msgIdx,
      preferPosition: AutoScrollPosition.middle,
      duration: const Duration(milliseconds: 250),
    );

    if (!mounted) return;

    await WidgetsBinding.instance.endOfFrame;

    final activeContext = activeMatchKey.currentContext;
    if (activeContext != null && activeContext.mounted && !isFullyVisible(activeContext)) {
      await Scrollable.ensureVisible(
        activeContext,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
    }
  }

  void nextSearchMatch() {
    context.read<ChatSearchNotifier>().nextMatch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToCurrentMatch();
    });
  }

  void prevSearchMatch() {
    context.read<ChatSearchNotifier>().previousMatch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToCurrentMatch();
    });
  }

  // ============================================================================
  // END SEARCH
  // ============================================================================

  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    final chatProvider = context.read<ChatProvider>();
    messageController.clear();

    // Web search: if enabled, fetch search results and pass as system context
    // (hidden from the user's message bubble, but visible to the AI)
    if (_isWebSearchEnabled) {
      setState(() => _isSearchingWeb = true);
      final searchContext = await WebSearchService.searchAndFormat(text);
      if (mounted) setState(() => _isSearchingWeb = false);
      if (searchContext.isNotEmpty) {
        await chatProvider.sendMessage(text, systemContext: searchContext);
      } else {
        await chatProvider.sendMessage(text);
      }
    } else {
      await chatProvider.sendMessage(text);
    }

    if (mounted) {
      setState(() => showAttachmentBar = false);
    }
    _scrollToBottom();
  }

  // ========================================================================
  // Attachment handling
  // ========================================================================

  /// Toggle the inline attachment bar above the keyboard.
  void _toggleAttachmentBar() {
    setState(() {
      showAttachmentBar = !showAttachmentBar;
    });
  }

  /// Returns true if the current platform supports camera (not Windows).
  bool get _canUseCamera => !Platform.isWindows;

  /// Pick an image from the camera.
  /// ImagePicker handles the native camera permission dialog automatically.
  Future<void> _pickFromCamera() async {
    if (!_canUseCamera) {
      showTopSnackBar(context, 'Camera is not available on Windows');
      return;
    }
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
        showTopSnackBar(context, 'Could not open camera. Check camera permissions in Settings.');
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
        showTopSnackBar(context, 'Could not open gallery. Check storage permissions in Settings.');
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
          showTopSnackBar(
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
        showTopSnackBar(context, 'Could not pick video: $e');
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
        showTopSnackBar(context, 'Could not pick PDF file');
      }
    }
  }

  // ========================================================================
  // Audio recording
  // ========================================================================

  /// Returns true if audio recording is available on this platform.
  bool get _canRecordAudio => !Platform.isWindows;

  /// Show the recording bottom sheet.
  void _showRecordingSheet() {
    if (!_canRecordAudio) {
      showTopSnackBar(context, 'Audio recording is not available on Windows');
      return;
    }
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
                              showTopSnackBar(this.context, 'Could not start recording: $e');
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
        messageController.text = transcribedText;
        // Move cursor to end
        messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: transcribedText.length),
        );
        showTopSnackBar(context, 'Transcription complete');
      } else {
        showTopSnackBar(context, 'Transcription failed. Check your API key and try again.');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading dialog
      showTopSnackBar(context, 'Transcription failed: ${e.toString()}');
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
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final screenWidth = MediaQuery.of(context).size.width;
    final showPersistentSidebar = isDesktop && screenWidth >= 900;

    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
          switch (event.logicalKey) {
            case LogicalKeyboardKey.keyN:
              // Ctrl+N = new chat (Shift+Ctrl+N = new folder)
              if (HardwareKeyboard.instance.isShiftPressed) {
                _showCreateFolderDialog(context);
              } else {
                context.read<ChatProvider>().createChat();
              }
              return KeyEventResult.handled;
            case LogicalKeyboardKey.keyF:
              toggleSearch();
              return KeyEventResult.handled;
            case LogicalKeyboardKey.keyE:
              messageController.selection = TextSelection.fromPosition(
                TextPosition(offset: messageController.text.length),
              );
              return KeyEventResult.handled;
            case LogicalKeyboardKey.keyV:
              _handlePasteClipboard();
              return KeyEventResult.handled;
            case LogicalKeyboardKey.keyC:
              if (HardwareKeyboard.instance.isShiftPressed) {
                _handleCopyMessage();
                return KeyEventResult.handled;
              }
              break;
          }
        }
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          if (isSearching) {
            toggleSearch();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
          appBar: isSearching ? buildSearchAppBar(theme) : _buildNormalAppBar(theme, isDesktop, showPersistentSidebar),
          drawer: showPersistentSidebar ? null : _buildChatListDrawer(context),
          // On desktop with wide screen, use a persistent sidebar
          body: Row(
            children: [
              // Collapsible persistent sidebar on desktop
              if (showPersistentSidebar && sidebarVisible)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 280,
                  child: Material(
                    elevation: 1,
                    child: _buildSidebarContent(),
                  ),
                ),
              // Main chat area with drag & drop support
              Expanded(
                child: DropTarget(
                  onDragDone: (detail) {
                    _handleDroppedFiles(detail.files);
                  },
                  onDragEntered: (detail) {
                    // Visual feedback handled by drag overlay
                  },
                  onDragExited: (detail) {
                    // Reset visual feedback
                  },
                  child: Stack(
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
                            child: Consumer2<ChatProvider, ChatSearchNotifier>(
                              builder: (context, chatProvider, search, _) {
                                if (chatProvider.isLoading) {
                                  return const Center(child: CircularProgressIndicator());
                                }

                                if (chatProvider.currentChatId == null) {
                                  return buildWelcomeMessage(context);
                                }

                                final messages = chatProvider.messages;
                                if (messages.isEmpty) {
                                  return const Center(child: Text('Start a conversation!'));
                                }

                                final currentMatch = search.currentMatch;

                                return ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                  itemCount: messages.length,
                                  itemBuilder: (context, index) {
                                    final msg = messages[index];
                                    final isFailed = msg.status == 'failed';

                                    final isSearchHighlight =
                                        isSearching &&
                                        currentMatch != null &&
                                        currentMatch.messageId == msg.id;

                                    return AutoScrollTag(
                                      key: ValueKey('scrolltag-${msg.id}'),
                                      controller: scrollController,
                                      index: index,
                                      child: RepaintBoundary(
                                        key: ValueKey('bubble-${msg.id}'),
                                        child: MessageBubble(
                                          key: ValueKey('msgwidget-${msg.id}'),
                                          message: msg,
                                          activeMatchStart: isSearchHighlight ? currentMatch.start : null,
                                          activeMatchEnd: isSearchHighlight ? currentMatch.end : null,
                                          activeMatchKey: isSearchHighlight ? activeMatchKey : null,
                                          isStarred: chatProvider.isMessageStarred(msg.id),
                                          showRetry: isFailed && msg.role == 'user',
                                          highlight: isSearchHighlight,
                                          searchQuery: isSearching ? searchController.text : null,
                                          onCopy: () {
                                            Clipboard.setData(ClipboardData(text: msg.content));
                                            showTopSnackBar(context, 'Message copied');
                                          },
                                          onStar: () => chatProvider.toggleStar(msg.id),
                                          onRetry: isFailed
                                              ? () => chatProvider.retryMessage(msg.id)
                                              : null,
                                          onFork: (msg.role == 'user' || msg.role == 'assistant')
                                              ? () => forkChat(chatProvider, msg.id)
                                              : null,
                                          onRegenerate: msg.role == 'assistant' && msg.status == 'sent'
                                              ? () => _handleRegenerate(chatProvider, msg.id)
                                              : null,
                                          onEdit: msg.role == 'user' && msg.status == 'sent'
                                              ? () => _handleEditMessage(chatProvider, msg)
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          // Error banner — only rebuilds when error changes
                          Selector<ChatProvider, String?>(
                            selector: (_, p) => p.error,
                            builder: (context, error, _) {
                            if (error == null) return const SizedBox.shrink();
                            final chatProvider = context.read<ChatProvider>();
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
                                      error,
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
                      if (showScrollToBottom)
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
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Refresh chat attachments when messages change.
  void _onChatChanged() {
    _refreshChatAttachments();
  }

  /// Handle files dropped from the OS onto the chat area.
  Future<void> _handleDroppedFiles(List<DropItem> files) async {
    final chatProvider = context.read<ChatProvider>();
    for (final file in files) {
      final path = file.path;
      final name = file.name;
      final ext = name.split('.').last.toLowerCase();
      if (ext.isEmpty) continue;

      String mimeType;
      String inputType;
      if (ext == 'pdf') {
        mimeType = 'application/pdf';
        inputType = 'pdf';
      } else if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
        mimeType = 'image/$ext';
        inputType = 'image';
      } else if (['mp4', 'avi', 'mov', 'mkv'].contains(ext)) {
        mimeType = 'video/$ext';
        inputType = 'video';
      } else {
        mimeType = 'application/octet-stream';
        inputType = 'file';
      }

      final fileSize = await File(path).length();
      if (!mounted) return;
      chatProvider.setPendingAttachment(
        FileAttachment(
          path: path,
          name: name,
          originalName: name,
          mimeType: mimeType,
          sizeBytes: fileSize,
          inputType: inputType,
        ),
      );
      if (!mounted) return;
      showTopSnackBar(context, 'File attached: $name');
      break; // Only handle the first dropped file for now
    }
  }

  /// Handle Ctrl+V: first try to paste an image from clipboard.
  /// If no image is available, falls back to text paste.
  Future<void> _handlePasteClipboard() async {
    // 1. Check for image first using the native channel
    final imageBytes = await ClipboardService.getClipboardImage();
    
    if (imageBytes != null) {
      // Detect format from magic bytes and convert BMP to PNG
      String extension = 'png';
      String mimeType = 'image/png';
      Uint8List finalBytes = imageBytes;
      
      if (imageBytes.length >= 2 && imageBytes[0] == 0x42 && imageBytes[1] == 0x4D) {
        // BMP — convert to PNG for Flutter compatibility
        final decoded = img.decodeImage(imageBytes);
        if (decoded != null) {
          finalBytes = Uint8List.fromList(img.encodePng(decoded));
        }
      } else if (imageBytes.length >= 8 && imageBytes[0] == 0x89 && imageBytes[1] == 0x50) {
        // Already PNG
      } else if (imageBytes.length >= 3 && imageBytes[0] == 0xFF && imageBytes[1] == 0xD8) {
        extension = 'jpg';
        mimeType = 'image/jpeg';
      } else if (imageBytes.length >= 4 && imageBytes[0] == 0x47 && imageBytes[1] == 0x49) {
        extension = 'gif';
        mimeType = 'image/gif';
      } else if (imageBytes.length >= 4 && imageBytes[0] == 0x52 && imageBytes[1] == 0x49) {
        extension = 'webp';
        mimeType = 'image/webp';
      }

      final tempDir = await Directory.systemTemp.createTemp('clipboard_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'clipboard_image_$timestamp.$extension';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(finalBytes);
      
      final fileSize = await file.length();
      if (!mounted) return;
      final chatProvider = context.read<ChatProvider>();
      chatProvider.setPendingAttachment(
        FileAttachment(
          path: filePath,
          name: fileName,
          originalName: fileName,
          mimeType: mimeType,
          sizeBytes: fileSize,
          inputType: 'image',
        ),
      );
      if (!mounted) return;
      showTopSnackBar(context, 'Image pasted from clipboard');
      return;
    }

    // 2. If no image, fallback to text paste
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData != null && clipboardData.text!.isNotEmpty) {
      final currentText = messageController.text;
      final selection = messageController.selection;
      final cursorPos = selection.isValid ? selection.baseOffset : currentText.length;
      final newText = currentText.substring(0, cursorPos) +
          clipboardData.text! +
          currentText.substring(cursorPos);
      messageController.text = newText;
      messageController.selection = TextSelection.collapsed(
        offset: cursorPos + clipboardData.text!.length,
      );
    }
  }

  /// Handle Ctrl+Shift+C: copy the last AI message to clipboard.
  void _handleCopyMessage() {
    final chatProvider = context.read<ChatProvider>();
    final msgs = chatProvider.messages;
    if (msgs.isNotEmpty) {
      final lastMsg = msgs.last;
      Clipboard.setData(ClipboardData(text: lastMsg.content));
      showTopSnackBar(context, 'Last message copied');
    }
  }

  /// Handle "Try again" on an AI message — finds the preceding user message and re-sends it.
  /// Uses edited text from the controller if the user edited the message first.
  Future<void> _handleRegenerate(ChatProvider chatProvider, String assistantMsgId) async {
    final messages = chatProvider.messages;
    final idx = messages.indexWhere((m) => m.id == assistantMsgId);
    if (idx <= 0) return; // No preceding user message

    // Find the preceding user message
    for (int i = idx - 1; i >= 0; i--) {
      if (messages[i].role == 'user') {
        // Check if there's a pending edit for this message
        if (messages[i].id == _pendingEditMessageId && _pendingEditText != null) {
          // Use the edited text and clear the pending state
          await chatProvider.sendMessage(_pendingEditText!, messageIdToReplace: messages[i].id);
          _pendingEditMessageId = null;
          _pendingEditText = null;
        } else {
          await chatProvider.retryMessage(messages[i].id);
        }
        return;
      }
    }
  }

  /// Tracks the text the user typed in the message controller after "Edit & Retry",
  /// so that regenerate uses the updated text rather than the DB original.
  void _updatePendingEditText() {
    if (_pendingEditMessageId != null) {
      final text = messageController.text.trim();
      if (text.isNotEmpty) {
        _pendingEditText = text;
      }
    }
  }

  /// Handle "Edit & Retry" on a user message — copies text and attachment to input without deleting anything.
  Future<void> _handleEditMessage(ChatProvider chatProvider, MessagesTableData msg) async {
    messageController.text = msg.content;
    _pendingEditMessageId = msg.id;
    _pendingEditText = msg.content;
    messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: msg.content.length),
    );
    // Copy attachment to input if present
    if (msg.attachmentPath != null) {
      final file = File(msg.attachmentPath!);
      if (await file.exists()) {
        chatProvider.setPendingAttachment(
          FileAttachment(
            path: msg.attachmentPath!,
            name: msg.attachmentPath!.split('/').last,
            originalName: msg.attachmentPath!.split('/').last,
            mimeType: msg.inputType == 'image' ? 'image/png' : 'application/pdf',
            sizeBytes: await file.length(),
            inputType: msg.inputType,
          ),
        );
      }
    }
    // No deletion — chat history stays intact
  }

  /// Build the persistent sidebar content (desktop-adaptive version of drawer).
  Widget _buildSidebarContent() {
    return Selector<ChatProvider, List<ChatsTableData>>(
      selector: (_, provider) => provider.chats,
      shouldRebuild: (prev, next) {
        if (prev.length != next.length) return true;
        for (int i = 0; i < prev.length; i++) {
          if (prev[i].id != next[i].id ||
              prev[i].title != next[i].title ||
              prev[i].isPinned != next[i].isPinned) {
            return true;
          }
        }
        return false;
      },
      builder: (context, chats, _) {
        final chatProvider = context.read<ChatProvider>();
        return Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Chat',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${chatProvider.chats.length} chats',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: TextField(
                controller: _drawerSearchController,
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: drawerSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _drawerSearchController.clear();
                            setState(() => drawerSearchQuery = '');
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
                onChanged: (value) => setState(() => drawerSearchQuery = value),
              ),
            ),
            // New Chat button
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New Chat'),
              onTap: () => chatProvider.createChat(),
            ),
            // Scrollable chat list
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Starred messages
                  ListTile(
                    leading: const Icon(Icons.star, color: Colors.amber),
                    title: const Text('Starred'),
                    dense: true,
                    trailing: chatProvider.starredMessages.isNotEmpty
                        ? Chip(
                            label: Text(
                              '${chatProvider.starredMessages.length}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                    onTap: () => _showStarredMessages(context),
                  ),
                  // Folders section
                  Material(
                    type: MaterialType.transparency,
                    child: ExpansionTile(
                      leading: const Icon(Icons.folder),
                      title: Text('Folders${chatProvider.folders.isNotEmpty ? ' (${chatProvider.folders.length})' : ''}'),
                      initiallyExpanded: false,
                      children: [
                        ...chatProvider.folders.map((folder) {
                          final folderChatCount = chatProvider.getChatsByFolder(folder.id).length;
                          return Material(
                            type: MaterialType.transparency,
                            child: ExpansionTile(
                              leading: const Icon(Icons.folder_open, size: 20),
                              title: Text('${folder.name} ($folderChatCount)'),
                              dense: true,
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
                                  .map((chat) => _buildChatTile(chatProvider, chat, isInSidebar: true))
                                  .toList(),
                            ),
                          );
                        }),
                        ListTile(
                          leading: const Icon(Icons.create_new_folder_outlined),
                          title: const Text('New Folder'),
                          dense: true,
                          onTap: () => _showCreateFolderDialog(context),
                        ),
                      ],
                    ),
                  ),
                  // Unfiled chats
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
                        .map((chat) => _buildChatTile(chatProvider, chat, isInSidebar: true)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  PreferredSizeWidget _buildNormalAppBar(ThemeData theme, [bool isDesktop = false, bool showSidebar = false]) {
    return AppBar(
      leading: (isDesktop && showSidebar)
          ? IconButton(
              icon: Icon(sidebarVisible ? Icons.menu_open : Icons.menu),
              tooltip: sidebarVisible ? 'Close sidebar' : 'Open sidebar',
              onPressed: () => setState(() => sidebarVisible = !sidebarVisible),
            )
          : null,
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
        if (isDesktop && showSidebar && !sidebarVisible)
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Show chat list',
            onPressed: () => setState(() => sidebarVisible = true),
          ),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: toggleSearch,
        ),
        IconButton(
          icon: const Icon(Icons.psychology_outlined),
          tooltip: 'Skills',
          onPressed: () => _showSkillsDrawer(context),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () => _openSettings(context),
        ),
      ],
    );
  }

  void _openSettings(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (isDesktop) {
      // Open as a half-screen dialog on desktop
      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: SizedBox(
            width: 600,
            child: SettingsScreen(),
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }
  }

  PreferredSizeWidget buildSearchAppBar(ThemeData theme) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: toggleSearch,
      ),
      title: TextField(
        controller: searchController,
        focusNode: searchFocusNode,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search messages...',
          border: InputBorder.none,
          fillColor: theme.colorScheme.surfaceContainerHighest,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onChanged: onSearchChanged,
      ),
      actions: [
        Consumer<ChatSearchNotifier>(
          builder: (context, search, _) {
            return Text(
              search.hasMatches
                  ? '${search.currentMatchIndex + 1}/${search.matches.length}'
                  : '0/0',
              style: const TextStyle(fontSize: 14),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.arrow_upward),
          onPressed: prevSearchMatch,
        ),
        IconButton(
          icon: const Icon(Icons.arrow_downward),
          onPressed: nextSearchMatch,
        ),
      ],
    );
  }

  Future<void> forkChat(ChatProvider chatProvider, String messageId) async {
    final newChatId = await chatProvider.forkChat(messageId);
    if (newChatId != null && mounted) {
      showTopSnackBar(context, 'Chat forked');
    }
  }

  Widget buildWelcomeMessage(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
            if (showAttachmentBar)
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
            // Web searching indicator
            if (_isSearchingWeb)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('Searching the web...',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            // PDF preparing indicator
            Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                if (!chatProvider.isPreparingPdf) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text('Preparing PDF...',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                );
              },
            ),
            // @ Mention overlay
            if (_showMentionOverlay && _filteredAttachments.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredAttachments.length,
                  itemBuilder: (context, index) {
                    final att = _filteredAttachments[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        att.isImage ? Icons.image : att.isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(att.originalName, style: const TextStyle(fontSize: 13)),
                      onTap: () {
                        context.read<ChatProvider>().setPendingAttachment(att);
                        final text = messageController.text;
                        final atIndex = text.lastIndexOf('@');
                        if (atIndex != -1) {
                          messageController.text = text.substring(0, atIndex);
                          messageController.selection = TextSelection.fromPosition(
                            TextPosition(offset: messageController.text.length),
                          );
                        }
                        setState(() => _showMentionOverlay = false);
                      },
                    );
                  },
                ),
              ),
            // Text input + buttons — icons beside text, expands up to 2 lines
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment button — toggles inline bar above keyboard
                Consumer<ChatProvider>(
                  builder: (context, chatProvider, _) {
                    return IconButton(
                      icon: Icon(
                        showAttachmentBar
                            ? Icons.close
                            : Icons.attach_file,
                        color: showAttachmentBar
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
                    controller: messageController,
                    textInputAction: TextInputAction.send,
                    maxLines: 2,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Message',
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
                    onChanged: (_) => _updatePendingEditText(),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                // Web search toggle button — more visible when enabled
                Consumer<ChatProvider>(
                  builder: (context, chatProvider, _) {
                    return Container(
                      decoration: _isWebSearchEnabled
                          ? BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            )
                          : null,
                      child: IconButton(
                        icon: Icon(
                          _isWebSearchEnabled ? Icons.language : Icons.language_outlined,
                          color: _isWebSearchEnabled
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        tooltip: _isWebSearchEnabled ? 'Web Search (on)' : 'Web Search',
                        onPressed: chatProvider.isSending
                            ? null
                            : () => setState(() => _isWebSearchEnabled = !_isWebSearchEnabled),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
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
      child: Selector<ChatProvider, List<ChatsTableData>>(
        selector: (_, provider) => provider.chats,
        shouldRebuild: (prev, next) {
          if (prev.length != next.length) return true;
          for (int i = 0; i < prev.length; i++) {
            if (prev[i].id != next[i].id ||
                prev[i].title != next[i].title ||
                prev[i].isPinned != next[i].isPinned) {
              return true;
            }
          }
          return false;
        },
        builder: (context, chats, _) {
          final chatProvider = context.read<ChatProvider>();
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
                    suffixIcon: drawerSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _drawerSearchController.clear();
                              setState(() => drawerSearchQuery = '');
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
                  onChanged: (value) => setState(() => drawerSearchQuery = value),
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
              if (drawerSearchQuery.isNotEmpty)
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
                Material(
                  type: MaterialType.transparency,
                  child: ExpansionTile(
                    leading: const Icon(Icons.folder),
                    title: Text('Folders${chatProvider.folders.isNotEmpty ? ' (${chatProvider.folders.length})' : ''}'),
                    initiallyExpanded: false,
                    children: [
                      // Individual folders
                      ...chatProvider.folders.map((folder) {
                        final folderChatCount = chatProvider.getChatsByFolder(folder.id).length;
                        return Material(
                          type: MaterialType.transparency,
                          child: ExpansionTile(
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
                              .map((chat) => Material(
                                type: MaterialType.transparency,
                                child: _buildChatTile(chatProvider, chat),
                              ))
                              .toList(),
                            ),
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
    final query = drawerSearchQuery.toLowerCase().trim();
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
      ...matchingChats.map((chat) => _buildChatTile(chatProvider, chat, isInSidebar: true)),
    ];
  }

  Widget _buildChatTile(ChatProvider chatProvider, ChatsTableData chat, {bool isInSidebar = false}) {
    final isGenerating = chatProvider.isChatGenerating(chat.id);
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: isGenerating
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              chat.isPinned ? Icons.push_pin : Icons.chat_bubble_outline,
              size: 18,
              color: chat.isPinned ? theme.colorScheme.primary : null,
            ),
      title: Text(
        chat.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isGenerating
              ? theme.colorScheme.primary
              : null,
        ),
      ),
      selected: chat.id == chatProvider.currentChatId,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pin/unpin button
          IconButton(
            icon: Icon(
              chat.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 16,
              color: chat.isPinned ? theme.colorScheme.primary : Colors.grey,
            ),
            onPressed: () => chatProvider.togglePinChat(chat.id),
            tooltip: chat.isPinned ? 'Unpin' : 'Pin',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16),
            onSelected: (value) {
              if (value == 'rename') {
                _showRenameChatDialog(context, chat.id, chat.title);
              } else if (value == 'move') {
                _showMoveChatDialog(context, chat.id, chat.folderId);
              } else if (value == 'delete') {
                if (chat.id == chatProvider.currentChatId && !isInSidebar) {
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
        ],
      ),
      onTap: () {
        if (!isInSidebar) {
          Navigator.pop(context);
        }
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

  /// Detects `@` mentions and shows/hides the attachment overlay.
  void _handleMentionDetection() {
    if (!mounted) return;
    final text = messageController.text;

    // 1. Find the LAST '@' character typed
    final atIndex = text.lastIndexOf('@');

    // If no '@' exists, hide the overlay
    if (atIndex == -1) {
      if (_showMentionOverlay && mounted) setState(() => _showMentionOverlay = false);
      return;
    }

    // 2. Check what is immediately BEFORE the '@'
    final isAtStart = atIndex == 0;
    final hasSpaceBefore = atIndex > 0 && text[atIndex - 1] == ' ';

    // If it's an email (e.g., "x@gmail.com"), the character before '@' is not a space.
    if (!isAtStart && !hasSpaceBefore) {
      if (_showMentionOverlay && mounted) setState(() => _showMentionOverlay = false);
      return;
    }

    // 3. Extract the query after '@' (until next space)
    String query = '';
    if (text.length > atIndex + 1) {
      final afterAt = text.substring(atIndex + 1);
      final spaceIndex = afterAt.indexOf(' ');
      query = spaceIndex == -1 ? afterAt : afterAt.substring(0, spaceIndex);
    }

    // 4. If user typed a space right after '@', hide
    if (query.isEmpty && text.length > atIndex + 1 && text[atIndex + 1] == ' ') {
      if (_showMentionOverlay && mounted) setState(() => _showMentionOverlay = false);
      return;
    }

    // 5. Valid mention — filter attachments
    if (!mounted) return;
    setState(() {
      _showMentionOverlay = true;
      _filteredAttachments = _chatAttachments
          .where((a) => a.originalName.toLowerCase().contains(query.toLowerCase()))
          .map((ref) => ref.toFileAttachment())
          .toList();
    });
  }
}

/// Lightweight reference to a file attachment found in chat messages.
class _MessageAttachmentRef {
  final String path;
  final String originalName;
  final String inputType;
  final int sizeBytes;

  const _MessageAttachmentRef({
    required this.path,
    required this.originalName,
    required this.inputType,
    required this.sizeBytes,
  });

  FileAttachment toFileAttachment() => FileAttachment(
        path: path,
        name: originalName,
        originalName: originalName,
        mimeType: inputType == 'image'
            ? 'image/png'
            : inputType == 'pdf'
                ? 'application/pdf'
                : 'application/octet-stream',
        sizeBytes: sizeBytes,
        inputType: inputType,
      );
}
