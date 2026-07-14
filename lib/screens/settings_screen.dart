import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SettingsProvider>();
      provider.loadSettings().then((_) {
        _apiKeyController.text = provider.apiKey;
        _modelController.text = provider.model;
      });
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          if (settings.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // API Key
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OpenRouter API Key',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: _obscureApiKey,
                        decoration: InputDecoration(
                          hintText: 'sk-or-...',
                          suffixIcon: IconButton(
                            icon: Icon(_obscureApiKey
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => _obscureApiKey = !_obscureApiKey),
                          ),
                        ),
                        onChanged: (value) => settings.saveApiKey(value),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: settings.connectionTestRunning
                              ? null
                              : () => settings.testConnection(),
                          icon: settings.connectionTestRunning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_find),
                          label: const Text('Test Connection'),
                        ),
                      ),
                      if (settings.connectionTestResult)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '✓ Connection successful',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (settings.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '✗ ${settings.error}',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Model
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Model', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          hintText: 'openai/gpt-4o',
                          helperText: 'OpenRouter model identifier',
                        ),
                        onChanged: (value) => settings.saveModel(value),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Max Tokens
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Max Tokens', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Slider(
                        value: settings.maxTokens.toDouble(),
                        min: 256,
                        max: 16384,
                        divisions: 63,
                        label: settings.maxTokens.toString(),
                        onChanged: (value) =>
                            settings.saveMaxTokens(value.round()),
                      ),
                      Text(
                        '${settings.maxTokens} tokens',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Temperature
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Temperature', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Slider(
                        value: settings.temperature,
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        label: settings.temperature.toStringAsFixed(1),
                        onChanged: (value) =>
                            settings.saveTemperature(value),
                      ),
                      Text(
                        '${settings.temperature.toStringAsFixed(1)} — ${settings.temperature < 0.5 ? 'More precise' : settings.temperature < 1.0 ? 'Balanced' : 'More creative'}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Theme
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'light', label: Text('Light')),
                          ButtonSegment(
                              value: 'dark', label: Text('Dark')),
                          ButtonSegment(
                              value: 'system', label: Text('System')),
                        ],
                        selected: {settings.theme},
                        onSelectionChanged: (value) =>
                            settings.saveTheme(value.first),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}