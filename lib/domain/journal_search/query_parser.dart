import 'package:flutter/foundation.dart';

@immutable
class DateRange {
  const DateRange(this.start, this.end);

  /// Inclusive.
  final DateTime start;

  /// Exclusive.
  final DateTime end;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start – $end)';
}

@immutable
class ParsedQuery {
  const ParsedQuery({required this.text, this.range, this.tags = const {}});

  final String text;
  final DateRange? range;

  /// Known symptom/medication names mentioned in the question (as stored).
  final Set<String> tags;
}

const _months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

const _numberWords = {
  'a': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'couple of': 2,
  'few': 3,
};

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Pulls a date range and known tag names out of a journal question, so
/// retrieval can combine structure ("last week", "headaches") with
/// semantic similarity. Deliberately small and predictable.
ParsedQuery parseQuery(
  String question, {
  required DateTime now,
  required Iterable<String> knownTags,
}) {
  final q = question.toLowerCase();
  return ParsedQuery(
    text: question,
    range: _range(q, now),
    tags: _tags(q, knownTags),
  );
}

DateRange? _range(String q, DateTime now) {
  final today = _day(now);
  final tomorrow = today.add(const Duration(days: 1));
  DateTime daysAgo(int n) => DateTime(today.year, today.month, today.day - n);
  final monday = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - 1),
  );

  if (RegExp(r'\btoday\b').hasMatch(q)) return DateRange(today, tomorrow);
  if (RegExp(r'\byesterday\b').hasMatch(q)) return DateRange(daysAgo(1), today);
  if (RegExp(r'\bthis week\b').hasMatch(q)) return DateRange(monday, tomorrow);
  if (RegExp(r'\blast week\b').hasMatch(q)) {
    return DateRange(monday.subtract(const Duration(days: 7)), monday);
  }
  if (RegExp(r'\bthis month\b').hasMatch(q)) {
    return DateRange(DateTime(today.year, today.month), tomorrow);
  }
  if (RegExp(r'\blast month\b').hasMatch(q)) {
    return DateRange(
      DateTime(today.year, today.month - 1),
      DateTime(today.year, today.month),
    );
  }

  final span = RegExp(
    r'\b(?:last|past)\s+(\d+|a|one|two|three|four|five|six|couple of|few)?\s*(day|week|month)s?\b',
  ).firstMatch(q);
  if (span != null) {
    final raw = span.group(1);
    final n = raw == null ? 1 : int.tryParse(raw) ?? _numberWords[raw] ?? 1;
    final days = switch (span.group(2)) {
      'day' => n,
      'week' => 7 * n,
      _ => 30 * n,
    };
    return DateRange(daysAgo(days - 1), tomorrow);
  }
  if (RegExp(r'\b(?:recently|lately)\b').hasMatch(q)) {
    return DateRange(daysAgo(29), tomorrow);
  }

  for (var i = 0; i < 12; i++) {
    final m = RegExp(
      '\\b(since|in|during|from)\\s+${_months[i]}(?:\\s+(\\d{4}))?\\b',
    ).firstMatch(q);
    if (m == null) continue;
    final explicitYear = int.tryParse(m.group(2) ?? '');
    // A month later than now without a year means last year's.
    final year =
        explicitYear ?? (i + 1 > today.month ? today.year - 1 : today.year);
    final start = DateTime(year, i + 1);
    return m.group(1) == 'since'
        ? DateRange(start, tomorrow)
        : DateRange(start, DateTime(year, i + 2));
  }
  return null;
}

/// Matches whole words, tolerating simple plurals ("headaches" → Headache).
Set<String> _tags(String q, Iterable<String> knownTags) {
  final words = RegExp(
    "[a-z0-9']+",
  ).allMatches(q).map((m) => m.group(0)!).toList();
  final text = ' ${words.join(' ')} ';
  final found = <String>{};
  for (final tag in knownTags) {
    final t = RegExp(
      "[a-z0-9']+",
    ).allMatches(tag.toLowerCase()).map((m) => m.group(0)!).join(' ');
    if (t.isEmpty) continue;
    // Also match the tag's first word for multi-word tags like "Sumatriptan 50mg".
    final first = t.split(' ').first;
    final variants = {
      t,
      '${t}s',
      '${t}es',
      if (first.length >= 4) first,
      if (first.length >= 4) '${first}s',
    };
    if (variants.any((v) => text.contains(' $v '))) found.add(tag);
  }
  return found;
}
