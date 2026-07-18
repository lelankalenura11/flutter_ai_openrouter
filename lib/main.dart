import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_ai_chat_app_openrouter/config/theme.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/services/auth_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/openrouter_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/embedding_service.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/chat_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/settings_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/skill_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/search_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/screens/chat_screen.dart';

final AppDatabase _database = AppDatabase();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop platforms (Windows, macOS, Linux)
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(false);

    WindowOptions windowOptions = WindowOptions(
      size: const Size(960, 680),
      center: true,
      minimumSize: const Size(800, 600),
      title: 'AI Chat',
      skipTaskbar: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final openRouterService = OpenRouterService(authService);
    final embeddingService = EmbeddingService(authService);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              ChatProvider(_database, openRouterService, embeddingService),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              SettingsProvider(_database, authService, openRouterService),
        ),
        ChangeNotifierProvider(
          create: (_) => SkillProvider(_database),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatSearchNotifier(),
        ),
      ],
      child: const AppWithTheme(),
    );
  }
}

class AppWithTheme extends StatelessWidget {
  const AppWithTheme({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'AI Chat',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _getThemeMode(settings.theme),
          home: const DesktopAdaptiveWrapper(
            child: ChatScreen(),
          ),
        );
      },
    );
  }

  ThemeMode _getThemeMode(String theme) {
    switch (theme) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

/// A wrapper that initializes desktop-specific features.
/// On desktop platforms this provides keyboard shortcut mapping.
/// On mobile, it's a simple pass-through.
class DesktopAdaptiveWrapper extends StatefulWidget {
  final Widget child;
  const DesktopAdaptiveWrapper({super.key, required this.child});

  @override
  State<DesktopAdaptiveWrapper> createState() => _DesktopAdaptiveWrapperState();
}

class _DesktopAdaptiveWrapperState extends State<DesktopAdaptiveWrapper> {
  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return widget.child;
    }

    // On desktop: wrap with keyboard shortcut handling
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              () => _dispatch('new_chat'),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true,
                  shift: true):
              () => _dispatch('new_folder'),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              () => _dispatch('search'),
          const SingleActivator(LogicalKeyboardKey.keyE, control: true):
              () => _dispatch('focus_input'),
          const SingleActivator(LogicalKeyboardKey.escape):
              () => _dispatch('escape'),
          const SingleActivator(LogicalKeyboardKey.keyC, control: true):
              () => _dispatch('copy_message'),
        },
        child: widget.child,
      ),
    );
  }

  void _dispatch(String action) {
    // Communicate with ChatScreen via notification
    DesktopShortcutNotification(action).dispatch(context);
  }
}

/// Notification dispatched by DesktopAdaptiveWrapper when a keyboard shortcut
/// is triggered. ChatScreen listens for this.
class DesktopShortcutNotification extends Notification {
  final String action;
  const DesktopShortcutNotification(this.action);
}