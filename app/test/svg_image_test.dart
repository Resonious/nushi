import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/images.dart';
import 'package:nushi/svg_image.dart';

import 'harness.dart';

// What an SVG in Markdown may hold (issue 69): it's someone else's file, so
// nothing in it may load from elsewhere or run.

const _xhtml = 'http://www.w3.org/1999/xhtml';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

String _svg(String inner, {String attrs = ''}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" '
    'xmlns:xlink="http://www.w3.org/1999/xlink" $attrs '
    'width="20" height="20">$inner</svg>';

/// One that's drawn: a gradient and a shape used by id, a style sheet,
/// text, a title.
final String _fine = _svg('''
<title>A mark</title>
<defs>
  <linearGradient id="g"><stop offset="0" stop-color="#fff"/></linearGradient>
  <circle id="c" r="4"/>
  <style>.a { fill: url(#g); stroke: url( '#g' ) }</style>
</defs>
<use href="#c" x="5" y="5"/>
<use xlink:href="#c" x="15" y="15"/>
<rect class="a" width="10" height="10" style="fill: url(#g)"/>
<text x="2" y="18">Hi</text>
''');

void main() {
  test('a plain SVG passes', () {
    expect(svgRefusal(_bytes(_fine)), isNull);
    expect(svgRefusal(_bytes('<?xml version="1.0"?>\n$_fine')), isNull);
  });

  // Each hostile case and why it's refused.
  final hostile = <String, (String, String)>{
    'a script': (_svg('<script>alert(1)</script>'), 'a <script>'),
    'a script, upper case': (_svg('<SCRIPT>x</SCRIPT>'), 'a <SCRIPT>'),
    'a foreignObject': (
      _svg('<foreignObject><div xmlns="$_xhtml">x</div></foreignObject>'),
      'a <foreignObject>',
    ),
    'an XHTML element': (
      _svg('<h:img xmlns:h="http://www.w3.org/1999/xhtml" src="x.png"/>'),
      'a foreign element',
    ),
    'an onload': (
      _svg('<rect/>', attrs: 'onload="alert(1)"'),
      'an event handler',
    ),
    'an onclick': (_svg('<rect onClick="x()"/>'), 'an event handler'),
    'a remote image': (
      _svg('<image href="https://example.com/a.png"/>'),
      'a link outside it',
    ),
    'a remote image by xlink': (
      _svg('<image xlink:href="//example.com/a.png"/>'),
      'a link outside it',
    ),
    'a local file': (
      _svg('<image href="file:///etc/hosts"/>'),
      'a link outside it',
    ),
    'an embedded image': (
      _svg('<image href="data:image/png;base64,AAAA"/>'),
      'a link outside it',
    ),
    'another document by use': (
      _svg('<use href="other.svg#a"/>'),
      'a link outside it',
    ),
    'a link': (
      _svg('<a href="javascript:alert(1)"><rect/></a>'),
      'a link outside it',
    ),
    'an xml:base': (
      _svg('<g xml:base="https://example.com/"><use href="#a"/></g>'),
      'a link outside it',
    ),
    'an @import': (
      _svg('<style>@import url(https://example.com/a.css);</style>'),
      'a style sheet that loads',
    ),
    'a url() in a style sheet': (
      _svg('<style>rect { fill: url(https://example.com/f.svg#p) }</style>'),
      'a style sheet that loads',
    ),
    'a url() in a style attribute': (
      _svg('<rect style="fill:url(\'https://example.com/a\')"/>'),
      'a link outside it',
    ),
    'a url() in a presentation attribute': (
      _svg('<rect filter="url(https://example.com/f.svg#f)"/>'),
      'a link outside it',
    ),
    'a font from elsewhere': (
      _svg(
        '<style>@font-face { font-family: x; '
        'src: url(https://example.com/x.woff) }</style>',
      ),
      'a style sheet that loads',
    ),
    'a CSS escape': (
      _svg(r'<style>rect { fill: \75 rl(https://example.com/a) }</style>'),
      'a style sheet that loads',
    ),
    'an animation that sets a link': (
      _svg(
        '<a href="#x"><set attributeName="href" '
        'to="https://example.com/"/></a>',
      ),
      'a <set>',
    ),
    'an animate': (
      _svg('<rect><animate attributeName="x" to="5"/></rect>'),
      'a <animate>',
    ),
    'an iframe': (_svg('<iframe src="https://example.com"/>'), 'a <iframe>'),
    'a DOCTYPE with entities': (
      '<?xml version="1.0"?>\n<!DOCTYPE svg [<!ENTITY a "aaaa">]>\n'
          '${_svg('<text>&a;</text>')}',
      'a DOCTYPE',
    ),
    'an external entity': (
      '<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
          '${_svg('<text>&x;</text>')}',
      'a DOCTYPE',
    ),
    'a style sheet by processing instruction': (
      '<?xml-stylesheet href="https://example.com/a.css"?>$_fine',
      'a processing instruction',
    ),
    'an HTML page': ('<html><body><svg/></body></html>', 'not an SVG'),
    'not well-formed': ('<svg><rect></svg>', 'not well-formed'),
  };
  for (final MapEntry(key: name, value: (svg, why)) in hostile.entries) {
    test('refused: $name', () {
      expect(svgRefusal(_bytes(svg)), why);
    });
  }

  test('refused: over 1 MB, and too many elements', () {
    final big = _svg('<!--${'x' * maxSvgBytes}-->');
    expect(svgRefusal(_bytes(big)), 'larger than 1 MB');
    final many = _svg('<g/>' * (maxSvgElements + 1));
    expect(svgRefusal(_bytes(many)), 'too many elements');
  });

  test('what looks like an SVG, by its bytes', () {
    expect(looksLikeSvg(_bytes(_fine)), isTrue);
    expect(looksLikeSvg(_bytes('﻿<?xml version="1.0"?>\n$_fine')), isTrue);
    expect(looksLikeSvg(_bytes('<!-- by hand -->\n$_fine')), isTrue);
    expect(
      looksLikeSvg(
        _bytes(
          '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" '
          '"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n$_fine',
        ),
      ),
      isTrue,
    );
    expect(looksLikeSvg(_bytes('<html><svg/></html>')), isFalse);
    expect(looksLikeSvg([0x89, 0x50, 0x4E, 0x47]), isFalse);
  });

  testWidgets('a plain one is drawn; a hostile one is its alt text, and '
      'flutter_svg never sees it', (tester) async {
    await tester.pumpWidget(
      themed(
        Column(
          children: [
            SvgImage(_bytes(_fine), alt: 'fine', size: 100),
            SvgImage(
              _bytes(_svg('<image href="https://example.com/t.png"/>')),
              alt: 'tracker',
              size: 100,
            ),
          ],
        ),
      ),
    );
    expect(find.byType(SvgPicture), findsOne);
    expect(
      find.text(
        '[image: tracker (an SVG Nushi doesn’t draw: a link outside it)]',
      ),
      findsOne,
    );
  });

  testWidgets("a data: URL's SVG in a message goes through the same checks", (
    tester,
  ) async {
    Uri data(String svg) =>
        Uri.dataFromString(svg, mimeType: 'image/svg+xml', encoding: utf8);
    await tester.pumpWidget(
      themed(
        Column(
          children: [
            markdownImage(data(_fine), 'fine'),
            markdownImage(data(_svg('<script>x()</script>')), 'bad'),
          ],
        ),
      ),
    );
    expect(find.byType(SvgPicture), findsOne);
    expect(find.textContaining('[image: bad (an SVG Nushi'), findsOne);
  });

  testWidgets('a local .svg file is read and checked, its size first', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('nushi-svg-'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    final fine = File('${dir.path}/fine.svg')..writeAsStringSync(_fine);
    final bad = File('${dir.path}/bad.svg')
      ..writeAsStringSync(_svg('<rect onload="x()"/>'));
    await tester.pumpWidget(
      themed(
        Column(
          children: [
            markdownImage(Uri.file(fine.path), 'fine'),
            markdownImage(Uri.file(bad.path), 'bad'),
          ],
        ),
      ),
    );
    await untilReal(
      tester,
      () => find.byType(SvgImage).evaluate().length == 2,
      limit: const Duration(seconds: 5),
    );
    expect(find.byType(SvgPicture), findsOne);
    expect(find.textContaining('[image: bad (an SVG Nushi'), findsOne);
  });
}
