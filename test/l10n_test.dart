import 'dart:io';

import 'package:docket/core/dates.dart';
import 'package:docket/l10n/arabic.dart';
import 'package:docket/l10n/l10n.dart';
import 'package:docket/l10n/projects.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `tr('…')` literal in lib/, found by scanning the source.
Set<String> usedKeys() {
  final keys = <String>{};
  final pattern = RegExp(
    r"""\btr(?:In\([^,]+,\s*)?\(\s*(?:'((?:\\.|[^'\\])*)'|"((?:\\.|[^"\\])*)")""",
  );
  final trIn = RegExp(
    r"""\btrIn\([^,]+,\s*(?:'((?:\\.|[^'\\])*)'|"((?:\\.|[^"\\])*)")""",
  );
  for (final f in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('l10n/arabic.dart')) {
      continue;
    }
    final src = f.readAsStringSync();
    for (final m in [...pattern.allMatches(src), ...trIn.allMatches(src)]) {
      final k = (m.group(1) ?? m.group(2))!;
      if (k.contains(r'$')) {
        continue; // dynamic keys (enum .en values) checked below
      }
      keys.add(k.replaceAll(r"\'", "'").replaceAll(r'\"', '"'));
    }
  }
  return keys;
}

Set<String> placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m[1]!).toSet();

void main() {
  test('every translated string has an Arabic version', () {
    final missing =
        usedKeys().where((k) => !arabicStrings.containsKey(k)).toList()..sort();
    expect(missing, isEmpty, reason: 'Add these to lib/l10n/arabic.dart');
  });

  test('"Projects" wording covers every string that says company', () {
    String visible(String key) =>
        key.replaceAll(RegExp(r'\{\w+\}'), '').split('|').last.toLowerCase();
    final saysCompany = {
      for (final e in arabicStrings.entries)
        if (!e.key.startsWith('term|') &&
            (visible(e.key).contains('compan') || e.value.contains('شرك')))
          e.key,
    };
    expect(
      saysCompany.difference(projectsEnglish.keys.toSet()),
      isEmpty,
      reason: 'Add to projectsEnglish in lib/l10n/projects.dart',
    );
    expect(projectsArabic.keys.toSet(), projectsEnglish.keys.toSet());
    expect(
      projectsEnglish.keys.where((k) => !arabicStrings.containsKey(k)),
      isEmpty,
      reason: 'keys must be real interface strings',
    );
    for (final map in [projectsEnglish, projectsArabic]) {
      for (final e in map.entries) {
        expect(placeholders(e.value), placeholders(e.key), reason: e.key);
        expect(e.value.toLowerCase(), isNot(contains('compan')));
        expect(e.value, isNot(contains('شرك')));
      }
    }
  });

  test('tr switches wording with L10n.projects', () {
    addTearDown(() {
      L10n.projects = false;
      L10n.current = AppLanguage.ar;
    });
    L10n.projects = true;
    L10n.current = AppLanguage.ar;
    expect(tr('Companies'), 'المشاريع');
    expect(tr('Add company'), 'إضافة مشروع');
    L10n.current = AppLanguage.en;
    expect(tr('Companies'), 'Projects');
    expect(tr('{n} companies', {'n': 3}), '3 projects');
    L10n.projects = false;
    expect(tr('Companies'), 'Companies');
  });

  test('Arabic keeps the same {placeholders}', () {
    final broken = [
      for (final e in arabicStrings.entries)
        if (placeholders(e.key).difference(placeholders(e.value)).isNotEmpty)
          e.key,
    ];
    expect(broken, isEmpty);
  });

  test('no unused Arabic strings', () {
    // Enum labels are looked up through their `.en` value rather than a literal.
    const viaEnums = {
      'To Do',
      'In Progress',
      'Completed',
      'Urgent',
      'Normal',
      'Low',
      'Never',
      'Every day',
      'Every week',
      'Every month',
      'Manual',
      'Priority',
      'Due date',
      'Date added',
      'Icon only',
      'Urgent + overdue',
      'Due today',
      'All open',
      'Small',
      'size|Normal',
      'Curtain',
      'Large',
      'All Tasks',
      'Today',
      'Overdue',
      'This Week',
      'Archived',
      'Yesterday',
      'Tomorrow',
      'Company A',
      'Company B',
      'Company C',
      'Personal',
      'New Company',
    };
    final used = usedKeys();
    final unused = arabicStrings.keys
        .where((k) => !used.contains(k) && !viaEnums.contains(k))
        .toList();
    expect(unused, isEmpty, reason: 'Remove or use these keys');
  });

  test('context prefixes never show', () {
    L10n.current = AppLanguage.en;
    expect(tr('stat|Open'), 'Open');
    L10n.current = AppLanguage.ar;
    expect(tr('stat|Open'), 'مفتوحة');
    expect(tr('Added to {company}', {'company': 'شخصي'}), 'أُضيفت إلى شخصي');
    L10n.current = AppLanguage.en;
  });

  test('Arabic dates and times', () {
    L10n.current = AppLanguage.ar;
    final now = DateTime(2026, 11, 18, 9);
    expect(formatLongDate(now), 'الأربعاء، 18 نوفمبر');
    expect(formatRelativeDay(DateTime(2026, 11, 19), now), 'غدًا');
    expect(formatTimeOfDay(14 * 60), '2:00 م');
    expect(formatTimeOfDay(9 * 60 + 5), '9:05 ص');
    expect(parseTimeInput('2 م'), 14 * 60);
    expect(parseTimeInput('٢:٣٠ م'), 14 * 60 + 30);
    expect(parseTimeInput('9 صباحا'), 9 * 60);
    expect(formatDuration(const Duration(minutes: 80)), '1 س 20 د');
    L10n.current = AppLanguage.en;
    expect(formatTimeOfDay(14 * 60), '2:00 PM');
  });
}
