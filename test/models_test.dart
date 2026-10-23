import 'package:flutter_test/flutter_test.dart';
import 'package:qall/core/channel_tree.dart';
import 'package:qall/core/models.dart';
import 'package:qall/core/session_store.dart';

void main() {
  group('userIdFromIdentity', () {
    const userId = '0d5b5d5e-1111-2222-3333-444455556666';
    const random = '01890f5e-2b5a-7cf3-9a8e-1c2d3e4f5a6b';

    test('extracts the traQ user id from a LiveKit identity', () {
      expect(userIdFromIdentity('${userId}_$random'), userId);
    });

    test('rejects identities that are not issued by traQ', () {
      expect(userIdFromIdentity('soundboard-$random'), isNull);
      expect(userIdFromIdentity(''), isNull);
      expect(userIdFromIdentity(random), isNull);
    });
  });

  test('QallRoom.fromJson dedupes users connected from multiple devices', () {
    const userA = '0d5b5d5e-1111-2222-3333-444455556666';
    const userB = '0d5b5d5e-aaaa-bbbb-cccc-ddddeeeeffff';
    final room = QallRoom.fromJson({
      'roomId': 'room',
      'isWebinar': false,
      'participants': [
        {
          'identity': '${userA}_01890f5e-2b5a-7cf3-9a8e-000000000001',
          'name': userA,
          'joinedAt': '2026-10-13T00:00:00Z',
          'canPublish': true,
        },
        {
          'identity': '${userA}_01890f5e-2b5a-7cf3-9a8e-000000000002',
          'name': userA,
          'joinedAt': '2026-10-13T00:01:00Z',
          'canPublish': true,
        },
        {
          'identity': '${userB}_01890f5e-2b5a-7cf3-9a8e-000000000003',
          'name': userB,
          'joinedAt': '2026-10-13T00:02:00Z',
          'canPublish': false,
          'attributes': {'TR_xxx': 'TR_yyy'},
        },
      ],
    });
    expect(room.participants, hasLength(3));
    expect(room.userIds, [userA, userB]);
    expect(room.participants.last.attributes, {'TR_xxx': 'TR_yyy'});
  });

  test('Message.fromJson sums stamp counts and detects edits', () {
    final message = Message.fromJson({
      'id': 'm',
      'userId': 'u',
      'channelId': 'c',
      'content': 'hello',
      'createdAt': '2026-10-13T00:00:00.000Z',
      'updatedAt': '2026-10-13T00:05:00.000Z',
      'pinned': false,
      'stamps': [
        {'userId': 'a', 'stampId': 's', 'count': 3},
        {'userId': 'b', 'stampId': 's', 'count': 1},
      ],
      'threadId': null,
    });
    expect(message.stampCount, 4);
    expect(message.edited, isTrue);
  });

  group('ChannelTree', () {
    final tree = ChannelTree(const [
      Channel(id: 'gps', parentId: null, name: 'gps', archived: false),
      Channel(id: 'times', parentId: 'gps', name: 'times', archived: false),
      Channel(id: 'me', parentId: 'times', name: 'takashi', archived: false),
    ]);

    test('builds full paths', () {
      expect(tree.path('me'), 'gps/times/takashi');
      expect(tree.displayName('times'), '#gps/times');
    });

    test('unknown channels fall back to a shortened id', () {
      expect(tree.path('0123456789abcdef'), isNull);
      expect(tree.displayName('0123456789abcdef'), '#01234567…');
    });

    test('a parent cycle does not loop forever', () {
      final cyclic = ChannelTree(const [
        Channel(id: 'a', parentId: 'b', name: 'a', archived: false),
        Channel(id: 'b', parentId: 'a', name: 'b', archived: false),
      ]);
      expect(cyclic.path('a'), 'b/a');
    });
  });

  test('normalizeOrigin', () {
    expect(normalizeOrigin('q.trap.jp'), 'https://q.trap.jp');
    expect(
      normalizeOrigin(' https://q.trap.jp/channels/gps '),
      'https://q.trap.jp',
    );
    // トークンを平文で流さないよう http は https にする
    expect(normalizeOrigin('http://localhost:3000/'), 'https://localhost:3000');
  });
}
