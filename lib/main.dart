import 'package:flutter/material.dart';

import 'src/ui/track_screen.dart';

void main() => runApp(const F1SceneApp());

class F1SceneApp extends StatelessWidget {
  const F1SceneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'f1_scene',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF5A36),
          brightness: Brightness.dark,
        ),
      ),
      home: const TrackScreen(),
    );
  }
}
