import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nushi/replies.dart';
import 'package:nushi/send_to_agent.dart';
import 'package:nushi/settings.dart';
import 'package:nushi/settings_rows.dart';
import 'package:nushi/theme/theme.dart';
import 'package:nushi/widgets.dart';

/// Settings › GitHub's What reply cards ask: for each kind of card Send to
/// agent makes, the words under its quote, the user's to change (one may
/// want the agent to commit what it fixed). A row a kind, its words on one
/// line: Edit opens them in a dialog; changed, an Edited pill and Reset.
/// Empty, or Reset, asks the default. The data line ([asData]) follows
/// whatever is written, and isn't shown as editable.
class CardAsksGroup extends StatelessWidget {
  const new({super.key});

  /// Keeps [k]'s words as [v]: nothing kept when they're empty or the
  /// default, so a default changed in a later Nushi reaches this card.
  static void keep(CardAsk k, String v) {
    final s = v.trim();
    final asks = {...cardAsks.value};
    if (s.isEmpty || s == k.standard) {
      asks.remove(k.name);
    } else {
      asks[k.name] = v;
    }
    cardAsks.value = asks;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: cardAsks,
    builder: (context, _, _) => SettingsGroup(
      title: 'What reply cards ask',
      footer: const Text('The quote from GitHub always comes first.'),
      children: [for (final k in CardAsk.values) _AskRow(k)],
    ),
  );
}

/// One kind's row: its name, what its card asks now on one line, Edited
/// and Reset once changed, and Edit.
class _AskRow extends StatelessWidget {
  const new(this.ask);

  final CardAsk ask;

  @override
  Widget build(BuildContext context) {
    final edited = ask.text != ask.standard;
    return SettingsRow(
      ask.label,
      key: ValueKey('card-ask-row-${ask.name}'),
      description: ask.text,
      descriptionLines: 1,
      control: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          if (edited) ...[
            const NotePill('Edited', tone: NoteTone.accent),
            Button(
              key: ValueKey('card-ask-reset-${ask.name}'),
              label: 'Reset',
              tooltip: 'Back to: ${ask.standard}',
              onPressed: () => CardAsksGroup.keep(ask, ask.standard),
            ),
          ],
          Button(
            key: ValueKey('card-ask-edit-${ask.name}'),
            label: 'Edit',
            onPressed: () => unawaited(editCardAsk(context, ask)),
          ),
        ],
      ),
    );
  }
}

/// Opens [ask]'s words in a dialog; Save keeps them ([CardAsksGroup.keep]),
/// Cancel or Esc leaves them.
Future<void> editCardAsk(BuildContext context, CardAsk ask) =>
    showDialog<void>(context: context, builder: (_) => _AskEditor(ask));

/// The dialog of [ask]'s words: a field of a few lines, as they are now,
/// the default as its hint; what always follows them under it.
class _AskEditor extends StatefulWidget {
  const new(this.ask);

  final CardAsk ask;

  @override
  State<_AskEditor> createState() => _AskEditorState();
}

class _AskEditorState extends State<_AskEditor> {
  late final _field = TextEditingController(text: widget.ask.text);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    CardAsksGroup.keep(widget.ask, _field.text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    final t = theme.t;
    final ask = widget.ask;
    return nushiDialog(
      ask.label,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            'What Send to agent, Fix checks and Address ask the agent to do '
            'with this card. Empty, it asks the default.',
            style: theme.ui(t.textSecondary),
          ),
          TextField(
            key: ValueKey('card-ask-${ask.name}'),
            controller: _field,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            style: theme.ui(t.text),
            inputFormatters: [
              FilteringTextInputFormatter.deny(CardAsk.notPlain),
              LengthLimitingTextInputFormatter(CardAsk.maxLength),
              // An edit that makes a reply mark's line is refused whole.
              TextInputFormatter.withFunction(
                (old, next) => hasReplyMarks(next.text) ? old : next,
              ),
            ],
            decoration: InputDecoration(hintText: ask.standard),
          ),
          Text('Then always: $asData', style: theme.ui(t.textMuted, size: 12)),
        ],
      ),
      [
        Button(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        Button(
          key: const ValueKey('card-ask-save'),
          label: 'Save',
          kind: ButtonKind.primary,
          onPressed: _save,
        ),
      ],
      width: 520,
    );
  }
}
