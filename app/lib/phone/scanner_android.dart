import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nushi/phone/scanner_stub.dart';

/// Android camera QR scanner backed by CameraX / ML Kit (`mobile_scanner`).
final class AndroidScanner implements ScannerBackend {
  new();

  final _codes = StreamController<String>.broadcast();
  final _controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  StreamSubscription<BarcodeCapture>? _sub;
  bool _stopped = false;

  @override
  Stream<String> get codes => _codes.stream;

  @override
  Widget view() => MobileScanner(
    controller: _controller,
    // design: behind the camera's picture while it starts.
    placeholderBuilder: (_) => const ColoredBox(color: Color(0xFF000000)),
  );

  @override
  Future<String?> start() async {
    // Wait until ScanScreen's build attaches the MobileScanner widget to the
    // controller; starting before attach fails with controllerNotAttached.
    await WidgetsBinding.instance.endOfFrame;
    if (_stopped) return null;
    _sub = _controller.barcodes.listen((capture) {
      if (_stopped) return;
      for (final barcode in capture.barcodes) {
        if (barcode.rawValue case final text? when text.isNotEmpty) {
          _codes.add(text);
        }
      }
    });
    try {
      await _controller.start();
      return null;
    } on MobileScannerException catch (e) {
      return switch (e.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          'Nushi may not use the camera. Allow Camera in Android Settings › '
              'Apps › Nushi › Permissions, or paste the link.',
        MobileScannerErrorCode.unsupported =>
          'No camera was found: paste the link instead.',
        _ => "The camera didn't start: paste the link instead.",
      };
    } on Object {
      return "The camera didn't start: paste the link instead.";
    }
  }

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    unawaited(_sub?.cancel());
    _sub = null;
    unawaited(_controller.dispose());
    unawaited(_codes.close());
  }
}
