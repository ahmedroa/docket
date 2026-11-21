import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/native.dart';
import '../data/settings.dart';
import '../data/store.dart';
import '../l10n/l10n.dart';

/// Registers the two global shortcuts and reports conflicts back to Settings.
class HotKeyService extends ChangeNotifier {
  HotKeyService(this.store, {Native? native})
    : _native = native ?? Native.instance;

  final TaskStore store;
  final Native _native;

  static const toggleId = 1;
  static const quickAddId = 2;

  /// id → "ok" | "system" | "taken" | "error"
  Map<int, String> status = {};

  Future<void> apply() async {
    final s = store.settings;
    await _native.setShortcutLabels(
      s.hotkeysEnabled ? s.toggleHotKey.label : '',
      s.hotkeysEnabled ? s.quickAddHotKey.label : '',
    );
    if (!s.hotkeysEnabled) {
      await _native.registerHotKeys([]);
      status = {};
      notifyListeners();
      return;
    }
    final result = await _native.registerHotKeys([
      {
        'id': toggleId,
        'keyCode': s.toggleHotKey.keyCode,
        'modifiers': s.toggleHotKey.modifiers,
      },
      {
        'id': quickAddId,
        'keyCode': s.quickAddHotKey.keyCode,
        'modifiers': s.quickAddHotKey.modifiers,
      },
    ]);
    status = result.map((k, v) => MapEntry(int.tryParse(k) ?? 0, v));
    notifyListeners();
  }

  Future<void> suspend() => _native.suspendHotKeys();

  static String describe(String? status) => switch (status) {
    'system' => tr('Used by macOS — pick another'),
    'taken' => tr('Used by another app — pick another'),
    'error' => tr("Couldn't register"),
    _ => '',
  };
}

final Map<PhysicalKeyboardKey, int> _physicalToMac = {
  for (final e in kMacOsToPhysicalKey.entries) e.value: e.key,
};

final _modifierKeys = {
  PhysicalKeyboardKey.shiftLeft,
  PhysicalKeyboardKey.shiftRight,
  PhysicalKeyboardKey.controlLeft,
  PhysicalKeyboardKey.controlRight,
  PhysicalKeyboardKey.altLeft,
  PhysicalKeyboardKey.altRight,
  PhysicalKeyboardKey.metaLeft,
  PhysicalKeyboardKey.metaRight,
  PhysicalKeyboardKey.capsLock,
  PhysicalKeyboardKey.fn,
};

final _namedKeys = <PhysicalKeyboardKey, String>{
  PhysicalKeyboardKey.space: 'Space',
  PhysicalKeyboardKey.enter: '↵',
  PhysicalKeyboardKey.tab: '⇥',
  PhysicalKeyboardKey.backspace: '⌫',
  PhysicalKeyboardKey.arrowUp: '↑',
  PhysicalKeyboardKey.arrowDown: '↓',
  PhysicalKeyboardKey.arrowLeft: '←',
  PhysicalKeyboardKey.arrowRight: '→',
  PhysicalKeyboardKey.f1: 'F1',
  PhysicalKeyboardKey.f2: 'F2',
  PhysicalKeyboardKey.f3: 'F3',
  PhysicalKeyboardKey.f4: 'F4',
  PhysicalKeyboardKey.f5: 'F5',
  PhysicalKeyboardKey.f6: 'F6',
  PhysicalKeyboardKey.f7: 'F7',
  PhysicalKeyboardKey.f8: 'F8',
  PhysicalKeyboardKey.f9: 'F9',
  PhysicalKeyboardKey.f10: 'F10',
  PhysicalKeyboardKey.f11: 'F11',
  PhysicalKeyboardKey.f12: 'F12',
};

/// Letters/digits are labelled by their US position so the label matches the
/// physical key Carbon listens to, whatever the active keyboard layout.
final _usLabels = <PhysicalKeyboardKey, String>{
  for (var i = 0; i < 26; i++)
    PhysicalKeyboardKey(0x00070004 + i): String.fromCharCode(0x41 + i),
  for (var i = 0; i < 9; i++) PhysicalKeyboardKey(0x0007001e + i): '${i + 1}',
  PhysicalKeyboardKey.digit0: '0',
  PhysicalKeyboardKey.minus: '-',
  PhysicalKeyboardKey.equal: '=',
  PhysicalKeyboardKey.bracketLeft: '[',
  PhysicalKeyboardKey.bracketRight: ']',
  PhysicalKeyboardKey.semicolon: ';',
  PhysicalKeyboardKey.quote: "'",
  PhysicalKeyboardKey.comma: ',',
  PhysicalKeyboardKey.period: '.',
  PhysicalKeyboardKey.slash: '/',
  PhysicalKeyboardKey.backslash: '\\',
  PhysicalKeyboardKey.backquote: '`',
};

bool isModifierKey(PhysicalKeyboardKey key) => _modifierKeys.contains(key);

/// Builds a [HotKey] from a key press while recording, or null when the press
/// isn't a usable global shortcut (needs ⌘, ⌃ or ⌥ unless it's a function key).
HotKey? hotKeyFromEvent(KeyEvent event) {
  final physical = event.physicalKey;
  if (isModifierKey(physical)) return null;
  final keyCode = _physicalToMac[physical];
  if (keyCode == null) return null;
  final keyboard = HardwareKeyboard.instance;
  var mods = 0;
  if (keyboard.isMetaPressed) mods |= HotKey.cmd;
  if (keyboard.isShiftPressed) mods |= HotKey.shift;
  if (keyboard.isAltPressed) mods |= HotKey.option;
  if (keyboard.isControlPressed) mods |= HotKey.control;
  final label =
      _namedKeys[physical] ??
      _usLabels[physical] ??
      (event.logicalKey.keyLabel.isNotEmpty
          ? event.logicalKey.keyLabel.toUpperCase()
          : '?');
  final isFunctionKey = label.startsWith('F') && label.length > 1;
  final hasStrongModifier =
      mods & (HotKey.cmd | HotKey.control | HotKey.option) != 0;
  if (!hasStrongModifier && !isFunctionKey) return null;
  return HotKey(keyCode: keyCode, modifiers: mods, key: label);
}
