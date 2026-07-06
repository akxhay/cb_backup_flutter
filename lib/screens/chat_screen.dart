import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../services/chat_parser.dart';
import '../services/chat_repository.dart';
import '../services/self_identity_service.dart';
import '../services/video_thumbnail_service.dart';
import '../theme/chat_theme.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_background.dart';
import '../widgets/chat_search_bar.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/self_chooser_dialog.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final String? initialMessageUniqueId;
  final String? initialSearchQuery;

  const ChatScreen({
    super.key,
    required this.chat,
    this.initialMessageUniqueId,
    this.initialSearchQuery,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<ChatMessage> _allMessages = [];
  List<ChatMessage> _filtered = [];
  List<dynamic> _displayItems = [];
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  List<int> _matchIndices = [];
  int _currentMatchIndex = -1;
  String? _highlightedMsgId;
  Timer? _highlightTimer;

  bool _loading = true;
  String _search = '';
  bool _showSearch = false;
  bool _hasScrolledToInitialMessage = false;
  int _activeScrollId = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchQuery != null) {
      _search = widget.initialSearchQuery!.trim().toLowerCase();
      _searchCtrl.text = widget.initialSearchQuery!;
      _showSearch = true;
    }
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
      if (widget.initialMessageUniqueId != null && !_hasScrolledToInitialMessage) {
        _hasScrolledToInitialMessage = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToMessageByUniqueId(widget.initialMessageUniqueId!);
        });
      }
    } catch (_) {
      setState(() {
        _allMessages = [];
        _applyFilter();
        _loading = false;
      });
    }
  }

  void _scrollToMessageByUniqueId(String uniqueId) {
    int targetDisplayIndex = -1;
    for (int i = 0; i < _displayItems.length; i++) {
      final item = _displayItems[i];
      if (item is ChatMessage && item.uniqueId == uniqueId) {
        targetDisplayIndex = i;
        break;
      }
    }
    if (targetDisplayIndex != -1) {
      final listViewIndex = _displayItems.length - 1 - targetDisplayIndex;
      final targetOffset = _estimateOffset(listViewIndex);

      final matchIdx = _matchIndices.indexWhere((idx) => idx == targetDisplayIndex);
      if (matchIdx != -1) {
        setState(() {
          _currentMatchIndex = matchIdx;
        });
      }

      _activeScrollId++;
      final currentScrollId = _activeScrollId;
      final keyKey = '${uniqueId}_$targetDisplayIndex';
      _performScrollAndHighlight(keyKey, uniqueId, targetOffset, 0, currentScrollId);
    }
  }

  void _rebuildDisplayItems() {
    if (_filtered.isEmpty) {
      _displayItems = [];
      return;
    }
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
    _displayItems = items;

    // Pre-populate keys with unique index suffix
    for (int i = 0; i < _displayItems.length; i++) {
      final item = _displayItems[i];
      if (item is ChatMessage) {
        _messageKeys.putIfAbsent('${item.uniqueId}_$i', () => GlobalKey());
      }
    }
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
      margin: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ChatTheme.datePillColor(context),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
            ),
          ],
        ),
        child: Text(
          _formatDateHeader(date),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: ChatTheme.datePillTextColor(context),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  bool _isGroupedWithPrevious(int displayIndex) {
    if (displayIndex <= 0) return false;
    final current = _displayItems[displayIndex];
    if (current is! ChatMessage || current.type == MessageType.system)
      return false;

    for (var i = displayIndex - 1; i >= 0; i--) {
      final prev = _displayItems[i];
      if (prev is DateTime) return false;
      if (prev is ChatMessage) {
        if (prev.type == MessageType.system) return false;
        return prev.sender == current.sender &&
            _isSelf(prev) == _isSelf(current);
      }
    }
    return false;
  }

  bool _isGroupedWithNext(int displayIndex) {
    if (displayIndex >= _displayItems.length - 1) return false;
    final current = _displayItems[displayIndex];
    if (current is! ChatMessage || current.type == MessageType.system)
      return false;

    for (var i = displayIndex + 1; i < _displayItems.length; i++) {
      final next = _displayItems[i];
      if (next is DateTime) return false;
      if (next is ChatMessage) {
        if (next.type == MessageType.system) return false;
        return next.sender == current.sender &&
            _isSelf(next) == _isSelf(current);
      }
    }
    return false;
  }

  void _applyFilter() {
    // We always display all messages to keep the context scrollable
    _filtered = List.of(_allMessages);
    _rebuildDisplayItems();

    if (_search.isEmpty) {
      _matchIndices = [];
      _currentMatchIndex = -1;
      _highlightedMsgId = null;
      _highlightTimer?.cancel();
    } else {
      // Find all matching indices in _displayItems
      final List<int> matches = [];
      for (int i = 0; i < _displayItems.length; i++) {
        final item = _displayItems[i];
        if (item is ChatMessage) {
          final sender = item.sender.toLowerCase();
          final text = item.text.toLowerCase();
          if (sender.contains(_search) || text.contains(_search)) {
            matches.add(i);
          }
        }
      }
      _matchIndices = matches;
      if (_matchIndices.isNotEmpty) {
        // Default to the newest match (end of list)
        _currentMatchIndex = _matchIndices.length - 1;
        if (widget.initialMessageUniqueId == null || _hasScrolledToInitialMessage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToMatch(_currentMatchIndex);
          });
        }
      } else {
        _currentMatchIndex = -1;
        _highlightedMsgId = null;
      }
    }
  }

  double _estimateOffset(int targetListViewIndex) {
    double offset = 0.0;
    for (int i = 0; i < targetListViewIndex; i++) {
      final displayIndex = _displayItems.length - 1 - i;
      if (displayIndex < 0 || displayIndex >= _displayItems.length) continue;
      final item = _displayItems[displayIndex];
      if (item is DateTime) {
        offset += 55.0;
      } else if (item is ChatMessage) {
        final isSelf = _isSelf(item);
        final showName = !isSelf && widget.chat.isGroup && !_isGroupedWithPrevious(displayIndex);
        final groupedAbove = _isGroupedWithPrevious(displayIndex);
        final groupedBelow = _isGroupedWithNext(displayIndex);
        final topMargin = showName ? 6.0 : (groupedAbove ? 1.5 : 6.0);
        final bottomMargin = groupedBelow ? 1.5 : 6.0;

        double bubbleHeight = 0.0;
        if (item.type == MessageType.system) {
          bubbleHeight = 45.0;
        } else if (item.type == MessageType.image) {
          final isStickerMsg = isSticker(item);
          if (isStickerMsg) {
            bubbleHeight = 160.0;
          } else {
            if (item.text.isEmpty) {
              bubbleHeight = 220.0;
            } else {
              // Estimate caption text lines
              final text = item.text;
              final lines = text.split('\n');
              int linesCount = 0;
              for (final line in lines) {
                linesCount += (line.length / 33).ceil();
                if (line.isEmpty) linesCount += 1;
              }
              if (linesCount == 0) linesCount = 1;
              final textHeight = (linesCount * 21.5) + 32.0;
              bubbleHeight = 220.0 + 6.0 + textHeight;
            }
          }
          bubbleHeight += topMargin + bottomMargin;
        } else if (item.type == MessageType.video) {
          if (item.text.isEmpty) {
            bubbleHeight = 220.0;
          } else {
            final text = item.text;
            final lines = text.split('\n');
            int linesCount = 0;
            for (final line in lines) {
              linesCount += (line.length / 33).ceil();
              if (line.isEmpty) linesCount += 1;
            }
            if (linesCount == 0) linesCount = 1;
            final textHeight = (linesCount * 21.5) + 32.0;
            bubbleHeight = 220.0 + 6.0 + textHeight;
          }
          bubbleHeight += topMargin + bottomMargin;
        } else if (item.type == MessageType.audio) {
          bubbleHeight = 85.0;
          bubbleHeight += topMargin + bottomMargin;
        } else if (item.type == MessageType.document) {
          if (item.text.isEmpty) {
            bubbleHeight = 75.0;
          } else {
            final text = item.text;
            final lines = text.split('\n');
            int linesCount = 0;
            for (final line in lines) {
              linesCount += (line.length / 33).ceil();
              if (line.isEmpty) linesCount += 1;
            }
            if (linesCount == 0) linesCount = 1;
            final textHeight = (linesCount * 20.0) + 15.0;
            bubbleHeight = 81.0 + textHeight;
          }
          bubbleHeight += topMargin + bottomMargin;
        } else {
          // Text message
          final text = item.text;
          final lines = text.split('\n');
          int linesCount = 0;
          for (final line in lines) {
            linesCount += (line.length / 33).ceil();
            if (line.isEmpty) linesCount += 1;
          }
          if (linesCount == 0) linesCount = 1;

          bubbleHeight = (linesCount * 21.5) + 32.0;
          if (showName) {
            bubbleHeight += 20.0;
          }
          bubbleHeight += topMargin + bottomMargin;
        }
        offset += bubbleHeight;
      }
    }
    return offset;
  }

  void _scrollToMatch(int matchIndex) {
    if (_matchIndices.isEmpty || matchIndex < 0 || matchIndex >= _matchIndices.length) return;
    setState(() {
      _currentMatchIndex = matchIndex;
    });

    final targetDisplayIndex = _matchIndices[matchIndex];
    final msg = _displayItems[targetDisplayIndex] as ChatMessage;

    // Calculate reversed list index
    final listViewIndex = _displayItems.length - 1 - targetDisplayIndex;
    final targetOffset = _estimateOffset(listViewIndex);

    _highlightTimer?.cancel();
    _highlightedMsgId = null;

    _activeScrollId++;
    final currentScrollId = _activeScrollId;
    final keyKey = '${msg.uniqueId}_$targetDisplayIndex';
    _performScrollAndHighlight(keyKey, msg.uniqueId, targetOffset, 0, currentScrollId);
  }

  void _performScrollAndHighlight(String keyKey, String uniqueId, double targetOffset, int retryCount, int scrollId) {
    if (!mounted) return;
    if (scrollId != _activeScrollId) return; // Cancelled by a newer scroll request!

    if (!_scrollCtrl.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performScrollAndHighlight(keyKey, uniqueId, targetOffset, retryCount, scrollId);
      });
      return;
    }

    final currentMax = _scrollCtrl.position.maxScrollExtent;
    final approxOffset = targetOffset.clamp(0.0, currentMax);

    // Only jump if we are not already close to the target offset to prevent flickering
    if ((approxOffset - _scrollCtrl.offset).abs() > 1.0) {
      _scrollCtrl.jumpTo(approxOffset);
    }

    // Increase delay to 150ms during retries to allow layout to update and build items
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (scrollId != _activeScrollId) return; // Cancelled!

      final key = _messageKeys[keyKey];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 250),
          alignment: 0.5,
        );
        setState(() {
          _highlightedMsgId = uniqueId;
        });

        _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              _highlightedMsgId = null;
            });
          }
        });
      } else if (retryCount < 12) {
        // Retry with larger retry limit to guarantee reaching deep-linked target in long histories
        _performScrollAndHighlight(keyKey, uniqueId, targetOffset, retryCount + 1, scrollId);
      } else {
        setState(() {
          _highlightedMsgId = uniqueId;
        });
        _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              _highlightedMsgId = null;
            });
          }
        });
      }
    });
  }

  void _prevMatch() {
    if (_currentMatchIndex > 0) {
      _scrollToMatch(_currentMatchIndex - 1);
    }
  }

  void _nextMatch() {
    if (_currentMatchIndex < _matchIndices.length - 1) {
      _scrollToMatch(_currentMatchIndex + 1);
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

    // Allow choosing from all senders in this chat
    List<String> candidates = chatSenders;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No participants found in this chat.',
          ),
        ),
      );
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          SelfChooserDialog(candidates: candidates, initialSelected: current),
    );

    if (selected != null && selected.isNotEmpty) {
      await identity.setSelfForChat(
        widget.chat.id,
        selected,
      ); // auto adds to config
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

  Future<void> _openMediaGallery() async {
    if (_loading || _allMessages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No messages loaded yet')));
      return;
    }

    final hasMedia = _allMessages.any((m) => m.mediaPath != null);
    if (!hasMedia) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No media in this chat')));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _MediaGalleryScreen(messages: _allMessages, chat: widget.chat),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final subtitle = widget.chat.isGroup
        ? '${widget.chat.participants.length} participants · ${_allMessages.length} messages'
        : '${_allMessages.length} messages';

    return Scaffold(
      backgroundColor: ChatTheme.chatBackground(context),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        leadingWidth: 40,
        titleSpacing: 0,
        title: Row(
          children: [
            ChatAvatar(
              name: widget.chat.title,
              radius: 20,
              isGroup: widget.chat.isGroup,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
            ),
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
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Change perspective',
              onPressed: _changePerspective,
            ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'View all media',
            onPressed: _openMediaGallery,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            ChatSearchBar(
              controller: _searchCtrl,
              hintText: 'Search in chat...',
              autofocus: true,
              showClear: _search.isNotEmpty,
              onClear: _searchCtrl.clear,
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _search.isEmpty
                              ? Icons.chat_bubble_outline_rounded
                              : Icons.search_off_rounded,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _search.isEmpty
                              ? 'No messages loaded yet'
                              : 'No matches for "$_search"',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ChatBackground(
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      reverse: true,
                      cacheExtent: 3000.0,
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      itemCount: _displayItems.length,
                      itemBuilder: (context, index) {
                        final displayIndex = _displayItems.length - 1 - index;
                        final item = _displayItems[displayIndex];

                        if (item is DateTime) {
                          return _buildDateSeparator(item);
                        }

                        final msg = item as ChatMessage;
                        final isSelf = _isSelf(msg);
                        final mediaPath = msg.mediaPath != null
                            ? _resolveMedia(msg)
                            : null;
                        
                        final key = _messageKeys.putIfAbsent('${msg.uniqueId}_$displayIndex', () => GlobalKey());

                        return MessageBubble(
                          key: key,
                          message: msg,
                          isSelf: isSelf,
                          mediaFullPath: mediaPath,
                          showSenderName: widget.chat.isGroup,
                          groupedAbove: _isGroupedWithPrevious(displayIndex),
                          groupedBelow: _isGroupedWithNext(displayIndex),
                          highlighted: msg.uniqueId == _highlightedMsgId,
                          searchQuery: _search,
                        );
                      },
                    ),
                  ),
          ),
          if (_search.isNotEmpty)
            Material(
              color: theme.colorScheme.surface,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Text(
                      _matchIndices.isEmpty
                          ? 'No matches'
                          : '${_currentMatchIndex + 1} of ${_matchIndices.length}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      onPressed: _currentMatchIndex > 0 ? _prevMatch : null,
                      tooltip: 'Previous match',
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      onPressed: _currentMatchIndex < _matchIndices.length - 1
                          ? _nextMatch
                          : null,
                      tooltip: 'Next match',
                    ),
                  ],
                ),
              ),
            )
          else
            _ArchiveFooter(messageCount: _allMessages.length),
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

  const _MediaGalleryScreen({required this.messages, required this.chat});

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
    _allMedia = widget.messages.where((m) => m.mediaPath != null).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _photos = _allMedia
        .where((m) => m.type == MessageType.image && !isSticker(m))
        .toList();

    _stickers = _allMedia.where((m) => isSticker(m)).toList();

    _videos = _allMedia.where((m) => m.type == MessageType.video).toList();

    _documents = _allMedia
        .where((m) => m.type == MessageType.document)
        .toList();

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
    FullScreenImageViewer.show(
      context,
      imagePath: path,
      caption: caption.isNotEmpty ? caption : null,
    );
  }

  Widget _buildModernGrid(List<ChatMessage> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
              child: Icon(
                Icons.broken_image,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        } else if (msg.type == MessageType.video) {
          preview = FutureBuilder<String?>(
            future: VideoThumbnailService.getThumbnail(fullPath),
            builder: (context, snapshot) {
              final thumb = snapshot.data;
              if (thumb != null && File(thumb).existsSync()) {
                return Image.file(
                  File(thumb),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: Icon(
                      Icons.broken_image,
                      size: 40,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Container(
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
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
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
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
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
          title: Text('Media · $total'),
          bottom: TabBar(
            isScrollable: true,
            labelColor: Theme.of(context).colorScheme.primary,
            indicatorColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant,
            dividerColor: Theme.of(context).dividerColor.withValues(alpha: 0.3),
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

class _ArchiveFooter extends StatelessWidget {
  final int messageCount;

  const _ArchiveFooter({required this.messageCount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.95),
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.archive_outlined,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  messageCount > 0
                      ? 'Viewing backup archive · $messageCount messages'
                      : 'Viewing backup archive',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
