import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nushi/attached_files.dart';
import 'package:nushi/conventions.dart';
import 'package:nushi/images.dart' show limitImageCache;
import 'package:nushi/paced.dart';
import 'package:nushi/phone/page_frame_android.dart';
import 'package:nushi/phone/page_frame_stub.dart';
import 'package:nushi/phone/phone.dart';
import 'package:nushi/phone/phone_app.dart';
import 'package:nushi/phone/platform.dart';
import 'package:nushi/phone/platform_android.dart';
import 'package:nushi/phone/platform_stub.dart';
import 'package:nushi/phone/scanner_android.dart';
import 'package:nushi/phone/scanner_stub.dart';

/// Starts Nushi's phone app on Android: installs the Android storage, QR
/// scanner and sandboxed WebView backends, then connects over the relay.
Future<void> runAndroidPhone() async {
  isPhone = true;
  sendWhole = true;
  Paced.paces = false;
  limitImageCache();
  final backend = AndroidPhonePlatform();
  await backend.init();
  phonePlatformHost = backend;
  scannerBackendFactory = AndroidScanner.new;
  pageFrameBuilder = androidFrameView;
  final phone = Phone(PhonePlatform(), sameRelay: false);
  unawaited(phone.start());
  runApp(PhoneApp(phone));
}
