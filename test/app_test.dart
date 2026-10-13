import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qall/app.dart';
import 'package:qall/core/providers.dart';
import 'package:qall/core/session_store.dart';

class _EmptySessionStore extends SessionStore {
  @override
  Future<StoredSession?> load() async => null;

  @override
  Future<String> lastOrigin() async => defaultTraqOrigin;
}

void main() {
  testWidgets('shows the login form when no session is stored', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(_EmptySessionStore()),
        ],
        child: const QallApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('traQ アカウントでログイン'), findsOneWidget);
    expect(find.text('ログイン'), findsOneWidget);

    // 空のまま送信するとバリデーションエラー
    await tester.tap(find.text('ログイン'));
    await tester.pump();
    expect(find.text('入力してください'), findsNWidgets(2));
  });
}
