import 'dart:async';

import 'package:flutter/widgets.dart';

/// Native camera QR scanner backend (Android's `scanner_android.dart`); null in
/// tests, where [Scanner] runs in memory.
abstract interface class ScannerBackend {
  Stream<String> get codes;
  Future<String?> start();
  Widget view();
  void stop();
}

/// Makes a native [ScannerBackend] on Android; null in tests.
ScannerBackend Function()? scannerBackendFactory;

/// A camera scanning for a QR code, in memory in tests or backed by
/// [scannerBackendFactory] on Android.
final class Scanner {
  new() : _backend = scannerBackendFactory?.call();

  final ScannerBackend? _backend;

  /// Why [start] fails, if a test wants it to.
  static String? refuse;

  /// What the last scanner saw, for a test to feed.
  static Scanner? last;

  final _codes = StreamController<String>.broadcast();
  bool stopped = false;

  /// The text of each QR code it reads.
  Stream<String> get codes => _backend?.codes ?? _codes.stream;

  /// A test's code in front of the camera.
  void see(String text) => _codes.add(text);

  Future<String?> start() async {
    last = this;
    if (_backend case final b?) return await b.start();
    return refuse;
  }

  Widget view() =>
      _backend?.view() ??
      // design: where the camera's picture would be, black as it starts.
      const ColoredBox(color: Color(0xFF000000));

  void stop() {
    stopped = true;
    if (_backend case final b?) {
      b.stop();
      return;
    }
    unawaited(_codes.close());
  }
}
