import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
    try {
      final repo = context.read<ChatRepository>();
      final msgs = await repo.loadMessages(widget.chat);
      setState(() {
        _allMessages = msgs;
        _applyFilter();
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _allMessages = [];
        _applyFilter();
        _loading = false;
      });
    }
  }

  List<dynamic> get _displayItems {
    if (_filtered.isEmpty) return [];
    final List<dynamic> items = [];
    DateTime? currentDate;

    // Work on a copy sorted oldest -> newest
    final sorted = List.of(_filtered)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final msg in sorted) {
      final msgDate = DateTime(
        msg.timestamp.year,
        msg.timestamp.month,
        msg.timestamp.day,
      );
      if (currentDate == null || msgDate != currentDate) {
        items.add(msgDate);
        currentDate = msgDate;
      }
      items.add(msg);
    }
    return items;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) return 'TODAY';
    if (date == yesterday) return 'YESTERDAY';
    return DateFormat('dd MMM yyyy').format(date);
  }

  Widget _buildDateSeparator(DateTime date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white12
              : Colors.black12,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _formatDateHeader(date),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ),
    );
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

    final allMedia = _allMessages.where((m) => m.mediaPath != null).toList();
    if (allMedia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No media in this chat')),
      );
      return;
    }

    // Sort newest first
    allMedia.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final photos = allMedia.where((m) => m.type == MessageType.image).toList();
    final videos = allMedia.where((m) => m.type == MessageType.video).toList();
    final documents = allMedia.where((m) => m.type == MessageType.document || m.type == MessageType.audio).toList();

    await showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 4,
        child: AlertDialog(
          title: const Text('Media'),
          contentPadding: const EdgeInsets.only(top: 8),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'All'),
                    Tab(text: 'Photos'),
                    Tab(text: 'Videos'),
                    Tab(text: 'Docs'),
                  ],
                  labelColor: Colors.teal,
                  indicatorColor: Colors.teal,
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildMediaGrid(allMedia, ctx),
                      _buildMediaGrid(photos, ctx),
                      _buildMediaGrid(videos, ctx),
                      _buildMediaGrid(documents, ctx),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrid(List<ChatMessage> mediaList, BuildContext dialogContext) {
    if (mediaList.isEmpty) {
      return const Center(child: Text('Nothing here'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: mediaList.length,
      itemBuilder: (c, index) {
        final msg = mediaList[index];
        final fullPath = _resolveMedia(msg);
        final filename = msg.mediaPath!.split(RegExp(r'[/\\]')).last;

        Widget preview;
        if (msg.type == MessageType.image) {
          preview = Image.file(
            File(fullPath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40),
          );
        } else if (msg.type == MessageType.video) {
          preview = VideoThumbnailWidget(
            path: fullPath,
            width: 100,
            height: 100,
          );
        } else {
          preview = Center(
            child: Icon(_getIconForType(msg.type), size: 42),
          );
        }

        return GestureDetector(
          onTap: () {
            Navigator.pop(dialogContext);
            OpenFilex.open(fullPath);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                preview,
                if (msg.type != MessageType.image)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    right: 4,
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        filename,
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
                    : Container(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF0B141A)
                            : const Color(0xFFECE5DD),
                        child: ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.only(top: 8, bottom: 12),
                          itemCount: _displayItems.length,
                        itemBuilder: (context, index) {
                          // reverse indexing for display (newest bottom)
                          final item = _displayItems[_displayItems.length - 1 - index];

                          if (item is DateTime) {
                            return _buildDateSeparator(item);
                          }

                          final msg = item as ChatMessage;
                          final isSelf = _isSelf(msg);
                          final mediaPath = msg.mediaPath != null ? _resolveMedia(msg) : null;
                          return MessageBubble(
                            message: msg,
                            isSelf: isSelf,
                            mediaFullPath: mediaPath,
                            showSenderName: widget.chat.isGroup,
                          );
                        },
                      ),
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
