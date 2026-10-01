import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mindfull/data/ai/embedder_manager.dart';
import 'package:mindfull/data/ai/gemma_embedder.dart';
import 'package:mindfull/data/ai/gemma_llm_engine.dart';
import 'package:mindfull/data/ai/journal_indexer.dart';
import 'package:mindfull/data/ai/model_manager.dart';
import 'package:mindfull/data/ai/platform_device_info.dart';
import 'package:mindfull/data/db/app_database.dart';
import 'package:mindfull/data/repositories/drift_embedding_store.dart';
import 'package:mindfull/data/repositories/drift_journal_repo.dart';
import 'package:mindfull/data/security/app_lock_service.dart';
import 'package:mindfull/data/speech/device_speech_input.dart';
import 'package:mindfull/domain/ai/embedder.dart';
import 'package:mindfull/domain/ai/llm_engine.dart';
import 'package:mindfull/domain/ai/model_status.dart';
import 'package:mindfull/domain/entities/entry_filter.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/entities/tag.dart';
import 'package:mindfull/domain/journal_search/embedding_store.dart';
import 'package:mindfull/domain/repositories/journal_repo.dart';
import 'package:mindfull/domain/services/device_info.dart';
import 'package:mindfull/domain/services/speech_input.dart';
import 'package:mindfull/domain/usecases/log_entry.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ---- Infrastructure (overridden in main() after async bootstrap) ----

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => throw UnimplementedError('overridden in bootstrap'),
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('overridden in bootstrap'),
);

final journalRepoProvider = Provider<JournalRepo>(
  (ref) => DriftJournalRepo(ref.watch(databaseProvider)),
);

final logEntryProvider = Provider<LogEntry>(
  (ref) => LogEntry(
    ref.watch(journalRepoProvider),
    // Keep search in step when it's already loaded; otherwise the next
    // journal question indexes whatever is new.
    afterSave: (entry) async {
      if (ref.read(embedderManagerProvider).value is! SearchReady) return;
      try {
        await ref
            .read(journalIndexerProvider)
            .index(ref.read(embedderRuntimeProvider), entry);
      } on Object catch (e) {
        debugPrint('Indexing after save failed: $e');
      }
    },
  ),
);

final appLockServiceProvider = Provider<AppLockService>(
  (ref) => AppLockService(storage: ref.watch(secureStorageProvider)),
);

final speechInputProvider = Provider<SpeechInput>((ref) => DeviceSpeechInput());

// ---- On-device AI ----

final deviceInfoProvider = Provider<DeviceInfoSource>(
  (ref) => const PlatformDeviceInfo(),
);

final llmEngineProvider = Provider<LlmEngine>((ref) => GemmaLlmEngine());

final modelManagerProvider = Provider<ModelManager>((ref) {
  final manager = ModelManager(
    engine: ref.watch(llmEngineProvider),
    deviceInfo: ref.watch(deviceInfoProvider),
    storage: ref.watch(secureStorageProvider),
    modelsDir: _modelsDir,
  );
  unawaited(manager.restore());
  ref.onDispose(manager.dispose);
  return manager;
});

/// Every AI surface renders from this, so the journal is fully usable
/// without a model.
class ModelStatusNotifier extends Notifier<ModelStatus> {
  @override
  ModelStatus build() {
    final manager = ref.watch(modelManagerProvider);
    void sync() => state = manager.value;
    manager.addListener(sync);
    ref.onDispose(() => manager.removeListener(sync));
    return manager.value;
  }
}

final modelStatusProvider = NotifierProvider<ModelStatusNotifier, ModelStatus>(
  ModelStatusNotifier.new,
);

Future<Directory> _modelsDir() async => Directory(
  p.join((await getApplicationSupportDirectory()).path, 'models'),
);

// ---- Journal search (embeddings + retrieval) ----

final embedderRuntimeProvider = Provider<EmbedderRuntime>(
  (ref) => GemmaEmbedder(),
);

final embeddingStoreProvider = Provider<EmbeddingStore>(
  (ref) => DriftEmbeddingStore(ref.watch(databaseProvider)),
);

final embedderManagerProvider = Provider<EmbedderManager>((ref) {
  final manager = EmbedderManager(
    embedder: ref.watch(embedderRuntimeProvider),
    deviceInfo: ref.watch(deviceInfoProvider),
    storage: ref.watch(secureStorageProvider),
    modelsDir: _modelsDir,
  );
  unawaited(manager.restore());
  ref.onDispose(manager.dispose);
  return manager;
});

class SearchStatusNotifier extends Notifier<SearchStatus> {
  @override
  SearchStatus build() {
    final manager = ref.watch(embedderManagerProvider);
    void sync() => state = manager.value;
    manager.addListener(sync);
    ref.onDispose(() => manager.removeListener(sync));
    return manager.value;
  }
}

final searchStatusProvider =
    NotifierProvider<SearchStatusNotifier, SearchStatus>(
      SearchStatusNotifier.new,
    );

final journalIndexerProvider = Provider<JournalIndexer>((ref) {
  final indexer = JournalIndexer(
    repo: ref.watch(journalRepoProvider),
    store: ref.watch(embeddingStoreProvider),
  );
  ref.onDispose(indexer.dispose);
  return indexer;
});

/// True only while a model download is transferring. Drives the "Offline"
/// badge; nothing else in the app uses the network.
final networkInUseProvider = Provider<bool>(
  (ref) =>
      switch (ref.watch(modelStatusProvider)) {
        ModelDownloading(paused: false) => true,
        _ => false,
      } ||
      switch (ref.watch(searchStatusProvider)) {
        SearchDownloading(paused: false) => true,
        _ => false,
      },
);

/// Whether the only connection is mobile data (warn before a big download).
final onMobileDataProvider = Provider<Future<bool> Function()>(
  (ref) => () async {
    final links = await Connectivity().checkConnectivity();
    final unmetered = links.any(
      (l) => l == ConnectivityResult.wifi || l == ConnectivityResult.ethernet,
    );
    return !unmetered && links.contains(ConnectivityResult.mobile);
  },
);

// ---- Journal ----

class EntryFilterNotifier extends Notifier<EntryFilter> {
  @override
  EntryFilter build() => const EntryFilter();

  // Plain method rather than a setter so it reads like the other actions.
  // ignore: use_setters_to_change_properties
  void set(EntryFilter filter) => state = filter;

  void clear() => state = const EntryFilter();
}

final entryFilterProvider = NotifierProvider<EntryFilterNotifier, EntryFilter>(
  EntryFilterNotifier.new,
);

final entriesProvider = StreamProvider<List<JournalEntry>>(
  (ref) => ref
      .watch(journalRepoProvider)
      .watchEntries(ref.watch(entryFilterProvider)),
);

final StreamProviderFamily<List<TagUsage>, TagKind> tagsProvider =
    StreamProvider.family(
      (ref, kind) => ref.watch(journalRepoProvider).watchTags(kind),
    );
