import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../services/chat_repository.dart';
import '../services/self_identity_service.dart';
import '../widgets/self_chooser_dialog.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<ChatMessage> _allMessages = [];
  List<ChatMessage> _filtered = [];
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() {
        _search = _searchCtrl.text.trim().toLowerCase();
        _applyFilter();
      });
    });
  }

  Future<void> _load() async {
    final repo = context.read<ChatRepository>();
    final msgs = await repo.loadMessages(widget.chat);
    setState(() {
      _allMessages = msgs;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    if (_search.isEmpty) {
      _filtered = List.of(_allMessages);
    } else {
      _filtered = _allMessages
          .where((m) => m.text.toLowerCase().contains(_search) ||
              m.sender.toLowerCase().contains(_search))
          .toList();
    }
  }

  bool _isSelf(ChatMessage msg) {
    final identity = context.read<SelfIdentityService>();
    return identity.isSelf(msg.sender, chatId: widget.chat.id);
  }

  String _resolveMedia(ChatMessage msg) {
    if (msg.mediaPath == null) return '';
    final repo = context.read<ChatRepository>();
    return repo.resolveMediaPath(widget.chat, msg.mediaPath!);
  }

  Future<void> _changePerspective() async {
    final identity = context.read<SelfIdentityService>();
    final current = identity.getSelfForChat(widget.chat.id);
    final chatSenders = widget.chat.participants;

    // Only allow choosing from the configured allowed usernames that appear in this chat
    List<String> candidates = chatSenders;
    final allowed = identity.myUsernames.where((u) =>
        chatSenders.any((p) => p.toLowerCase() == u.toLowerCase())).toList();
    if (allowed.isNotEmpty) {
      candidates = allowed;
    }

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching usernames from your config. Manage usernames in the list screen.')),
      );
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SelfChooserDialog(
        candidates: candidates,
        initialSelected: current,
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      await identity.setSelfForChat(widget.chat.id, selected); // auto adds to config
      setState(() {}); // refresh message alignments
    } else if (selected == '') {
      final custom = await _askCustomName(context);
      if (custom != null && custom.trim().isNotEmpty) {
        final name = custom.trim();
        await identity.setSelfForChat(widget.chat.id, name); // auto adds
        setState(() {});
      }
    }
  }

  // Simple custom name prompt (duplicated for now)
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

  IconData _getIconForType(MessageType type) {
    switch (type) {
      case MessageType.image:
        return Icons.image;
      case MessageType.video:
        return Icons.videocam;
      case MessageType.audio:
        return Icons.audiotrack;
      case MessageType.document:
        return Icons.insert_drive_file;
      default:
        return Icons.attach_file;
    }
  }

  Future<void> _showAllMedia() async {
    if (_loading || _allMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages loaded yet')),
      );
      return;
    }

    final mediaMessages = _allMessages.where((m) => m.mediaPath != null).toList();
    if (mediaMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No media in this chat')),
      );
      return;
    }

    // Newest first
    final sortedMedia = List.of(mediaMessages)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('All Media (${sortedMedia.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sortedMedia.length,
            itemBuilder: (c, index) {
              final msg = sortedMedia[index];
              final fullPath = _resolveMedia(msg);
              final filename = msg.mediaPath!.split(RegExp(r'[/\\]')).last;
              return ListTile(
                leading: Icon(_getIconForType(msg.type)),
                title: Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(msg.sender),
                onTap: () async {
                  Navigator.pop(ctx);
                  await OpenFilex.open(fullPath);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<String>(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                widget.chat.isGroup
                    ? '${widget.chat.participants.length} participants'
                    : widget.chat.participants.join(', '),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          onSelected: (value) async {
            if (value == 'perspective') {
              await _changePerspective();
            } else if (value == 'media') {
              await _showAllMedia();
            }
          },
          itemBuilder: (context) {
            final items = <PopupMenuEntry<String>>[
              const PopupMenuItem(
                value: 'media',
                child: ListTile(
                  leading: Icon(Icons.perm_media),
                  title: Text('View all media'),
                  dense: true,
                ),
              ),
            ];
            if (!widget.chat.isGroup) {
              items.add(const PopupMenuItem(
                value: 'perspective',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Change perspective'),
                  dense: true,
                ),
              ));
            }
            return items;
          },
        ),
      ),
      body: Column(
        children: [
          // Search bar mimicking WA style
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search in chat...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                isDense: true,
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(_search.isEmpty
                            ? 'No messages'
                            : 'No matches for "$_search"'),
                      )
                    : ListView.builder(
                        reverse: true, // newest at bottom when scrolled
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          // reverse indexing
                          final msg = _filtered[_filtered.length - 1 - index];
                          final isSelf = _isSelf(msg);
                          final mediaPath = msg.mediaPath != null ? _resolveMedia(msg) : null;
                          return MessageBubble(
                            message: msg,
                            isSelf: isSelf,
                            mediaFullPath: mediaPath,
                          );
                        },
                      ),
          ),
          if (_search.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                '${_filtered.length} of ${_allMessages.length} messages',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
