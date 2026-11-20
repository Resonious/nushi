import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nushi/theme/theme.dart';
import 'package:xml/xml.dart';

// An SVG image in Markdown (issue 69): someone else's file, drawn by
// flutter_svg, which runs no script, only after it passes [svgRefusal]:
// it loads nothing outside itself and holds nothing a browser would run.
// One that doesn't pass shows as its alt text. docs/security.md says what
// is refused.

/// The largest SVG drawn in Markdown.
const int maxSvgBytes = 1 << 20;

/// The most elements an SVG drawn in Markdown may have.
const int maxSvgElements = 20000;

/// Whether [bytes] look like an SVG: an XML document whose root is `svg`,
/// by its first bytes (a byte order mark, an XML declaration and comments
/// aside), whatever the file is named.
bool looksLikeSvg(List<int> bytes) {
  final head = utf8
      .decode(bytes.take(4096).toList(), allowMalformed: true)
      .replaceFirst('﻿', '');
  return RegExp(r'^\s*(<\?xml[^>]*>\s*)?(<!--[\s\S]*?-->\s*)*<svg[\s>]')
      .hasMatch(head);
}

/// The elements an SVG may not hold: script, other documents or media, and
/// animation, which can set an attribute (a link) after the checks.
const _refusedElements = {
  'script',
  'foreignobject',
  'iframe',
  'object',
  'embed',
  'audio',
  'video',
  'canvas',
  'animate',
  'animatemotion',
  'animatetransform',
  'animatecolor',
  'set',
  'discard',
  'handler',
  'listener',
};

/// The namespaces an SVG's elements may be in: SVG's own (or none, as
/// parsed without a declaration).
const _svgNamespace = 'http://www.w3.org/2000/svg';

/// A `url(…)` that points outside the document: anything but `url(#id)`.
final _outsideUrl = RegExp(r'''url\((?!\s*['"]?\s*#)''', caseSensitive: false);

/// Why [bytes] isn't drawn, or null when it may be: too large, not
/// well-formed XML, not an `svg` root, a DOCTYPE (entities) or a processing
/// instruction other than the XML declaration, too many elements, an
/// element outside SVG's namespace or one of [_refusedElements], an event
/// handler attribute (`on…`), a link (`href`, `xlink:href`, `xml:base`) to
/// anything but `#id` in the document, a `url(…)`, `@import` or CSS
/// escape in an attribute or a style sheet ([_outsideStyle]).
String? svgRefusal(Uint8List bytes) {
  if (bytes.length > maxSvgBytes) return 'larger than 1 MB';
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(bytes));
  } on Object {
    return 'not well-formed';
  }
  for (final node in doc.children) {
    if (node is XmlDoctype) return 'a DOCTYPE';
    if (node is XmlProcessing) return 'a processing instruction';
  }
  final root = doc.rootElement;
  if (root.name.local != 'svg') return 'not an SVG';
  var count = 0;
  for (final node in doc.descendants) {
    if (node is XmlProcessing) return 'a processing instruction';
    if (node is XmlDoctype) return 'a DOCTYPE';
    if (node is! XmlElement) continue;
    if (++count > maxSvgElements) return 'too many elements';
    final name = node.name.local.toLowerCase();
    final ns = node.name.namespaceUri;
    if (ns != null && ns != _svgNamespace) return 'a foreign element';
    if (_refusedElements.contains(name)) return 'a <${node.name.local}>';
    if (name == 'style' && _outsideStyle(node.innerText)) {
      return 'a style sheet that loads';
    }
    for (final a in node.attributes) {
      final attr = a.name.local.toLowerCase();
      final value = a.value.trim();
      if (attr.startsWith('on')) return 'an event handler';
      if (attr == 'base' || attr == 'href' || attr == 'src') {
        if (!value.startsWith('#')) return 'a link outside it';
      }
      if (_outsideStyle(value)) return 'a link outside it';
    }
  }
  return null;
}

/// Whether CSS [text] may load something: an `@import`, a `url(…)` that
/// isn't `#id`, or an escape (a backslash), which could spell either.
bool _outsideStyle(String text) =>
    text.toLowerCase().contains('@import') ||
    text.contains(r'\') ||
    _outsideUrl.hasMatch(text);

/// An SVG drawn in Markdown, at most [size] tall, or [alt] in its place
/// when [svgRefusal] refuses it or it doesn't draw.
class SvgImage extends StatefulWidget {
  const new(this.bytes, {required this.alt, required this.size, super.key});

  final Uint8List bytes;
  final String alt;
  final double size;

  @override
  State<SvgImage> createState() => _SvgImageState();
}

class _SvgImageState extends State<SvgImage> {
  // Checked once for its bytes, not at each build.
  late String? _refused = svgRefusal(widget.bytes);

  @override
  void didUpdateWidget(SvgImage old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes)) {
      _refused = svgRefusal(widget.bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = NushiTheme.of(context);
    Widget said(String why) => Text(
      '[image: ${widget.alt} ($why)]',
      style: TextStyle(color: theme.t.textMuted),
    );
    if (_refused case final why?) {
      return said('an SVG Nushi doesn\u2019t draw: $why');
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.size,
        maxWidth: widget.size * 4,
      ),
      child: SvgPicture.memory(
        widget.bytes,
        alignment: Alignment.centerLeft,
        semanticsLabel: widget.alt,
        errorBuilder: (context, _, _) => said('an SVG that doesn\u2019t draw'),
      ),
    );
  }
}
