import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mindfull/data/ai/checksum.dart';
import 'package:mindfull/data/ai/model_downloader.dart';
import 'package:mindfull/data/ai/model_manager.dart' show InsufficientStorage;
import 'package:mindfull/domain/ai/device_profile.dart';
import 'package:mindfull/domain/ai/embedder.dart';
import 'package:mindfull/domain/ai/model_spec.dart';
import 'package:mindfull/domain/services/device_info.dart';
import 'package:path/path.dart' as p;

sealed class SearchStatus {
  const SearchStatus();
}

class SearchNotInstalled extends SearchStatus {
  const SearchNotInstalled();
}

class SearchDownloading extends SearchStatus {
  const SearchDownloading({
    required this.receivedBytes,
    required this.totalBytes,
    this.paused = false,
  });

  final int receivedBytes;
  final int totalBytes;
  final bool paused;

  double get progress => totalBytes == 0 ? 0 : receivedBytes / totalBytes;
}

class SearchVerifying extends SearchStatus {
  const SearchVerifying();
}

/// Files verified on disk; loads with the first journal question.
class SearchInstalled extends SearchStatus {
  const SearchInstalled();
}

class SearchReady extends SearchStatus {
  const SearchReady();
}

class SearchFailed extends SearchStatus {
  const SearchFailed(this.message, {this.canResume = true});

  final String message;
  final bool canResume;
}

/// Download → verify → load for the small embedding model behind journal
/// search. Same guarantees as the chat model: resumable, checksum-verified,
/// kept out of backups.
class EmbedderManager extends ChangeNotifier
    implements ValueListenable<SearchStatus> {
  EmbedderManager({
    required this.embedder,
    required this.deviceInfo,
    required FlutterSecureStorage storage,
    required Future<Directory> Function() modelsDir,
    this.spec = EmbedderSpec.gecko,
    ModelDownloader? downloader,
    this.hashInIsolate = true,
  }) : _storage = storage,
       _modelsDir = modelsDir,
       _downloader = downloader ?? ModelDownloader();

  static const _installedKey = 'embedder_installed_id';

  final EmbedderRuntime embedder;
  final DeviceInfoSource deviceInfo;
  final EmbedderSpec spec;
  final FlutterSecureStorage _storage;
  final Future<Directory> Function() _modelsDir;
  final ModelDownloader _downloader;
  final bool hashInIsolate;

  SearchStatus _status = const SearchNotInstalled();
  StreamSubscription<DownloadProgress>? _download;

  /// Completes when the current file finishes, fails, or is paused.
  Completer<void>? _fileDone;
  Future<void>? _loading;

  @override
  SearchStatus get value => _status;

  void _set(SearchStatus s) {
    _status = s;
    notifyListeners();
  }

  Future<File> _file(ModelFile f) async =>
      File(p.join((await _modelsDir()).path, f.fileName));

  Future<File> _part(ModelFile f) async =>
      File('${(await _file(f)).path}.part');

  Future<int> _bytesOnDisk() async {
    var n = 0;
    for (final f in spec.files) {
      final done = await _file(f);
      final part = await _part(f);
      n += done.existsSync()
          ? done.lengthSync()
          : (part.existsSync() ? part.lengthSync() : 0);
    }
    return n;
  }

  Future<void> restore() async {
    try {
      final installed = await _storage.read(key: _installedKey) == spec.id;
      final files = [for (final f in spec.files) await _file(f)];
      if (installed && files.every((f) => f.existsSync())) {
        _set(const SearchInstalled());
        return;
      }
      final have = await _bytesOnDisk();
      _set(
        have > 0
            ? SearchDownloading(
                receivedBytes: have,
                totalBytes: spec.sizeBytes,
                paused: true,
              )
            : const SearchNotInstalled(),
      );
    } on Object catch (e) {
      debugPrint('Search model restore failed: $e');
      _set(const SearchNotInstalled());
    }
  }

  /// Downloads whatever is missing, then verifies each file.
  Future<void> download() async {
    if (_download != null ||
        _status is SearchInstalled ||
        _status is SearchReady) {
      return;
    }
    final have = await _bytesOnDisk();
    final device = await deviceInfo.profile();
    final need = spec.sizeBytes - have + storageHeadroomBytes;
    if (device.freeDiskBytes < need) {
      throw InsufficientStorage(need - device.freeDiskBytes);
    }

    var doneBytes = 0;
    _set(SearchDownloading(receivedBytes: have, totalBytes: spec.sizeBytes));
    for (final f in spec.files) {
      final target = await _file(f);
      if (target.existsSync()) {
        doneBytes += target.lengthSync();
        continue;
      }
      final part = await _part(f);
      final completer = _fileDone = Completer<void>();
      final base = doneBytes;
      _download = _downloader
          .download(
            url: Uri.parse(f.url),
            partFile: part,
            expectedSize: f.sizeBytes,
          )
          .listen(
            (d) => _set(
              SearchDownloading(
                receivedBytes: base + d.receivedBytes,
                totalBytes: spec.sizeBytes,
              ),
            ),
            onError: (Object e) {
              if (!completer.isCompleted) completer.completeError(e);
            },
            onDone: () {
              if (!completer.isCompleted) completer.complete();
            },
            cancelOnError: true,
          );
      try {
        await completer.future;
      } on Object catch (e) {
        _download = null;
        _set(
          SearchFailed(
            e is DownloadException ? e.message : 'Download failed.',
            canResume: e is! DownloadException || e.retryable,
          ),
        );
        return;
      }
      _download = null;
      if (_status case SearchDownloading(paused: true)) return;
      doneBytes += f.sizeBytes;
    }

    _set(const SearchVerifying());
    for (final f in spec.files) {
      final target = await _file(f);
      if (target.existsSync()) continue;
      final part = await _part(f);
      final digest = await sha256OfFile(part, useIsolate: hashInIsolate);
      if (digest != f.sha256) {
        await part.delete();
        _set(
          const SearchFailed(
            'The search model download was damaged and has been deleted. Please try again.',
          ),
        );
        return;
      }
      await part.rename(target.path);
      try {
        await deviceInfo.excludeFromBackup(target.path);
      } on Object catch (e) {
        debugPrint('excludeFromBackup failed: $e');
      }
    }
    await _storage.write(key: _installedKey, value: spec.id);
    _set(const SearchInstalled());
  }

  Future<void> pause() async {
    final sub = _download;
    if (sub == null) return;
    _download = null;
    if (_status case final SearchDownloading d) {
      _set(
        SearchDownloading(
          receivedBytes: d.receivedBytes,
          totalBytes: d.totalBytes,
          paused: true,
        ),
      );
    }
    await sub.cancel();
    // Release download(), which is waiting on this file.
    if (_fileDone case final c? when !c.isCompleted) c.complete();
  }

  /// Loads the embedder into memory (idempotent, shared by concurrent callers).
  Future<bool> ensureLoaded() async {
    if (_status is SearchReady && embedder.isLoaded) return true;
    if (_status is! SearchInstalled && _status is! SearchReady) return false;
    await (_loading ??= _load());
    _loading = null;
    return _status is SearchReady;
  }

  Future<void> _load() async {
    try {
      await embedder.load(
        spec,
        modelPath: (await _file(spec.model)).path,
        tokenizerPath: (await _file(spec.tokenizer)).path,
      );
      _set(const SearchReady());
    } on Object catch (e) {
      debugPrint('Embedder load failed: $e');
      _set(
        const SearchFailed(
          "The search model couldn't be loaded on this phone.",
          canResume: false,
        ),
      );
    }
  }

  Future<void> remove() async {
    await pause();
    await embedder.unload();
    for (final f in spec.files) {
      for (final file in [await _file(f), await _part(f)]) {
        if (file.existsSync()) await file.delete();
      }
    }
    await _storage.delete(key: _installedKey);
    _set(const SearchNotInstalled());
  }

  @override
  void dispose() {
    unawaited(_download?.cancel());
    super.dispose();
  }
}
