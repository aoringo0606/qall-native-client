import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'features/qall/call_background.dart';
import 'features/settings/call_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CallBackgroundService.initialize();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const QallApp(),
    ),
  );
}
