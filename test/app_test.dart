import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qall/app.dart';
import 'package:qall/core/providers.dart';
import 'package:qall/core/session_store.dart';

class _EmptySessionStore extends SessionStore {
  @override
  Future<StoredSession?> load() async => null;

  @override
  Future<LoginSettings> loginSettings() async =>
      const LoginSettings(origin: defaultTraqOrigin, clientId: '');
}

void main() {
  testWidgets('shows the OAuth login button when no session is stored', (
    tester,
  ) async {
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
    expect(find.text('traQ でログイン'), findsOneWidget);

    // クライアントIDが空のまま押すと、詳細設定が開いてバリデーションエラーが出る
    await tester.tap(find.text('traQ でログイン'));
    await tester.pumpAndSettle();
    expect(find.text('OAuth2 クライアントID'), findsOneWidget);
    expect(find.text('入力してください'), findsOneWidget);
  });
}
