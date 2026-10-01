import 'package:intl/intl.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/journal_search/retriever.dart';

const journalSystemInstruction =
    "You are Mindfull, a calm assistant that answers questions about the user's own "
    'health journal, entirely on their phone. Rules:\n'
    '1. Use ONLY the numbered journal entries and the summary numbers you are given.\n'
    '2. Cite entries by their number in square brackets, like [2] or [1][3]. Only entries '
    'have numbers: never put a citation after a summary number.\n'
    '3. If asked WHY something happens: say the journal cannot show causes, then describe '
    'what tends to appear with it in the entries (sleep, stress, food, screen time, '
    'medication, mood) compared with other days, citing entries, and suggest discussing '
    'the pattern with a doctor.\n'
    "4. If the entries don't contain the answer, say you couldn't find that in the journal.\n"
    '5. Describe patterns as possible links, never causes. Never diagnose or suggest '
    'changing medication.\n'
    '6. Answer the question asked, in 2 to 5 short sentences. Be consistent with the numbers.';

/// The previous exchange, so a follow-up like "No, I meant…" makes sense.
class PriorTurn {
  const PriorTurn({required this.question, required this.answer});

  final String question;
  final String answer;
}

const _moodWords = ['very low', 'low', 'okay', 'good', 'great'];
const _maxNoteChars = 320;

String describeEntry(JournalEntry e) {
  final when = DateFormat('EEE d MMM y, h:mm a').format(e.createdAt);
  final note = e.note.trim().replaceAll(RegExp(r'\s+'), ' ');
  return [
    when,
    'mood ${e.mood}/5 (${_moodWords[e.mood - 1]})',
    if (e.sleepHours != null) 'slept ${e.sleepHours} h',
    if (e.symptoms.isNotEmpty) 'symptoms: ${e.symptoms.join(', ')}',
    if (e.medications.isNotEmpty) 'medication: ${e.medications.join(', ')}',
    if (note.isNotEmpty)
      'note: "${note.length > _maxNoteChars ? '${note.substring(0, _maxNoteChars)}…' : note}"',
  ].join(' · ');
}

/// The user turn sent to the model for a journal question.
String buildJournalPrompt(
  String question,
  Retrieval r, {
  required DateTime now,
  PriorTurn? previous,
}) {
  final b = StringBuffer();
  if (previous != null) {
    final answer = previous.answer.replaceAll(RegExp(r'\s+'), ' ').trim();
    b
      ..writeln('Earlier in this conversation:')
      ..writeln('User: ${previous.question}')
      ..writeln(
        'You: ${answer.length > 400 ? '${answer.substring(0, 400)}…' : answer}',
      )
      ..writeln();
  }
  b.writeln('Journal entries:');
  if (r.entries.isEmpty) b.writeln('(none match this question)');
  for (var i = 0; i < r.entries.length; i++) {
    b.writeln('[${i + 1}] ${describeEntry(r.entries[i].entry)}');
  }
  if (r.facts.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        'Summary numbers computed by the app from the whole journal (not entries; do not cite):',
      );
    for (final f in r.facts) {
      b.writeln('- $f');
    }
  }
  b
    ..writeln()
    ..writeln('Today is ${DateFormat('EEEE d MMMM y').format(now)}.')
    ..write('Question: $question');
  return b.toString();
}

/// Entry numbers the answer cites, e.g. "[2]", "[1][3]" or "[1, 3]", in order
/// of first appearance. Numbers outside 1..[count] are ignored.
List<int> citedNumbers(String answer, int count) {
  final seen = <int>{};
  for (final m in RegExp(r'\[(\d+(?:\s*[,;]\s*\d+)*)\]').allMatches(answer)) {
    for (final n in m.group(1)!.split(RegExp(r'\s*[,;]\s*'))) {
      final i = int.parse(n);
      if (i >= 1 && i <= count) seen.add(i);
    }
  }
  return seen.toList();
}

/// Words that mark a message as a follow-up to the previous question.
bool isFollowUp(String question) {
  final q = question.trim().toLowerCase();
  if (RegExp(
    r'^(no|nope|not|i meant|i mean|what about|how about|and|but|also|then|why|so)\b',
  ).hasMatch(q)) {
    return true;
  }
  return RegExp(r'\b(it|that|those|them)\b').hasMatch(q) &&
      q.split(RegExp(r'\s+')).length <= 8;
}
