import 'package:flutter/material.dart';

import 'package:nushi/alerts.dart';
import 'package:nushi/conventions.dart';
import 'package:nushi/native.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/settings_rows.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/widgets.dart';

/// Settings › General's Notifications: each kind on or off, the sound and
/// the app icon's badge (`alerts.dart`), in the platform's words; and, when
/// the system has them off for Nushi, a way to its settings. They're shown
/// while Nushi isn't the app in front, or for a chat other than the one
/// showing; a click opens the chat.
class NotificationsGroup extends StatefulWidget {
  const new({super.key});

  @override
  State<NotificationsGroup> createState() => _NotificationsGroupState();
}

class _NotificationsGroupState extends State<NotificationsGroup> {
  NotifyPermission? _allowed;

  @override
  void initState() {
    super.initState();
    alertsAllowed().then((a) {
      if (mounted) setState(() => _allowed = a);
    }).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final t = NushiTheme.of(context).t;
    final words = conventions;
    SettingsRow row(String label, String? text, ValueNotifier<bool> on) =>
        SettingsRow(
          label,
          description: text,
          control: SettingsSwitch(
            value: on.value,
            onChanged: (v) => on.value = v,
          ),
        );
    return ListenableBuilder(
      listenable: Listenable.merge([
        alertNeedsYou,
        alertFinished,
        alertFailed,
        alertSound,
        dockBadge,
      ]),
      builder: (context, _) => SettingsGroup(
        title: 'Notifications',
        footer: const Text('Only for chats you aren’t looking at.'),
        children: [
          if (_allowed == NotifyPermission.denied)
            SettingsRow(
              'Off in ${words.system}',
              description: '${words.system} has notifications off for Nushi.',
              descriptionColor: t.needs,
              control: Button(
                label: 'Open Notifications…',
                onPressed: () => tryOrShow(context, native.alerts.openSettings),
              ),
            ),
          row(
            'A chat needs you',
            'A permission prompt or a question.',
            alertNeedsYou,
          ),
          row('A turn ends', 'Or a workflow finishes.', alertFinished),
          row(
            'A turn fails',
            'An error, the agent quit mid-turn, or a workflow failed or '
                'stopped.',
            alertFailed,
          ),
          row('Sound', null, alertSound),
          row(words.badge, 'Chats that need you.', dockBadge),
        ],
      ),
    );
  }
}
