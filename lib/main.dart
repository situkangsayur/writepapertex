import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/features/project/presentation/start_screen.dart';

/// `writepapertex ~/tulisan/paper` opens that folder straight away.
///
/// A desktop editor that can only be driven by its own file dialog is
/// awkward to use from a terminal and impossible to test without one.
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  final folder = args.isEmpty ? null : args.first;
  runApp(ProviderScope(child: WritePaperTexApp(initialFolder: folder)));
}

class WritePaperTexApp extends StatelessWidget {
  const WritePaperTexApp({this.initialFolder, super.key});

  final String? initialFolder;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WritePaperTeX',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6B4F)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6B4F),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: StartScreen(initialFolder: initialFolder),
  );
}
