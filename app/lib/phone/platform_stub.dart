import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:nushi/phone/subscription.dart';

/// Native phone backend (Android's `platform_android.dart`), installed once at
/// startup; null in tests, where [PhonePlatform] stays in memory.
abstract interface class PhonePlatformHost {
  String get defaultName;
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> record);
  Future<void> clear();
  Future<String?> loadTheme();
  Future<void> saveTheme(String id);
  Future<String?> loadDrafts();
  Future<void> saveDrafts(String? json);
  void onVisible(void Function({required bool visible}) f);
  void onOnline(void Function() f);
  void onResume(void Function() f);
}

/// The native phone backend when running as an installed mobile app (Android);
/// null in tests.
PhonePlatformHost? phonePlatformHost;

/// The browser, in memory: for tests, and delegating to [phonePlatformHost]
/// when running as a native phone app (Android).
final class PhonePlatform {
  new() : _host = phonePlatformHost;

  final PhonePlatformHost? _host;

  /// Whether this runs as a native mobile app (Android) rather than a browser.
  bool get nativeApp => _host != null;

  /// The default device name offered on the pairing screen.
  String get defaultName =>
      _host?.defaultName ?? (iPhone ? 'iPhone' : 'Web browser');

  /// The on-screen keyboard's height over the app (a test sets it).
  final keyboard = ValueNotifier<double>(0);

  /// What [save] kept.
  Map<String, Object?>? saved;

  /// The push subscription [subscribe] made, as a test sets it up.
  PushSub? sub;
  PushState push = PushState.off;
  bool installed = true;
  bool iPhone = false;

  /// A pairing link the page was opened with.
  String? openedWith;

  /// A pairing link that came while the app ran.
  void Function(String link)? onPairLink;

  /// The chat a notification asked to open.
  void Function(String chat)? onOpenChat;

  Future<Map<String, Object?>?> load() async =>
      _host != null ? await _host.load() : saved;
  Future<void> save(Map<String, Object?> record) async {
    if (_host case final h?) {
      await h.save(record);
    } else {
      saved = record;
    }
  }

  Future<void> clear() async {
    if (_host case final h?) {
      await h.clear();
      return;
    }
    if (clearFails case final e?) throw e;
    saved = null;
    drafts = null;
  }

  /// The theme's id as [saveTheme] kept it.
  String? theme;
  Future<String?> loadTheme() async =>
      _host != null ? await _host.loadTheme() : theme;
  Future<void> saveTheme(String id) async {
    if (_host case final h?) {
      await h.saveTheme(id);
    } else {
      theme = id;
    }
  }

  /// The chats' drafts as [saveDrafts] kept them.
  String? drafts;
  Future<String?> loadDrafts() async =>
      _host != null ? await _host.loadDrafts() : drafts;
  Future<void> saveDrafts(String? json) async {
    if (_host case final h?) {
      await h.saveDrafts(json);
    } else {
      drafts = json;
    }
  }

  /// What [clear] throws (a test sets it).
  Error? clearFails;

  /// How many times [registerWorker] was asked.
  int workerRegistered = 0;
  Future<void> registerWorker() async => workerRegistered++;

  /// Whether a newer version waits (a test sets it).
  final updateReady = ValueNotifier<bool>(false);
  bool updated = false;
  Future<void> checkForUpdate() async {}
  void applyUpdate() => updated = true;

  /// The page's origin's host.
  String host = 'relay.example.com';

  /// What [reset] and [closeNotifications] were asked.
  bool wasReset = false;
  final closed = <String>[];

  /// The VAPID key the subscription was made with.
  Uint8List? subscribedKey;

  Future<void> reset() async => wasReset = true;
  Future<void> closeNotifications(String chat) async => closed.add(chat);
  Future<Uint8List?> subscribedWith() async =>
      push == PushState.on ? subscribedKey : null;
  Future<PushState> pushState() async =>
      _host != null ? PushState.unsupported : push;

  Future<PushSub?> subscription() async => push == PushState.on ? sub : null;

  Future<PushSub?> subscribe(Uint8List key) async {
    if (_host != null) return null;
    push = PushState.on;
    subscribedKey = key;
    return sub;
  }

  Future<void> unsubscribe() async => push = PushState.off;

  /// Calls [f] when the page shows or hides; a test calls
  /// [visibilityChanged].
  void onVisible(void Function({required bool visible}) f) {
    visibilityChanged = f;
    _host?.onVisible(f);
  }

  /// What [onVisible] was given: the page shown or hidden.
  void Function({required bool visible})? visibilityChanged;

  /// Calls [f] when the network comes back.
  void onOnline(void Function() f) => _host?.onOnline(f);

  /// Calls [f] when the page comes back from the back-forward cache.
  void onResume(void Function() f) => _host?.onResume(f);

  /// The browser's history, as a test sees it: each entry's depth, the
  /// first the page's own (the root), and the one it's at.
  final entries = [0];
  int at = 0;

  /// The browser moved to an entry: its depth.
  void Function(int depth)? onEntry;

  /// A screen's entry over the current one (the ones after it go).
  void pushEntry(int depth) {
    entries
      ..removeRange(at + 1, entries.length)
      ..add(depth);
    at++;
  }

  /// How late a [go]'s popstate comes; null, at once (a test sets it: a
  /// page waking from the background is slower).
  Duration? goDelay;

  /// What a browser's `history.go` does: the move, and its popstate after.
  void go(int delta) {
    final to = at + delta;
    if (to < 0 || to >= entries.length) return;
    at = to;
    final landed = entries[at];
    if (goDelay case final d?) {
      Timer(d, () => onEntry?.call(landed));
    } else {
      scheduleMicrotask(() => onEntry?.call(landed));
    }
  }

  /// The browser's back (iOS's edge swipe, Safari's back button): at the
  /// first entry it would leave the page, false here.
  bool back() {
    if (at == 0) return false;
    at--;
    onEntry?.call(entries[at]);
    return true;
  }

  /// The chat a notification asked to open when the app started, if any.
  String? takeOpenChat() => null;
}
