import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../services/chat_parser.dart';
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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      final file = File(path);
      final repo = context.read<ChatRepository>();

      // Check using base title (strip labels like (2))
      String? prospectiveTitle;
      try {
        prospectiveTitle = parseChatTitleFromZipFilename(path);
      } catch (_) {}

      List<Chat> variants = [];
      String baseTitle = '';
      if (prospectiveTitle != null) {
        baseTitle = extractBaseChatTitle(prospectiveTitle);
        final l = baseTitle.toLowerCase().trim();
        variants = repo.chats
            .where((c) => extractBaseChatTitle(c.title).toLowerCase().trim() == l)
            .toList();
      }

      Chat? mergeTarget;
      String? newLabeledTitle;

      if (variants.isNotEmpty) {
        // Build options for dialog
        final options = <Map<String, dynamic>>[];
        for (final v in variants) {
          options.add({'type': 'merge', 'chat': v, 'label': v.title});
        }

        // Compute next label
        int maxLabel = 1;
        for (final v in variants) {
          final num = extractLabelNumber(v.title);
          if (num > maxLabel) maxLabel = num;
        }
        final nextLabel = maxLabel + 1;
        final importNewLabel = '$baseTitle ($nextLabel)';
        options.add({'type': 'new', 'label': importNewLabel});

        final choice = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Chat already exists'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A chat for "$baseTitle" already exists.'),
                const SizedBox(height: 12),
                const Text('Choose action:'),
                const SizedBox(height: 8),
                ...options.map((opt) {
                  return ListTile(
                    title: Text(opt['label']),
                    onTap: () => Navigator.pop(ctx, opt),
                    leading: Icon(
                      opt['type'] == 'merge' ? Icons.merge_type : Icons.add,
                    ),
                  );
                }).toList(),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );

        if (choice == null) {
          setState(() => _importing = false);
          return;
        }

        if (choice['type'] == 'merge') {
          mergeTarget = choice['chat'] as Chat;
        } else {
          newLabeledTitle = choice['label'] as String;
        }
      }

      if (mergeTarget != null) {
        await repo.mergeIntoChat(mergeTarget, file);
      } else {
        await repo.importZip(file, forceTitle: newLabeledTitle);
      }

      // Handle self prompt for the relevant chat
      Chat? theChat;
      if (mergeTarget != null) {
        theChat = mergeTarget;
      } else if (repo.chats.isNotEmpty) {
        // The newly imported one (with label if any) is now first
        theChat = repo.chats.first;
      }
      if (theChat != null && mounted) {
        await _maybePromptForSelf(context, theChat);
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $msg')));
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
      await identity.setSelfForChat(
        chat.id,
        autoSelf,
      ); // auto-add happens inside
      return; // no prompt needed
    }

    // Only allow choosing from configured (allowed) usernames if any match in this chat
    List<String> chooserCandidates = chat.participants;
    final allowed = identity.myUsernames
        .where(
          (u) =>
              chat.participants.any((p) => p.toLowerCase() == u.toLowerCase()),
        )
        .toList();
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
      await identity.setSelfForChat(
        chat.id,
        selected,
      ); // auto-adds to usernames
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
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
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
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
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
                  title: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                      MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
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
