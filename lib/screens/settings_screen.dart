import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_service.dart';
import 'my_usernames_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const String _appVersion = '1.1.5';

  String _getThemeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
      default:
        return 'System default';
    }
  }

  void _showThemeDialog(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('System default'),
              value: ThemeMode.system,
              groupValue: themeService.themeMode,
              onChanged: (mode) {
                if (mode != null) {
                  themeService.setThemeMode(mode);
                  Navigator.pop(ctx);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: themeService.themeMode,
              onChanged: (mode) {
                if (mode != null) {
                  themeService.setThemeMode(mode);
                  Navigator.pop(ctx);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: themeService.themeMode,
              onChanged: (mode) {
                if (mode != null) {
                  themeService.setThemeMode(mode);
                  Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CB Backup', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          // Profile block
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFF00A884).withValues(alpha: 0.15),
                  child: const Icon(Icons.person, size: 40, color: Color(0xFF00A884)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WhatsApp Backup Viewer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Offline Local Database Archiver',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          const SizedBox(height: 8),

          // Usernames
          ListTile(
            leading: const Icon(Icons.person_outline_rounded, color: Color(0xFF00A884)),
            title: const Text('Usernames', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Manage your aliases for "me" identity detection'),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyUsernamesScreen()),
              );
            },
          ),

          // Theme / Appearance
          ListTile(
            leading: const Icon(Icons.palette_outlined, color: Color(0xFF00A884)),
            title: const Text('Theme', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('Current theme: ${_getThemeLabel(themeService.themeMode)}'),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: () => _showThemeDialog(context, themeService),
          ),

          // Help / About
          ListTile(
            leading: const Icon(Icons.help_outline_rounded, color: Color(0xFF00A884)),
            title: const Text('Help', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Version details, contact support, licenses'),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: () {
              showAboutDialog(

                context: context,
                applicationName: 'CB Backup',
                applicationVersion: 'Version $_appVersion',
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFF00A884).withValues(alpha: 0.15),
                    child: const Icon(Icons.person, color: Color(0xFF00A884)),
                  ),
                ),
                children: const [
                  Text('Offline local database and media archive viewer for WhatsApp exports.'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
