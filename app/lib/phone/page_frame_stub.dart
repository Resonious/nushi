import 'package:flutter/widgets.dart';

/// Native embedded preview builder (Android's `page_frame_android.dart`); null
/// in tests, where [frameView] returns a blank placeholder.
Widget Function(String html, {required bool mermaid})? pageFrameBuilder;

/// No frame outside the browser (tests) unless [pageFrameBuilder] is installed.
Widget frameView(String html, {bool mermaid = false}) =>
    pageFrameBuilder?.call(html, mermaid: mermaid) ?? const SizedBox.expand();
