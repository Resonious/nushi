import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/mermaid_windows.dart';
import 'package:nushi/web_page_windows.dart';
import 'package:nushi/web_view_windows.dart';

void main() {
  test("a page is served from the chat's folder when it's inside, else "
      'from its own, case aside', () {
    expect(
      servedRoot(r'C:\Work\app\docs\a.html', r'C:\Work\app'),
      r'C:\Work\app',
    );
    expect(servedRoot(r'C:\work\APP\a.html', r'C:\Work\app\'), r'C:\Work\app\');
    expect(
      servedRoot(r'C:\Work\other\a.html', r'C:\Work\app'),
      r'C:\Work\other',
    );
    expect(
      servedRoot(r'C:\Work\apple\a.html', r'C:\Work\app'),
      r'C:\Work\apple',
    );
  });

  test('each root is its own host, under the reserved .example', () {
    final one = pageHost(r'C:\Work\app');
    expect(one, matches(RegExp(r'^p[0-9a-f]{16}\.nushi\.example$')));
    expect(pageHost(r'c:\work\APP'), one);
    expect(pageHost(r'C:\Work\other'), isNot(one));
  });

  test("the web views' folder is beside the data folder, never in it, a "
      'separator at its end aside', () {
    const beside = r'C:\nd.WebView2';
    expect(webViewFolder(r'C:\nd'), beside);
    expect(webViewFolder(r'C:\nd\'), beside);
    expect(webViewFolder(r'C:\nd\\'), beside);
    expect(webViewFolder('C:/nd/'), 'C:/nd.WebView2');
  });

  test("a page's address names it under its root, each name encoded, and "
      'comes back as the file', () {
    const root = r'C:\Work\app';
    final host = pageHost(root);
    final url = pageUrl(r'C:\Work\app\docs\page one#1.html', root, host);
    expect('$url', 'https://$host/docs/page%20one%231.html');
    expect(
      servedFile(Uri.parse('https://$host/docs/other%20page.html'), root),
      Uri.file(r'C:\Work\app\docs\other page.html', windows: true),
    );
    expect(servedFile(Uri.parse('https://$host/a%5C..%5Cb'), root), isNull);
  });

  test('a page leaving for a file opens it only inside its root, never '
      'a UNC path (SMB would send the NTLM credentials)', () {
    const root = r'C:\Work\app';
    final host = pageHost(root);
    Uri? left(String url) => leaving(Uri.parse(url), root);
    expect(
      left('file:///C:/Work/app/docs/a.html'),
      Uri.file(r'C:\Work\app\docs\a.html', windows: true),
    );
    expect(left('file:///c:/work/APP/a.html'), isNotNull);
    expect(left('https://$host/b.html'), isNotNull);
    expect(left('https://example.com/x'), Uri.parse('https://example.com/x'));
    for (final url in [
      'file://attacker.example/share/x.html',
      'file://localhost/C:/Work/app/a.html',
      'file:////attacker.example/share/x.html',
      'file:///C:/Work/other/a.html',
      'file:///C:/Work/apple/a.html',
      'file:///C:/Work/app/../other/a.html',
      'file:///C:/Work/app/a%5C..%5C..%5Cb.html',
      'file:///C:/Work/app/a.html:hidden',
      'file:///C:/Work/app',
    ]) {
      expect(left(url), isNull, reason: url);
    }
    expect(leaving(Uri.parse('file:///C:/x.html'), ''), isNull);
  });

  test("the hidden renderer's answer is a PNG and its size, or why "
      'not', () {
    final png = [0x89, 0x50, 0x4e, 0x47];
    final drawn = drawnFrom({
      'png': base64Encode(png),
      'width': 320,
      'height': 120.5,
    });
    expect(drawn.png, png);
    expect((drawn.width, drawn.height), (320.0, 120.5));
    final blank = drawnFrom({'png': '', 'width': 320, 'height': 120});
    expect((blank.png, blank.error), (null, 'Not drawn'));
    final broken = drawnFrom({'error': 'Parse error on line 2'});
    expect(
      (broken.png, broken.error, broken.retry),
      (null, 'Parse error on line 2', false),
    );
  });
}
