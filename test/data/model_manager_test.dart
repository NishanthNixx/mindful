import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/data/ai/model_downloader.dart';
import 'package:mindfull/data/ai/model_manager.dart';
import 'package:mindfull/domain/ai/model_spec.dart';
import 'package:mindfull/domain/ai/model_status.dart';

import '../helpers.dart';
import '../support/file_server.dart';

ModelSpec _spec(Uri url, String sha, int size) => ModelSpec(
  id: 'tiny',
  displayName: 'Tiny',
  family: ModelFamily.qwen3,
  url: url.toString(),
  fileName: 'tiny.litertlm',
  sizeBytes: size,
  sha256: sha,
  minRamBytes: 1024,
  useGpu: false,
  temperature: 0.7,
  topK: 40,
  topP: 0.95,
  contextTokens: 1024,
  thinking: false,
  summary: '',
  license: 'test',
);

void main() {
  final bytes = testBytes(200000);
  final goodSha = sha256.convert(bytes).toString();
  late FileServer server;
  late Directory dir;
  late MemoryStorage storage;
  late FakeDeviceInfo device;
  late FakeLlmEngine engine;

  ModelManager manager(ModelSpec spec) => ModelManager(
    engine: engine,
    deviceInfo: device,
    storage: storage,
    modelsDir: () async => dir,
    catalog: [spec],
    downloader: ModelDownloader(progressInterval: Duration.zero),
    hashInIsolate: false,
  );

  Future<ModelStatus> until(
    ModelManager m,
    bool Function(ModelStatus) done,
  ) async {
    if (done(m.value)) return m.value;
    final c = Completer<ModelStatus>();
    void l() {
      if (done(m.value) && !c.isCompleted) c.complete(m.value);
    }

    m.addListener(l);
    final s = await c.future.timeout(const Duration(seconds: 10));
    m.removeListener(l);
    return s;
  }

  setUp(() async {
    server = FileServer(bytes);
    await server.start();
    dir = Directory.systemTemp.createTempSync('mm_test');
    storage = MemoryStorage();
    device = FakeDeviceInfo();
    engine = FakeLlmEngine();
  });

  tearDown(() async {
    await server.close();
    dir.deleteSync(recursive: true);
  });

  test('download → verify → install → load → ready', () async {
    final spec = _spec(server.url('/redirect'), goodSha, bytes.length);
    final m = manager(spec);
    await m.restore();
    expect(m.value, isA<ModelNotInstalled>());

    final seen = <Type>{};
    m.addListener(() => seen.add(m.value.runtimeType));
    await m.download(spec);
    final end = await until(m, (s) => s is ModelReady || s is ModelFailed);

    expect(end, isA<ModelReady>());
    expect(
      seen,
      containsAll([ModelDownloading, ModelVerifying, ModelLoading, ModelReady]),
    );
    final file = File('${dir.path}/tiny.litertlm');
    expect(file.readAsBytesSync(), bytes);
    expect(File('${file.path}.part').existsSync(), isFalse);
    expect(engine.loadedPath, file.path);
    expect(device.excluded, [file.path]);
    expect(storage.data['model_installed_id'], 'tiny');
  });

  test('checksum mismatch deletes the file and reports it', () async {
    final spec = _spec(server.url('/file'), '0' * 64, bytes.length);
    final m = manager(spec);
    await m.restore();
    await m.download(spec);
    final end = await until(m, (s) => s is ModelFailed || s is ModelReady);
    expect(
      end,
      isA<ModelFailed>().having(
        (f) => f.message,
        'message',
        contains('checksum'),
      ),
    );
    expect(dir.listSync(), isEmpty);
    expect(engine.loaded, isNull);
  });

  test('refuses to start without enough free space', () async {
    device.freeDiskBytes = 1000;
    final spec = _spec(server.url('/file'), goodSha, bytes.length);
    final m = manager(spec);
    await m.restore();
    await expectLater(m.download(spec), throwsA(isA<InsufficientStorage>()));
  });

  test('a download interrupted by an app restart resumes from disk', () async {
    final spec = _spec(server.url('/file'), goodSha, bytes.length);
    // Simulate a previous run that got 60% of the file then the app was killed.
    File(
      '${dir.path}/tiny.litertlm.part',
    ).writeAsBytesSync(bytes.sublist(0, 120000));
    storage.data['model_pending_id'] = 'tiny';

    final m = manager(spec);
    await m.restore();
    expect(
      m.value,
      isA<ModelDownloading>()
          .having((d) => d.paused, 'paused', isTrue)
          .having((d) => d.receivedBytes, 'received', 120000),
    );

    await m.download(spec);
    expect(
      await until(m, (s) => s is ModelReady || s is ModelFailed),
      isA<ModelReady>(),
    );
    expect(server.rangeHeaders.single, 'bytes=120000-');
  });

  test(
    'installed model is restored lazily, loaded on demand, and removable',
    () async {
      final spec = _spec(server.url('/file'), goodSha, bytes.length);
      File('${dir.path}/tiny.litertlm').writeAsBytesSync(bytes);
      storage.data['model_installed_id'] = 'tiny';

      final m = manager(spec);
      await m.restore();
      expect(m.value, isA<ModelInstalled>());
      expect(engine.loaded, isNull, reason: 'not loaded at start-up');

      await m.ensureLoaded();
      expect(m.value, isA<ModelReady>());

      await m.remove(spec);
      expect(m.value, isA<ModelNotInstalled>());
      expect(engine.loaded, isNull);
      expect(dir.listSync(), isEmpty);
      expect(storage.data.containsKey('model_installed_id'), isFalse);
    },
  );

  test('low-memory phone reports unsupported', () async {
    device.totalRamBytes = 512;
    final m = manager(_spec(server.url('/file'), goodSha, bytes.length));
    await m.restore();
    expect(m.value, isA<ModelUnsupported>());
  });

  test('a model that fails to load is reported, not crashed on', () async {
    final spec = _spec(server.url('/file'), goodSha, bytes.length);
    File('${dir.path}/tiny.litertlm').writeAsBytesSync(bytes);
    storage.data['model_installed_id'] = 'tiny';
    engine.loadError = 'GPU exploded';
    final m = manager(spec);
    await m.restore();
    await m.ensureLoaded();
    expect(
      m.value,
      isA<ModelFailed>().having(
        (f) => f.message,
        'message',
        contains("couldn't be loaded"),
      ),
    );
  });

  test('pause keeps progress; cancel deletes it', () async {
    final spec = _spec(server.url('/slow'), goodSha, bytes.length);
    final m = manager(spec);
    await m.restore();
    await m.download(spec);
    await until(m, (s) => s is ModelDownloading && s.receivedBytes > 20000);
    await m.pause();
    expect(
      m.value,
      isA<ModelDownloading>().having((d) => d.paused, 'paused', isTrue),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(File('${dir.path}/tiny.litertlm.part').existsSync(), isTrue);

    await m.cancel(spec);
    expect(m.value, isA<ModelNotInstalled>());
    expect(File('${dir.path}/tiny.litertlm.part').existsSync(), isFalse);
  });
}
