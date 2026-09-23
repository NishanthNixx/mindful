import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/domain/ai/llm_engine.dart';

enum Sender { user, assistant }

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
  ReplyMetrics? metrics;
  bool stopped = false;
  String? error;

  void dispose() {
    text.dispose();
    thinking.dispose();
    streaming.dispose();
  }
}

@immutable
class AskState {
  const AskState({this.messages = const [], this.generating = false});

  final List<ChatMessage> messages;
  final bool generating;
}

const systemInstruction =
    "You are Mindfull, a calm and kind wellness companion running entirely on the user's "
    'phone. Keep answers short, warm and practical. You are not a doctor: never diagnose, '
    'never recommend starting, stopping or changing medication, and suggest a healthcare '
    "professional for anything medical or urgent. You cannot see the user's journal yet; "
    'if asked about their entries, say that journal answers are coming soon.';

class AskController extends Notifier<AskState> {
  LlmSession? _session;
  StreamSubscription<LlmChunk>? _reply;
  ChatMessage? _current;
  Stopwatch? _clock;
  Duration? _firstToken;

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
      for (final m in _owned) {
        m.dispose();
      }
    });
    return const AskState();
  }

  Future<void> send(String input) async {
    final text = input.trim();
    if (text.isEmpty || state.generating) return;
    final reply = ChatMessage(sender: Sender.assistant)..streaming.value = true;
    _current = reply;
    _emit(
      AskState(
        messages: [
          ...state.messages,
          ChatMessage(sender: Sender.user, text: text),
          reply,
        ],
        generating: true,
      ),
    );

    try {
      _session ??= await ref
          .read(llmEngineProvider)
          .openSession(systemInstruction: systemInstruction);
    } on Object catch (e) {
      _finish(error: "Couldn't start the model: $e");
      return;
    }
    _clock = Stopwatch()..start();
    _firstToken = null;
    _reply = _session!
        .send(text)
        .listen(
          (chunk) {
            switch (chunk) {
              case LlmText(:final text):
                if (text.isEmpty) return;
                _firstToken ??= _clock!.elapsed;
                reply.thinking.value = false;
                reply.text.value += text;
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

  /// Stops generation on the native side (cancelling the stream does that).
  Future<void> stop() async {
    final sub = _reply;
    if (sub == null) return;
    _current?.stopped = true;
    _reply = null;
    await sub.cancel();
    _finish();
  }

  Future<void> newChat() async {
    await stop();
    await _session?.close();
    _session = null;
    for (final m in state.messages) {
      m.dispose();
    }
    _emit(const AskState());
  }

  void _finish({String? error}) {
    final reply = _current;
    if (reply == null) return;
    _current = null;
    _reply = null;
    final elapsed = _clock?.elapsed ?? Duration.zero;
    final first = _firstToken;
    reply
      ..error = error
      ..thinking.value = false
      ..streaming.value = false;
    _emit(AskState(messages: [...state.messages]));
    if (first != null && reply.text.value.isNotEmpty) {
      // Count tokens after the fact so it never slows streaming.
      unawaited(
        _session?.countTokens(reply.text.value).then((tokens) {
          reply.metrics = ReplyMetrics(
            timeToFirstToken: first,
            total: elapsed,
            tokens: tokens,
          );
          if (ref.mounted) {
            _emit(
              AskState(
                messages: [...state.messages],
                generating: state.generating,
              ),
            );
          }
        }),
      );
    }
  }
}

final askControllerProvider = NotifierProvider<AskController, AskState>(
  AskController.new,
);
