/// Date helpers. Due dates are stored as calendar dates (no time zone) plus an
/// optional minute-of-day, so a task due "Thursday" stays Thursday when travelling.
///
/// Every formatter speaks the current interface language unless [lang] is given.
library;

import '../l10n/l10n.dart';

const _monthsShortEn = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _monthsLongEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _monthsAr = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];
const _weekdaysShortEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysLongEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _weekdaysAr = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// Calendar column headers, Sunday first.
List<String> get weekdayInitials => L10n.isArabic
    ? const ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س']
    : const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

List<String> monthsShortIn(AppLanguage l) =>
    l == AppLanguage.ar ? _monthsAr : _monthsShortEn;
List<String> monthsLongIn(AppLanguage l) =>
    l == AppLanguage.ar ? _monthsAr : _monthsLongEn;
List<String> weekdaysShortIn(AppLanguage l) =>
    l == AppLanguage.ar ? _weekdaysAr : _weekdaysShortEn;
List<String> weekdaysLongIn(AppLanguage l) =>
    l == AppLanguage.ar ? _weekdaysAr : _weekdaysLongEn;

List<String> get monthsShort => monthsShortIn(L10n.current);
List<String> get monthsLong => monthsLongIn(L10n.current);
List<String> get weekdaysShort => weekdaysShortIn(L10n.current);
List<String> get weekdaysLong => weekdaysLongIn(L10n.current);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole days from [from] to [to], ignoring time of day and DST shifts.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? parseYmd(String? s) {
  if (s == null || s.length < 10) return null;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(5, 7));
  final d = int.tryParse(s.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Same day-of-month [months] later, clamped (31 Jan + 1 month → 28/29 Feb).
DateTime addMonths(DateTime d, int months) {
  final target = DateTime(d.year, d.month + months, 1);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(target.year, target.month, d.day > lastDay ? lastDay : d.day);
}

/// Weeks start on Sunday (Saudi work week).
DateTime startOfWeek(DateTime d) => addDays(dateOnly(d), -(d.weekday % 7));
DateTime endOfWeek(DateTime d) => addDays(startOfWeek(d), 6);

/// "2:00 PM" / "2:00 م" / "14:00"
String formatTimeOfDay(int minutes, {bool use24h = false, AppLanguage? lang}) {
  final l = lang ?? L10n.current;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final mm = m.toString().padLeft(2, '0');
  if (use24h) return '${h.toString().padLeft(2, '0')}:$mm';
  final pm = h >= 12;
  final suffix = l == AppLanguage.ar ? (pm ? 'م' : 'ص') : (pm ? 'PM' : 'AM');
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$mm $suffix';
}

String formatClock(DateTime t, {bool use24h = false}) =>
    formatTimeOfDay(t.hour * 60 + t.minute, use24h: use24h);

/// "18 Nov" / "18 نوفمبر" — adds the year only when it differs from [now].
String formatShortDate(DateTime d, DateTime now, {AppLanguage? lang}) {
  final l = lang ?? L10n.current;
  final base = '${d.day} ${monthsShortIn(l)[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// "Today", "Tomorrow", "Yesterday", a weekday within the next week, else a short date.
String formatRelativeDay(DateTime d, DateTime now, {AppLanguage? lang}) {
  final l = lang ?? L10n.current;
  final diff = daysBetween(now, d);
  if (diff == 0) return trIn(l, 'Today');
  if (diff == 1) return trIn(l, 'Tomorrow');
  if (diff == -1) return trIn(l, 'Yesterday');
  if (diff > 1 && diff < 7) return weekdaysShortIn(l)[d.weekday - 1];
  return formatShortDate(d, now, lang: l);
}

String get _comma => L10n.isArabic ? '،' : ',';

/// "Wednesday, 18 November" / "الأربعاء، 18 نوفمبر"
String formatLongDate(DateTime d) =>
    '${weekdaysLong[d.weekday - 1]}$_comma ${d.day} ${monthsLong[d.month - 1]}';

/// "18 Nov, 2:14 PM" style timestamp for logs.
String formatStamp(DateTime t, DateTime now, {bool use24h = false}) {
  final day = sameDay(t, now) ? tr('Today') : formatShortDate(t, now);
  return '$day$_comma ${formatClock(t, use24h: use24h)}';
}

/// "just now", "5m ago", "3h ago", "2d ago", else a short date.
String formatAgo(DateTime t, DateTime now) {
  final ar = L10n.isArabic;
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return ar ? 'الآن' : 'just now';
  if (diff.inHours < 1) {
    return ar ? 'قبل ${diff.inMinutes} د' : '${diff.inMinutes}m ago';
  }
  if (diff.inDays < 1) {
    return ar ? 'قبل ${diff.inHours} س' : '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return ar ? 'قبل ${diff.inDays} ي' : '${diff.inDays}d ago';
  }
  return formatShortDate(t, now);
}

/// "1h 20m" / "1 س 20 د"
String formatDuration(Duration d) {
  final (hu, mu) = L10n.isArabic ? (' س', ' د') : ('h', 'm');
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m$mu';
  return m == 0 ? '$h$hu' : '$h$hu $m$mu';
}

/// Parses "14:30", "2:30 pm", "2pm", "1430", "9", "٢:٣٠ م", "2 مساء" into minutes since midnight.
int? parseTimeInput(String input) {
  var s = input.trim().toLowerCase();
  // Arabic-Indic digits → ASCII.
  s = s.replaceAllMapped(
    RegExp('[٠-٩]'),
    (m) => '${m[0]!.codeUnitAt(0) - 0x0660}',
  );
  s = s.replaceAll('٫', ':').replaceAll('٬', ':');
  int? offset;
  if (RegExp(r'(مساء|مساءً|م)$').hasMatch(s)) {
    offset = 12;
    s = s.replaceAll(RegExp(r'(مساءً|مساء|م)$'), '');
  } else if (RegExp(r'(صباحا|صباحًا|صباح|ص)$').hasMatch(s)) {
    offset = 0;
    s = s.replaceAll(RegExp(r'(صباحًا|صباحا|صباح|ص)$'), '');
  }
  s = s.replaceAll(' ', '').replaceAll('.', '');
  if (s.isEmpty) return null;
  if (offset == null) {
    if (s.endsWith('am') || s.endsWith('a')) {
      offset = 0;
      s = s.replaceAll(RegExp(r'a(m)?$'), '');
    } else if (s.endsWith('pm') || s.endsWith('p')) {
      offset = 12;
      s = s.replaceAll(RegExp(r'p(m)?$'), '');
    }
  }
  int h;
  int m = 0;
  if (s.contains(':')) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    h = int.tryParse(parts[0]) ?? -1;
    m = int.tryParse(parts[1]) ?? -1;
  } else if (s.length >= 3 && s.length <= 4) {
    final n = int.tryParse(s);
    if (n == null) return null;
    h = n ~/ 100;
    m = n % 100;
  } else {
    h = int.tryParse(s) ?? -1;
  }
  if (h < 0 || m < 0 || m > 59) return null;
  if (offset != null) {
    if (h < 1 || h > 12) return null;
    h = h % 12 + offset;
  }
  if (h > 23) return null;
  return h * 60 + m;
}
