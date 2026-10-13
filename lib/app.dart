import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';

class QallApp extends StatelessWidget {
  const QallApp({super.key});

  static const _seed = Color(0xFF005BAC);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // セッション切れなどでログアウトしたら、上に積まれている画面 (チャット・通話) を閉じる
    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.value != null && next is AsyncData && next.value == null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final auth = ref.watch(authControllerProvider);
    return switch (auth) {
      AsyncData(value: null) => const LoginPage(),
      AsyncData() => const HomePage(),
      AsyncError(:final error) => _StartupError(
        message: '$error',
        onRetry: () => ref.invalidate(authControllerProvider),
        onLogout: () => ref.read(authControllerProvider.notifier).logout(),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({
    required this.message,
    required this.onRetry,
    required this.onLogout,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('再試行')),
              TextButton(onPressed: onLogout, child: const Text('ログアウト')),
            ],
          ),
        ),
      ),
    );
  }
}
