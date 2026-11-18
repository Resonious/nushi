import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/clipboard_files_windows.dart';

/// A BITMAPINFOHEADER of [width] by [height] (negative: rows from the
/// top), [bits] a pixel, [compression]; [extra] after it (masks), then
/// [pixels].
Uint8List _dib({
  required int width,
  required int height,
  required int bits,
  required List<int> pixels,
  int compression = 0,
  int colorsUsed = 0,
  List<int> extra = const [],
}) {
  final header = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, width, Endian.little)
    ..setInt32(8, height, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, bits, Endian.little)
    ..setUint32(16, compression, Endian.little)
    ..setUint32(32, colorsUsed, Endian.little);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...extra,
    ...pixels,
  ]);
}

/// [value] as 4 little-endian bytes.
List<int> _le(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

void main() {
  test('a 24-bit bitmap, bottom row first and each row padded to 4 '
      'bytes, reads top down as opaque RGBA', () {
    // 1×2: the bottom row blue, then the top row red, each BGR + 1 pad.
    final dib = _dib(
      width: 1,
      height: 2,
      bits: 24,
      pixels: [255, 0, 0, 0, 0, 0, 255, 0],
    );
    final (width, height, rgba) = dibPixels(dib)!;
    expect((width, height), (1, 2));
    expect(rgba, [255, 0, 0, 255, 0, 0, 255, 255]);
  });

  test("a 32-bit bitmap whose alpha is 0 everywhere (a screenshot's) is "
      'opaque; one with alpha keeps it', () {
    final opaque = _dib(
      width: 2,
      height: -1,
      bits: 32,
      pixels: [0, 255, 0, 0, 10, 20, 30, 0],
    );
    expect(dibPixels(opaque)!.$3, [0, 255, 0, 255, 30, 20, 10, 255]);
    final clear = _dib(
      width: 2,
      height: -1,
      bits: 32,
      pixels: [0, 255, 0, 128, 10, 20, 30, 0],
    );
    expect(dibPixels(clear)!.$3, [0, 255, 0, 128, 30, 20, 10, 0]);
  });

  test("a 24-bit bitmap's color table (biClrUsed) is skipped, not read "
      'as pixels', () {
    final dib = _dib(
      width: 1,
      height: 1,
      bits: 24,
      colorsUsed: 2,
      extra: [9, 9, 9, 0, 8, 8, 8, 0],
      pixels: [3, 2, 1, 0],
    );
    expect(dibPixels(dib)!.$3, [1, 2, 3, 255]);
  });

  test("BI_BITFIELDS's masks after the header say where each channel "
      'is', () {
    final dib = _dib(
      width: 1,
      height: 1,
      bits: 32,
      compression: 3,
      extra: [..._le(0xff), ..._le(0xff00), ..._le(0xff0000)],
      pixels: [1, 2, 3, 0],
    );
    expect(dibPixels(dib)!.$3, [1, 2, 3, 255]);
  });

  test("a kind it doesn't read, or one too short, gives null; a BMP "
      "file's header points past the palette", () {
    final paletted = _dib(
      width: 1,
      height: 1,
      bits: 8,
      pixels: [...List.filled(256 * 4, 0), 0, 0, 0, 0],
    );
    expect(dibPixels(paletted), isNull);
    expect(dibPixels(Uint8List(12)), isNull);
    expect(
      dibPixels(_dib(width: 4, height: 4, bits: 24, pixels: [1, 2, 3])),
      isNull,
    );
    final bmp = dibAsBmp(paletted)!;
    expect(bmp.sublist(0, 2), 'BM'.codeUnits);
    final head = ByteData.sublistView(bmp);
    expect(head.getUint32(2, Endian.little), bmp.length);
    expect(head.getUint32(10, Endian.little), 14 + 40 + 256 * 4);
  });

  test('a bitmap comes out as a PNG of its size', () async {
    final dib = _dib(
      width: 2,
      height: 2,
      bits: 24,
      pixels: [0, 0, 255, 0, 255, 0, 0, 0, 0, 255, 0, 255, 255, 255, 0, 0],
    );
    final png = (await dibAsPng(dib))!;
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    expect((image.width, image.height), (2, 2));
    image.dispose();
    codec.dispose();
  });

  test("Windows's clipboard is read on an isolate of its own, whatever it "
      'holds (read, never changed)', () async {
    const clipboard = WindowsClipboardFiles();
    expect(await clipboard.files(), isA<List<String>>());
    final png = await clipboard.image();
    if (png != null) expect(png.sublist(1, 4), 'PNG'.codeUnits);
  }, skip: !Platform.isWindows);
}
