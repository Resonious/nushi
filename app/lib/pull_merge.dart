import 'package:flutter/material.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/menu.dart';
import 'package:nushi/pull_merge_dialog.dart';
import 'package:nushi/pull_merge_state.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/widgets.dart';

/// The merge status card's merge button, for an open pull request: what
/// the viewer may do about merging it ([mergeView]: a method as a split
/// button with its menu, Enable auto-merge, Add to queue, Merge when
/// ready, or the way out of auto-merge or the queue). Nothing the viewer
/// has no permission for, and no admin bypass (ADR 0069). Every way in
/// goes through the confirmation (`pull_merge_dialog.dart`); [onChanged]
/// reads the pull request again. While the card shows what was kept from
/// before ([stale]) it offers nothing.
class MergeButtons extends StatelessWidget {
  const new({
    required this.daemon,
    required this.pull,
    required this.onChanged,
    super.key,
    this.stale = false,
  });

  final Daemon daemon;
  final GitHubPull pull;
  final Future<void> Function() onChanged;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final view = mergeView(pull);
    if (view == null || stale) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: mergeMethods,
      builder: (context, _, _) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: _actions(context, view),
      ),
    );
  }

  /// The methods to pick from, the one picked ticked; picked is remembered
  /// for this repository.
  List<MenuEntry> _methods(String picked) => [
    for (final m in pull.merge.methods)
      MenuEntry(
        methodLabel(m),
        checked: m == picked,
        detail: mergeMethodsOf(pull).contains(m) ? '' : "It can't rebase now",
        onPick: mergeMethodsOf(pull).contains(m)
            ? () => mergeMethods.value = {
                ...mergeMethods.value,
                mergeRepoKey(pull): m,
              }
            : null,
      ),
  ];

  Future<void> _confirm(BuildContext context, MergeAct act, String method) =>
      confirmMerge(
        context,
        daemon,
        pull,
        act,
        method: method,
        onDone: onChanged,
      );

  List<Widget> _actions(BuildContext context, MergeView view) {
    final ref = pull.item.ref;
    final picked = pickedMethod(pull);
    return switch (view.step) {
      MergeStep.words => const [],
      MergeStep.merge => [
        SplitButton(
          label: methodLabel(picked),
          tooltip: 'Asks you first',
          menuTooltip: 'How it merges',
          entries: _methods(picked),
          onPressed: () => _confirm(context, MergeAct.merge, picked),
        ),
      ],
      MergeStep.auto => [
        SplitButton(
          label: 'Enable auto-merge',
          kind: ButtonKind.secondary,
          tooltip:
              'GitHub merges it with ${methodWords(picked)} once it can. '
              'Asks you first',
          menuTooltip: 'How it merges',
          entries: _methods(picked),
          onPressed: () => _confirm(context, MergeAct.auto, picked),
        ),
      ],
      MergeStep.addToQueue => [
        Button(
          label: 'Add to queue',
          kind: ButtonKind.primary,
          tooltip: 'Asks you first',
          onPressed: () => _confirm(context, MergeAct.enqueue, ''),
        ),
      ],
      MergeStep.whenReady => [
        Button(
          label: 'Merge when ready',
          tooltip: 'Joins the merge queue once it can. Asks you first',
          onPressed: () => _confirm(context, MergeAct.whenReady, ''),
        ),
      ],
      MergeStep.autoOn => [
        if (pull.merge.canDisableAuto)
          RunButton(
            label: 'Disable auto-merge',
            running: 'Disabling…',
            run: () async {
              await daemon.client.disableGitHubAutoMerge(
                DisableGitHubAutoMergeRequest(ref: ref),
              );
              await onChanged();
            },
          ),
      ],
      MergeStep.inQueue => [
        if (pull.merge.canMerge)
          RunButton(
            label: 'Remove from queue',
            running: 'Removing…',
            run: () async {
              await daemon.client.dequeueGitHubPull(
                DequeueGitHubPullRequest(ref: ref),
              );
              await onChanged();
            },
          ),
      ],
    };
  }
}
