import 'package:flutter/foundation.dart';

enum ModelFamily { gemma4, qwen3 }

/// One downloadable on-device model. Sizes and SHA-256 come from the
/// Hugging Face LFS metadata, so a download can be verified byte-for-byte.
@immutable
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.displayName,
    required this.family,
    required this.url,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.minRamBytes,
    required this.useGpu,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.contextTokens,
    required this.thinking,
    required this.summary,
    required this.license,
  });

  final String id;
  final String displayName;
  final ModelFamily family;
  final String url;
  final String fileName;
  final int sizeBytes;
  final String sha256;

  /// Below this much physical RAM the model is not offered.
  final int minRamBytes;
  final bool useGpu;
  final double temperature;
  final int topK;
  final double topP;

  /// Context window (prompt + reply).
  final int contextTokens;

  /// Model emits a separate "thinking" channel (hidden in the UI).
  final bool thinking;
  final String summary;
  final String license;

  @override
  bool operator ==(Object other) => other is ModelSpec && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

const int _gib = 1024 * 1024 * 1024;

/// Phones report RAM in GiB and a little under the advertised size (an "8 GB"
/// iPhone reports ~7.45 GiB, a "3 GB" iPad ~2.8 GiB), so thresholds sit
/// below the marketing number.
/// 90% of the advertised size (6 GB → 5.4 GiB, 3 GB → 2.7 GiB).
const int _advertised6Gb = 6 * 9 * _gib ~/ 10;
const int _advertised3Gb = 3 * 9 * _gib ~/ 10;

abstract final class ModelCatalog {
  static const gemma4E2b = ModelSpec(
    id: 'gemma-4-e2b',
    displayName: 'Gemma 4 E2B',
    family: ModelFamily.gemma4,
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    fileName: 'gemma-4-E2B-it.litertlm',
    sizeBytes: 2588147712,
    sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
    minRamBytes: _advertised6Gb,
    useGpu: true,
    temperature: 1,
    topK: 64,
    topP: 0.95,
    contextTokens: 4096,
    thinking: false,
    summary: 'Best quality. For phones with 6 GB of memory or more.',
    license: 'Apache 2.0',
  );

  static const qwen3_0_6b = ModelSpec(
    id: 'qwen3-0.6b',
    displayName: 'Qwen3 0.6B',
    family: ModelFamily.qwen3,
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    fileName: 'Qwen3-0.6B.litertlm',
    sizeBytes: 614236160,
    sha256: '555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4',
    minRamBytes: _advertised3Gb,
    useGpu: false,
    temperature: 0.7,
    topK: 40,
    topP: 0.95,
    contextTokens: 4096,
    thinking: true,
    summary: 'Small and fast. Works on phones with 3 GB of memory.',
    license: 'Apache 2.0',
  );

  /// Best first.
  static const List<ModelSpec> all = [gemma4E2b, qwen3_0_6b];

  static ModelSpec? byId(String? id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }
}
