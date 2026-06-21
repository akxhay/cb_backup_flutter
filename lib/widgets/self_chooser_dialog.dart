import 'package:flutter/material.dart';

class SelfChooserDialog extends StatefulWidget {
  final List<String> candidates;
  final String? initialSelected;

  const SelfChooserDialog({
    super.key,
    required this.candidates,
    this.initialSelected,
  });

  @override
  State<SelfChooserDialog> createState() => _SelfChooserDialogState();
}

class _SelfChooserDialogState extends State<SelfChooserDialog> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Who are you in this chat?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select your name so messages are aligned correctly.'),
          const SizedBox(height: 12),
          ...widget.candidates.map((name) => RadioListTile<String>(
                title: Text(name),
                value: name,
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v),
              )),
          RadioListTile<String>(
            title: const Text('Other / custom name'),
            value: '',
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip for now')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}