import 'package:flutter/material.dart';

import 'package:nushi/arrangement.dart';
import 'package:nushi/controls.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/settings_fonts.dart';
import 'package:nushi/settings_rows.dart';
import 'package:nushi/settings_theme.dart';
import 'package:nushi/sidebar_view.dart';
import 'package:nushi/view_options.dart';

/// Settings › Appearance: the theme first (Mode, then a card for each
/// theme; ADR 0086), then the layout (the chat's width, the project rail,
/// Pinned, whitespace in Files) and every font in one group (ADR 0114).
class AppearanceSection extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPage(
    title: 'Appearance',
    children: [ThemeGroup(), _Layout(), FontsGroup()],
  );
}

/// The appearance, as the Theme group's first row: as the system is,
/// Light or Dark, remembered (the View menu's items set it too).
class ModeRow extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: appearance,
    builder: (context, mode, _) => SettingsRow(
      'Mode',
      control: Segmented<ThemeMode>(
        key: const ValueKey('appearance-mode'),
        value: mode,
        onCard: true,
        segments: const [
          (ThemeMode.system, 'System'),
          (ThemeMode.light, 'Light'),
          (ThemeMode.dark, 'Dark'),
        ],
        onChanged: (m) => appearance.value = m,
      ),
    ),
  );
}

/// The chat's width (ADR 0074), whether the sidebar has its project rail
/// (ADR 0112; off at first), Pinned from every project, and whether a
/// file's source in the Files pane marks its whitespace (ADR 0096; View ›
/// Show Whitespace and the pane's ⋯ too, [whitespaceOption]).
class _Layout extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => SettingsGroup(
    title: 'Layout',
    children: [
      ValueListenableBuilder(
        valueListenable: chatFullWidth,
        builder: (context, full, _) => SettingsRow(
          'Chat width',
          control: Segmented<bool>(
            key: const ValueKey('chat-width'),
            value: full,
            onCard: true,
            segments: const [(false, 'Centered'), (true, 'Full width')],
            onChanged: (v) => chatFullWidth.value = v,
          ),
        ),
      ),
      ListenableBuilder(
        listenable: Listenable.merge([projectRail, sidebarGroupBy, railFits]),
        builder: (context, _) => SettingsRow(
          'Project rail',
          description: _railNote(),
          control: SettingsSwitch(
            value: projectRail.value,
            onChanged: (v) => projectRail.value = v,
          ),
        ),
      ),
      ValueListenableBuilder(
        valueListenable: pinnedEveryProject,
        builder: (context, every, _) => SettingsRow(
          'Pinned from every project',
          description: 'Pinned keeps the other projects’ chats too.',
          control: SettingsSwitch(
            value: every,
            onChanged: (v) => pinnedEveryProject.value = v,
          ),
        ),
      ),
      ValueListenableBuilder(
        valueListenable: whitespaceOption.pref,
        builder: (context, on, _) => SettingsRow(
          'Show whitespace in files',
          description: 'Dots for spaces, arrows for tabs.',
          control: SettingsSwitch(
            value: on,
            onChanged: (v) => whitespaceOption.pref.value = v,
          ),
        ),
      ),
    ],
  );
}

/// What Project rail says: what it is, or, while it's on and not shown,
/// why not (the sidebar grouped by something else, or the window too
/// narrow for it), which a switch that changed nothing left unsaid.
String _railNote() => switch (projectRail.value) {
  true when sidebarGroupBy.value != GroupBy.project =>
    'Shows while chats are grouped by project.',
  true when !railFits.value => 'Shows in a wider window.',
  _ => 'A column of project tiles beside the chats.',
};
