import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qall/features/channels/favorite_channels.dart';
import 'package:qall/features/settings/call_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('toggles favorites and persists channel IDs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer container() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

    final first = container();
    final notifier = first.read(favoriteChannelsProvider.notifier);
    notifier.toggle('a');
    notifier.toggle('b');
    notifier.toggle('a');
    expect(first.read(favoriteChannelsProvider), {'b'});
    first.dispose();

    // 作り直しても残っている
    final second = container();
    expect(second.read(favoriteChannelsProvider), {'b'});
    second.dispose();
  });
}
