part of 'streaming_markdown.dart';

// HTML's <img> in Markdown (a README's logo): an image as `![alt](src)`
// would be, through the same image builder, at most its width and height;
// the rest of the HTML still shows as the text it is, but for the tags
// that only wrap an image (a centered paragraph, a <picture>), which go.

/// An `<img>` tag: its src, alt, width and height as written.
final _imgTag = RegExp(r'<img\b([^>]*?)/?>', caseSensitive: false);

/// One of a tag's attributes: its name and its value, quoted or not.
final _attribute = RegExp(
  r'''([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s"'=<>`]+))?''',
);

/// The tags an HTML block of images loses: those that only lay them out.
final _wrapperTag = RegExp(
  r'</?(?:p|div|center|picture|source|a|span|h[1-6])\b[^>]*>',
  caseSensitive: false,
);

/// A `<br>`, which breaks the line.
final _brTag = RegExp(r'<br\s*/?>', caseSensitive: false);

/// [tag]'s attributes, by lower-case name, their values unquoted and their
/// character references for `&`, quotes and angle brackets read.
Map<String, String> _attributes(String tag) => {
  for (final m in _attribute.allMatches(tag))
    m[1]!.toLowerCase(): _unescape(_unquote(m[2] ?? '')),
};

String _unquote(String v) =>
    v.length >= 2 &&
        (v.startsWith('"') && v.endsWith('"') ||
            v.startsWith("'") && v.endsWith("'"))
    ? v.substring(1, v.length - 1)
    : v;

String _unescape(String v) => v
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

/// [match] (an `<img>` tag) as an element of [_HtmlImageSyntax.tag], or
/// null when it names no image.
md.Element? _imageElement(Match match) {
  final a = _attributes(match[1]!);
  final src = a['src']?.trim() ?? '';
  if (src.isEmpty) return null;
  final alt = a['alt'] ?? '';
  return md.Element.text(_HtmlImageSyntax.tag, alt)
    ..attributes['src'] = src
    ..attributes['alt'] = alt
    ..attributes['width'] = a['width'] ?? ''
    ..attributes['height'] = a['height'] ?? '';
}

/// An `<img>` tag in a line of Markdown (a heading's too), as an image.
class _HtmlImageSyntax extends md.InlineSyntax {
  new() : super(_imgTag.pattern, caseSensitive: false);

  static const tag = 'htmlimg';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    // One without a src stays as written (onMatch's false would match it
    // again, at the same place, for ever).
    parser.addNode(_imageElement(match) ?? md.Text(match[0]!));
    return true;
  }
}

/// A length of HTML's (`200`, `200px`); null for anything else (a share).
double? _length(String? v) {
  final n = double.tryParse((v ?? '').trim().replaceFirst(RegExp(r'px$'), ''));
  return n == null || n <= 0 || n.isInfinite ? null : n;
}

/// An `<img>`: what the image builder makes of its src and alt, at most
/// its width and height.
class _HtmlImageBuilder extends MarkdownElementBuilder {
  new(this.image);

  final Widget Function(Uri uri, String? alt) image;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final a = element.attributes;
    final uri = Uri.tryParse(a['src'] ?? '');
    final alt = a['alt'] ?? '';
    final style = (parentStyle ?? const TextStyle()).merge(preferredStyle);
    final built = uri == null
        ? Text('[image: $alt]', style: style)
        : image(uri, alt.isEmpty ? null : alt);
    final w = _length(a['width']);
    final h = _length(a['height']);
    // A widget of its own in the line's run, as `![]()`'s is: a span in
    // the text would take only the line's height.
    if (w == null && h == null) return built;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: w ?? double.infinity,
        maxHeight: h ?? double.infinity,
      ),
      child: built,
    );
  }
}

/// An HTML block's [lines] that hold an `<img>`, as a paragraph: each tag
/// an image, a `<br>` a break, the tags that only lay them out gone, the
/// rest as written; a line left empty adds nothing.
md.Element _htmlImageBlock(List<String> lines) {
  final children = <md.Node>[];
  for (final line in lines) {
    final pieces = <md.Node>[];
    var at = 0;
    for (final m in _imgTag.allMatches(line)) {
      _textOf(line.substring(at, m.start), pieces);
      final e = _imageElement(m);
      if (e != null) {
        pieces.add(e);
      } else {
        pieces.add(md.Text(m[0]!));
      }
      at = m.end;
    }
    _textOf(line.substring(at), pieces);
    if (pieces.isEmpty) continue;
    final last = children.lastOrNull;
    if (last != null && !(last is md.Element && last.tag == 'br')) {
      children.add(md.Element.empty('br'));
    }
    children.addAll(pieces);
  }
  return md.Element('p', children);
}

/// [text] of an HTML block into [into]: the layout tags gone, a `<br>` a
/// break, the rest as written (blank text adds nothing).
void _textOf(String text, List<md.Node> into) {
  final parts = text.replaceAll(_wrapperTag, '').split(_brTag);
  for (final (i, part) in parts.indexed) {
    if (i > 0) into.add(md.Element.empty('br'));
    if (part.trim().isNotEmpty) into.add(md.Text(part.trim()));
  }
}
