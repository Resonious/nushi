import 'package:nushi/gen/nushi/v1/nushi.pb.dart';

/// `overviewPull`'s four files, made up, as GetGitHubFiles answers them.
GetGitHubFilesResponse overviewFiles() => GetGitHubFilesResponse(
  files: [
    for (final (path, added, removed) in [
      ('auth/session.go', 12, 4),
      ('auth/middleware.go', 3, 9),
      ('auth/session_test.go', 58, 0),
      ('docs/auth.md', 11, 6),
    ])
      FileChange(
        path: path,
        status: 'modified',
        oldText: [for (var i = 1; i <= 30; i++) '// line $i'].join('\n'),
        newText: [
          for (var i = 1; i <= 30; i++)
            if (i == 12) '// line $i, changed' else '// line $i',
        ].join('\n'),
        added: added,
        removed: removed,
      ),
  ],
);
