import 'package:meta/meta.dart';

/// One changed file in the working tree.
@immutable
class GitChange {
  const GitChange({required this.path, required this.status});

  final String path;

  /// The two-letter code from `git status --porcelain`, e.g. ` M`, `??`, `A `.
  final String status;

  bool get isUntracked => status == '??';
  bool get isDeleted => status.contains('D');

  String get label => switch (status.trim()) {
    '??' => 'baru',
    'M' => 'diubah',
    'A' => 'ditambahkan',
    'D' => 'dihapus',
    'R' => 'dipindah',
    _ => status.trim(),
  };
}

/// Where the working tree stands against its remote.
@immutable
class GitStatus {
  const GitStatus({
    required this.branch,
    required this.changes,
    this.ahead = 0,
    this.behind = 0,
    this.remoteUrl = '',
    this.lastCommit = '',
  });

  final String branch;
  final List<GitChange> changes;

  /// Commits made here that the remote does not have, and the other way round.
  final int ahead;
  final int behind;

  final String remoteUrl;
  final String lastCommit;

  bool get isClean => changes.isEmpty;
  bool get hasRemote => remoteUrl.isNotEmpty;
}

/// What a git command did.
@immutable
class GitResult {
  const GitResult({required this.ok, required this.output, this.message = ''});

  final bool ok;

  /// Everything git printed, kept whole — its errors are usually the clearest
  /// explanation available, and paraphrasing them loses the part that helps.
  final String output;

  final String message;
}

/// Talks to a git repository.
///
/// Deliberately not "GitHub". Projects live wherever their author put them:
/// GitHub, GitLab, a Gitea on the office network, a bare repository on a USB
/// disk. Everything here speaks plain git, so all of those work without the
/// app knowing which is which.
abstract class GitBackend {
  String get name;

  Future<bool> isAvailable();

  /// True when [directory] is inside a git working tree.
  Future<bool> isRepository(String directory);

  Future<GitStatus?> status(String directory);

  Future<GitResult> clone({
    required String remoteUrl,
    required String directory,
    String? branch,
    void Function(String line)? onOutput,
  });

  Future<GitResult> pull(String directory, {void Function(String line)? onOutput});

  Future<GitResult> commitAll(
    String directory, {
    required String message,
    String? authorName,
    String? authorEmail,
  });

  Future<GitResult> push(String directory, {void Function(String line)? onOutput});

  /// Turns an existing folder into a repository, so a project started from a
  /// template can be pushed somewhere later.
  Future<GitResult> init(String directory, {String branch = 'main'});

  Future<GitResult> setRemote(String directory, String remoteUrl, {String name = 'origin'});
}
