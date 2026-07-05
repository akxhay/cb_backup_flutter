import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/chat.dart';
import '../services/chat_parser.dart';
import '../services/chat_repository.dart';
import '../services/self_identity_service.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_search_bar.dart';
import '../widgets/self_chooser_dialog.dart';
import 'chat_screen.dart';
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

  late StreamSubscription _intentSubscription;

  @override
  void initState() {
    super.initState();

    // Listen for shared files while app is running
    _intentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((sharedFiles) {
      _handleSharedFiles(sharedFiles);
    }, onError: (err) {
      debugPrint("getMediaStream error: $err");
    });

    // Get shared files when app is opened from share
    ReceiveSharingIntent.instance.getInitialMedia().then((sharedFiles) {
      _handleSharedFiles(sharedFiles);
      // Important: reset so it doesn't trigger again
      ReceiveSharingIntent.instance.reset();
    });
  }

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

    // Fast filter: title or last message preview or any sender (participant)
    for (final chat in allChats) {
      if (chat.title.toLowerCase().contains(q) ||
          (chat.lastMessagePreview ?? '').toLowerCase().contains(q) ||
          chat.participants.any((p) => p.toLowerCase().contains(q))) {
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

    // Remove duplicates (in case a chat matched both fast and content)
    final seen = <String>{};
    final finalResults = <Chat>[];
    for (final c in results) {
      if (seen.add(c.id)) finalResults.add(c);
    }

    if (!mounted) return;

    setState(() {
      _searchResults = finalResults;
      _isLoadingSearch = false;
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> sharedFiles) {
    if (sharedFiles.isEmpty) return;

    final file = sharedFiles.first;
    String? path = file.path;

    // Handle content URIs on Android
    if (path != null && path.toLowerCase().endsWith('.zip')) {
      final sharedFile = File(path);
      // Use a post frame callback so context is available and UI is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _importSharedZip(sharedFile);
        }
      });
    }
  }

  Future<void> _importSharedZip(File zipFile) async {
    if (_importing) return;
    setState(() => _importing = true);

    try {
      final repo = context.read<ChatRepository>();

      // Reuse similar logic as _importChat but without picker
      String? prospectiveTitle;
      try {
        prospectiveTitle = parseChatTitleFromZipFilename(zipFile.path);
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
        // Show merge/new dialog (same as before)
        final options = <Map<String, dynamic>>[];
        for (final v in variants) {
          options.add({'type': 'merge', 'chat': v, 'label': v.title});
        }

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
        await repo.mergeIntoChat(mergeTarget, zipFile);
      } else {
        await repo.importZip(zipFile, forceTitle: newLabeledTitle);
      }

      // Handle self prompt
      Chat? theChat;
      if (mergeTarget != null) {
        theChat = mergeTarget;
      } else if (repo.chats.isNotEmpty) {
        theChat = repo.chats.first;
      }
      if (theChat != null && mounted) {
        await _maybePromptForSelf(context, theChat);
      }

      setState(() {});
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import from share failed: $msg')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ChatRepository>();
    final chats = repo.chats;
    final displayChats = _isSearching ? _searchResults : chats;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'CB Backup',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Color(0xFF00A884),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _isSearching ? 'Close search' : 'Search chats',
            onPressed: () {
              if (_isSearching) {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchResults = [];
                  _isLoadingSearch = false;
                });
                _searchDebounce?.cancel();
              } else {
                final currentChats = context.read<ChatRepository>().chats;
                setState(() {
                  _isSearching = true;
                  _searchQuery = '';
                  _searchResults = List.of(currentChats);
                  _isLoadingSearch = false;
                });
                _searchDebounce?.cancel();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
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
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete all chats?'),
                    content: const Text('This will remove every imported chat from the app.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Delete all'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  for (final c in [...chats]) {
                    await context.read<ChatRepository>().deleteChat(c);
                  }
                  setState(() {});
                }
              },
            ),
        ],
      ),
      body: chats.isEmpty
          ? _EmptyChatsState(importing: _importing, onImport: () => _importChat(context))
          : Column(
              children: [
                if (_isSearching)
                  ChatSearchBar(
                    hintText: 'Search chats, messages, or contacts...',
                    autofocus: true,
                    showClear: _searchQuery.isNotEmpty,
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 250),
                        () => _performGlobalSearch(value),
                      );
                    },
                    onClear: () {
                      setState(() => _searchQuery = '');
                      _performGlobalSearch('');
                    },
                  ),
                if (_isSearching && _searchQuery.isNotEmpty && _isLoadingSearch)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: displayChats.isEmpty && _isSearching && _searchQuery.isNotEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_rounded, size: 48, color: cs.onSurfaceVariant),
                              const SizedBox(height: 12),
                              Text(
                                'No results for "$_searchQuery"',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: displayChats.length,
                          padding: const EdgeInsets.only(bottom: 88),
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 76,
                            color: cs.outlineVariant.withValues(alpha: 0.4),
                          ),
                          itemBuilder: (context, index) {
                            final chat = displayChats[index];
                            return _ChatListTile(
                              chat: chat,
                              dateLabel: _formatDate(chat.importDate),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
                                );
                              },
                              onDelete: () => _deleteChat(chat),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: chats.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _importing ? null : () => _importChat(context),
              tooltip: 'Import chat zip',
              icon: _importing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_rounded),
              label: const Text('Import'),
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
    _intentSubscription.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }
}

class _ChatListTile extends StatelessWidget {
  final Chat chat;
  final String dateLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChatListTile({
    required this.chat,
    required this.dateLabel,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = (chat.lastMessagePreview ?? '').trim().isNotEmpty
        ? chat.lastMessagePreview!
        : '${chat.messageCount} messages';

    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ChatAvatar(
                name: chat.title,
                radius: 25,
                isGroup: chat.isGroup,
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF00A884),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    alignment: Alignment.center,
                    child: Text(
                      '${chat.messageCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChatsState extends StatelessWidget {
  final bool importing;
  final VoidCallback onImport;

  const _EmptyChatsState({
    required this.importing,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 48,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your chats live here',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Import a WhatsApp chat export (.zip) to browse your backup with a familiar chat interface.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 15,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: importing ? null : onImport,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Import chat zip'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
