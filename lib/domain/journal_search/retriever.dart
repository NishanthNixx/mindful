import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:mindfull/domain/ai/embedder.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/journal_search/embedding_store.dart';
import 'package:mindfull/domain/journal_search/query_parser.dart';

@immutable
class RetrievedEntry {
  const RetrievedEntry({required this.entry, required this.score});

  final JournalEntry entry;
  final double score;
}

@immutable
class Retrieval {
  const Retrieval({
    required this.query,
    required this.entries,
    required this.facts,
  });

  final ParsedQuery query;

  /// Chronological; the prompt numbers them 1..n in this order.
  final List<RetrievedEntry> entries;

  /// Plain numbers computed from the whole journal (not just the top-k), so
  /// trend questions rest on counts rather than the model's guess.
  final List<String> facts;
}

/// The text embedded for an entry. Changing this changes every hash, so all
/// entries are re-embedded once.
String embeddingText(JournalEntry e) {
  final parts = [
    if (e.symptoms.isNotEmpty) 'Symptoms: ${e.symptoms.join(', ')}.',
    if (e.medications.isNotEmpty) 'Medication: ${e.medications.join(', ')}.',
    'Mood ${e.mood} of 5.',
    if (e.sleepHours != null) 'Slept ${e.sleepHours} hours.',
    if (e.note.trim().isNotEmpty) e.note.trim(),
  ];
  return parts.join(' ');
}

double cosine(List<double> a, List<double> b) {
  var dot = 0.0;
  var na = 0.0;
  var nb = 0.0;
  for (var i = 0; i < min(a.length, b.length); i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na == 0 || nb == 0 ? 0 : dot / (sqrt(na) * sqrt(nb));
}

/// Hybrid retrieval: date range and tag names narrow and boost candidates,
/// cosine similarity ranks them, recency breaks ties. Entries not indexed
/// yet fall back to word overlap so search degrades rather than fails.
class JournalRetriever {
  JournalRetriever({
    required this.embedder,
    required this.store,
    this.k = 8,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Embedder embedder;
  final EmbeddingStore store;
  final int k;
  final DateTime Function() _now;

  static const _tagBoost = 0.25;
  static const _recencyBoost = 0.05;

  Future<Retrieval> retrieve(
    String question,
    List<JournalEntry> journal,
  ) async {
    final now = _now();
    final knownTags = {
      for (final e in journal) ...e.symptoms,
      for (final e in journal) ...e.medications,
    };
    final query = parseQuery(question, now: now, knownTags: knownTags);

    var candidates = journal;
    if (query.range case final r?) {
      candidates = [
        for (final e in journal)
          if (r.contains(e.createdAt)) e,
      ];
    }
    if (query.tags.isNotEmpty) {
      final tagged = [
        for (final e in candidates)
          if (_hasAny(e, query.tags) ||
              query.tags.any((t) => _noteMentions(e, t)))
            e,
      ];
      // Asking about a symptom: those entries first, but keep a few others
      // (e.g. good days) for contrast.
      if (tagged.isNotEmpty) {
        candidates = [
          ...tagged,
          ...candidates.where((e) => !tagged.contains(e)),
        ];
      }
    }

    final vectors = await store.all(embedder.modelId);
    final queryVector = await embedder.embed(question);
    final queryWords = _words(question);

    double similarity(JournalEntry e) {
      final v = vectors[e.id];
      return v != null
          ? cosine(queryVector, v.vector)
          : _overlap(queryWords, _words(embeddingText(e)));
    }

    final scored = <RetrievedEntry>[
      for (final e in candidates)
        RetrievedEntry(
          entry: e,
          score:
              similarity(e) +
              (_hasAny(e, query.tags) ||
                      query.tags.any((t) => _noteMentions(e, t))
                  ? _tagBoost
                  : 0) +
              _recencyBoost *
                  exp(-now.difference(e.createdAt).inHours / (24 * 30)),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));

    final top = scored.take(k).toList()
      ..sort((a, b) => a.entry.createdAt.compareTo(b.entry.createdAt));
    return Retrieval(
      query: query,
      entries: top,
      facts: _facts(query, journal, now),
    );
  }

  static String _times(int n, String one, String many) =>
      '$n ${n == 1 ? one : many}';

  /// The note mentions [tag] (or its first word, plural-tolerant).
  static bool _noteMentions(JournalEntry e, String tag) {
    final note =
        ' ${e.note.toLowerCase().replaceAll(RegExp('[^a-z0-9 ]'), ' ')} ';
    final t = tag.toLowerCase().split(' ').first;
    if (t.length < 4) return false;
    return note.contains(' $t ') ||
        note.contains(' ${t}s ') ||
        note.contains(' ${t}es ');
  }

  static const _stopwords = {
    'the',
    'and',
    'was',
    'were',
    'with',
    'after',
    'before',
    'this',
    'that',
    'had',
    'have',
    'from',
    'but',
    'for',
    'all',
    'too',
    'very',
    'felt',
    'feel',
    'feeling',
    'day',
    'today',
    'again',
    'some',
    'just',
    'then',
    'into',
    'about',
    'still',
    'much',
    'more',
    'got',
    'went',
    'really',
    'bit',
    'also',
  };

  /// Non-trivial words appearing in the notes of at least two of [entries].
  static List<String> _recurringNoteWords(
    List<JournalEntry> entries, {
    required String exclude,
  }) {
    final skip = exclude.toLowerCase().split(' ').first;
    final counts = <String, int>{};
    for (final e in entries) {
      final words = RegExp(
        '[a-z]{4,}',
      ).allMatches(e.note.toLowerCase()).map((m) => m.group(0)!).toSet();
      for (final w in words) {
        if (_stopwords.contains(w) || w.startsWith(skip)) continue;
        counts.update(w, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return (counts.entries.where((c) => c.value >= 2).toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((c) => c.key)
        .toList();
  }

  static bool _hasAny(JournalEntry e, Set<String> tags) =>
      tags.isNotEmpty &&
      [...e.symptoms, ...e.medications].any((t) => tags.contains(t));

  static Set<String> _words(String s) => RegExp(
    '[a-z]{3,}',
  ).allMatches(s.toLowerCase()).map((m) => m.group(0)!).toSet();

  static double _overlap(Set<String> a, Set<String> b) => a.isEmpty || b.isEmpty
      ? 0
      : a.intersection(b).length / sqrt(a.length * b.length);

  List<String> _facts(ParsedQuery q, List<JournalEntry> journal, DateTime now) {
    final fmt = DateFormat('d MMM');
    final facts = <String>[];
    final range = q.range;
    final scope = range == null
        ? journal
        : [
            for (final e in journal)
              if (range.contains(e.createdAt)) e,
          ];

    if (range != null) {
      final end = range.end.subtract(const Duration(days: 1));
      facts.add(
        'Period asked about: ${fmt.format(range.start)} – ${fmt.format(end)} (${scope.length} entries).',
      );
    }
    if (scope.isNotEmpty) {
      final mood = scope.map((e) => e.mood).average;
      final sleep = scope.map((e) => e.sleepHours).nonNulls.toList();
      facts.add(
        'Average mood ${mood.toStringAsFixed(1)} of 5'
        '${sleep.isEmpty ? '' : ', average sleep ${sleep.average.toStringAsFixed(1)} h'}'
        '${range == null ? ' across all ${scope.length} entries' : ' in that period'}.',
      );
    }

    for (final tag in q.tags) {
      final tagged = [
        for (final e in journal)
          if (_hasAny(e, {tag})) e,
      ];
      final noted = [
        for (final e in journal)
          if (!_hasAny(e, {tag}) && _noteMentions(e, tag)) e,
      ];
      final hits = [...tagged, ...noted]..sortBy((e) => e.createdAt);
      if (hits.isEmpty) continue;
      facts.add(
        '$tag: ${_times(hits.length, 'entry', 'entries')} in total '
        '(tagged in ${tagged.length}${noted.isEmpty ? '' : ', mentioned only in the note of ${noted.length}'}); '
        'first ${fmt.format(hits.first.createdAt)}, most recent ${fmt.format(hits.last.createdAt)}.',
      );

      // Weekly counts over the last 6 weeks show direction ("getting worse").
      final today = DateTime(now.year, now.month, now.day);
      final weeks = <String>[];
      for (var w = 5; w >= 0; w--) {
        final start = today.subtract(Duration(days: 7 * w + 6));
        final end = today.subtract(Duration(days: 7 * w - 1));
        final n = hits
            .where(
              (e) => !e.createdAt.isBefore(start) && e.createdAt.isBefore(end),
            )
            .length;
        weeks.add('week of ${fmt.format(start)}: $n');
      }
      facts.add('$tag per week, oldest first: ${weeks.join('; ')}.');

      // Contrast with the rest of the journal: the raw material for "why?".
      final others = [
        for (final e in journal)
          if (!hits.contains(e)) e,
      ];
      String avg(List<JournalEntry> es) {
        final sleep = es.map((e) => e.sleepHours).nonNulls.toList();
        return 'mood ${es.map((e) => e.mood).average.toStringAsFixed(1)}/5'
            '${sleep.isEmpty ? '' : ', sleep ${sleep.average.toStringAsFixed(1)} h'}';
      }

      if (others.isNotEmpty) {
        facts.add(
          'On $tag days the average was ${avg(hits)}; on other days ${avg(others)}.',
        );
      }
      final withSleep = hits.where((e) => e.sleepHours != null).toList();
      if (withSleep.length >= 2) {
        final short = withSleep.where((e) => e.sleepHours! < 6).length;
        facts.add(
          '$short of ${withSleep.length} $tag entries with sleep logged had under 6 h of sleep.',
        );
      }
      final together = <String, int>{};
      for (final e in hits) {
        for (final t in [...e.symptoms, ...e.medications]) {
          if (t != tag) together.update(t, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      if (together.isNotEmpty) {
        final top = together.entries
            .sorted((a, b) => b.value.compareTo(a.value))
            .take(4);
        facts.add(
          'Often logged together with $tag: ${top.map((t) => '${t.key} (${t.value})').join(', ')}.',
        );
      }
      final words = _recurringNoteWords(hits, exclude: tag);
      if (words.isNotEmpty) {
        facts.add(
          'Words that recur in notes on $tag days: ${words.join(', ')}.',
        );
      }
    }
    return facts;
  }
}
