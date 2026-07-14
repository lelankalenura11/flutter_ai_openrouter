import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_ai_chat_app_openrouter/config/theme.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/services/auth_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/openrouter_service.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/chat_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/settings_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/skill_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/screens/chat_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Create services
    final authService = AuthService();
    final database = AppDatabase();
    final openRouterService = OpenRouterService(authService);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatProvider(database, openRouterService),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(database, authService, openRouterService),
        ),
        ChangeNotifierProvider(
          create: (_) => SkillProvider(database),
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
          home: const ChatScreen(),
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