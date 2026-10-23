import 'package:flutter_test/flutter_test.dart';
import 'package:qall/core/channel_tree.dart';
import 'package:qall/core/models.dart';

Channel _ch(String id, String name, {String? parent, bool archived = false}) =>
    Channel(id: id, parentId: parent, name: name, archived: archived);

void main() {
  final tree = ChannelTree([
    _ch('gps', 'gps'),
    _ch('times', 'times', parent: 'gps'),
    _ch('takashi', 'takashi', parent: 'times'),
    _ch('general', 'general'),
    _ch('team', 'team'),
    _ch('sysad', 'SysAd', parent: 'team'),
    _ch('old', 'times_old', parent: 'gps', archived: true),
  ]);

  List<String> ids(String q) => [for (final c in tree.search(q)) c.id];

  test('matches every word against the full path, ignoring case and #', () {
    expect(ids('gps takashi'), ['takashi']);
    expect(ids('#team/sys'), ['sysad']);
    expect(ids('SYSAD'), ['sysad']);
  });

  test('ranks exact and prefix name matches first', () {
    // times (名前が一致) → takashi (パスにだけ含む)
    expect(ids('times'), ['times', 'takashi']);
  });

  test('skips archived channels and empty queries', () {
    expect(ids('old'), isEmpty);
    expect(ids('  '), isEmpty);
  });

  test('follows a channel after it moves', () {
    final moved = ChannelTree([
      _ch('gps', 'gps'),
      _ch('general', 'general'),
      _ch('times', 'times', parent: 'general'),
    ]);
    expect(moved.path('times'), 'general/times');
    expect([for (final c in moved.search('general times')) c.id], ['times']);
  });
}
