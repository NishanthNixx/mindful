import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/domain/ai/device_profile.dart';
import 'package:mindfull/domain/ai/model_spec.dart';

const int _gb = 1024 * 1024 * 1024;

DeviceProfile _device(double ramGb, {double freeGb = 64}) => DeviceProfile(
  totalRamBytes: (ramGb * _gb).round(),
  freeDiskBytes: (freeGb * _gb).round(),
  model: 'x',
  osVersion: '1',
);

void main() {
  test('flagship gets Gemma 4 E2B', () {
    final r = recommendModel(_device(12));
    expect(
      r,
      isA<Recommended>().having(
        (r) => r.model,
        'model',
        ModelCatalog.gemma4E2b,
      ),
    );
  });

  test('budget phone (4 GB) gets Qwen3 0.6B', () {
    final r = recommendModel(_device(4));
    expect(
      r,
      isA<Recommended>().having(
        (r) => r.model,
        'model',
        ModelCatalog.qwen3_0_6b,
      ),
    );
  });

  test('real-world reported RAM maps to the right model', () {
    // What iOS actually reports for advertised sizes.
    expect(
      (recommendModel(_device(7.45)) as Recommended).model,
      ModelCatalog.gemma4E2b,
      reason: '8 GB iPhone',
    );
    expect(
      (recommendModel(_device(5.6)) as Recommended).model,
      ModelCatalog.gemma4E2b,
      reason: '6 GB phone',
    );
    expect(
      (recommendModel(_device(2.8)) as Recommended).model,
      ModelCatalog.qwen3_0_6b,
      reason: '3 GB iPad',
    );
    expect(
      recommendModel(_device(1.9)),
      isA<NotSupported>(),
      reason: '2 GB phone',
    );
  });

  test('under 3 GB turns AI off with a clear reason', () {
    final r = recommendModel(_device(1.9));
    expect(
      r,
      isA<NotSupported>().having(
        (r) => r.reason,
        'reason',
        contains('switched off'),
      ),
    );
  });

  test('storage is flagged separately from memory', () {
    final r = recommendModel(_device(12, freeGb: 1)) as Recommended;
    expect(r.model, ModelCatalog.gemma4E2b);
    expect(r.fitsStorage, isFalse);
  });

  test('partial download counts towards the space needed', () {
    final d = _device(12, freeGb: 1.5);
    const m = ModelCatalog.gemma4E2b;
    expect(fitsStorage(d, m, alreadyDownloaded: 0), isFalse);
    expect(
      fitsStorage(d, m, alreadyDownloaded: m.sizeBytes - 256 * 1024 * 1024),
      isTrue,
    );
  });

  test('compatible models are listed best first', () {
    expect(compatibleModels(_device(12)), [
      ModelCatalog.gemma4E2b,
      ModelCatalog.qwen3_0_6b,
    ]);
    expect(compatibleModels(_device(4)), [ModelCatalog.qwen3_0_6b]);
  });

  test('catalog checksums look like SHA-256', () {
    for (final m in ModelCatalog.all) {
      expect(m.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(m.url, startsWith('https://huggingface.co/'));
    }
  });
}
