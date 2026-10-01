import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/app.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/router.dart';
import 'package:mindfull/data/ai/embedder_manager.dart';
import 'package:mindfull/data/ai/model_manager.dart';
import 'package:mindfull/data/db/app_database.dart';
import 'package:mindfull/data/security/app_lock_service.dart';
import 'package:mindfull/data/security/pin_hasher.dart';
import 'package:mindfull/domain/ai/device_profile.dart';
import 'package:mindfull/domain/ai/embedder.dart';
import 'package:mindfull/domain/ai/llm_engine.dart';
import 'package:mindfull/domain/ai/model_spec.dart';
import 'package:mindfull/domain/services/device_info.dart';
import 'package:mindfull/domain/services/speech_input.dart';
import 'package:mindfull/presentation/shared/appearance.dart';
import 'package:mocktail/mocktail.dart';

class MemoryStorage extends Mock implements FlutterSecureStorage {
  final data = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => value == null ? data.remove(key) : data[key] = value;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data.remove(key);
}

class FakeSpeech implements SpeechInput {
  void Function(String, {required bool isFinal})? onResult;
  bool available = true;
  @override
  bool isListening = false;

  @override
  Future<bool> initialize() async => available;

  @override
  Future<void> start({
    required void Function(String transcript, {required bool isFinal}) onResult,
    required void Function(String message) onError,
  }) async {
    isListening = true;
    this.onResult = onResult;
  }

  @override
  Future<void> stop() async => isListening = false;
}

class TestApp {
  TestApp({this.onboarded = true}) {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    if (onboarded) storage.data['onboarded_v1'] = 'true';
  }

  final bool onboarded;
  final storage = MemoryStorage();
  final speech = FakeSpeech();
  final device = FakeDeviceInfo();
  final engine = FakeLlmEngine();
  final embedder = FakeEmbedder();
  late final AppDatabase db;
  late final Directory modelsDir = Directory.systemTemp.createTempSync(
    'mindfull_models',
  );
  late final ModelManager models = ModelManager(
    engine: engine,
    deviceInfo: device,
    storage: storage,
    modelsDir: () async => modelsDir,
    hashInIsolate: false,
  );
  late final EmbedderManager search = EmbedderManager(
    embedder: embedder,
    deviceInfo: device,
    storage: storage,
    modelsDir: () async => modelsDir,
    hashInIsolate: false,
  );

  /// Pretend the search model files are downloaded and verified.
  void installSearchModel() {
    for (final f in EmbedderSpec.gecko.files) {
      File('${modelsDir.path}/${f.fileName}').writeAsBytesSync([1]);
    }
    storage.data['embedder_installed_id'] = EmbedderSpec.gecko.id;
  }

  Widget build({
    bool natureBackgrounds = false,
    ThemeMode themeMode = ThemeMode.system,
  }) => ProviderScope(
    overrides: [
      themeModeProvider.overrideWith(
        () => ThemeModeNotifier(initial: themeMode),
      ),
      natureBackgroundsProvider.overrideWith(
        () => NatureBackgroundsNotifier(initial: natureBackgrounds),
      ),
      secureStorageProvider.overrideWithValue(storage),
      databaseProvider.overrideWithValue(db),
      speechInputProvider.overrideWithValue(speech),
      deviceInfoProvider.overrideWithValue(device),
      llmEngineProvider.overrideWithValue(engine),
      modelManagerProvider.overrideWith((ref) {
        unawaited(models.restore());
        return models;
      }),
      embedderRuntimeProvider.overrideWithValue(embedder),
      embedderManagerProvider.overrideWith((ref) {
        unawaited(search.restore());
        return search;
      }),
      // Fast PBKDF2 so widget tests stay quick.
      appLockServiceProvider.overrideWithValue(
        AppLockService(
          storage: storage,
          hasher: const PinHasher(iterations: 10, useIsolate: false),
        ),
      ),
    ],
    child: MindfullApp(router: buildRouter(onboarded: onboarded)),
  );
}

/// iPhone-sized viewport (390x844 logical).
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Drift completes queries outside the fake-async zone; give it real time,
/// then settle. Bounded so a stuck animation fails fast instead of hanging.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

/// Scrolls [finder] to the middle of the viewport (clear of the translucent
/// header and floating nav) and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await scrollTo(tester, finder);
  final element = tester.element(finder);
  if (Scrollable.maybeOf(element) != null) {
    await Scrollable.ensureVisible(element, alignment: 0.5);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

/// Scrolls the main vertical list until [finder] is built (lists are lazy).
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
}

// ---- On-device AI fakes ----

class FakeDeviceInfo implements DeviceInfoSource {
  FakeDeviceInfo({
    this.totalRamBytes = 12 * _gb,
    this.freeDiskBytes = 64 * _gb,
  });

  static const int _gb = 1024 * 1024 * 1024;

  int totalRamBytes;
  int freeDiskBytes;
  final excluded = <String>[];

  @override
  Future<DeviceProfile> profile() async => DeviceProfile(
    totalRamBytes: totalRamBytes,
    freeDiskBytes: freeDiskBytes,
    model: 'Test Phone',
    osVersion: '1.0',
  );

  @override
  Future<void> excludeFromBackup(String path) async => excluded.add(path);
}

/// Streams whatever the test pushes, and records native stop requests.
class FakeLlmEngine implements LlmEngine {
  ModelSpec? loaded;
  String? loadedPath;
  Object? loadError;
  final sessions = <FakeLlmSession>[];

  @override
  bool get isLoaded => loaded != null;

  @override
  Future<void> load(ModelSpec model, String filePath) async {
    if (loadError case final e?) throw Exception(e);
    loaded = model;
    loadedPath = filePath;
  }

  @override
  Future<LlmSession> openSession({String? systemInstruction}) async {
    final s = FakeLlmSession(systemInstruction);
    sessions.add(s);
    return s;
  }

  @override
  Future<void> unload() async => loaded = null;
}

class FakeLlmSession implements LlmSession {
  FakeLlmSession(this.systemInstruction);

  final String? systemInstruction;
  final prompts = <String>[];
  late StreamController<LlmChunk> _reply;
  int stops = 0;
  bool closed = false;

  @override
  Stream<LlmChunk> send(String message) {
    prompts.add(message);
    _reply = StreamController<LlmChunk>(onCancel: () => stops++);
    return _reply.stream;
  }

  void emit(String text) => _reply.add(LlmText(text));

  void think() => _reply.add(const LlmThinking('…'));

  Future<void> finish() => _reply.close();

  @override
  Future<int?> countTokens(String text) async => text.split(' ').length;

  @override
  Future<void> close() async => closed = true;
}

/// Deterministic bag-of-words "embedder": similar words → similar vectors.
/// Lets retrieval be tested exactly, without a native model.
class FakeEmbedder implements EmbedderRuntime {
  FakeEmbedder({this.modelId = 'fake-embedder'});

  @override
  final String modelId;
  bool loaded = false;
  int calls = 0;
  Object? loadError;

  static const dims = 256;

  @override
  bool get isLoaded => loaded;

  @override
  Future<void> load(
    EmbedderSpec spec, {
    required String modelPath,
    required String tokenizerPath,
  }) async {
    if (loadError case final e?) throw Exception(e);
    loaded = true;
  }

  @override
  Future<void> unload() async => loaded = false;

  @override
  Future<List<double>> embed(
    String text, {
    EmbedPurpose purpose = EmbedPurpose.query,
  }) async {
    calls++;
    final v = List<double>.filled(dims, 0);
    for (final m in RegExp('[a-z]{3,}').allMatches(text.toLowerCase())) {
      var w = m.group(0)!;
      if (w.endsWith('s') && w.length > 4) w = w.substring(0, w.length - 1);
      v[w.hashCode % dims] += 1;
    }
    return v;
  }
}
