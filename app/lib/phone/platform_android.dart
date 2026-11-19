import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nushi/phone/platform_stub.dart';

/// Android's phone backend: private app storage for the device's key, pairing,
/// drafts and theme, Flutter's [AppLifecycleListener] for visibility and
/// resume, and Android's ConnectivityManager over an EventChannel for network
/// recovery.
final class AndroidPhonePlatform implements PhonePlatformHost {
  new() : _forTest = false;

  /// Backed by [_dir] with no platform channels, for unit tests.
  @visibleForTesting
  new forTesting(Directory this._dir, {String? deviceName})
    : _deviceName = deviceName ?? 'Android',
      _forTest = true;

  static const _channel = MethodChannel('nushi/android');
  static const _network = EventChannel('nushi/android/network');

  static const _fields = [
    'key',
    'name',
    'relay',
    'daemon',
    'daemonKey',
    'seen',
    'os',
  ];
  static const _byteFields = {'key', 'daemonKey'};

  final bool _forTest;
  Directory? _dir;
  String _deviceName = 'Android';
  AppLifecycleListener? _lifecycle;
  StreamSubscription<Object?>? _netSub;
  void Function({required bool visible})? _onVisible;
  void Function()? _onOnline;
  void Function()? _onResume;

  /// Resolves Android's private files directory and device model name once at
  /// startup, before Phone.start reads storage.
  Future<void> init() async {
    if (_forTest) return;
    final path = await _channel.invokeMethod<String>('filesDir');
    if (path != null && path.isNotEmpty) {
      _dir = Directory('$path/nushi');
    }
    final name = await _channel.invokeMethod<String>('deviceName');
    if (name != null && name.trim().isNotEmpty) {
      _deviceName = name.trim();
    }
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _onVisible?.call(visible: true);
        _onResume?.call();
      },
      onInactive: () => _onVisible?.call(visible: false),
      onHide: () => _onVisible?.call(visible: false),
      onPause: () => _onVisible?.call(visible: false),
    );
    _netSub = _network.receiveBroadcastStream().listen(
      (_) => _onOnline?.call(),
      onError: (Object _) {},
    );
  }

  /// Releases lifecycle and network listeners.
  void dispose() {
    _lifecycle?.dispose();
    _lifecycle = null;
    unawaited(_netSub?.cancel());
    _netSub = null;
  }

  @override
  String get defaultName => _deviceName;

  File _file(String name) => File('${_dir!.path}/$name');

  Future<void> _writeAtomic(String name, String text) async {
    final dir = _dir;
    if (dir == null) return;
    await dir.create(recursive: true);
    final tmp = File('${dir.path}/$name.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(_file(name).path);
  }

  Future<void> _deleteIfExists(String name) async {
    final dir = _dir;
    if (dir == null) return;
    final f = _file(name);
    if (f.existsSync()) await f.delete();
  }

  @override
  Future<Map<String, Object?>?> load() async {
    final dir = _dir;
    if (dir == null) return null;
    final f = _file('phone.json');
    if (!f.existsSync()) return null;
    final raw = jsonDecode(await f.readAsString());
    if (raw is! Map<String, Object?>) return null;
    final out = <String, Object?>{};
    for (final k in _fields) {
      final v = raw[k];
      if (v is! String) {
        out[k] = null;
      } else if (_byteFields.contains(k)) {
        out[k] = base64Decode(v);
      } else {
        out[k] = v;
      }
    }
    return out;
  }

  @override
  Future<void> save(Map<String, Object?> record) async {
    final out = <String, String>{};
    for (final k in _fields) {
      switch (record[k]) {
        case final Uint8List b:
          out[k] = base64Encode(b);
        case final String s:
          out[k] = s;
      }
    }
    await _writeAtomic('phone.json', jsonEncode(out));
  }

  @override
  Future<void> clear() async {
    await _deleteIfExists('phone.json');
    await _deleteIfExists('drafts.json');
  }

  @override
  Future<String?> loadTheme() async {
    final dir = _dir;
    if (dir == null) return null;
    final f = _file('theme.txt');
    if (!f.existsSync()) return null;
    final id = (await f.readAsString()).trim();
    return id.isEmpty ? null : id;
  }

  @override
  Future<void> saveTheme(String id) => _writeAtomic('theme.txt', id);

  @override
  Future<String?> loadDrafts() async {
    final dir = _dir;
    if (dir == null) return null;
    final f = _file('drafts.json');
    if (!f.existsSync()) return null;
    return await f.readAsString();
  }

  @override
  Future<void> saveDrafts(String? json) => json == null
      ? _deleteIfExists('drafts.json')
      : _writeAtomic('drafts.json', json);

  @override
  void onVisible(void Function({required bool visible}) f) => _onVisible = f;

  @override
  void onOnline(void Function() f) => _onOnline = f;

  @override
  void onResume(void Function() f) => _onResume = f;
}
