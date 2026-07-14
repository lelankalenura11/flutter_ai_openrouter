import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/skill_provider.dart';
import 'package:flutter_ai_chat_app_openrouter/providers/chat_provider.dart';

class SkillsSheet extends StatefulWidget {
  const SkillsSheet({super.key});

  @override
  State<SkillsSheet> createState() => _SkillsSheetState();
}

class _SkillsSheetState extends State<SkillsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SkillProvider>().loadSkills();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Skills', style: theme.textTheme.titleLarge),
              TextButton.icon(
                onPressed: () => _showAddSkillDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Skill'),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: Consumer<SkillProvider>(
              builder: (context, skillProvider, _) {
                if (skillProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (skillProvider.skills.isEmpty) {
                  return const Center(child: Text('No skills yet'));
                }

                return ListView.builder(
                  itemCount: skillProvider.skills.length,
                  itemBuilder: (context, index) {
                    final skill = skillProvider.skills[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          skill.isBuiltin
                              ? Icons.auto_awesome
                              : Icons.psychology,
                          color: skill.isBuiltin
                              ? theme.colorScheme.primary
                              : theme.colorScheme.secondary,
                        ),
                        title: Text(skill.name),
                        subtitle: Text(
                          skill.systemPrompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow, size: 20),
                              tooltip: 'Use skill',
                              onPressed: () {
                                context
                                    .read<ChatProvider>()
                                    .setSkill(skill.id, skill.systemPrompt);
                                Navigator.pop(context);
                              },
                            ),
                            if (!skill.isBuiltin)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () =>
                                    skillProvider.deleteSkill(skill.id),
                              ),
                          ],
                        ),
                        onTap: () {
                          context
                              .read<ChatProvider>()
                              .setSkill(skill.id, skill.systemPrompt);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSkillDialog(BuildContext context) {
    final nameController = TextEditingController();
    final promptController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Skill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Skill Name',
                hintText: 'e.g., Translator',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: promptController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'System Prompt',
                hintText: 'Describe what this skill does...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isNotEmpty &&
                  promptController.text.isNotEmpty) {
                context
                    .read<SkillProvider>()
                    .createSkill(nameController.text, promptController.text);
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}