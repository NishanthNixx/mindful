import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mindfull/data/db/app_database.dart';
import 'package:mindfull/data/repositories/drift_journal_repo.dart';
import 'package:mindfull/data/security/app_lock_service.dart';
import 'package:mindfull/data/speech/device_speech_input.dart';
import 'package:mindfull/domain/ai/model_status.dart';
import 'package:mindfull/domain/entities/entry_filter.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/entities/tag.dart';
import 'package:mindfull/domain/repositories/journal_repo.dart';
import 'package:mindfull/domain/services/speech_input.dart';
import 'package:mindfull/domain/usecases/log_entry.dart';

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
  (ref) => LogEntry(ref.watch(journalRepoProvider)),
);

final appLockServiceProvider = Provider<AppLockService>(
  (ref) => AppLockService(storage: ref.watch(secureStorageProvider)),
);

final speechInputProvider = Provider<SpeechInput>((ref) => DeviceSpeechInput());

// ---- AI (week 2+: backed by ModelManager / flutter_gemma) ----

/// Until the model manager lands, the model is simply not installed. Every AI
/// surface renders from this, so the journal is fully usable without a model.
final modelStatusProvider = Provider<ModelStatus>(
  (ref) => const ModelNotInstalled(),
);

/// True while the app is making a network request (only model downloads, and
/// only when the user starts one). Drives the "Network: Off" indicator.
final networkInUseProvider = Provider<bool>((ref) => false);

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
