import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../widgets/user_avatar.dart';
import '../channels/channel_list.dart';
import '../messages/channel_page.dart';
import '../qall/call_bar.dart';
import '../qall/call_controller.dart';
import '../settings/settings_page.dart';

/// ログイン後のトップ画面。
///
/// 幅が広い端末 (iPad・タブレット・横向き) ではチャンネル一覧とメッセージを
/// 2ペインで並べ、狭い端末 (スマホ) では画面遷移で切り替える。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  static const _twoPaneBreakpoint = 720.0;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  String? _selectedChannelId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // バックグラウンド中に OS に切られた WebSocket をつなぎ直す
      ref.read(traqWsProvider).ensureConnected();
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(qallCallProvider).leave();
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    // WebSocket はログイン中ずっと接続しておく
    ref.watch(traqWsProvider);
    final me = ref.watch(sessionProvider).me;
    final wide =
        MediaQuery.sizeOf(context).width >= HomePage._twoPaneBreakpoint;

    final list = ChannelList(
      selectedChannelId: wide ? _selectedChannelId : null,
      onSelect: (id) {
        if (wide) {
          setState(() => _selectedChannelId = id);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ChannelPage(channelId: id)),
          );
        }
      },
    );

    final appBar = AppBar(
      title: const Text('Qall'),
      actions: [
        PopupMenuButton<_MenuAction>(
          tooltip: 'アカウント',
          icon: UserAvatar(userId: me.id, radius: 14),
          // onTap で画面を開くとメニューを閉じる処理に巻き込まれるので onSelected で開く
          onSelected: (action) => switch (action) {
            _MenuAction.settings => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            _MenuAction.logout => _confirmLogout(),
          },
          itemBuilder: (context) => [
            PopupMenuItem(enabled: false, child: Text('@${me.name}')),
            const PopupMenuItem(
              value: _MenuAction.settings,
              child: Text('通話の設定'),
            ),
            const PopupMenuItem(
              value: _MenuAction.logout,
              child: Text('ログアウト'),
            ),
          ],
        ),
      ],
    );

    if (!wide) {
      return Scaffold(
        appBar: appBar,
        body: list,
        bottomNavigationBar: const CallBar(),
      );
    }

    final selected = _selectedChannelId;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Scaffold(appBar: appBar, body: list),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selected == null
                ? const Center(child: Text('チャンネルを選択してください'))
                : ChannelPage(
                    key: ValueKey(selected),
                    channelId: selected,
                    showCallBar: false,
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const CallBar(),
    );
  }
}

enum _MenuAction { settings, logout }
