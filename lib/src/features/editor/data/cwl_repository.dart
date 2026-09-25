import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../domain/cwl.dart';
import '../domain/latex_language.dart';

/// Finds and reads CWL files for the packages a document loads.
///
/// Three places are searched, in this order, so a project can override what
/// is bundled and a user can drop in TeX Live's own CWL files without the app
/// being rebuilt:
///
/// 1. `<proyek>/.writepapertex/cwl/<nama>.cwl`
/// 2. the user's own folder, [userCwlDir]
/// 3. the CWL files bundled with the app
class CwlRepository {
  CwlRepository({this.projectDir, this.userCwlDir});

  final String? projectDir;
  final String? userCwlDir;

  final CwlParser _parser = const CwlParser();
  final Map<String, List<Completion>> _cache = <String, List<Completion>>{};

  /// Completions for every package [source] loads, plus what it includes.
  ///
  /// Only the packages the document actually loads are read. A list holding
  /// every command in TeX Live would bury the dozen that matter.
  Future<List<Completion>> forDocument(String source) async {
    final wanted = <String>{...scanPackages(source)};
    final out = <Completion>[];
    final done = <String>{};

    while (wanted.isNotEmpty) {
      final name = wanted.first;
      wanted.remove(name);
      if (!done.add(name)) continue;

      final text = await _read(name);
      if (text == null) continue;
      out.addAll(_cachedParse(name, text));
      // A CWL may declare that it needs another; those are pulled in too.
      wanted.addAll(_parser.includesOf(text).where((i) => !done.contains(i)));
    }
    return out;
  }

  List<Completion> _cachedParse(String name, String text) =>
      _cache.putIfAbsent(name, () => _parser.parse(text, from: name));

  Future<String?> _read(String name) async {
    for (final dir in <String?>[
      if (projectDir != null) p.join(projectDir!, '.writepapertex', 'cwl'),
      userCwlDir,
    ]) {
      if (dir == null) continue;
      final file = File(p.join(dir, '$name.cwl'));
      if (file.existsSync()) {
        try {
          return await file.readAsString();
        } on FileSystemException {
          continue;
        }
      }
    }
    try {
      return await rootBundle.loadString('assets/cwl/$name.cwl');
    } catch (_) {
      // No file for this package is ordinary: most packages have none, and
      // the built-in command list still covers the common ones.
      return null;
    }
  }
}
