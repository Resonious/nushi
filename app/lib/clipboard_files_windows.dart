import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:nushi/app_log.dart';
import 'package:nushi/clipboard_files.dart';

/// Windows's clipboard for what Ctrl+V attaches (ADR 0125), read through
/// user32 by FFI: Explorer's copied files (`CF_HDROP`), and a picture as
/// PNG when the clipboard holds no text: the PNG an app put there (a
/// browser's copied image), else its device-independent bitmap
/// (`CF_DIB`, which a screenshot is and Windows makes of any other
/// bitmap), drawn as PNG by the engine. A clipboard another app holds
/// open, or one that can't be read, gives nothing, as an empty one does.
///
/// It's read on an isolate of its own, never the window's: a format an app
/// renders only when asked (Office, a browser, a remote desktop's window)
/// keeps `GetClipboardData` waiting on that app, for good if it hangs. A
/// read that takes longer than [_wait] gives nothing; its isolate ends when
/// the call returns.
class WindowsClipboardFiles implements ClipboardFiles {
  const new();

  @override
  Future<List<String>> files() async =>
      await _off(_readFiles) ?? const <String>[];

  @override
  Future<Uint8List?> image() async {
    final copied = await _off(_readImage);
    if (copied == null) return null;
    try {
      return switch (copied) {
        (final png?, _, _) => png,
        (_, (final width, final height, final rgba)?, _) => await rgbaAsPng(
          width,
          height,
          rgba,
        ),
        (_, _, final dib?) => await dibAsPng(dib),
        _ => null,
      };
    } on Object catch (e) {
      appLog.warn("the clipboard's picture wasn't read", {
        'error': e.runtimeType.toString(),
      });
      return null;
    }
  }
}

/// How long a paste waits for the clipboard before it gives nothing.
const _wait = Duration(seconds: 5);

/// What [read] gives on an isolate of its own, or null when it fails or
/// takes longer than [_wait].
Future<T?> _off<T extends Object>(T? Function() read) async {
  try {
    return await Isolate.run(read).timeout(_wait, onTimeout: () => null);
  } on Object catch (e) {
    appLog.warn("the clipboard wasn't read", {
      'error': e.runtimeType.toString(),
    });
    return null;
  }
}

/// The clipboard's copied files, on the isolate that reads it.
List<String>? _readFiles() {
  if (!_user32.providesSymbol('OpenClipboard') ||
      !_shell32.providesSymbol('DragQueryFileW')) {
    return null;
  }
  return _opened(() {
    if (_isAvailable(_cfHdrop) == 0) return const <String>[];
    final drop = _getData(_cfHdrop);
    if (drop == nullptr) return const <String>[];
    final count = _dragQueryFile(drop, _all, nullptr, 0);
    return [for (var i = 0; i < count; i++) ?_dropped(drop, i)];
  });
}

/// The clipboard's picture, on the isolate that reads it: a PNG as it is,
/// a bitmap's pixels read here ([dibPixels]), or any other bitmap for the
/// engine to read; null without one, or while it holds text.
(Uint8List?, (int, int, Uint8List)?, Uint8List?)? _readImage() {
  if (!_user32.providesSymbol('OpenClipboard')) return null;
  final copied = _opened<(Uint8List, bool)?>(() {
    if (_isAvailable(_cfUnicodeText) != 0) return null;
    final png = _registerFormat(_wide('PNG').address);
    if (png != 0 && _isAvailable(png) != 0) {
      if (_global(png) case final bytes?) return (bytes, true);
    }
    if (_isAvailable(_cfDib) != 0) {
      if (_global(_cfDib) case final bytes?) return (bytes, false);
    }
    return null;
  });
  return switch (copied) {
    null => null,
    (final png, true) => (png, null, null),
    (final dib, false) => switch (dibPixels(dib)) {
      final pixels? => (null, pixels, null),
      null => (null, null, dib),
    },
  };
}

/// What [read] gives from the clipboard, opened for it and closed after,
/// on this thread (the clipboard is opened for a thread); null when it
/// can't be opened, as while another app holds it.
T? _opened<T>(T Function() read) {
  if (_openClipboard(nullptr) == 0) return null;
  try {
    return read();
  } finally {
    _closeClipboard();
  }
}

/// The [index]th of the dropped files [drop] names, null for an empty one.
String? _dropped(Pointer<Void> drop, int index) {
  final length = _dragQueryFile(drop, index, nullptr, 0);
  if (length == 0) return null;
  final name = Uint16List(length + 1);
  final got = _dragQueryFile(drop, index, name.address, name.length);
  return got == 0 ? null : String.fromCharCodes(name, 0, got);
}

/// A copy of the clipboard's [format], a global memory block, while it's
/// open; null without one.
Uint8List? _global(int format) {
  final handle = _getData(format);
  if (handle == nullptr) return null;
  final size = _globalSize(handle);
  final data = _globalLock(handle);
  if (data == nullptr) return null;
  try {
    return Uint8List.fromList(data.cast<Uint8>().asTypedList(size));
  } finally {
    _globalUnlock(handle);
  }
}

/// [text] as a NUL-ended UTF-16 string, for a leaf call.
Uint16List _wide(String text) => Uint16List.fromList([...text.codeUnits, 0]);

/// [dib], a `CF_DIB` (a BITMAPINFOHEADER or a later one, its masks or
/// palette, then its pixels), as PNG: its 24- and 32-bit pixels read here
/// ([dibPixels]), any other kind as a BMP file the engine reads.
Future<Uint8List?> dibAsPng(Uint8List dib) async {
  if (dibPixels(dib) case (final width, final height, final rgba)) {
    return await rgbaAsPng(width, height, rgba);
  }
  if (dibAsBmp(dib) case final bmp?) {
    return await _asPng(await ui.instantiateImageCodec(bmp));
  }
  return null;
}

/// [rgba], straight RGBA rows of [width] by [height], as PNG.
Future<Uint8List?> rgbaAsPng(int width, int height, Uint8List rgba) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  return await _asPng(await descriptor.instantiateCodec());
}

/// [codec]'s first frame as PNG, the codec disposed after.
Future<Uint8List?> _asPng(ui.Codec codec) async {
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// BI_RGB and BI_BITFIELDS, a DIB's plain pixels and its masked ones.
const _biRgb = 0;
const _biBitfields = 3;

/// [dib]'s pixels as straight RGBA rows from the top, with its width and
/// height: a 24-bit or 32-bit bitmap, uncompressed or masked, either way
/// up, past any color table it carries. Null for any other kind, or one
/// too short for its size. A 32-bit
/// bitmap whose alpha is 0 everywhere is opaque: apps that draw without
/// alpha leave it so (a screenshot's `CF_DIB` among them).
(int, int, Uint8List)? dibPixels(Uint8List dib) {
  if (dib.length < 40) return null;
  final head = ByteData.sublistView(dib);
  final headerSize = head.getUint32(0, Endian.little);
  final width = head.getInt32(4, Endian.little);
  final rawHeight = head.getInt32(8, Endian.little);
  final bits = head.getUint16(14, Endian.little);
  final compression = head.getUint32(16, Endian.little);
  final used = head.getUint32(32, Endian.little);
  if (headerSize < 40 || width <= 0 || rawHeight == 0) return null;
  if (bits != 24 && bits != 32) return null;
  final height = rawHeight.abs();
  final fromTop = rawHeight < 0;
  // The masks, red, green, blue then alpha: in the header from a V4 one
  // on (108 bytes), else after a plain one for BI_BITFIELDS.
  var masks = const [0x00ff0000, 0x0000ff00, 0x000000ff, 0];
  var offset = headerSize;
  if (compression == _biBitfields) {
    if (bits != 32) return null;
    final at = headerSize >= 108 ? 40 : headerSize;
    if (dib.length < at + 12) return null;
    masks = [
      for (var i = 0; i < 3; i++) head.getUint32(at + 4 * i, Endian.little),
      if (headerSize >= 108) head.getUint32(52, Endian.little) else 0,
    ];
    if (headerSize < 108) offset += 12;
  } else if (compression != _biRgb) {
    return null;
  }
  // A color table of biClrUsed entries may come before the pixels, even
  // of a bitmap that doesn't need one.
  offset += used * 4;
  final stride = (width * bits + 31) ~/ 32 * 4;
  if (dib.length < offset + stride * height) return null;
  final rgba = Uint8List(width * height * 4);
  var anyAlpha = false;
  for (var y = 0; y < height; y++) {
    final row = offset + stride * (fromTop ? y : height - 1 - y);
    for (var x = 0; x < width; x++) {
      final out = (y * width + x) * 4;
      if (bits == 24) {
        final at = row + x * 3;
        rgba
          ..[out] = dib[at + 2]
          ..[out + 1] = dib[at + 1]
          ..[out + 2] = dib[at]
          ..[out + 3] = 255;
        continue;
      }
      final pixel = head.getUint32(row + x * 4, Endian.little);
      for (var c = 0; c < 4; c++) {
        rgba[out + c] = _channel(pixel, masks[c]);
      }
      if (masks[3] == 0 && compression == _biRgb) {
        rgba[out + 3] = pixel >>> 24; // BI_RGB's fourth byte
      }
      if (rgba[out + 3] != 0) anyAlpha = true;
    }
  }
  if (!anyAlpha) {
    for (var i = 3; i < rgba.length; i += 4) {
      rgba[i] = 255;
    }
  }
  return (width, height, rgba);
}

/// The 8-bit value of [pixel]'s channel under [mask], 0 without a mask.
int _channel(int pixel, int mask) {
  if (mask == 0) return 0;
  final shift = (mask & -mask).bitLength - 1; // its lowest bit
  final value = (pixel & mask) >>> shift;
  final width = (mask >>> shift).bitLength;
  return width >= 8
      ? value >>> (width - 8)
      : (value * 255 / ((1 << width) - 1)).round();
}

/// [dib] as a BMP file, its file header put before it, for the engine to
/// read: null when it's too short to be one.
Uint8List? dibAsBmp(Uint8List dib) {
  if (dib.length < 40) return null;
  final head = ByteData.sublistView(dib);
  final headerSize = head.getUint32(0, Endian.little);
  final bits = head.getUint16(14, Endian.little);
  final compression = head.getUint32(16, Endian.little);
  final used = head.getUint32(32, Endian.little);
  final colors = bits <= 8 ? (used == 0 ? 1 << bits : used) : used;
  final masks = compression == _biBitfields && headerSize == 40 ? 12 : 0;
  final pixels = 14 + headerSize + masks + colors * 4;
  final file = ByteData(14 + dib.length)
    ..setUint8(0, 0x42) // 'B'
    ..setUint8(1, 0x4d) // 'M'
    ..setUint32(2, 14 + dib.length, Endian.little)
    ..setUint32(10, pixels, Endian.little);
  final bytes = file.buffer.asUint8List()..setRange(14, 14 + dib.length, dib);
  return bytes;
}

/// Clipboard formats: CF_DIB, CF_UNICODETEXT and CF_HDROP.
const _cfDib = 8;
const _cfUnicodeText = 13;
const _cfHdrop = 15;

/// DragQueryFileW's index for how many files there are.
const _all = 0xffffffff;

/// user32 and shell32, loaded before the first call, so the process's
/// lookup of the calls below finds them.
final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');

// Not leaf calls, the three that can wait on another process: a leaf call
// never reaches a safepoint, so one that blocks holds up garbage
// collection for the whole isolate group, the window's isolate included,
// and reading on an isolate of its own would protect nothing.
// GetClipboardData sends a format rendered only when asked to its owner
// and waits on it; OpenClipboard takes the clipboard's lock; GlobalLock is
// on that data, kept off the leaf path too. The rest return at once, and
// those given a typed list's address must be leaf calls.

@Native<Int32 Function(Pointer<Void>)>(symbol: 'OpenClipboard')
external int _openClipboard(Pointer<Void> owner);

@Native<Int32 Function()>(symbol: 'CloseClipboard', isLeaf: true)
external int _closeClipboard();

@Native<Int32 Function(Uint32)>(
  symbol: 'IsClipboardFormatAvailable',
  isLeaf: true,
)
external int _isAvailable(int format);

@Native<Pointer<Void> Function(Uint32)>(symbol: 'GetClipboardData')
external Pointer<Void> _getData(int format);

@Native<Uint32 Function(Pointer<Uint16>)>(
  symbol: 'RegisterClipboardFormatW',
  isLeaf: true,
)
external int _registerFormat(Pointer<Uint16> name);

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: 'GlobalLock')
external Pointer<Void> _globalLock(Pointer<Void> memory);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'GlobalUnlock', isLeaf: true)
external int _globalUnlock(Pointer<Void> memory);

@Native<Size Function(Pointer<Void>)>(symbol: 'GlobalSize', isLeaf: true)
external int _globalSize(Pointer<Void> memory);

@Native<Uint32 Function(Pointer<Void>, Uint32, Pointer<Uint16>, Uint32)>(
  symbol: 'DragQueryFileW',
  isLeaf: true,
)
external int _dragQueryFile(
  Pointer<Void> drop,
  int index,
  Pointer<Uint16> name,
  int length,
);
