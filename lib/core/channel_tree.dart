import 'models.dart';

/// チャンネル一覧から `親/子/孫` 形式のパスを引けるようにしたもの。
class ChannelTree {
  ChannelTree(Iterable<Channel> channels)
    : _byId = {for (final c in channels) c.id: c};

  final Map<String, Channel> _byId;
  final Map<String, String> _pathCache = {};

  Channel? operator [](String id) => _byId[id];

  Iterable<Channel> get channels => _byId.values;

  /// 例: `gps/times/takashi`。存在しないチャンネルは null。
  String? path(String id) {
    final cached = _pathCache[id];
    if (cached != null) return cached;
    final channel = _byId[id];
    if (channel == null) return null;

    final names = <String>[];
    final visited = <String>{};
    Channel? current = channel;
    while (current != null && visited.add(current.id)) {
      names.add(current.name);
      final parentId = current.parentId;
      current = parentId == null ? null : _byId[parentId];
    }
    return _pathCache[id] = names.reversed.join('/');
  }

  /// `#` 付きの表示名。見つからなければIDの先頭を表示する。
  String displayName(String id) {
    final p = path(id);
    if (p != null) return '#$p';
    return id.length > 8 ? '#${id.substring(0, 8)}…' : '#$id';
  }
}
