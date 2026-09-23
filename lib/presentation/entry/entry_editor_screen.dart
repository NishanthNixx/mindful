import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/entities/tag.dart';
import 'package:mindfull/presentation/entry/mood_picker.dart';
import 'package:mindfull/presentation/entry/tag_picker.dart';
import 'package:mindfull/presentation/shared/appearance.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart';
import 'package:mindfull/presentation/shared/mood.dart';
import 'package:mindfull/presentation/shared/network_indicator.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';
import 'package:mindfull/presentation/shared/pill.dart';
import 'package:mindfull/presentation/timeline/entry_tile.dart'
    show relativeTimestamp;
import 'package:uuid/uuid.dart';

class EntryEditorScreen extends ConsumerStatefulWidget {
  const EntryEditorScreen({this.entryId, super.key});

  /// Null for a new entry.
  final String? entryId;

  @override
  ConsumerState<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends ConsumerState<EntryEditorScreen> {
  final _note = TextEditingController();
  JournalEntry? _original;
  bool _loading = true;
  bool _saving = false;

  late DateTime _createdAt = clock.now();
  int? _mood;
  double? _sleep;
  List<String> _symptoms = [];
  List<String> _meds = [];
  bool _fromVoice = false;

  // Voice
  bool _listening = false;
  String _noteBeforeListening = '';

  bool get _isNew => widget.entryId == null;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_isNew) {
      setState(() => _loading = false);
      return;
    }
    final e = await ref.read(journalRepoProvider).getEntry(widget.entryId!);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _original = e;
      if (e == null) return;
      _createdAt = e.createdAt;
      _mood = e.mood;
      _sleep = e.sleepHours;
      _symptoms = [...e.symptoms];
      _meds = [...e.medications];
      _fromVoice = e.fromVoice;
      _note.text = e.note;
    });
  }

  JournalEntry? _build() => _mood == null
      ? null
      : JournalEntry(
          id: _original?.id ?? const Uuid().v4(),
          createdAt: _createdAt,
          mood: _mood!,
          sleepHours: _sleep,
          note: _note.text,
          symptoms: _symptoms,
          medications: _meds,
          fromVoice: _fromVoice,
        );

  bool get _dirty {
    final current = _build();
    if (_original == null) {
      return _mood != null ||
          _note.text.trim().isNotEmpty ||
          _symptoms.isNotEmpty ||
          _meds.isNotEmpty;
    }
    return current != _original;
  }

  Future<void> _save() async {
    final entry = _build();
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a mood to save this entry.')),
      );
      return;
    }
    setState(() => _saving = true);
    await _stopListening();
    await ref.read(logEntryProvider)(entry);
    if (!mounted) return;
    // The caller shows this in its own tab once we're gone.
    Navigator.of(context).pop(_isNew ? 'Entry saved' : 'Entry updated');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('It will be permanently removed from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(journalRepoProvider).deleteEntry(_original!.id);
    if (mounted) Navigator.of(context).pop('Entry deleted');
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _createdAt,
      firstDate: DateTime(2000),
      lastDate: clock.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_createdAt),
    );
    if (time == null) return;
    setState(
      () => _createdAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _toggleVoice() async {
    if (_listening) return _stopListening();
    final speech = ref.read(speechInputProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (!await speech.initialize()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Speech recognition is unavailable or microphone access was denied.',
          ),
        ),
      );
      return;
    }
    _noteBeforeListening = _note.text.trimRight();
    setState(() => _listening = true);
    await speech.start(
      onResult: (text, {required isFinal}) {
        if (!mounted) return;
        final sep = _noteBeforeListening.isEmpty ? '' : ' ';
        setState(() {
          _note.text = '$_noteBeforeListening$sep$text';
          if (text.isNotEmpty) _fromVoice = true;
          if (isFinal) _listening = false;
        });
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _listening = false);
        messenger.showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    await ref.read(speechInputProvider).stop();
    if (mounted) setState(() => _listening = false);
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  void dispose() {
    unawaited(_stopListening());
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = MindfullTokens.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_isNew && _original == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This entry no longer exists.')),
      );
    }

    const gap = SizedBox(height: 16);
    final sleep = _sleep;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: MindfullScaffold(
        title: _isNew ? 'New Entry' : 'Edit Entry',
        scene: Scene.entry,
        showOverline: false,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          const NetworkIndicator(),
        ],
        body: (context, padding) => ListView(
          padding: padding,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Material(
                    color: t.card,
                    shape: StadiumBorder(side: BorderSide(color: t.cardBorder)),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: _pickDateTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 17,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                clock.now().difference(_createdAt).inDays < 6
                                    ? relativeTimestamp(_createdAt)
                                    : DateFormat(
                                        'EEE d MMM, ',
                                      ).add_jm().format(_createdAt),
                                style: theme.textTheme.labelMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.edit_outlined,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
            gap,
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardHeading(
                    title: 'How are you feeling?',
                    trailing: Text(
                      _mood == null ? 'Tap to set' : moodLabel(_mood!),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  const SizedBox(height: 14),
                  MoodPicker(
                    value: _mood,
                    onChanged: (m) => setState(() => _mood = m),
                  ),
                ],
              ),
            ),
            gap,
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardHeading(
                    title: 'Symptoms',
                    icon: Icons.cyclone,
                    iconColor: theme.colorScheme.tertiary,
                    trailing: _count(_symptoms.length, 'recorded'),
                  ),
                  const SizedBox(height: 12),
                  TagPicker(
                    kind: TagKind.symptom,
                    selected: _symptoms,
                    hint: 'Add a symptom',
                    onChanged: (v) => setState(() => _symptoms = v),
                  ),
                ],
              ),
            ),
            gap,
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardHeading(
                    title: 'Medications & Relief',
                    icon: Icons.medication_outlined,
                    iconColor: theme.colorScheme.secondary,
                    trailing: _count(_meds.length, 'taken'),
                  ),
                  const SizedBox(height: 12),
                  TagPicker(
                    kind: TagKind.medication,
                    selected: _meds,
                    hint: 'e.g. Sumatriptan 50mg',
                    onChanged: (v) => setState(() => _meds = v),
                  ),
                ],
              ),
            ),
            gap,
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardHeading(
                    title: 'Rest & Sleep',
                    icon: Icons.dark_mode_outlined,
                    trailing: Pill(
                      label: sleep == null
                          ? 'Not logged'
                          : '${sleep.toStringAsFixed(1)} hours',
                      background: sleep == null
                          ? null
                          : theme.colorScheme.primaryFixed.withValues(
                              alpha: 0.5,
                            ),
                      foreground: sleep == null
                          ? null
                          : theme.colorScheme.onPrimaryFixedVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: sleep == null
                          ? theme.colorScheme.surfaceContainerHighest
                          : null,
                      thumbColor: sleep == null
                          ? theme.colorScheme.outline
                          : null,
                    ),
                    child: Slider(
                      max: 14,
                      divisions: 28,
                      value: sleep ?? 7,
                      semanticFormatterCallback: (v) => sleep == null
                          ? 'Sleep not logged'
                          : '${v.toStringAsFixed(1)} hours',
                      onChanged: (v) => setState(() => _sleep = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Text('0h', style: theme.textTheme.labelSmall),
                        const Spacer(),
                        Text(
                          '7–8h (Restorative)',
                          style: theme.textTheme.labelSmall,
                        ),
                        const Spacer(),
                        Text('14h', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                  if (sleep != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _sleep = null),
                        child: const Text('Clear'),
                      ),
                    ),
                ],
              ),
            ),
            gap,
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardHeading(
                    title: 'Notes',
                    icon: Icons.draw_outlined,
                    iconColor: theme.colorScheme.onSurfaceVariant,
                    trailing: _listening
                        ? null
                        : ActionChip(
                            avatar: Icon(
                              Icons.graphic_eq,
                              size: 16,
                              color: theme.colorScheme.secondary,
                            ),
                            label: const Text('Dictate'),
                            tooltip: 'Dictate (on-device)',
                            labelStyle: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.secondary,
                            ),
                            backgroundColor: theme
                                .colorScheme
                                .secondaryContainer
                                .withValues(alpha: 0.5),
                            visualDensity: VisualDensity.compact,
                            onPressed: _toggleVoice,
                          ),
                  ),
                  if (_listening) ...[
                    const SizedBox(height: 12),
                    _ListeningBanner(onStop: _toggleVoice),
                  ],
                  const SizedBox(height: 8),
                  _RuledNoteField(
                    controller: _note,
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kept on this phone in AES-256 encrypted storage. Nothing is uploaded.',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.spa_outlined),
              label: const Text('Save Journal Entry'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _count(int n, String word) => n == 0
      ? null
      : Text('$n $word', style: Theme.of(context).textTheme.labelSmall);
}

class _ListeningBanner extends StatelessWidget {
  const _ListeningBanner({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: 'Listening on-device',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Listening on-device…',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: scheme.onPrimary),
              ),
            ),
            TextButton(
              onPressed: onStop,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onPrimary,
                backgroundColor: scheme.onPrimary.withValues(alpha: 0.2),
                minimumSize: const Size(48, 36),
              ),
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Borderless multi-line field over faint notebook ruling.
class _RuledNoteField extends StatelessWidget {
  const _RuledNoteField({required this.controller, required this.onChanged});

  static const _lineHeight = 30.0;

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge!.copyWith(height: _lineHeight / 18);
    return CustomPaint(
      painter: _RulingPainter(
        color: MindfullTokens.of(context).brand.withValues(alpha: 0.1),
        lineHeight: _lineHeight,
        top: 8,
      ),
      child: TextField(
        controller: controller,
        minLines: 5,
        maxLines: null,
        style: style,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.only(top: 8, bottom: 8),
          hintText:
              'How does your body feel right now? Triggers, food, stress, how the day went…',
          hintMaxLines: 4,
          hintStyle: style.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _RulingPainter extends CustomPainter {
  _RulingPainter({
    required this.color,
    required this.lineHeight,
    required this.top,
  });

  final Color color;
  final double lineHeight;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = top + lineHeight - 2; y < size.height; y += lineHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RulingPainter old) =>
      old.color != color || old.lineHeight != lineHeight;
}
