import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/session_store.dart';
import '../../core/traq_api.dart';
import '../../core/traq_oauth.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _origin = TextEditingController(text: defaultTraqOrigin);
  final _clientId = TextEditingController(text: defaultTraqClientId);
  bool _submitting = false;
  final _advanced = ExpansibleController();
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(sessionStoreProvider).loginSettings().then((settings) {
      if (!mounted) return;
      _origin.text = settings.origin;
      _clientId.text = settings.clientId;
    });
  }

  @override
  void dispose() {
    _origin.dispose();
    _clientId.dispose();
    _advanced.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      // 未入力の欄が閉じた「詳細設定」の中にあると気づけないので開く
      _advanced.expand();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            origin: normalizeOrigin(_origin.text),
            clientId: _clientId.text.trim(),
          );
    } on OAuthCanceledException {
      // ブラウザを閉じただけなので何も出さない
    } on TraqApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.call,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Qall',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    Text(
                      'traQ アカウントでログイン',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'kaitoyama による非公式のプロトタイプです。\ntraP 公式のアプリではありません。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('traQ でログイン'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ExpansionTile(
                      controller: _advanced,
                      // 閉じていても入力欄のバリデーションが効くよう保持する
                      maintainState: true,
                      title: const Text('詳細設定'),
                      tilePadding: EdgeInsets.zero,
                      children: [
                        TextFormField(
                          controller: _origin,
                          decoration: const InputDecoration(
                            labelText: 'traQ サーバー',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? '入力してください' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _clientId,
                          decoration: const InputDecoration(
                            labelText: 'OAuth2 クライアントID',
                            helperText: 'コールバックURL: $oauthRedirectUri',
                            border: OutlineInputBorder(),
                          ),
                          autocorrect: false,
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? '入力してください' : null,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
