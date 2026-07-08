import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_repository.dart';
import '../widgets/chat_avatar.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, ChatStorageInfo>? _storageBreakdown;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    setState(() => _isLoading = true);
    final repo = context.read<ChatRepository>();
    final breakdown = await repo.getChatStorageBreakdown();
    if (mounted) {
      setState(() {
        _storageBreakdown = breakdown;
        _isLoading = false;
      });
    }
  }

  String _formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    i = i.clamp(0, suffixes.length - 1);
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  Future<void> _confirmDeleteChat(BuildContext context, ChatRepository repo, var chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat Archive?'),
        content: Text(
          'Are you sure you want to delete the archive for "${chat.title}"? This will delete all messages and media associated with it from the app storage. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await repo.deleteChat(chat);
      await _loadStorageInfo();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${chat.title}"')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ChatRepository>();
    final cs = Theme.of(context).colorScheme;

    int totalMessagesSize = 0;
    int totalMediaSize = 0;

    if (_storageBreakdown != null) {
      for (final info in _storageBreakdown!.values) {
        totalMessagesSize += info.messageSize;
        totalMediaSize += info.mediaSize;
      }
    }

    final int totalStorageUsed = totalMessagesSize + totalMediaSize;

    // Sort chats by total storage used descending
    final chatsSorted = List.of(repo.chats);
    if (_storageBreakdown != null) {
      chatsSorted.sort((a, b) {
        final sizeA = _storageBreakdown![a.id]?.totalSize ?? 0;
        final sizeB = _storageBreakdown![b.id]?.totalSize ?? 0;
        return sizeB.compareTo(sizeA);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Usage', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadStorageInfo,
            tooltip: 'Refresh storage info',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : chatsSorted.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.storage_rounded, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(
                        'No chats stored yet',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // Dashboard Card
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00A884).withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.storage_rounded, color: Color(0xFF00A884)),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Total Storage Used',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatBytes(totalStorageUsed),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                // Storage bar
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    height: 8,
                                    width: double.infinity,
                                    color: cs.surfaceContainerHighest,
                                    child: totalStorageUsed > 0
                                        ? Row(
                                            children: [
                                              Flexible(
                                                flex: totalMessagesSize,
                                                child: Container(color: Colors.green),
                                              ),
                                              Flexible(
                                                flex: totalMediaSize,
                                                child: Container(color: const Color(0xFF00A884)),
                                              ),
                                            ],
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Legend
                                Row(
                                  children: [
                                    _LegendItem(
                                      color: Colors.green,
                                      label: 'Messages',
                                      value: _formatBytes(totalMessagesSize),
                                    ),
                                    const SizedBox(width: 24),
                                    _LegendItem(
                                      color: const Color(0xFF00A884),
                                      label: 'Media Files',
                                      value: _formatBytes(totalMediaSize),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'Chats by Size',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // Chat list
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final chat = chatsSorted[index];
                          final storage = _storageBreakdown?[chat.id];
                          final totalSize = storage?.totalSize ?? 0;
                          final msgSize = storage?.messageSize ?? 0;
                          final mediaSize = storage?.mediaSize ?? 0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Card(
                              elevation: 0,
                              color: cs.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: ChatAvatar(name: chat.title),
                                title: Text(
                                  chat.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Messages: ${_formatBytes(msgSize)}',
                                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Media: ${_formatBytes(mediaSize)}',
                                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatBytes(totalSize),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, color: cs.error, size: 22),
                                      onPressed: () => _confirmDeleteChat(context, repo, chat),
                                      tooltip: 'Delete Chat Archive',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: chatsSorted.length,
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
