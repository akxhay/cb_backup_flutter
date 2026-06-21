import 'dart:async';
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
import 'settings_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _importing = false;
  bool _isSearching = false;
  String _searchQuery = '';
  List<Chat> _searchResults = [];
  bool _isLoadingSearch = false;
  Timer? _searchDebounce;

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
      if (_isSearching) {
        _performGlobalSearch(_searchQuery);
      }
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

  Future<void> _performGlobalSearch(String query) async {
    if (!mounted) return;

    final repo = context.read<ChatRepository>();
    final allChats = repo.chats;

    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = List.of(allChats);
        _isLoadingSearch = false;
      });
      return;
    }

    setState(() {
      _isLoadingSearch = true;
    });

    final q = query.toLowerCase().trim();
    final List<Chat> results = [];

    // Fast filter: title or last message preview
    for (final chat in allChats) {
      if (chat.title.toLowerCase().contains(q) ||
          (chat.lastMessagePreview ?? '').toLowerCase().contains(q)) {
        results.add(chat);
      }
    }

    // Search inside messages for remaining chats
    final remaining = allChats.where((c) => !results.any((r) => r.id == c.id)).toList();

    if (remaining.isNotEmpty) {
      final futures = remaining.map((chat) async {
        try {
          final messages = await repo.loadMessages(chat);
          final hasMatch = messages.any((msg) =>
              msg.text.toLowerCase().contains(q) ||
              msg.sender.toLowerCase().contains(q));
          return hasMatch ? chat : null;
        } catch (_) {
          return null;
        }
      });

      final messageMatches = await Future.wait(futures);
      results.addAll(messageMatches.whereType<Chat>());
    }

    if (!mounted) return;

    setState(() {
      _searchResults = results;
      _isLoadingSearch = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ChatRepository>();
    final chats = repo.chats;

    final displayChats = _isSearching ? _searchResults : chats;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                    _performGlobalSearch(value);
                  });
                },
              )
            : const Text('CB Backup'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchResults = [];
                  _isLoadingSearch = false;
                });
                _searchDebounce?.cancel();
              },
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search chats',
              onPressed: () {
                final currentChats = context.read<ChatRepository>().chats;
                setState(() {
                  _isSearching = true;
                  _searchQuery = '';
                  _searchResults = List.of(currentChats);
                  _isLoadingSearch = false;
                });
                _searchDebounce?.cancel();
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            if (chats.isNotEmpty)
              IconButton(
                tooltip: 'Delete all chats',
                icon: const Icon(Icons.delete_sweep),
                onPressed: () async {
                  for (final c in [...chats]) {
                    await context.read<ChatRepository>().deleteChat(c);
                  }
                  setState(() {});
                },
              ),
          ],
        ],
      ),
      body: chats.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_outlined, size: 72, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 20),
                  const Text('No chats yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    'Import a WhatsApp chat export (.zip)',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _importing ? null : () => _importChat(context),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import chat zip'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_isSearching && _searchQuery.isNotEmpty && _isLoadingSearch)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: displayChats.isEmpty && _isSearching && _searchQuery.isNotEmpty
                      ? Center(
                          child: Text(
                            'No results for "$_searchQuery"',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        )
                      : ListView.builder(
                          itemCount: displayChats.length,
                          padding: const EdgeInsets.only(top: 8, bottom: 80),
                          itemBuilder: (context, index) {
                            final chat = displayChats[index];
                            final preview = (chat.lastMessagePreview ?? '').trim().isNotEmpty
                                ? chat.lastMessagePreview!
                                : '${chat.messageCount} messages';

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: Card(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
                                    );
                                  },
                                  onLongPress: () => _deleteChat(chat),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundColor: chat.isGroup
                                              ? Theme.of(context).colorScheme.primaryContainer
                                              : Theme.of(context).colorScheme.secondaryContainer,
                                          child: Icon(
                                            chat.isGroup ? Icons.group : Icons.person,
                                            color: chat.isGroup
                                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                                : Theme.of(context).colorScheme.onSecondaryContainer,
                                            size: 26,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                chat.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(fontWeight: FontWeight.w600),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                preview,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          _formatDate(chat.importDate),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                        const SizedBox(width: 4),
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, size: 18),
                                          onSelected: (value) {
                                            if (value == 'delete') {
                                              _deleteChat(chat);
                                            }
                                          },
                                          itemBuilder: (c) => [
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete, color: Colors.red, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Delete chat'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
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

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
