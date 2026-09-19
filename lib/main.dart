import 'package:flutter/material.dart';

import 'screens/editor_screen.dart';

void main() {
  runApp(const SpriteCutApp());
}

class SpriteCutApp extends StatelessWidget {
  const SpriteCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 스프라이트 시트 분할 도구',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const EditorScreen(),
    );
  }
}