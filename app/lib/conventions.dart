import 'package:flutter/foundation.dart';

import 'package:nushi/native.dart';

/// The modifier a platform's shortcuts are held with: the Mac's ⌘, or
/// Control.
enum CommandKey { meta, control }

/// What a platform names differently, and the key its shortcuts take
/// (ADR 0104): plain data on [Native], so a test or a render shows Linux's
/// on the Mac. Widgets read [conventions], never `defaultTargetPlatform`,
/// which says android under `flutter test`.
class Conventions {
  const new({
    required this.commandKey,
    required this.reveal,
    required this.system,
    required this.machine,
    required this.keyring,
    required this.badge,
    this.altGr = false,
  });

  /// The modifier of the app's shortcuts.
  final CommandKey commandKey;

  /// The action that shows a file in the file manager.
  final String reveal;

  /// The operating system's name.
  final String system;

  /// The computer the app runs on, as a sentence names it.
  final String machine;

  /// Where the system keeps passwords and tokens.
  final String keyring;

  /// The count on the app's icon.
  final String badge;

  /// Whether Control and Alt held together are AltGr, which types a
  /// character (a Spanish keyboard's `@` is AltGr+2): Windows reports
  /// AltGr as both, and takes Ctrl+Alt for it too. No shortcut holds the
  /// two there.
  final bool altGr;

  /// These words, with [key] as the shortcuts' modifier.
  Conventions withKey(CommandKey key) => key == commandKey
      ? this
      : Conventions(
          commandKey: key,
          reveal: reveal,
          system: system,
          machine: machine,
          keyring: keyring,
          badge: badge,
          altGr: altGr,
        );
}

/// The Mac's.
const macConventions = Conventions(
  commandKey: CommandKey.meta,
  reveal: 'Show in Finder',
  system: 'macOS',
  machine: 'Mac',
  keyring: 'keychain',
  badge: 'Dock badge',
);

/// Linux's.
const linuxConventions = Conventions(
  commandKey: CommandKey.control,
  reveal: 'Show in Folder',
  system: 'Linux',
  machine: 'computer',
  keyring: 'keyring',
  badge: 'App icon badge',
);

/// Windows's (ADR 0125).
const windowsConventions = Conventions(
  commandKey: CommandKey.control,
  reveal: 'Show in Explorer',
  system: 'Windows',
  machine: 'PC',
  keyring: 'Credential Manager',
  badge: 'taskbar badge',
  altGr: true,
);

/// Whether this process runs the phone app (web or Android), rather than the
/// desktop app: shared widgets read this instead of [kIsWeb] so the Android
/// phone app never reaches [native] or assumes a local daemon's files.
bool isPhone = kIsWeb;

/// The platform's conventions, as a widget reads them: on the phone, which
/// shares the widgets but has no native edge, the paired computer's words
/// ([phoneHost]) with the phone's own modifier, ⌘, as an iPad's keyboard has
/// it: its keys never follow the computer's system.
Conventions get conventions =>
    isPhone ? phoneHost.withKey(CommandKey.meta) : native.conventions;

/// The phone's paired computer's conventions, by the system its daemon
/// says it runs on ([conventionsOf]); the phone sets them.
Conventions phoneHost = macConventions;

/// The conventions of a daemon's system, as Go names it
/// (PingResponse.os): the Mac's for "darwin", and for a daemon from before
/// it said, which ran on a Mac.
Conventions conventionsOf(String os) => switch (os) {
  'linux' => linuxConventions,
  'windows' => windowsConventions,
  _ => macConventions,
};
