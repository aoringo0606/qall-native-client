import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'call_actions.dart';
import 'call_controller.dart';

/// 通話中に画面下部に出すバー。タップで通話画面を開く。
class CallBar extends ConsumerWidget {
  const CallBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(qallCallProvider);
    final tree = ref.watch(channelTreeProvider).value;
    return ListenableBuilder(
      listenable: call,
      builder: (context, _) {
        final channelId = call.channelId;
        if (!call.inCall || channelId == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.primaryContainer,
          child: SafeArea(
            top: false,
            child: InkWell(
              onTap: () => openCallPage(Navigator.of(context)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                child: Row(
                  children: [
                    Icon(Icons.graphic_eq, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tree?.displayName(channelId) ?? 'Qall',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            switch (call.status) {
                              CallStatus.connecting => '接続中…',
                              CallStatus.reconnecting => '再接続中…',
                              _ =>
                                call.isScreenSharing
                                    ? '画面共有中'
                                    : '通話中 (${call.participants.length}人)',
                            },
                            style: TextStyle(color: scheme.onPrimaryContainer),
                          ),
                        ],
                      ),
                    ),
                    if (call.canPublish)
                      IconButton(
                        tooltip: call.isMicEnabled ? 'ミュート' : 'ミュート解除',
                        icon: Icon(
                          call.isMicEnabled ? Icons.mic : Icons.mic_off,
                        ),
                        onPressed: () {
                          final messenger = ScaffoldMessenger.of(context);
                          call.toggleMicrophone().catchError(
                            (Object e) => messenger.showSnackBar(
                              SnackBar(content: Text('$e')),
                            ),
                          );
                        },
                      ),
                    IconButton(
                      tooltip: '退出',
                      color: scheme.error,
                      icon: const Icon(Icons.call_end),
                      onPressed: call.leave,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
