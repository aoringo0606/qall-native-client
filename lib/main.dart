import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/qall/call_background.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CallBackgroundService.initialize();
  runApp(const ProviderScope(child: QallApp()));
}
