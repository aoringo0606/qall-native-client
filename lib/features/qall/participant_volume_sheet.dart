import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/user_avatar.dart';
import '../settings/call_settings.dart';

/// 参加者ごとの音量 (Web版の参加者一覧の音量スライダーに相当)。
Future<void> showParticipantVolume(BuildContext context, String userId) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ParticipantVolumeSheet(userId: userId),
    );

class _ParticipantVolumeSheet extends ConsumerWidget {
  const _ParticipantVolumeSheet({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(
      callSettingsProvider.select((s) => s.userVolume(userId)),
    );
    final notifier = ref.read(callSettingsProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                UserAvatar(userId: userId, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    userDisplayName(ref, userId),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  volume == 0 ? 'ミュート' : '${(volume * 100).round()}%',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: volume == 0 ? 'ミュート解除' : 'この人をミュート',
                  icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
                  onPressed: () =>
                      notifier.setUserVolume(userId, volume == 0 ? 1 : 0),
                ),
                Expanded(
                  child: Slider(
                    value: volume.clamp(0, 2),
                    max: 2,
                    divisions: 40,
                    onChanged: (v) => notifier.setUserVolume(userId, v),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => notifier.setUserVolume(userId, 1),
                child: const Text('100% に戻す'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
