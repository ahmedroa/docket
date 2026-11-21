import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../l10n/l10n.dart';

/// A global shortcut as Carbon understands it: a virtual key code (physical
/// key position) plus Carbon modifier bits.
@immutable
class HotKey {
  const HotKey({
    required this.keyCode,
    required this.modifiers,
    required this.key,
  });

  final int keyCode;
  final int modifiers;

  /// Display label of the key itself ("T", "Space", "F5").
  final String key;

  static const cmd = 0x100;
  static const shift = 0x200;
  static const option = 0x800;
  static const control = 0x1000;

  String get label {
    final b = StringBuffer();
    if (modifiers & control != 0) b.write('⌃');
    if (modifiers & option != 0) b.write('⌥');
    if (modifiers & shift != 0) b.write('⇧');
    if (modifiers & cmd != 0) b.write('⌘');
    b.write(key);
    // Wrapped in left-to-right marks so ⌃⌥T doesn't reverse inside Arabic text.
    return '\u200E$b\u200E';
  }

  Map<String, dynamic> toJson() => {
    'keyCode': keyCode,
    'modifiers': modifiers,
    'key': key,
  };

  static HotKey? fromJson(Object? j) {
    if (j is! Map) return null;
    final code = j['keyCode'];
    final mods = j['modifiers'];
    final key = j['key'];
    if (code is! int || mods is! int || key is! String) return null;
    return HotKey(keyCode: code, modifiers: mods, key: key);
  }

  @override
  bool operator ==(Object other) =>
      other is HotKey &&
      other.keyCode == keyCode &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(keyCode, modifiers);

  /// ⌃⌥T and ⌃⌥N: no macOS default uses Control+Option+letter, and these
  /// combinations don't type characters in any keyboard layout.
  static const defaultToggle = HotKey(
    keyCode: 17,
    modifiers: control | option,
    key: 'T',
  );
  static const defaultQuickAdd = HotKey(
    keyCode: 45,
    modifiers: control | option,
    key: 'N',
  );
}

enum SortMode {
  manual('manual', 'Manual'),
  priority('priority', 'Priority'),
  dueDate('due', 'Due date'),
  created('created', 'Date added');

  const SortMode(this.key, this.en);
  final String key;

  /// English label; [label] is the translated one.
  final String en;
  String get label => tr(en);
  static SortMode parse(Object? k) =>
      values.firstWhere((v) => v.key == k, orElse: () => SortMode.manual);
}

enum BadgeMode {
  none('none', 'Icon only'),
  attention('attention', 'Urgent + overdue'),
  today('today', 'Due today'),
  open('open', 'All open');

  const BadgeMode(this.key, this.en);
  final String key;

  /// English label; [label] is the translated one.
  final String en;
  String get label => tr(en);
  static BadgeMode parse(Object? k) =>
      values.firstWhere((v) => v.key == k, orElse: () => BadgeMode.attention);
}

/// How Docket appears: a drop-down under the menu bar icon in three sizes,
/// or the full-width glass curtain.
enum DisplayMode {
  small('small', 'Small', 360, 500),
  normal('normal', 'size|Normal', 400, 640),
  large('large', 'Large', 520, 820),
  curtain('curtain', 'Curtain', 0, 0);

  const DisplayMode(this.key, this.en, this.width, this.height);
  final String key;

  /// English label; [label] is the translated one.
  final String en;
  String get label => tr(en);

  /// Drop-down size (unused for the curtain, which follows the screen).
  final double width;
  final double height;

  bool get isCurtain => this == curtain;

  /// Also reads the older `panelSize` values.
  static DisplayMode parse(Object? k) => switch (k) {
    'small' || 'compact' => small,
    'large' => large,
    'curtain' => curtain,
    _ => normal,
  };
}

/// Tint of the curtain glass.
enum GlassTone {
  auto('auto', 'Auto'),
  light('light', 'Light'),
  dark('dark', 'Dark');

  const GlassTone(this.key, this.en);
  final String key;
  final String en;
  String get label => tr(en);
  static GlassTone parse(Object? k) =>
      values.firstWhere((v) => v.key == k, orElse: () => GlassTone.auto);
}

/// User preferences, persisted as one JSON document in the settings table.
class AppSettings {
  AppLanguage language = AppLanguage.ar;
  ThemeMode themeMode = ThemeMode.system;
  bool use24h = false;
  SortMode sortMode = SortMode.manual;
  BadgeMode badgeMode = BadgeMode.attention;
  DisplayMode displayMode = DisplayMode.normal;

  // Curtain mode
  /// 0 = solid tint, 1 = almost clear glass.
  double curtainTransparency = 0.45;

  /// Strength of the native background blur (0–1).
  double curtainBlur = 0.85;

  /// Fraction of the screen height the curtain covers.
  double curtainHeight = 0.78;
  bool curtainAnimation = true;
  GlassTone curtainTone = GlassTone.auto;

  /// The session list on the curtain's end side (left in Arabic).
  bool curtainShowSession = true;

  /// When the first line of the current session list was written.
  DateTime? sessionStartedAt;

  // Home sections
  bool showSummary = true;
  bool showCompanies = true;
  bool showToday = true;

  /// Completed tasks stay at the bottom of lists, ticked and crossed out,
  /// instead of leaving the list.
  bool showCompletedInLists = true;

  // Shortcuts
  bool hotkeysEnabled = true;
  HotKey toggleHotKey = HotKey.defaultToggle;
  HotKey quickAddHotKey = HotKey.defaultQuickAdd;

  // Notifications
  bool notificationsEnabled = true;
  bool notifyAtDue = true;

  /// Minutes before a timed due date (0 = off). 1440 = a day before.
  int remindBefore = 30;
  bool dailyDigest = true;

  /// Minutes after midnight for the morning summary and date-only reminders.
  int digestMinutes = 9 * 60;

  /// Hours between urgent nudges during the work day (0 = off).
  int urgentNudgeHours = 0;

  // Backups
  bool autoBackup = true;
  int backupKeep = 14;
  DateTime? lastBackupAt;

  // One-time state
  bool welcomeDismissed = false;
  bool launchAtLoginInitialized = false;

  Map<String, dynamic> toJson() => {
    'language': language.code,
    'themeMode': themeMode.name,
    'use24h': use24h,
    'sortMode': sortMode.key,
    'badgeMode': badgeMode.key,
    'displayMode': displayMode.key,
    'curtainTransparency': curtainTransparency,
    'curtainBlur': curtainBlur,
    'curtainHeight': curtainHeight,
    'curtainAnimation': curtainAnimation,
    'curtainTone': curtainTone.key,
    'curtainShowSession': curtainShowSession,
    'sessionStartedAt': sessionStartedAt?.millisecondsSinceEpoch,
    'showSummary': showSummary,
    'showCompanies': showCompanies,
    'showToday': showToday,
    'showCompletedInLists': showCompletedInLists,
    'hotkeysEnabled': hotkeysEnabled,
    'toggleHotKey': toggleHotKey.toJson(),
    'quickAddHotKey': quickAddHotKey.toJson(),
    'notificationsEnabled': notificationsEnabled,
    'notifyAtDue': notifyAtDue,
    'remindBefore': remindBefore,
    'dailyDigest': dailyDigest,
    'digestMinutes': digestMinutes,
    'urgentNudgeHours': urgentNudgeHours,
    'autoBackup': autoBackup,
    'backupKeep': backupKeep,
    'lastBackupAt': lastBackupAt?.millisecondsSinceEpoch,
    'welcomeDismissed': welcomeDismissed,
    'launchAtLoginInitialized': launchAtLoginInitialized,
  };

  static AppSettings fromJson(Map<String, dynamic>? j) {
    final s = AppSettings();
    if (j == null) return s;
    T read<T>(String key, T fallback) {
      final v = j[key];
      return v is T ? v : fallback;
    }

    s.language = AppLanguage.parse(j['language']);
    s.themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == j['themeMode'],
      orElse: () => ThemeMode.system,
    );
    s.use24h = read('use24h', s.use24h);
    s.sortMode = SortMode.parse(j['sortMode']);
    s.badgeMode = BadgeMode.parse(j['badgeMode']);
    s.displayMode = DisplayMode.parse(j['displayMode'] ?? j['panelSize']);
    double unit(String key, double fallback, {double min = 0, double max = 1}) {
      final v = j[key];
      return v is num ? v.toDouble().clamp(min, max) : fallback;
    }

    s.curtainTransparency = unit('curtainTransparency', s.curtainTransparency);
    s.curtainBlur = unit('curtainBlur', s.curtainBlur);
    s.curtainHeight = unit('curtainHeight', s.curtainHeight, min: 0.4, max: 1);
    s.curtainAnimation = read('curtainAnimation', s.curtainAnimation);
    s.curtainTone = GlassTone.parse(j['curtainTone']);
    s.curtainShowSession = read('curtainShowSession', s.curtainShowSession);
    final started = j['sessionStartedAt'];
    s.sessionStartedAt = started is int
        ? DateTime.fromMillisecondsSinceEpoch(started)
        : null;
    s.showSummary = read('showSummary', s.showSummary);
    s.showCompanies = read('showCompanies', s.showCompanies);
    s.showToday = read('showToday', s.showToday);
    s.showCompletedInLists = read(
      'showCompletedInLists',
      s.showCompletedInLists,
    );
    s.hotkeysEnabled = read('hotkeysEnabled', s.hotkeysEnabled);
    s.toggleHotKey = HotKey.fromJson(j['toggleHotKey']) ?? s.toggleHotKey;
    s.quickAddHotKey = HotKey.fromJson(j['quickAddHotKey']) ?? s.quickAddHotKey;
    s.notificationsEnabled = read(
      'notificationsEnabled',
      s.notificationsEnabled,
    );
    s.notifyAtDue = read('notifyAtDue', s.notifyAtDue);
    s.remindBefore = read('remindBefore', s.remindBefore);
    s.dailyDigest = read('dailyDigest', s.dailyDigest);
    s.digestMinutes = read('digestMinutes', s.digestMinutes);
    s.urgentNudgeHours = read('urgentNudgeHours', s.urgentNudgeHours);
    s.autoBackup = read('autoBackup', s.autoBackup);
    s.backupKeep = read('backupKeep', s.backupKeep);
    final last = j['lastBackupAt'];
    s.lastBackupAt = last is int
        ? DateTime.fromMillisecondsSinceEpoch(last)
        : null;
    s.welcomeDismissed = read('welcomeDismissed', s.welcomeDismissed);
    s.launchAtLoginInitialized = read(
      'launchAtLoginInitialized',
      s.launchAtLoginInitialized,
    );
    return s;
  }
}
