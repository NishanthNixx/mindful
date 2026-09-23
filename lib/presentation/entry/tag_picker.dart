import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/domain/entities/tag.dart';

const _starterSymptoms = [
  'Migraine',
  'Headache',
  'Nausea',
  'Fatigue',
  'Light sensitivity',
  'Brain fog',
  'Neck tension',
];
const _starterMeds = ['Ibuprofen 400mg', 'Paracetamol 500mg', 'Magnesium'];

/// Selected tags as removable chips, then "+ suggestion" chips from history
/// (plus a few starters), and "+ Add custom" which opens an inline field.
class TagPicker extends ConsumerStatefulWidget {
  const TagPicker({
    required this.kind,
    required this.selected,
    required this.onChanged,
    required this.hint,
    super.key,
  });

  final TagKind kind;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final String hint;

  @override
  ConsumerState<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends ConsumerState<TagPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _adding = false;

  bool _has(String name) =>
      widget.selected.any((s) => s.toLowerCase() == name.toLowerCase());

  void _add(String raw) {
    final name = raw.trim();
    _controller.clear();
    setState(() => _adding = false);
    if (name.isEmpty || name.length > 64 || _has(name)) return;
    widget.onChanged([...widget.selected, name]);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = MindfullTokens.of(context);
    final isMed = widget.kind == TagKind.medication;
    final known = ref.watch(tagsProvider(widget.kind)).value ?? const [];
    final starters = isMed ? _starterMeds : _starterSymptoms;
    final seen = <String>{};
    final knownLower = [for (final k in known) k.name.toLowerCase()];
    // Skip a starter like "Magnesium" when history already has "Magnesium 400mg".
    bool coveredByHistory(String starter) => knownLower.any(
      (k) => k != starter.toLowerCase() && k.startsWith(starter.toLowerCase()),
    );
    final suggestions = [
      for (final n in [
        ...known.map((k) => k.name),
        if (known.length < 6) ...starters.where((st) => !coveredByHistory(st)),
      ])
        if (!_has(n) && seen.add(n.toLowerCase())) n,
    ].take(8);

    final selectedBg = isMed ? t.medChip : t.symptomChip;
    final selectedFg = isMed ? t.onMedChip : theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in widget.selected)
                  InputChip(
                    avatar: isMed
                        ? Icon(
                            Icons.medication_outlined,
                            size: 16,
                            color: selectedFg,
                          )
                        : null,
                    label: Text(s),
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: selectedFg,
                    ),
                    backgroundColor: selectedBg,
                    deleteIconColor: selectedFg,
                    deleteButtonTooltipMessage: 'Remove $s',
                    onDeleted: () =>
                        widget.onChanged([...widget.selected]..remove(s)),
                  ),
              ],
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in suggestions)
              ActionChip(
                label: Text('+ $s'),
                labelStyle: theme.textTheme.labelSmall,
                visualDensity: VisualDensity.compact,
                onPressed: () => _add(s),
              ),
            if (!_adding)
              ActionChip(
                avatar: Icon(
                  Icons.add,
                  size: 16,
                  color: theme.colorScheme.secondary,
                ),
                label: const Text('Add custom'),
                labelPadding: const EdgeInsets.only(left: 2, right: 6),
                labelStyle: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
                backgroundColor: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.4),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() => _adding = true);
                  _focus.requestFocus();
                },
              ),
          ],
        ),
        if (_adding)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Add',
                  icon: const Icon(Icons.check),
                  onPressed: () => _add(_controller.text),
                ),
              ),
              onSubmitted: _add,
              onTapOutside: (_) {
                if (_controller.text.trim().isEmpty) {
                  setState(() => _adding = false);
                }
              },
            ),
          ),
      ],
    );
  }
}
