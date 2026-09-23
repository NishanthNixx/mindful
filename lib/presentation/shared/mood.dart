import 'package:flutter/material.dart';

const List<String> moodLabels = ['Very low', 'Low', 'Okay', 'Good', 'Great'];

const List<IconData> _moodIcons = [
  Icons.sentiment_very_dissatisfied_outlined,
  Icons.sentiment_dissatisfied_outlined,
  Icons.sentiment_neutral_outlined,
  Icons.sentiment_satisfied_outlined,
  Icons.sentiment_very_satisfied_outlined,
];

// Stitch "accessible mood spectrum": terracotta -> amber -> olive wheat ->
// muted sage -> ocean teal. Never red/green, always shown with icon + label.
const List<Color> _moodColors = [
  Color(0xFFD9764A),
  Color(0xFFE0A24E),
  Color(0xFF9E9754),
  Color(0xFF5E987E),
  Color(0xFF388787),
];

IconData moodIcon(int mood) => _moodIcons[mood - 1];

Color moodColor(int mood) => _moodColors[mood - 1];

String moodLabel(int mood) => moodLabels[mood - 1];

/// Text/icon colour on a light wash of [moodColor]: darkened in light mode,
/// lightened in dark mode, to keep AA contrast.
Color moodInk(int mood, Brightness brightness) {
  final hsl = HSLColor.fromColor(moodColor(mood));
  return brightness == Brightness.light
      ? hsl.withLightness((hsl.lightness * 0.55).clamp(0.2, 0.35)).toColor()
      : hsl.withLightness(0.78).toColor();
}

/// Soft background wash behind a mood icon or pill.
Color moodWash(int mood, {double strength = 0.18}) =>
    moodColor(mood).withValues(alpha: strength);
