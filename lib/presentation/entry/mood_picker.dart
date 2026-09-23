import 'package:flutter/material.dart';
import 'package:mindfull/presentation/shared/mood.dart';

class MoodPicker extends StatelessWidget {
  const MoodPicker({required this.value, required this.onChanged, super.key});

  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var m = 1; m <= 5; m++)
          Expanded(
            child: Semantics(
              button: true,
              selected: value == m,
              label: 'Mood ${moodLabel(m)}',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onChanged(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      AnimatedScale(
                        scale: value == m ? 1.08 : 1,
                        duration: const Duration(milliseconds: 160),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: moodWash(
                              m,
                              strength: value == m ? 0.38 : 0.16,
                            ),
                            border: value == m
                                ? Border.all(color: moodColor(m), width: 2)
                                : null,
                            boxShadow: value == m
                                ? [
                                    BoxShadow(
                                      color: moodColor(
                                        m,
                                      ).withValues(alpha: 0.3),
                                      blurRadius: 12,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            moodIcon(m),
                            size: 28,
                            color: moodInk(m, theme.brightness),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        moodLabel(m),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: value == m
                              ? moodInk(m, theme.brightness)
                              : null,
                          fontWeight: value == m ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
