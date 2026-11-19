import 'dart:io';

import 'package:flutter/material.dart';

import 'package:nushi/alerts_settings.dart';
import 'package:nushi/daemon.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/login_item.dart';
import 'package:nushi/menu.dart';
import 'package:nushi/native.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/settings_rows.dart';
import 'package:nushi/settings_updates.dart';
import 'package:nushi/speller.dart';
import 'package:nushi/web_views.dart';
import 'package:nushi/widgets.dart';

/// Changes the daemon's settings: the function given applied to them.
typedef SettingsChange = Future<void> Function(void Function(Settings));

/// The choices for when idle chats sleep, in minutes; 0: never.
const _sleepAfter = {
  0: 'Never',
  15: '15 minutes',
  30: '30 minutes',
  60: '1 hour',
  120: '2 hours',
  300: '5 hours',
};

String _sleepLabel(int m) => _sleepAfter[m] ?? '$m minute${m == 1 ? '' : 's'}';

/// Settings › General: the chats' group (when idle chats sleep, whether
/// the composer checks spelling, where a chat's local links open, whether
/// the daemon starts at login), the notifications, and updates.
/// [settings] is the daemon's, null until it said.
class GeneralSection extends StatelessWidget {
  const new({
    required this.daemon,
    required this.settings,
    required this.onChange,
    super.key,
  });

  final Daemon daemon;
  final Settings? settings;
  final SettingsChange onChange;

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'General',
    children: [
      // Start at login starts the usual data folder's daemon; it joins the
      // group once the system says whether it's on.
      if (native.install.daemon != null &&
          Platform.environment['NUSHI_DATA'] == null)
        StartAtLogin(group: _chats)
      else
        _chats(const []),
      const NotificationsGroup(),
      if (settings case final s? when s.hasCheckUpdates())
        UpdatesGroup(daemon: daemon, settings: s, onChange: onChange),
    ],
  );

  /// The Chats group, [more] (Start at login's rows) at its end.
  Widget _chats(List<Widget> more) =>
      _ChatsGroup(settings: settings, onChange: onChange, more: more);
}

/// Settings › General's first group, one card of the chat's settings that
/// were each a group of one row: when idle chats sleep (the daemon's, once
/// it said), spelling (the app's own preference, where there's a checker;
/// ADR 0083), local links in a browser tab beside the chat (ADR 0094;
/// where there are web views), then [more].
class _ChatsGroup extends StatelessWidget {
  const new({
    required this.settings,
    required this.onChange,
    required this.more,
  });

  final Settings? settings;
  final SettingsChange onChange;
  final List<Widget> more;

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (settings?.sleepAfterMinutes case final sleep?)
        SettingsRow(
          'Sleep idle chats',
          description: 'The agent stops; your next message wakes it.',
          control: MenuField(
            entries: [
              for (final MapEntry(:key, :value) in {
                ..._sleepAfter,
                sleep: _sleepLabel(sleep),
              }.entries)
                MenuEntry(
                  value,
                  checked: key == sleep,
                  onPick: () => tryOrShow(
                    context,
                    () => onChange((s) => s.sleepAfterMinutes = key),
                  ),
                ),
            ],
            label: Text(sleep == 0 ? 'Never' : 'After ${_sleepLabel(sleep)}'),
          ),
        ),
      if (speller != null)
        ValueListenableBuilder(
          valueListenable: checkSpelling,
          builder: (context, on, _) => SettingsRow(
            'Check spelling while typing',
            description: 'Typos get a dotted underline.',
            control: SettingsSwitch(
              value: on,
              onChanged: (v) => checkSpelling.value = v,
            ),
          ),
        ),
      if (webEmbedded)
        ValueListenableBuilder(
          valueListenable: linksInBrowserTab,
          builder: (context, on, _) => SettingsRow(
            'Open local links in built-in browser',
            description: 'Dev servers open in a tab beside the chat.',
            control: SettingsSwitch(
              value: on,
              onChanged: (v) => linksInBrowserTab.value = v,
            ),
          ),
        ),
      ...more,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return SettingsGroup(title: 'Chats', children: rows);
  }
}
