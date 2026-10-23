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

  /// パスで絞り込んだチャンネル (アーカイブ済みを除く)。
  ///
  /// [query] は空白区切りで、すべての語をパスに含むものを返す (大文字小文字は区別しない、
  /// 先頭の `#` は無視)。チャンネル名が語に一致・前方一致するものほど前に並べる。
  List<Channel> search(String query, {int limit = 100}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((w) => w.startsWith('#') ? w.substring(1) : w)
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];

    final hits = <({Channel channel, String path, int rank})>[];
    for (final channel in _byId.values) {
      if (channel.archived) continue;
      final p = path(channel.id)!;
      final lower = p.toLowerCase();
      if (!words.every(lower.contains)) continue;
      final name = channel.name.toLowerCase();
      final last = words.last;
      final rank = name == last
          ? 0
          : name.startsWith(last)
          ? 1
          : lower.startsWith(words.first)
          ? 2
          : 3;
      hits.add((channel: channel, path: p, rank: rank));
    }
    hits.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      final byDepth = '/'
          .allMatches(a.path)
          .length
          .compareTo('/'.allMatches(b.path).length);
      if (byDepth != 0) return byDepth;
      return a.path.compareTo(b.path);
    });
    return [for (final h in hits.take(limit)) h.channel];
  }

  /// `#` 付きの表示名。見つからなければIDの先頭を表示する。
  String displayName(String id) {
    final p = path(id);
    if (p != null) return '#$p';
    return id.length > 8 ? '#${id.substring(0, 8)}…' : '#$id';
  }
}
