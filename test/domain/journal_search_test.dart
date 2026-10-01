import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/journal_search/embedding_store.dart';
import 'package:mindfull/domain/journal_search/prompt.dart';
import 'package:mindfull/domain/journal_search/query_parser.dart';
import 'package:mindfull/domain/journal_search/retriever.dart';

import '../helpers.dart';
import '../support/sample_journal.dart';

class _MemoryStore implements EmbeddingStore {
  final rows = <String, StoredEmbedding>{};

  @override
  Future<Map<String, StoredEmbedding>> all(String modelId) async => {
    for (final r in rows.values)
      if (r.modelId == modelId) r.entryId: r,
  };

  @override
  Future<void> clear() async => rows.clear();

  @override
  Future<void> delete(String entryId) async => rows.remove(entryId);

  @override
  Future<void> upsert(StoredEmbedding e) async => rows[e.entryId] = e;
}

void main() {
  final tags = {
    for (final e in sampleJournal) ...e.symptoms,
    for (final e in sampleJournal) ...e.medications,
  };
  ParsedQuery parse(String q) => parseQuery(q, now: sampleNow, knownTags: tags);

  group('query parser', () {
    test('relative date phrases', () {
      expect(
        parse('how was today?').range,
        DateRange(DateTime(2026, 9, 23), DateTime(2026, 9, 24)),
      );
      expect(
        parse('what about yesterday').range,
        DateRange(DateTime(2026, 9, 22), DateTime(2026, 9, 23)),
      );
      // Wednesday 23 Sep: this week starts Monday 21, last week is 14–20.
      expect(
        parse('sleep this week').range,
        DateRange(DateTime(2026, 9, 21), DateTime(2026, 9, 24)),
      );
      expect(
        parse('sleep last week').range,
        DateRange(DateTime(2026, 9, 14), DateTime(2026, 9, 21)),
      );
      expect(
        parse('in the last 3 days').range,
        DateRange(DateTime(2026, 9, 21), DateTime(2026, 9, 24)),
      );
      expect(
        parse('past two weeks').range,
        DateRange(DateTime(2026, 9, 10), DateTime(2026, 9, 24)),
      );
      expect(
        parse('this month').range,
        DateRange(DateTime(2026, 9), DateTime(2026, 9, 24)),
      );
      expect(
        parse('last month').range,
        DateRange(DateTime(2026, 8), DateTime(2026, 9)),
      );
      expect(parse('lately').range?.start, DateTime(2026, 8, 25));
    });

    test('month names, with and without a year', () {
      expect(
        parse('what did I do in August?').range,
        DateRange(DateTime(2026, 8), DateTime(2026, 9)),
      );
      expect(
        parse('since June').range,
        DateRange(DateTime(2026, 6), DateTime(2026, 9, 24)),
      );
      // December is in the future in September, so it means last year.
      expect(
        parse('in December').range,
        DateRange(DateTime(2025, 12), DateTime(2026)),
      );
      expect(
        parse('during March 2025').range,
        DateRange(DateTime(2025, 3), DateTime(2025, 4)),
      );
      expect(
        parse('may I ask something').range,
        isNull,
        reason: '"may" is not a month here',
      );
    });

    test('tags match whole words and simple plurals', () {
      expect(parse('When did my headaches start getting worse?').tags, {
        'Headache',
      });
      expect(parse('migraines and nausea').tags, {'Migraine', 'Nausea'});
      expect(parse('did sumatriptan help').tags, {'Sumatriptan 50mg'});
      expect(parse('light sensitivity at work').tags, {'Light sensitivity'});
      expect(parse('I feel great').tags, isEmpty);
    });
  });

  group('retriever', () {
    late JournalRetriever retriever;
    late _MemoryStore store;
    final embedder = FakeEmbedder();

    setUp(() async {
      store = _MemoryStore();
      for (final e in sampleJournal) {
        store.rows[e.id] = StoredEmbedding(
          entryId: e.id,
          modelId: embedder.modelId,
          textHash: 'h',
          vector: Float32List.fromList(await embedder.embed(embeddingText(e))),
        );
      }
      retriever = JournalRetriever(
        embedder: embedder,
        store: store,
        k: 4,
        now: () => sampleNow,
      );
    });

    Future<List<String>> ids(String q) async => (await retriever.retrieve(
      q,
      sampleJournal,
    )).entries.map((r) => r.entry.id).toList();

    // Each question lists entries that must be among the sources.
    final expectations = <String, List<String>>{
      'When did my migraines start getting worse?': [
        'sep02-migraine',
        'sep12-worst',
        'sep15-migraine',
      ],
      'How were my headaches this month?': ['sep10-headache', 'sep22-screen'],
      'Did Sumatriptan help?': ['sep02-migraine', 'sep12-worst'],
      'Did I feel anxious recently?': ['sep21-anxious'],
      'When did I do yoga?': ['sep20-yoga'],
      'What did I do in August?': ['aug-river'],
    };

    for (final MapEntry(key: q, value: want) in expectations.entries) {
      test('cites the right entries: "$q"', () async {
        expect(await ids(q), containsAll(want));
      });
    }

    test('a date range excludes entries outside it', () async {
      final got = await ids('How did I sleep last week?');
      expect(got, isNotEmpty);
      final r = (await retriever.retrieve(
        'How did I sleep last week?',
        sampleJournal,
      )).entries;
      for (final e in r) {
        expect(
          e.entry.createdAt.isAfter(DateTime(2026, 9, 14)) &&
              e.entry.createdAt.isBefore(DateTime(2026, 9, 21)),
          isTrue,
        );
      }
    });

    test('sources are chronological for the prompt', () async {
      final r = await retriever.retrieve('migraines', sampleJournal);
      final dates = r.entries.map((e) => e.entry.createdAt).toList();
      expect(dates, [...dates]..sort());
    });

    test('facts carry counts, dates and the sleep link', () async {
      final r = await retriever.retrieve(
        'When did my migraines start getting worse?',
        sampleJournal,
      );
      expect(
        r.facts,
        contains(
          'Migraine: 3 entries in total (tagged in 3); first 2 Sep, most recent 15 Sep.',
        ),
      );
      expect(r.facts.any((f) => f.startsWith('Migraine per week')), isTrue);
      expect(
        r.facts,
        contains(
          '3 of 3 Migraine entries with sleep logged had under 6 h of sleep.',
        ),
      );
    });

    test(
      'a symptom only mentioned in a note is counted, and counts stay consistent',
      () async {
        // The on-device case: one entry tagged Headache, another only says it in the note.
        final journal = [
          sampleJournal[0],
          JournalEntry(
            id: 'tagged',
            createdAt: DateTime(2026, 9, 23, 9),
            mood: 1,
            symptoms: const ['Headache'],
            note: 'Bad day.',
          ),
          JournalEntry(
            id: 'noted',
            createdAt: DateTime(2026, 9, 23, 18),
            mood: 3,
            symptoms: const ['Brain fog'],
            note: 'Headache again after work.',
          ),
        ];
        final r = await JournalRetriever(
          embedder: FakeEmbedder(),
          store: _MemoryStore(),
          now: () => sampleNow,
        ).retrieve('why am I having headaches all the time', journal);
        expect(
          r.facts,
          contains(
            'Headache: 2 entries in total (tagged in 1, mentioned only in the note of 1); first 23 Sep, most recent 23 Sep.',
          ),
        );
        expect(
          r.entries.map((e) => e.entry.id),
          containsAll(['tagged', 'noted']),
        );
      },
    );

    test(
      'why-facts: contrast with other days, companions, recurring note words',
      () async {
        final r = await retriever.retrieve(
          'Why do I keep getting migraines?',
          sampleJournal,
        );
        final contrast = r.facts.firstWhere(
          (f) => f.startsWith('On Migraine days'),
        );
        expect(contrast, contains('mood 1.7/5, sleep 4.8 h'));
        expect(contrast, contains('on other days mood 3.5/5, sleep 7.1 h'));
        expect(
          r.facts,
          contains(
            'Often logged together with Migraine: Sumatriptan 50mg (2), Nausea (1), Light sensitivity (1).',
          ),
        );
      },
    );

    test('unindexed entries still match by words', () async {
      store.rows.remove('sep20-yoga');
      expect(await ids('When did I do yoga?'), contains('sep20-yoga'));
    });
  });

  group('prompt', () {
    test('numbers entries and includes facts, date and question', () async {
      final store = _MemoryStore();
      final r = await JournalRetriever(
        embedder: FakeEmbedder(),
        store: store,
        k: 2,
        now: () => sampleNow,
      ).retrieve('migraines', sampleJournal);
      final prompt = buildJournalPrompt('migraines', r, now: sampleNow);
      expect(prompt, contains('[1] '));
      expect(prompt, contains('[2] '));
      expect(prompt, isNot(contains('[3] ')));
      expect(prompt, contains('Summary numbers computed by the app'));
      expect(prompt, contains('do not cite'));
      expect(prompt, contains('Today is Wednesday 23 September 2026.'));
      expect(prompt, endsWith('Question: migraines'));
    });

    test('entry description is compact and complete', () {
      final text = describeEntry(sampleJournal[3]);
      expect(text, contains('Sat 12 Sep 2026'));
      expect(text, contains('mood 1/5 (very low)'));
      expect(text, contains('slept 4.5 h'));
      expect(text, contains('symptoms: Migraine, Nausea'));
      expect(text, contains('medication: Sumatriptan 50mg'));
      expect(
        text,
        contains('note: "Worst migraine this month, aura at work."'),
      );
    });

    test('citations: formats, order, bounds', () {
      expect(citedNumbers('Worse from [2] to [3].', 5), [2, 3]);
      expect(citedNumbers('See [1][3] and [1, 4].', 5), [1, 3, 4]);
      expect(citedNumbers('Out of range [9] and [0].', 3), isEmpty);
      expect(citedNumbers('No citations.', 3), isEmpty);
    });

    test(
      'the instruction demands citations, handles "why", forbids diagnosis',
      () {
        expect(journalSystemInstruction, contains('ONLY'));
        expect(journalSystemInstruction, contains('[2]'));
        expect(
          journalSystemInstruction,
          contains('never put a citation after a summary number'),
        );
        expect(journalSystemInstruction, contains('WHY'));
        expect(journalSystemInstruction, contains('cannot show causes'));
        expect(journalSystemInstruction, contains('Never diagnose'));
      },
    );

    test('a follow-up carries the previous exchange', () async {
      final r = await JournalRetriever(
        embedder: FakeEmbedder(),
        store: _MemoryStore(),
        k: 2,
        now: () => sampleNow,
      ).retrieve('why do I get headaches', sampleJournal);
      final prompt = buildJournalPrompt(
        'No, I meant why am I having headaches all the time',
        r,
        now: sampleNow,
        previous: const PriorTurn(
          question: 'How often do I get headaches?',
          answer: 'Twice this month [1][2].',
        ),
      );
      expect(
        prompt,
        startsWith(
          'Earlier in this conversation:\nUser: How often do I get headaches?\nYou: Twice',
        ),
      );
    });

    test('follow-up detection', () {
      expect(
        isFollowUp('No i meant why am i ahaving headaches all time'),
        isTrue,
      );
      expect(isFollowUp('what about last week?'), isTrue);
      expect(isFollowUp('why does that happen'), isTrue);
      expect(isFollowUp('How has my sleep been this month?'), isFalse);
      expect(isFollowUp('When did my migraines start getting worse?'), isFalse);
    });
  });
}
