import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../services/chat_parser.dart';
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
  bool _showSearch = false;

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
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _formatDateHeader(date),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
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

  Future<void> _openMediaGallery() async {
    if (_loading || _allMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages loaded yet')),
      );
      return;
    }

    final hasMedia = _allMessages.any((m) => m.mediaPath != null);
    if (!hasMedia) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No media in this chat')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MediaGalleryScreen(
          messages: _allMessages,
          chat: widget.chat,
        ),
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
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: widget.chat.isGroup
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.secondaryContainer,
            child: Icon(
              widget.chat.isGroup ? Icons.group : Icons.person,
              color: widget.chat.isGroup
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSecondaryContainer,
              size: 20,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            tooltip: _showSearch ? 'Hide search' : 'Search in chat',
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchCtrl.clear();
                  _search = '';
                  _applyFilter();
                }
              });
            },
          ),
          if (!widget.chat.isGroup)
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Change perspective',
              onPressed: _changePerspective,
            ),
          IconButton(
            icon: const Icon(Icons.photo_library_rounded),
            tooltip: 'View all media',
            onPressed: _openMediaGallery,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            // Search bar - shown only when search icon is tapped
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 15),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search in chat...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                          },
                        )
                      : null,
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
                            ? 'No messages loaded yet'
                            : 'No matches for "$_search"'),
                      )
                    : Container(
                        color: Theme.of(context).colorScheme.surface,
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

/// Full-screen modern media gallery.
/// Separate tabs for: All, Photos, Stickers, Videos, Documents, Audio.
/// Modern grid with rounded corners, overlays, catchy presentation.
class _MediaGalleryScreen extends StatefulWidget {
  final List<ChatMessage> messages;
  final Chat chat;

  const _MediaGalleryScreen({
    required this.messages,
    required this.chat,
  });

  @override
  State<_MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<_MediaGalleryScreen> {
  late final List<ChatMessage> _allMedia;
  late final List<ChatMessage> _photos;
  late final List<ChatMessage> _stickers;
  late final List<ChatMessage> _videos;
  late final List<ChatMessage> _documents;
  late final List<ChatMessage> _audios;

  @override
  void initState() {
    super.initState();
    // Filter + newest first
    _allMedia = widget.messages
        .where((m) => m.mediaPath != null)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _photos = _allMedia
        .where((m) => m.type == MessageType.image && !isSticker(m))
        .toList();

    _stickers = _allMedia.where((m) => isSticker(m)).toList();

    _videos = _allMedia.where((m) => m.type == MessageType.video).toList();

    _documents = _allMedia.where((m) => m.type == MessageType.document).toList();

    _audios = _allMedia.where((m) => m.type == MessageType.audio).toList();
  }

  String _resolve(ChatMessage msg) {
    if (msg.mediaPath == null) return '';
    final repo = context.read<ChatRepository>();
    return repo.resolveMediaPath(widget.chat, msg.mediaPath!);
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

  void _openItem(ChatMessage msg) {
    final fullPath = _resolve(msg);
    if (fullPath.isEmpty) return;

    final isImg = msg.type == MessageType.image;

    if (isImg) {
      // Modern full screen viewer with pinch zoom for photos and stickers
      _showFullScreenImage(fullPath, msg.text);
    } else {
      OpenFilex.open(fullPath);
    }
  }

  void _showFullScreenImage(String path, String caption) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Preview', style: TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6.0,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.white38, size: 80),
                    ),
                  ),
                ),
              ),
              if (caption.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: Text(
                      caption,
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.3),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernGrid(List<ChatMessage> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No items',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final msg = list[index];
        final fullPath = _resolve(msg);
        final filename = msg.mediaPath!.split(RegExp(r'[/\\]')).last;
        final displayText = msg.text.isNotEmpty ? msg.text : filename;

        Widget preview;
        if (msg.type == MessageType.image) {
          preview = Image.file(
            File(fullPath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Icon(Icons.broken_image, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
        } else if (msg.type == MessageType.video) {
          preview = VideoThumbnailWidget(
            path: fullPath,
            width: 140,
            height: 140,
          );
        } else {
          preview = Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getIconForType(msg.type),
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          );
        }

        return GestureDetector(
          onTap: () => _openItem(msg),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  preview,
                  // Catchy bottom overlay for caption / name
                  if (displayText.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Text(
                          displayText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  // Small type badge top-right for non-photos
                  if (msg.type != MessageType.image)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          _getIconForType(msg.type),
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _allMedia.length;

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Media • $total'),
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.teal,
            indicatorColor: Colors.teal,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'All (${_allMedia.length})'),
              Tab(text: 'Photos (${_photos.length})'),
              Tab(text: 'Stickers (${_stickers.length})'),
              Tab(text: 'Videos (${_videos.length})'),
              Tab(text: 'Documents (${_documents.length})'),
              Tab(text: 'Audio (${_audios.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildModernGrid(_allMedia),
            _buildModernGrid(_photos),
            _buildModernGrid(_stickers),
            _buildModernGrid(_videos),
            _buildModernGrid(_documents),
            _buildModernGrid(_audios),
          ],
        ),
      ),
    );
  }
}

