import 'package:flutter_test/flutter_test.dart';
import 'package:nushi/browser_tabs.dart';
import 'package:nushi/chat.dart';
import 'package:nushi/file_tabs.dart';
import 'package:nushi/preview_entry.dart';
import 'package:nushi/settings.dart';

// A chat's file tabs and browser tabs, apart (ADR 0094, 0123).

void main() {
  const folder = '/Users/me/nushi';

  group('file tabs', () {
    test('open in order, one tab a file however it is named', () {
      final f = FileTabs()
        ..open('a.md', folder: folder)
        ..open('docs/b.md', folder: folder);
      expect(f.tabs.value, const [
        PreviewFile('a.md'),
        PreviewFile('docs/b.md'),
      ]);
      expect(f.shown.value, const PreviewFile('docs/b.md'));
      f
        ..open('./a.md', folder: folder)
        ..open('$folder/a.md', folder: folder);
      expect(f.tabs.value, hasLength(2));
      expect(f.shown.value, const PreviewFile('a.md'));
    });

    test('closing the shown one shows the next or the last; another leaves '
        'it; the last leaves none', () {
      final f = FileTabs();
      for (final p in ['a', 'b', 'c']) {
        f.open(p, folder: folder);
      }
      f
        ..show(const PreviewFile('b'))
        ..close(const PreviewFile('b'));
      expect(f.shown.value, const PreviewFile('c'));
      f.close(const PreviewFile('a'));
      expect(f.shown.value, const PreviewFile('c'));
      f.close(const PreviewFile('c'));
      expect(f.shown.value, isNull);
      expect(f.tabs.value, isEmpty);
    });

    group('preview tabs (ADR 0070)', () {
      test('an open without keeping is provisional; the next takes its '
          'place, in its slot', () {
        final f = FileTabs()
          ..open('a', folder: folder)
          ..open('b', folder: folder, keep: false)
          ..open('c', folder: folder);
        expect(f.provisional.value, const PreviewFile('b'));
        f.open('d', folder: folder, keep: false);
        expect(f.tabs.value, const [
          PreviewFile('a'),
          PreviewFile('d'),
          PreviewFile('c'),
        ]);
        expect(f.shown.value, const PreviewFile('d'));
        expect(f.provisional.value, const PreviewFile('d'));
      });

      test('at most one; kept by an open that keeps, or keep; then the next '
          'one is a new tab', () {
        final f = FileTabs()
          ..open('a', folder: folder, keep: false)
          ..open('./a', folder: folder);
        expect(f.provisional.value, isNull);
        f
          ..open('b', folder: folder, keep: false)
          ..keep(const PreviewFile('b'))
          ..open('c', folder: folder, keep: false);
        expect(f.tabs.value, hasLength(3));
        expect(f.provisional.value, const PreviewFile('c'));
      });

      test('an open without keeping of a kept tab shows it and leaves it '
          'kept', () {
        final f = FileTabs()
          ..open('a', folder: folder)
          ..open('b', folder: folder, keep: false)
          ..open('a', folder: folder, keep: false);
        expect(f.shown.value, const PreviewFile('a'));
        expect(f.provisional.value, const PreviewFile('b'));
        expect(f.tabs.value, hasLength(2));
      });

      test('closing it leaves none provisional; a replaced '
          'one forgets its Source', () {
        final f = FileTabs()
          ..open('a', folder: folder, keep: false)
          ..sources.add('a')
          ..open('b', folder: folder, keep: false);
        expect(f.sources, isEmpty);
        f.close(const PreviewFile('b'));
        expect(f.provisional.value, isNull);
      });

      test("a chat's tree click is provisional only with preview tabs on", () {
        final c = ChatState('c', folder);
        addTearDown(c.dispose);
        c.openInFiles('a', keep: false);
        expect(c.files.provisional.value, const PreviewFile('a'));
        previewTabs.value = false;
        c.openInFiles('b', keep: false);
        expect(c.files.tabs.value, hasLength(2));
        expect(
          c.files.provisional.value,
          const PreviewFile('a'),
          reason: 'turned off, the one there stays as it was',
        );
      });
    });

    test('a Source shown is kept while its tab is open', () {
      final f = FileTabs()..open('a.md', folder: folder);
      f.sources.add('a.md');
      f.open('b.md', folder: folder);
      expect(f.sources, {'a.md'});
      f.close(const PreviewFile('a.md'));
      expect(f.sources, isEmpty);
    });
  });

  group('browser tabs', () {
    test('hold browser tabs alone; the last closed closes the pane', () {
      final b = BrowserTabs();
      final one = b.open('http://localhost:3000');
      final two = b.open();
      expect(b.tabs.value, [one, two]);
      b.close(two);
      expect(b.shown.value, one);
      b.close(one);
      expect(b.shown.value, isNull);
      expect(b.tabs.value, isEmpty);
    });

    test('hidden, they come back as they were', () {
      final b = BrowserTabs();
      final one = b.open('http://localhost:3000');
      final two = b.open('http://localhost:5173');
      b
        ..showTab(one)
        ..hide();
      expect(b.shown.value, isNull);
      expect(b.tabs.value, [one, two]);
      b.show();
      expect(b.shown.value, one);
      expect(b.tabs.value, [one, two]);
    });
  });

  group('the chat', () {
    test("a subagent's pane closes the browser and leaves the files and "
        'their edits', () {
      final c = ChatState('c', folder)
        ..openInFiles('a.md')
        ..openBrowserTab('http://localhost:3000');
      c.pane.value = 'agent';
      expect(c.browser.shown.value, isNull);
      // Its tab stays, to come back with the globe.
      expect(
        [for (final b in c.browser.tabs.value) b.address.value],
        ['http://localhost:3000'],
      );
      expect(c.shownFile, 'a.md');
      // A browser tab takes the subagent's place again.
      c.openBrowserTab();
      expect(c.pane.value, isNull);
    });

    test('remembers which kind of tab showed last', () {
      final c = ChatState('c', folder)..openInFiles('a.md');
      expect(c.lastTabbed, TabKind.file);
      c.openBrowserTab();
      expect(c.lastTabbed, TabKind.browser);
      c.showTab(const PreviewFile('a.md'));
      expect(c.lastTabbed, TabKind.file);
    });
  });
}
