import 'package:flutter/widgets.dart';

import 'arabic.dart';

enum AppLanguage {
  ar('ar', 'العربية'),
  en('en', 'English');

  const AppLanguage(this.code, this.nativeName);
  final String code;

  /// The language's name in itself, shown in the language picker.
  final String nativeName;

  Locale get locale => Locale(code);
  TextDirection get direction =>
      this == ar ? TextDirection.rtl : TextDirection.ltr;

  static AppLanguage parse(Object? code) =>
      values.firstWhere((l) => l.code == code, orElse: () => AppLanguage.ar);
}

/// The interface language. English text is the key; Arabic comes from
/// [arabicStrings]. Set from settings at launch and when the user switches.
class L10n {
  static AppLanguage current = AppLanguage.ar;
  static bool get isArabic => current == AppLanguage.ar;
}

/// Translates an English interface string into the current language.
///
/// `{name}` placeholders are filled from [args]. A key may carry a context
/// prefix (`'stat|Open'`) when one English word needs two Arabic renderings;
/// the prefix is never shown.
String tr(String key, [Map<String, Object?> args = const {}]) =>
    trIn(L10n.current, key, args);

String trIn(
  AppLanguage lang,
  String key, [
  Map<String, Object?> args = const {},
]) {
  var s = lang == AppLanguage.ar
      ? (arabicStrings[key] ?? _english(key))
      : _english(key);
  for (final e in args.entries) {
    s = s.replaceAll('{${e.key}}', '${e.value}');
  }
  return s;
}

String _english(String key) {
  final bar = key.indexOf('|');
  return bar < 0 ? key : key.substring(bar + 1);
}
