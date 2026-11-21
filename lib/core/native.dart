import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart side of the `docket/native` channel (see macos/Runner/NativeBridge.swift).
/// Every call degrades gracefully so widget tests run without the host app.
class Native {
  Native._();
  static final Native instance = Native._();

  static const _channel = MethodChannel('docket/native');

  /// reason: `toggle`, `quickAdd`, `settings`, `task:ID` or `harness`.
  void Function(String reason)? onPanelShow;
  VoidCallback? onPanelHide;
  void Function(String action, String taskId)? onNotificationAction;

  bool _listening = false;

  void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      final args =
          (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'panelDidShow':
          onPanelShow?.call(args['reason'] as String? ?? 'toggle');
        case 'panelDidHide':
          onPanelHide?.call();
        case 'notificationAction':
          onNotificationAction?.call(
            args['action'] as String? ?? '',
            args['taskId'] as String? ?? '',
          );
      }
      return null;
    });
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Native.$method failed: ${e.message}');
      return null;
    }
  }

  Future<void> showPanel([String reason = 'toggle']) =>
      _call('showPanel', {'reason': reason});
  Future<void> hidePanel() => _call('hidePanel');

  /// Drop-down size or curtain configuration; applied live if the panel is open.
  Future<void> setDisplayMode({
    required bool curtain,
    required double width,
    required double height,
    required double curtainHeight,
    required bool animated,
    required double blur,
    required String tone,
  }) => _call('setDisplayMode', {
    'mode': curtain ? 'curtain' : 'dropdown',
    'width': width,
    'height': height,
    'curtainHeight': curtainHeight,
    'animated': animated,
    'blur': blur,
    'tone': tone,
  });
  Future<void> setBadge(String text) => _call('setBadge', {'text': text});

  /// Labels for the native status-item menu and notification actions.
  Future<void> setLocalizedStrings(Map<String, String> strings) =>
      _call('setLocalizedStrings', strings);
  Future<void> setShortcutLabels(String toggle, String quickAdd) =>
      _call('setShortcutLabels', {'toggle': toggle, 'quickAdd': quickAdd});

  /// Returns id → "ok" | "system" | "taken" | "error".
  Future<Map<String, String>> registerHotKeys(
    List<Map<String, int>> hotkeys,
  ) async {
    final r = await _call<Map>('registerHotKeys', {'hotkeys': hotkeys});
    return r?.map((k, v) => MapEntry('$k', '$v')) ?? {};
  }

  Future<String> checkHotKey(int keyCode, int modifiers) async =>
      await _call<String>('checkHotKey', {
        'keyCode': keyCode,
        'modifiers': modifiers,
      }) ??
      'ok';

  Future<void> suspendHotKeys() => _call('suspendHotKeys');

  Future<String> notificationStatus() async =>
      await _call<String>('notificationStatus') ?? 'unsupported';
  Future<bool> requestNotificationPermission() async =>
      await _call<bool>('requestNotificationPermission') ?? false;
  Future<void> scheduleNotifications(List<Map<String, Object?>> items) =>
      _call('scheduleNotifications', {'items': items});
  Future<void> openNotificationSettings() => _call('openNotificationSettings');

  /// "enabled" | "disabled" | "requiresApproval" | "unsupported"
  Future<String> launchAtLogin() async =>
      await _call<String>('getLaunchAtLogin') ?? 'unsupported';
  Future<String> setLaunchAtLogin(bool enabled) async =>
      await _call<String>('setLaunchAtLogin', {'enabled': enabled}) ??
      'unsupported';

  Future<String?> appSupportDirectory() => _call<String>('appSupportDirectory');
  Future<String?> saveFile(String suggestedName) =>
      _call<String>('saveFile', {'suggestedName': suggestedName});
  Future<String?> openFile() => _call<String>('openFile');
  Future<void> revealInFinder(String path) =>
      _call('revealInFinder', {'path': path});

  Future<Map<String, String>> appInfo() async {
    final r = await _call<Map>('appInfo');
    return r?.map((k, v) => MapEntry('$k', '$v')) ?? {};
  }

  Future<void> quit() => _call('quit');
}
