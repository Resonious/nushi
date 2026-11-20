import 'package:flutter/material.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/settings_rows.dart';
import 'package:nushi/theme/theme.dart';

/// Settings › GitHub's Review bots: off at first; on, a pull request's
/// merge status card (its Comments) lists the must-address findings read
/// out of the
/// named bots' reviews (the list items under a heading with one of the
/// words given), a guess at one bot's Markdown that only fits some.
class FindingsGroup extends StatefulWidget {
  const new({super.key});

  @override
  State<FindingsGroup> createState() => _FindingsGroupState();
}

class _FindingsGroupState extends State<FindingsGroup> {
  late final _bots = TextEditingController(text: githubFindingBots.value);
  late final _headings = TextEditingController(
    text: githubFindingHeadings.value,
  );

  @override
  void dispose() {
    _bots.dispose();
    _headings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    Widget field(
      TextEditingController c,
      ValueNotifier<String> to,
      String hint,
    ) => SizedBox(
      width: 260,
      child: TextField(
        controller: c,
        style: theme.code(t.text, size: 12),
        decoration: InputDecoration(hintText: hint, isDense: true),
        onChanged: (v) => to.value = v,
      ),
    );
    return ValueListenableBuilder(
      valueListenable: githubFindings,
      builder: (context, on, _) => SettingsGroup(
        title: 'Review bots',
        footer: on
            ? const Text(
                "The list items under such a heading in a bot's newest "
                'review; Comments keeps its message.',
              )
            : null,
        children: [
          SettingsRow(
            "Show bots' findings to address",
            description: 'What a review bot says must be fixed.',
            control: SettingsSwitch(
              value: on,
              onChanged: (v) => githubFindings.value = v,
            ),
          ),
          if (on) ...[
            SettingsRow(
              'Bot logins',
              description: 'Comma-separated',
              control: field(_bots, githubFindingBots, 'github-actions'),
            ),
            SettingsRow(
              'Heading that starts the findings',
              description: 'Any of these words, comma-separated, any case',
              control: field(
                _headings,
                githubFindingHeadings,
                findingHeadingsDefault,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
