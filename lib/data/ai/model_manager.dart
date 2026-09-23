import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mindfull/data/ai/checksum.dart';
import 'package:mindfull/data/ai/model_downloader.dart';
import 'package:mindfull/domain/ai/device_profile.dart';
import 'package:mindfull/domain/ai/llm_engine.dart';
import 'package:mindfull/domain/ai/model_spec.dart';
import 'package:mindfull/domain/ai/model_status.dart';
import 'package:mindfull/domain/services/device_info.dart';
import 'package:path/path.dart' as p;

/// Owns the model lifecycle: device check → download (resumable) → SHA-256
/// verify → load → ready. Exposed as a [ValueListenable] so both Riverpod and
/// tests can observe it.
class ModelManager extends ChangeNotifier
    implements ValueListenable<ModelStatus> {
  ModelManager({
    required this.engine,
    required this.deviceInfo,
    required FlutterSecureStorage storage,
    required Future<Directory> Function() modelsDir,
    ModelDownloader? downloader,
    List<ModelSpec> catalog = ModelCatalog.all,
    this.hashInIsolate = true,
  }) : _storage = storage,
       _modelsDir = modelsDir,
       _downloader = downloader ?? ModelDownloader(),
       _catalog = catalog;

  static const _installedKey = 'model_installed_id';
  static const _pendingKey = 'model_pending_id';

  final LlmEngine engine;
  final DeviceInfoSource deviceInfo;
  final FlutterSecureStorage _storage;
  final Future<Directory> Function() _modelsDir;
  final ModelDownloader _downloader;
  final List<ModelSpec> _catalog;
  final bool hashInIsolate;

  ModelStatus _status = const ModelNotInstalled();
  StreamSubscription<DownloadProgress>? _download;
  DeviceProfile? _device;

  @override
  ModelStatus get value => _status;

  DeviceProfile? get device => _device;

  void _set(ModelStatus s) {
    _status = s;
    notifyListeners();
  }

  ModelSpec? _byId(String? id) {
    for (final m in _catalog) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<File> fileFor(ModelSpec m) async =>
      File(p.join((await _modelsDir()).path, m.fileName));

  Future<File> _partFor(ModelSpec m) async =>
      File('${(await fileFor(m)).path}.part');

  Future<DeviceProfile> refreshDevice() async =>
      _device = await deviceInfo.profile();

  /// Called once at start-up: restores an installed model or a paused
  /// download. Never throws; the journal must work whatever happens here.
  Future<void> restore() async {
    try {
      await _restore();
    } on Object catch (e) {
      debugPrint('Model restore failed: $e');
      _set(const ModelNotInstalled());
    }
  }

  Future<void> _restore() async {
    final device = await refreshDevice();
    final installed = _byId(await _storage.read(key: _installedKey));
    if (installed != null && (await fileFor(installed)).existsSync()) {
      _set(ModelInstalled(installed));
      return;
    }
    if (recommendModel(device, catalog: _catalog) case NotSupported(
      :final reason,
    )) {
      _set(ModelUnsupported(reason));
      return;
    }
    final pending = _byId(await _storage.read(key: _pendingKey));
    if (pending != null) {
      final part = await _partFor(pending);
      if (part.existsSync()) {
        _set(
          ModelDownloading(
            model: pending,
            receivedBytes: part.lengthSync(),
            totalBytes: pending.sizeBytes,
            paused: true,
          ),
        );
        return;
      }
    }
    _set(const ModelNotInstalled());
  }

  /// Loads an installed model into memory (first time Ask is opened).
  Future<void> ensureLoaded() async {
    if (_status case ModelInstalled(:final model)) await _load(model);
  }

  /// Starts or resumes downloading [model]. Throws [InsufficientStorage] when
  /// the phone lacks space for the rest of the file plus headroom.
  Future<void> download(ModelSpec model) async {
    if (_download != null) return;
    final part = await _partFor(model);
    final have = part.existsSync() ? part.lengthSync() : 0;
    final device = await refreshDevice();
    if (!fitsStorage(device, model, alreadyDownloaded: have)) {
      final need =
          model.sizeBytes - have + storageHeadroomBytes - device.freeDiskBytes;
      throw InsufficientStorage(need);
    }
    await _storage.write(key: _pendingKey, value: model.id);
    _set(
      ModelDownloading(
        model: model,
        receivedBytes: have,
        totalBytes: model.sizeBytes,
      ),
    );

    _download = _downloader
        .download(
          url: Uri.parse(model.url),
          partFile: part,
          expectedSize: model.sizeBytes,
        )
        .listen(
          (d) => _set(
            ModelDownloading(
              model: model,
              receivedBytes: d.receivedBytes,
              totalBytes: d.totalBytes,
              bytesPerSecond: d.bytesPerSecond,
            ),
          ),
          onError: (Object e) {
            _download = null;
            final message = e is DownloadException
                ? e.message
                : 'Download failed.';
            final retryable = e is! DownloadException || e.retryable;
            _set(
              ModelFailed(message: message, model: model, canResume: retryable),
            );
          },
          onDone: () async {
            _download = null;
            if (_status case ModelDownloading(paused: true)) return;
            await _verifyAndInstall(model, part);
          },
          cancelOnError: true,
        );
  }

  /// Stops the transfer; bytes so far are kept for [download] to resume.
  Future<void> pause() async {
    final sub = _download;
    if (sub == null) return;
    _download = null;
    if (_status case final ModelDownloading d) {
      _set(
        ModelDownloading(
          model: d.model,
          receivedBytes: d.receivedBytes,
          totalBytes: d.totalBytes,
          paused: true,
        ),
      );
    }
    await sub.cancel();
  }

  /// Abandons a download and deletes the partial file.
  Future<void> cancel(ModelSpec model) async {
    await pause();
    final part = await _partFor(model);
    if (part.existsSync()) await part.delete();
    await _storage.delete(key: _pendingKey);
    await _settleIdle();
  }

  /// Unloads and deletes the installed model file.
  Future<void> remove(ModelSpec model) async {
    await engine.unload();
    for (final f in [await fileFor(model), await _partFor(model)]) {
      if (f.existsSync()) await f.delete();
    }
    await _storage.delete(key: _installedKey);
    await _storage.delete(key: _pendingKey);
    await _settleIdle();
  }

  Future<void> _settleIdle() async {
    final device = await refreshDevice();
    _set(switch (recommendModel(device, catalog: _catalog)) {
      NotSupported(:final reason) => ModelUnsupported(reason),
      Recommended() => const ModelNotInstalled(),
    });
  }

  Future<void> _verifyAndInstall(ModelSpec model, File part) async {
    _set(ModelVerifying(model: model, progress: 0));
    final String digest;
    try {
      digest = await sha256OfFile(
        part,
        useIsolate: hashInIsolate,
        onProgress: (p) => _set(ModelVerifying(model: model, progress: p)),
      );
    } on Object {
      _set(
        ModelFailed(
          message: "Couldn't check the downloaded file.",
          model: model,
          canResume: true,
        ),
      );
      return;
    }
    if (digest != model.sha256) {
      await part.delete();
      await _storage.delete(key: _pendingKey);
      _set(
        ModelFailed(
          message:
              'The download was damaged (checksum mismatch) and has been deleted. Please try again.',
          model: model,
        ),
      );
      return;
    }
    final file = await part.rename((await fileFor(model)).path);
    try {
      await deviceInfo.excludeFromBackup(file.path);
    } on Object catch (e) {
      debugPrint('excludeFromBackup failed: $e');
    }
    await _storage.write(key: _installedKey, value: model.id);
    await _storage.delete(key: _pendingKey);
    await _load(model);
  }

  Future<void> _load(ModelSpec model) async {
    _set(ModelLoading(model));
    try {
      await engine.load(model, (await fileFor(model)).path);
      _set(ModelReady(model));
    } on Object catch (e) {
      debugPrint('Model load failed: $e');
      _set(
        ModelFailed(
          message:
              "The model is downloaded but couldn't be loaded on this phone. You can remove it and try the smaller model.",
          model: model,
        ),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_download?.cancel());
    super.dispose();
  }
}

class InsufficientStorage implements Exception {
  const InsufficientStorage(this.bytesToFree);

  final int bytesToFree;
}
