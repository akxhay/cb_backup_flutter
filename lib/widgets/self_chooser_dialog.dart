import 'package:flutter/material.dart';

import 'chat_avatar.dart';

class SelfChooserResult {
  final String selectedName;
  final bool addToConfig;

  const SelfChooserResult({
    required this.selectedName,
    required this.addToConfig,
  });
}

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
  bool _addToConfig = true;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected ?? '_global_';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Who are you in this chat?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick your name so your messages appear on the right.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.35,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IdentityOption(
                    name: 'Global (Match all my usernames)',
                    value: '_global_',
                    groupValue: _selected,
                    isGlobal: true,
                    onTap: () => setState(() => _selected = '_global_'),
                  ),
                  ...widget.candidates.map((name) => _IdentityOption(
                        name: name,
                        value: name,
                        groupValue: _selected,
                        onTap: () => setState(() => _selected = name),
                      )),
                  _IdentityOption(
                    name: 'Other / custom name',
                    value: '',
                    groupValue: _selected,
                    isCustom: true,
                    onTap: () => setState(() => _selected = ''),
                  ),
                ],
              ),
            ),
          ),
          if (_selected != '_global_' && _selected != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: InkWell(
                onTap: () => setState(() => _addToConfig = !_addToConfig),
                child: Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _addToConfig,
                        onChanged: (val) {
                          setState(() {
                            _addToConfig = val ?? true;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Add to my global usernames list',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip for now')),
        FilledButton(
          onPressed: () {
            if (_selected == null) {
              Navigator.pop(context);
            } else {
              Navigator.pop(
                context,
                SelfChooserResult(
                  selectedName: _selected!,
                  addToConfig: _addToConfig,
                ),
              );
            }
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _IdentityOption extends StatelessWidget {
  final String name;
  final String value;
  final String? groupValue;
  final bool isCustom;
  final bool isGlobal;
  final VoidCallback onTap;

  const _IdentityOption({
    required this.name,
    required this.value,
    required this.groupValue,
    required this.onTap,
    this.isCustom = false,
    this.isGlobal = false,
  });

  bool get isSelected => groupValue == value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? cs.primaryContainer.withValues(alpha: 0.45) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                if (isCustom)
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
                  )
                else if (isGlobal)
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(Icons.public, size: 18, color: cs.onSurfaceVariant),
                  )
                else
                  ChatAvatar(name: name, radius: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                Radio<String>(
                  value: value,
                  groupValue: groupValue,
                  onChanged: (_) => onTap(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}