import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../services/chat_repository.dart';
import '../services/self_identity_service.dart';
import '../widgets/self_chooser_dialog.dart';
import 'chat_screen.dart';
import 'my_usernames_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _importing = false;

  Future<void> _importChat(BuildContext context) async {
    setState(() => _importing = true);
    try {
      final repo = context.read<ChatRepository>();
      final chat = await repo.importFromPicker();
      if (chat != null && mounted) {
        await _maybePromptForSelf(context, chat);
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $msg')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _loadSample(BuildContext context) async {
    setState(() => _importing = true);
    try {
      final repo = context.read<ChatRepository>();
      // Relative to project root for demo. Title will be parsed from "WhatsApp Chat - Rashmi Arya.zip"
      const samplePath = 'sample/WhatsApp Chat - Rashmi Arya.zip';
      final chat = await repo.importSample(samplePath);
      if (chat != null && mounted) {
        await _maybePromptForSelf(context, chat);
        setState(() {});
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sample zip not found at sample/ directory')),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sample import failed: $msg')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _maybePromptForSelf(BuildContext context, Chat chat) async {
    final identity = context.read<SelfIdentityService>();

    // Try to auto-resolve using my usernames (priority order) or 1:1 title logic
    final autoSelf = identity.resolveSelfForChat(
      chat.participants,
      chatTitle: chat.title,
      chatId: chat.id,
    );

    if (autoSelf != null && autoSelf.isNotEmpty) {
      await identity.setSelfForChat(chat.id, autoSelf); // auto-add happens inside
      return; // no prompt needed
    }

    // Only allow choosing from configured (allowed) usernames if any match in this chat
    List<String> chooserCandidates = chat.participants;
    final allowed = identity.myUsernames.where((u) =>
        chat.participants.any((p) => p.toLowerCase() == u.toLowerCase())).toList();
    if (allowed.isNotEmpty) {
      chooserCandidates = allowed;
    }

    // Show chooser dialog with smart default pre-selection
    final defaultSelection = identity.suggestDefaultSelf(
      chooserCandidates,
      chatTitle: chat.title,
    );

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SelfChooserDialog(
        candidates: chooserCandidates,
        initialSelected: defaultSelection,
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      await identity.setSelfForChat(chat.id, selected); // auto-adds to usernames
    } else if (selected == '') {
      // user picked custom in dialog
      final custom = await _askCustomName(context);
      if (custom != null && custom.trim().isNotEmpty) {
        final name = custom.trim();
        await identity.setSelfForChat(chat.id, name); // auto-adds
      }
    }
  }

  Future<String?> _askCustomName(BuildContext ctx) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Enter your name/alias'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Xharma'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChat(Chat chat) async {
    final repo = context.read<ChatRepository>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text('Remove "${chat.title}" from the app?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await repo.deleteChat(chat);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ChatRepository>();
    final chats = repo.chats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('cbbackup'),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts),
            tooltip: 'Manage my usernames (for default perspective)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyUsernamesScreen()),
              );
            },
          ),
          if (chats.isNotEmpty)
            IconButton(
              tooltip: 'Delete all',
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                for (final c in [...chats]) {
                  await context.read<ChatRepository>().deleteChat(c);
                }
                setState(() {});
              },
            ),
        ],
      ),
      body: chats.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chat_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No chats yet', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('Import a WhatsApp chat export (.zip)'),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _importing ? null : () => _importChat(context),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import chat zip'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _importing ? null : () => _loadSample(context),
                    icon: const Icon(Icons.folder_special_outlined),
                    label: const Text('Load sample demo'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: chats.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final chat = chats[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: chat.isGroup
                        ? Colors.teal.shade200
                        : Colors.indigo.shade200,
                    child: Icon(
                      chat.isGroup ? Icons.group : Icons.person,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    chat.lastMessagePreview ?? '${chat.messageCount} messages',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _formatDate(chat.importDate),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(chat: chat),
                      ),
                    );
                  },
                  onLongPress: () => _deleteChat(chat),
                );
              },
            ),
      floatingActionButton: chats.isNotEmpty
          ? FloatingActionButton(
              onPressed: _importing ? null : () => _importChat(context),
              tooltip: 'Import chat zip',
              child: _importing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.add),
            )
          : null,
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    return '${d.day}/${d.month}/${d.year}';
  }
}


