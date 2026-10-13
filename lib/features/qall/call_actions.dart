import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'call_controller.dart';
import 'call_page.dart';

/// 通話に参加して通話画面を開く。別のチャンネルで通話中なら確認する。
/// [webinar] が true ならウェビナーモードで開始する。
Future<void> joinCallAndOpen(
  BuildContext context,
  WidgetRef ref,
  String channelId, {
  bool webinar = false,
}) async {
  final call = ref.read(qallCallProvider);
  if (call.inCall && call.channelId != channelId) {
    final tree = ref.read(channelTreeProvider).value;
    final current = tree?.displayName(call.channelId!) ?? '別のチャンネル';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('通話を切り替えますか？'),
        content: Text('$current の通話から退出して参加します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('切り替える'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }

  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final joining = call.join(channelId, webinar: webinar);
  // 接続処理中から通話画面を開いて状態を見せる
  unawaited(openCallPage(navigator));
  try {
    await joining;
  } on CallException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// 通話画面を開く。すでに開いていれば何もしない。
Future<void> openCallPage(NavigatorState navigator) async {
  if (CallPage.isOpen) return;
  // 画面の State ができる前に連打されても二重に開かないよう、先に立てておく
  CallPage.isOpen = true;
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => const CallPage()),
  );
}
