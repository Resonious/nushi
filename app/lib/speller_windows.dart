import 'dart:ffi';
import 'dart:io';

import 'package:nushi/speller.dart';

/// Windows's spell checker (ADR 0134): the Spell Checking API's
/// `ISpellChecker` (`spellcheck.h`), through COM by FFI, the one Windows's
/// own text boxes check with, in the user's language, over its
/// dictionaries and the user's own. Ignore lasts the session; Learn adds
/// the word to the user's dictionary for that language
/// (`%APPDATA%\Microsoft\Spelling\<language>\default.dic`), which every app
/// that checks with it shares. Every call is on the app's own thread, the
/// one it opened on: COM's objects belong to their apartment.
class WindowsSpeller implements Speller {
  new _(this._checker);

  /// The checker for the user's language ([language] of the factory's),
  /// or null where there's no such API or dictionary: then there's no
  /// spell check, as a platform without one. Off Windows (a test of
  /// Windows's set on another machine) there's no ole32 to load: none.
  static WindowsSpeller? open({String? locale}) {
    if (!Platform.isWindows) return null;
    if (!_ole32.providesSymbol('CoCreateInstance') ||
        !_kernel32.providesSymbol('GetUserDefaultLocaleName')) {
      return null;
    }
    // The runner's thread is in an apartment already (S_FALSE); a thread
    // in the other model (RPC_E_CHANGED_MODE) can call COM too. Either is
    // never undone: the checker lives as long as the app.
    _coInitializeEx(nullptr, _apartment);
    final factory = _create(_factoryClass, _factoryInterface);
    if (factory == nullptr) return null;
    try {
      final supported = _languages(factory);
      final tag = language(locale ?? _userLocale(), supported);
      if (tag == null) return null;
      final checker = _withOut(
        (out) => _wide(tag, (w) => _textOutCall(factory, 5)(factory, w, out)),
      );
      return checker == nullptr ? null : WindowsSpeller._(checker);
    } finally {
      _release(factory);
    }
  }

  /// The ISpellChecker, held for the app's life.
  final Pointer<Void> _checker;

  /// A word the checker can't judge (a failed call) isn't flagged.
  @override
  Future<List<String>> misspelled(List<String> words) async => [
    for (final w in words)
      if (w.isNotEmpty && _flagged(w)) w,
  ];

  bool _flagged(String word) {
    final errors = _withOut(
      (out) => _wide(word, (w) => _textOutCall(_checker, 4)(_checker, w, out)),
    );
    if (errors == nullptr) return false;
    try {
      // IEnumSpellingError::Next: S_OK with an error, S_FALSE with none.
      final error = _withOut((out) => _outCall(errors, 3)(errors, out));
      if (error == nullptr) return false;
      _release(error);
      return true;
    } finally {
      _release(errors);
    }
  }

  @override
  Future<List<String>> guesses(String word) async {
    if (word.isEmpty) return const [];
    final list = _withOut(
      (out) => _wide(word, (w) => _textOutCall(_checker, 5)(_checker, w, out)),
    );
    if (list == nullptr) return const [];
    try {
      return _strings(list);
    } finally {
      _release(list);
    }
  }

  @override
  Future<void> ignore(String word) async {
    if (word.isNotEmpty) _wordCall(7, word);
  }

  @override
  Future<void> learn(String word) async {
    if (word.isNotEmpty) _wordCall(6, word);
  }

  /// ISpellChecker's Add (6) or Ignore (7) of [word].
  void _wordCall(int index, String word) =>
      _wide(word, (w) => _textCall(_checker, index)(_checker, w));
}

/// Which of the factory's [supported] languages checks [locale]'s words
/// (`en-GB`): the same tag, else the first of its language (`en-US` for
/// `en-AU`), null without one.
String? language(String locale, List<String> supported) {
  final want = locale.toLowerCase();
  for (final tag in supported) {
    if (tag.toLowerCase() == want) return tag;
  }
  final primary = want.split('-').first;
  for (final tag in supported) {
    if (tag.toLowerCase().split('-').first == primary) return tag;
  }
  return null;
}

/// The user's locale's name (`en-GB`), `en-US` when Windows gives none.
String _userLocale() {
  final name = _alloc(_localeNameMax * 2).cast<Uint16>();
  try {
    final n = _userDefaultLocaleName(name, _localeNameMax);
    return n > 1 ? String.fromCharCodes(name.asTypedList(n - 1)) : 'en-US';
  } finally {
    _free(name.cast());
  }
}

/// The languages [factory] has a checker for (its SupportedLanguages).
List<String> _languages(Pointer<Void> factory) {
  final list = _withOut((out) => _outCall(factory, 3)(factory, out));
  if (list == nullptr) return const [];
  try {
    return _strings(list);
  } finally {
    _release(list);
  }
}

/// Every string an IEnumString gives, each freed after.
List<String> _strings(Pointer<Void> list) {
  final next = _slot(
    list,
    3,
  ).cast<NativeFunction<_NextCall>>().asFunction<_NextDart>();
  final item = _alloc(sizeOf<Pointer<Void>>()).cast<Pointer<Uint16>>();
  final fetched = _alloc(4).cast<Uint32>();
  final out = <String>[];
  try {
    while (next(list, 1, item, fetched) == 0 && fetched.value == 1) {
      final s = item.value;
      var n = 0;
      while (s[n] != 0) {
        n++;
      }
      out.add(String.fromCharCodes(s.asTypedList(n)));
      _free(s.cast());
    }
  } finally {
    _free(item.cast());
    _free(fetched.cast());
  }
  return out;
}

/// The interface [call] gives through its out parameter, nullptr when it
/// fails or gives none.
Pointer<Void> _withOut(int Function(Pointer<Pointer<Void>> out) call) {
  final out = _alloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
  try {
    out.value = nullptr;
    final hr = call(out);
    if (hr != 0 && out.value != nullptr) {
      _release(out.value); // S_FALSE with an object, or a failure's leftover
      return nullptr;
    }
    return hr == 0 ? out.value : nullptr;
  } finally {
    _free(out.cast());
  }
}

/// Calls [f] with [s] as a NUL-ended UTF-16 string, freed after.
T _wide<T>(String s, T Function(Pointer<Uint16> w) f) {
  final w = _alloc((s.length + 1) * 2).cast<Uint16>();
  try {
    w.asTypedList(s.length + 1)
      ..setAll(0, s.codeUnits)
      ..[s.length] = 0;
    return f(w);
  } finally {
    _free(w.cast());
  }
}

/// An instance of the COM class [clsid] as [iid], nullptr when it fails.
Pointer<Void> _create(List<int> clsid, List<int> iid) {
  final ids = _alloc(32).cast<Uint8>();
  try {
    ids.asTypedList(32)
      ..setAll(0, clsid)
      ..setAll(16, iid);
    return _withOut(
      (out) => _coCreateInstance(
        ids.cast(),
        nullptr,
        _inProcess,
        (ids + 16).cast(),
        out,
      ),
    );
  } finally {
    _free(ids.cast());
  }
}

/// Method [index] of COM object [object]'s vtable, to be cast to its
/// type (FFI takes a function's type only as a constant).
Pointer<Void> _slot(Pointer<Void> object, int index) =>
    object.cast<Pointer<Pointer<Void>>>().value[index];

/// IUnknown::Release of [object].
void _release(Pointer<Void> object) => _slot(
  object,
  2,
).cast<NativeFunction<_ReleaseCall>>().asFunction<_ReleaseDart>()(object);

/// A method of [object]'s that takes an out parameter.
_OutDart _outCall(Pointer<Void> object, int index) =>
    _slot(object, index).cast<NativeFunction<_OutCall>>().asFunction();

/// A method of [object]'s that takes a string.
_TextDart _textCall(Pointer<Void> object, int index) =>
    _slot(object, index).cast<NativeFunction<_TextCall>>().asFunction();

/// A method of [object]'s that takes a string and an out parameter.
_TextOutDart _textOutCall(Pointer<Void> object, int index) =>
    _slot(object, index).cast<NativeFunction<_TextOutCall>>().asFunction();

typedef _ReleaseCall = Uint32 Function(Pointer<Void>);
typedef _ReleaseDart = int Function(Pointer<Void>);
typedef _OutCall = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _OutDart = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _TextCall = Int32 Function(Pointer<Void>, Pointer<Uint16>);
typedef _TextDart = int Function(Pointer<Void>, Pointer<Uint16>);
typedef _TextOutCall = Int32 Function(
  Pointer<Void>,
  Pointer<Uint16>,
  Pointer<Pointer<Void>>,
);
typedef _TextOutDart = int Function(
  Pointer<Void>,
  Pointer<Uint16>,
  Pointer<Pointer<Void>>,
);
typedef _NextCall = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Pointer<Uint16>>,
  Pointer<Uint32>,
);
typedef _NextDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Pointer<Uint16>>,
  Pointer<Uint32>,
);

/// CLSID_SpellCheckerFactory, {7AB36653-1796-484B-BDFA-E74F1DB7C1DC}, and
/// IID_ISpellCheckerFactory, {8E018A9D-2415-4677-BF08-794EA61F94BB}, as
/// GUIDs lie in memory (the first three fields little-endian).
const _factoryClass = [
  0x53, 0x66, 0xb3, 0x7a, 0x96, 0x17, 0x4b, 0x48, //
  0xbd, 0xfa, 0xe7, 0x4f, 0x1d, 0xb7, 0xc1, 0xdc,
];
const _factoryInterface = [
  0x9d, 0x8a, 0x01, 0x8e, 0x15, 0x24, 0x77, 0x46, //
  0xbf, 0x08, 0x79, 0x4e, 0xa6, 0x1f, 0x94, 0xbb,
];

/// COINIT_APARTMENTTHREADED, CLSCTX_INPROC_SERVER and
/// LOCALE_NAME_MAX_LENGTH.
const _apartment = 0x2;
const _inProcess = 0x1;
const _localeNameMax = 85;

/// ole32 and kernel32, loaded before the first call, so the process's
/// lookup of the calls below finds them.
final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

@Native<Int32 Function(Pointer<Void>, Uint32)>(symbol: 'CoInitializeEx')
external int _coInitializeEx(Pointer<Void> reserved, int model);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Void>,
    Uint32,
    Pointer<Void>,
    Pointer<Pointer<Void>>,
  )
>(symbol: 'CoCreateInstance')
external int _coCreateInstance(
  Pointer<Void> clsid,
  Pointer<Void> outer,
  int context,
  Pointer<Void> iid,
  Pointer<Pointer<Void>> out,
);

@Native<Pointer<Void> Function(Size)>(symbol: 'CoTaskMemAlloc', isLeaf: true)
external Pointer<Void> _alloc(int size);

@Native<Void Function(Pointer<Void>)>(symbol: 'CoTaskMemFree', isLeaf: true)
external void _free(Pointer<Void> p);

@Native<Int32 Function(Pointer<Uint16>, Int32)>(
  symbol: 'GetUserDefaultLocaleName',
  isLeaf: true,
)
external int _userDefaultLocaleName(Pointer<Uint16> name, int length);
