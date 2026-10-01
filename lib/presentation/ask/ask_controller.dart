import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/domain/ai/llm_engine.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/journal_search/prompt.dart';
import 'package:mindfull/domain/journal_search/retriever.dart';

enum Sender { user, assistant }

/// Where answers come from: the user's entries (cited), or general chat.
enum AskMode { journal, general }

@immutable
class ReplyMetrics {
  const ReplyMetrics({
    required this.timeToFirstToken,
    required this.total,
    required this.tokens,
  });

  final Duration timeToFirstToken;
  final Duration total;

  /// Tokenizer count of the reply; null when the engine can't count.
  final int? tokens;

  /// Decode speed, measured from the first token (excludes prefill).
  double? get tokensPerSecond {
    final t = tokens;
    final decode = total - timeToFirstToken;
    if (t == null || t < 2 || decode.inMilliseconds <= 0) return null;
    return (t - 1) / (decode.inMicroseconds / 1e6);
  }
}

/// A chat message. Assistant text streams through [text] so only that bubble
/// rebuilds per token, not the whole list.
class ChatMessage {
  ChatMessage({required this.sender, String text = ''})
    : text = ValueNotifier(text);

  final Sender sender;
  final ValueNotifier<String> text;
  final ValueNotifier<bool> thinking = ValueNotifier(false);
  final ValueNotifier<bool> streaming = ValueNotifier(false);

  /// "Searching your journal…" etc. before the first token.
  final ValueNotifier<String?> phase = ValueNotifier(null);

  /// Journal answers: the numbered entries given to the model; citation `[n]`
  /// refers to `sources[n - 1]`.
  List<JournalEntry> sources = const [];
  AskMode mode = AskMode.general;
  ReplyMetrics? metrics;
  bool stopped = false;
  String? error;

  void dispose() {
    text.dispose();
    thinking.dispose();
    streaming.dispose();
    phase.dispose();
  }
}

@immutable
class AskState {
  const AskState({
    this.messages = const [],
    this.generating = false,
    this.mode = AskMode.journal,
  });

  final List<ChatMessage> messages;
  final bool generating;
  final AskMode mode;

  AskState copyWith({
    List<ChatMessage>? messages,
    bool? generating,
    AskMode? mode,
  }) => AskState(
    messages: messages ?? this.messages,
    generating: generating ?? this.generating,
    mode: mode ?? this.mode,
  );
}

const systemInstruction =
    "You are Mindfull, a calm and kind wellness companion running entirely on the user's "
    'phone. Keep answers short, warm and practical. You are not a doctor: never diagnose, '
    'never recommend starting, stopping or changing medication, and suggest a healthcare '
    "professional for anything medical or urgent. You cannot see the user's journal yet; "
    'if asked about their entries, say that journal answers are coming soon.';

class AskController extends Notifier<AskState> {
  LlmSession? _session;
  LlmSession? _journalSession;
  StreamSubscription<LlmChunk>? _reply;
  ChatMessage? _current;
  Stopwatch? _clock;
  Duration? _firstToken;
  var _cancelled = false;

  /// Last journal question and answer, for follow-ups.
  PriorTurn? _lastJournalTurn;
  String? _pendingQuestion;

  /// Mirror of state.messages for disposal (state isn't readable in onDispose).
  List<ChatMessage> _owned = const [];

  void _emit(AskState next) {
    _owned = next.messages;
    state = next;
  }

  @override
  AskState build() {
    ref.onDispose(() {
      unawaited(_reply?.cancel());
      unawaited(_session?.close());
      unawaited(_journalSession?.close());
      for (final m in _owned) {
        m.dispose();
      }
    });
    return const AskState();
  }

  void setMode(AskMode mode) {
    if (!state.generating) _emit(state.copyWith(mode: mode));
  }

  Future<void> send(String input) async {
    final text = input.trim();
    if (text.isEmpty || state.generating) return;
    final mode = state.mode;
    final reply = ChatMessage(sender: Sender.assistant)
      ..streaming.value = true
      ..mode = mode;
    _current = reply;
    _cancelled = false;
    _emit(
      state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(sender: Sender.user, text: text)..mode = mode,
          reply,
        ],
        generating: true,
      ),
    );

    final LlmSession session;
    final String prompt;
    try {
      if (mode == AskMode.journal) {
        reply.phase.value = 'Searching your journal…';
        final previous = _lastJournalTurn;
        final followUp = previous != null && isFollowUp(text);
        // A follow-up like "no, I meant why…" searches with the earlier question too.
        final (retrieval, now) = await _retrieve(
          followUp ? '${previous.question} $text' : text,
        );
        if (_cancelled) return;
        reply.sources = [for (final r in retrieval.entries) r.entry];
        reply.phase.value = retrieval.entries.isEmpty
            ? 'No matching entries — asking anyway…'
            : 'Reading ${retrieval.entries.length} entries…';
        prompt = buildJournalPrompt(
          text,
          retrieval,
          now: now,
          previous: previous,
        );
        _pendingQuestion = text;
        // Each journal question gets a fresh context: the entries differ per
        // question and stale ones would crowd the context window.
        await _journalSession?.close();
        session = _journalSession = await ref
            .read(llmEngineProvider)
            .openSession(systemInstruction: journalSystemInstruction);
      } else {
        prompt = text;
        session = _session ??= await ref
            .read(llmEngineProvider)
            .openSession(systemInstruction: systemInstruction);
      }
    } on Object catch (e) {
      debugPrint('Ask failed before generating: $e');
      _finish(
        error: mode == AskMode.journal
            ? "Couldn't search your journal."
            : "Couldn't start the model.",
      );
      return;
    }
    if (_cancelled) return;

    _clock = Stopwatch()..start();
    _firstToken = null;
    _reply = session
        .send(prompt)
        .listen(
          (chunk) {
            switch (chunk) {
              case LlmText(:final text):
                if (text.isEmpty) return;
                _firstToken ??= _clock!.elapsed;
                reply
                  ..phase.value = null
                  ..thinking.value = false
                  ..text.value += text;
              case LlmThinking():
                _firstToken ??= _clock!.elapsed;
                reply.thinking.value = true;
            }
          },
          onError: (Object e) =>
              _finish(error: 'Something went wrong while generating.'),
          onDone: _finish,
        );
  }

  Future<(Retrieval, DateTime)> _retrieve(String question) async {
    final search = ref.read(embedderManagerProvider);
    if (!await search.ensureLoaded()) {
      throw StateError('Search model not ready');
    }
    final embedder = ref.read(embedderRuntimeProvider);
    // Picks up entries saved since the last question (usually zero or one).
    await ref.read(journalIndexerProvider).sync(embedder);
    final now = clock.now();
    final journal = await ref.read(journalRepoProvider).entries();
    final retrieval = await JournalRetriever(
      embedder: embedder,
      store: ref.read(embeddingStoreProvider),
      now: () => now,
    ).retrieve(question, journal);
    return (retrieval, now);
  }

  /// Stops generation on the native side (cancelling the stream does that).
  Future<void> stop() async {
    if (!state.generating) return;
    _cancelled = true;
    _current?.stopped = true;
    final sub = _reply;
    _reply = null;
    await sub?.cancel();
    _finish();
  }

  Future<void> newChat() async {
    await stop();
    await _session?.close();
    await _journalSession?.close();
    _session = null;
    _journalSession = null;
    _lastJournalTurn = null;
    for (final m in state.messages) {
      m.dispose();
    }
    _emit(AskState(mode: state.mode));
  }

  void _finish({String? error}) {
    final reply = _current;
    if (reply == null) return;
    _current = null;
    _reply = null;
    final elapsed = _clock?.elapsed ?? Duration.zero;
    final first = _firstToken;
    final session = reply.mode == AskMode.journal ? _journalSession : _session;
    reply
      ..error = error
      ..phase.value = null
      ..thinking.value = false
      ..streaming.value = false;
    if (reply.mode == AskMode.journal &&
        _pendingQuestion != null &&
        reply.text.value.isNotEmpty) {
      _lastJournalTurn = PriorTurn(
        question: _pendingQuestion!,
        answer: reply.text.value,
      );
    }
    _pendingQuestion = null;
    _emit(state.copyWith(messages: [...state.messages], generating: false));
    if (first != null && reply.text.value.isNotEmpty) {
      // Count tokens after the fact so it never slows streaming.
      unawaited(
        session?.countTokens(reply.text.value).then((tokens) {
          reply.metrics = ReplyMetrics(
            timeToFirstToken: first,
            total: elapsed,
            tokens: tokens,
          );
          if (ref.mounted) _emit(state.copyWith(messages: [...state.messages]));
        }),
      );
    }
  }
}

final askControllerProvider = NotifierProvider<AskController, AskState>(
  AskController.new,
);
