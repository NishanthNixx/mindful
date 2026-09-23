import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/presentation/shared/pill.dart';

/// Always-visible reassurance that nothing is being sent. Turns "On" only
/// while the user-initiated model download runs.
class NetworkIndicator extends ConsumerWidget {
  const NetworkIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inUse = ref.watch(networkInUseProvider);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: inUse
          ? 'Downloading a model. No journal data is sent.'
          : 'Mindfull is not using the network. Your journal stays on this phone.',
      child: Pill(
        dense: true,
        icon: inUse ? Icons.cloud_download_outlined : Icons.cloud_off_outlined,
        label: inUse ? 'Downloading' : 'Offline',
        semanticLabel: inUse ? 'Network on, downloading model' : 'Network: Off',
        background:
            (inUse ? scheme.tertiaryContainer : scheme.secondaryContainer)
                .withValues(alpha: 0.6),
        foreground: inUse ? scheme.onTertiaryContainer : scheme.secondary,
      ),
    );
  }
}
