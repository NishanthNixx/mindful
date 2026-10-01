import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/data/ai/embedder_manager.dart';
import 'package:mindfull/data/ai/journal_indexer.dart';
import 'package:mindfull/data/ai/model_downloader.dart';
import 'package:mindfull/data/db/app_database.dart';
import 'package:mindfull/data/repositories/drift_embedding_store.dart';
import 'package:mindfull/data/repositories/drift_journal_repo.dart';
import 'package:mindfull/domain/ai/model_spec.dart';
import 'package:mindfull/domain/journal_search/embedding_store.dart';

import '../helpers.dart';
import '../support/file_server.dart';
import '../support/sample_journal.dart';

void main() {
  group('embedding store + indexer', () {
    late AppDatabase db;
    late DriftJournalRepo repo;
    late DriftEmbeddingStore store;
    late JournalIndexer indexer;
    final embedder = FakeEmbedder();

    setUp(() async {
      db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      repo = DriftJournalRepo(db);
      store = DriftEmbeddingStore(db);
      indexer = JournalIndexer(repo: repo, store: store);
      for (final e in sampleJournal) {
        await repo.saveEntry(e);
      }
    });

    tearDown(() => db.close());

    test('vectors round-trip through the database exactly', () async {
      final v = Float32List.fromList([0.5, -1.25, 3, 0]);
      await store.upsert(
        StoredEmbedding(
          entryId: 'aug-river',
          modelId: 'm',
          textHash: 'h',
          vector: v,
        ),
      );
      final got = (await store.all('m'))['aug-river']!;
      expect(got.vector, v);
      expect(await store.all('other-model'), isEmpty);
    });

    test('sync embeds everything once, then only what changed', () async {
      expect(await indexer.sync(embedder), sampleJournal.length);
      expect((await store.all(embedder.modelId)).length, sampleJournal.length);
      expect(await indexer.sync(embedder), 0, reason: 'nothing changed');

      final edited = sampleJournal.first.copyWith(
        note: 'Actually it rained all day.',
      );
      await repo.saveEntry(edited);
      expect(await indexer.sync(embedder), 1, reason: 'only the edited entry');

      expect(
        await indexer.sync(FakeEmbedder(modelId: 'v2')),
        sampleJournal.length,
        reason: 'new model re-indexes',
      );
    });

    test('deleting an entry deletes its vector (cascade)', () async {
      await indexer.sync(embedder);
      await repo.deleteEntry('sep20-yoga');
      expect(
        (await store.all(embedder.modelId)).containsKey('sep20-yoga'),
        isFalse,
      );
    });

    test('delete all wipes vectors too', () async {
      await indexer.sync(embedder);
      await repo.deleteAll();
      expect(await store.all(embedder.modelId), isEmpty);
    });
  });

  group('search model manager', () {
    final modelBytes = testBytes(90000);
    final tokBytes = testBytes(4000);
    late FileServer modelServer;
    late FileServer tokServer;
    late Directory dir;
    late MemoryStorage storage;
    late FakeEmbedder embedder;

    EmbedderSpec spec({String? modelSha}) => EmbedderSpec(
      id: 'tiny-embedder',
      displayName: 'Tiny',
      model: ModelFile(
        url: modelServer.url('/file').toString(),
        fileName: 'embed.tflite',
        sizeBytes: modelBytes.length,
        sha256: modelSha ?? sha256.convert(modelBytes).toString(),
      ),
      tokenizer: ModelFile(
        url: tokServer.url('/file').toString(),
        fileName: 'tok.model',
        sizeBytes: tokBytes.length,
        sha256: sha256.convert(tokBytes).toString(),
      ),
    );

    EmbedderManager manager(EmbedderSpec s) => EmbedderManager(
      embedder: embedder,
      deviceInfo: FakeDeviceInfo(),
      storage: storage,
      modelsDir: () async => dir,
      spec: s,
      downloader: ModelDownloader(progressInterval: Duration.zero),
      hashInIsolate: false,
    );

    setUp(() async {
      modelServer = FileServer(modelBytes);
      tokServer = FileServer(tokBytes);
      await modelServer.start();
      await tokServer.start();
      dir = Directory.systemTemp.createTempSync('emb_mgr');
      storage = MemoryStorage();
      embedder = FakeEmbedder();
    });

    tearDown(() async {
      await modelServer.close();
      await tokServer.close();
      dir.deleteSync(recursive: true);
    });

    test(
      'downloads both files, verifies, installs, then loads on demand',
      () async {
        final m = manager(spec());
        await m.restore();
        expect(m.value, isA<SearchNotInstalled>());
        await m.download();
        expect(m.value, isA<SearchInstalled>());
        expect(File('${dir.path}/embed.tflite').readAsBytesSync(), modelBytes);
        expect(File('${dir.path}/tok.model').readAsBytesSync(), tokBytes);
        expect(embedder.loaded, isFalse);

        expect(await m.ensureLoaded(), isTrue);
        expect(m.value, isA<SearchReady>());

        // A fresh start restores it as installed.
        final again = manager(spec());
        await again.restore();
        expect(again.value, isA<SearchInstalled>());
      },
    );

    test('a damaged file is deleted and reported', () async {
      final m = manager(spec(modelSha: '0' * 64));
      await m.restore();
      await m.download();
      expect(
        m.value,
        isA<SearchFailed>().having(
          (f) => f.message,
          'message',
          contains('damaged'),
        ),
      );
      expect(File('${dir.path}/embed.tflite').existsSync(), isFalse);
    });

    test('remove deletes the files', () async {
      final m = manager(spec());
      await m.download();
      await m.remove();
      expect(m.value, isA<SearchNotInstalled>());
      expect(dir.listSync(), isEmpty);
    });
  });
}
