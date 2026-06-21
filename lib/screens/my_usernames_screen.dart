import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/self_identity_service.dart';

class MyUsernamesScreen extends StatefulWidget {
  const MyUsernamesScreen({super.key});

  @override
  State<MyUsernamesScreen> createState() => _MyUsernamesScreenState();
}

class _MyUsernamesScreenState extends State<MyUsernamesScreen> {
  final TextEditingController _addController = TextEditingController();
  late List<String> _names;

  @override
  void initState() {
    super.initState();
    final identity = context.read<SelfIdentityService>();
    _names = List.from(identity.myUsernames);
  }

  Future<void> _save() async {
    final identity = context.read<SelfIdentityService>();
    await identity.setMyUsernames(_names);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('My usernames updated. Order affects default perspective.')),
      );
      Navigator.pop(context);
    }
  }

  void _addName() {
    final name = _addController.text.trim();
    if (name.isEmpty) return;
    if (!_names.any((n) => n.toLowerCase() == name.toLowerCase())) {
      setState(() {
        _names.add(name);
        _addController.clear();
      });
    }
  }

  void _remove(int index) {
    setState(() {
      _names.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Usernames'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    decoration: const InputDecoration(
                      hintText: 'Add a new username (e.g. Xharma, me)',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addName(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _addName,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Drag to reorder. The order determines default "me" selection (first match wins).',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _names.isEmpty
                ? const Center(child: Text('No usernames yet. Add some!'))
                : ReorderableListView.builder(
                    itemCount: _names.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _names.removeAt(oldIndex);
                        _names.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final name = _names[index];
                      return ListTile(
                        key: ValueKey(name),
                        leading: const Icon(Icons.person),
                        title: Text(name),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _remove(index),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }
}