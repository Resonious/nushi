import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/pull_header.dart';

/// What keeps an open pull request from merging, in a word each: its
/// checks, its review, its threads, conflicts, being behind its base.
List<String> mergeBlockers(GitHubPull p) => [
  if (p.checks.any((c) => c.failed) ||
      p.checks.any((c) => c.state == 'pending'))
    'checks',
  if (p.item.review == 'changes_requested' ||
      p.item.review == 'review_required' ||
      p.reviewers.any((r) => r.state == 'requested'))
    'review',
  if (p.threads.any((x) => !x.resolved)) 'threads',
  if (hasConflicts(p)) 'conflicts',
  if (p.mergeState == 'behind') 'behind ${p.base}',
];

/// Whether [p] can merge, as GitHub's merge state has it: for a daemon
/// before the Merge control (API 96), which may still serve the app until
/// it restarts when idle (ADR 0056). No conflicts, and clean, with hooks,
/// or unstable (checks not passing that aren't required) with nothing of
/// [mergeBlockers] in the way.
bool mergeStateReady(GitHubPull p) =>
    !hasConflicts(p) &&
    (p.mergeState == 'clean' ||
        p.mergeState == 'has_hooks' ||
        (p.mergeState == 'unstable' && mergeBlockers(p).isEmpty));
