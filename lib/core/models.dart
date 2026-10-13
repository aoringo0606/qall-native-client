/// traQ API v3 のレスポンスのうち、このアプリで使う部分だけを表すモデル。
library;

DateTime _parseTime(Object? value) =>
    DateTime.tryParse(value as String? ?? '')?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

class Me {
  const Me({required this.id, required this.name, required this.displayName});

  factory Me.fromJson(Map<String, dynamic> json) => Me(
    id: json['id'] as String,
    name: json['name'] as String,
    displayName: json['displayName'] as String? ?? json['name'] as String,
  );

  final String id;
  final String name;
  final String displayName;
}

class User {
  const User({
    required this.id,
    required this.name,
    required this.displayName,
    required this.bot,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    name: json['name'] as String,
    displayName: (json['displayName'] as String?)?.isNotEmpty == true
        ? json['displayName'] as String
        : json['name'] as String,
    bot: json['bot'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String displayName;
  final bool bot;
}

class Channel {
  const Channel({
    required this.id,
    required this.parentId,
    required this.name,
    required this.archived,
    this.topic = '',
  });

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: json['id'] as String,
    parentId: json['parentId'] as String?,
    name: json['name'] as String,
    archived: json['archived'] as bool? ?? false,
    topic: json['topic'] as String? ?? '',
  );

  final String id;
  final String? parentId;
  final String name;
  final bool archived;
  final String topic;
}

/// `GET /users/me/subscriptions` の購読レベル。
enum SubscriptionLevel {
  none,

  /// 未読管理のみ
  subscribed,

  /// 未読管理 + 通知
  notified;

  static SubscriptionLevel fromInt(int value) =>
      SubscriptionLevel.values[value.clamp(0, 2)];
}

class UnreadChannel {
  const UnreadChannel({
    required this.channelId,
    required this.count,
    required this.noticeable,
  });

  factory UnreadChannel.fromJson(Map<String, dynamic> json) => UnreadChannel(
    channelId: json['channelId'] as String,
    count: json['count'] as int? ?? 0,
    noticeable: json['noticeable'] as bool? ?? false,
  );

  final String channelId;
  final int count;
  final bool noticeable;
}

class Message {
  const Message({
    required this.id,
    required this.userId,
    required this.channelId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.stampCount = 0,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    userId: json['userId'] as String,
    channelId: json['channelId'] as String,
    content: json['content'] as String? ?? '',
    createdAt: _parseTime(json['createdAt']),
    updatedAt: _parseTime(json['updatedAt']),
    stampCount: (json['stamps'] as List<dynamic>? ?? const []).fold<int>(
      0,
      (sum, s) => sum + ((s as Map)['count'] as int? ?? 1),
    ),
  );

  final String id;
  final String userId;
  final String channelId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int stampCount;

  bool get edited => updatedAt.isAfter(createdAt);
}

/// Qall (LiveKit) のルーム参加者。
///
/// `identity` は traQ サーバーが `{userId}_{randomUUID}` 形式で発行する。
/// 同じユーザーが複数端末から参加すると identity は別になる。
class QallParticipant {
  const QallParticipant({
    required this.identity,
    required this.joinedAt,
    required this.canPublish,
    this.attributes = const {},
  });

  factory QallParticipant.fromJson(Map<String, dynamic> json) =>
      QallParticipant(
        identity: json['identity'] as String? ?? '',
        joinedAt: _parseTime(json['joinedAt']),
        canPublish: json['canPublish'] as bool? ?? true,
        attributes: (json['attributes'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, v.toString())),
      );

  final String identity;
  final DateTime joinedAt;
  final bool canPublish;
  final Map<String, String> attributes;

  String? get userId => userIdFromIdentity(identity);
}

/// `{userId}_{randomUUID}` 形式の identity から traQ のユーザーIDを取り出す。
String? userIdFromIdentity(String identity) {
  // UUID (36文字) + 区切りの '_' (1文字)
  const suffixLength = 37;
  if (identity.length <= suffixLength) return null;
  final separator = identity.length - suffixLength;
  if (identity[separator] != '_') return null;
  return identity.substring(0, separator);
}

class QallRoom {
  const QallRoom({
    required this.roomId,
    required this.participants,
    required this.isWebinar,
  });

  factory QallRoom.fromJson(Map<String, dynamic> json) => QallRoom(
    roomId: json['roomId'] as String,
    participants: (json['participants'] as List<dynamic>? ?? const [])
        .map((p) => QallParticipant.fromJson(p as Map<String, dynamic>))
        .toList(),
    isWebinar: json['isWebinar'] as bool? ?? false,
  );

  /// ルームID = チャンネルID
  final String roomId;
  final List<QallParticipant> participants;
  final bool isWebinar;

  /// 参加中のユーザーID (同一ユーザーの多重接続は1人として数える)
  List<String> get userIds =>
      {for (final p in participants) ?p.userId}.toList();
}

class Stamp {
  const Stamp({required this.id, required this.name, this.isUnicode = false});

  factory Stamp.fromJson(Map<String, dynamic> json) => Stamp(
    id: json['id'] as String,
    name: json['name'] as String,
    isUnicode: json['isUnicode'] as bool? ?? false,
  );

  final String id;
  final String name;

  /// 絵文字 (Unicode) 由来のスタンプか
  final bool isUnicode;
}

/// Qall のサウンドボードに登録された音声。
class SoundboardItem {
  const SoundboardItem({
    required this.soundId,
    required this.soundName,
    this.stampId,
    this.creatorId,
  });

  factory SoundboardItem.fromJson(Map<String, dynamic> json) {
    String? uuid(Object? v) =>
        v is String && v.isNotEmpty && v != _nilUuid ? v : null;
    return SoundboardItem(
      soundId: json['soundId'] as String,
      soundName: json['soundName'] as String? ?? '',
      stampId: uuid(json['stampId']),
      creatorId: uuid(json['creatorId']),
    );
  }

  static const _nilUuid = '00000000-0000-0000-0000-000000000000';

  final String soundId;
  final String soundName;
  final String? stampId;
  final String? creatorId;
}
