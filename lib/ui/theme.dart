import 'package:flutter/material.dart';

/// Design tokens. Calm neutrals, one accent, and a single red reserved for
/// "Urgent" so it stays meaningful everywhere it appears.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.hover,
    required this.pressed,
    required this.selected,
    required this.border,
    required this.divider,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.urgent,
    required this.urgentSoft,
    required this.warning,
    required this.warningSoft,
    required this.success,
    required this.progress,
    required this.field,
    required this.shadow,
    required this.isDark,
    this.solidBg,
  });

  final Color bg;
  final Color surface;
  final Color raised;
  final Color hover;
  final Color pressed;
  final Color selected;
  final Color border;
  final Color divider;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final Color urgent;
  final Color urgentSoft;
  final Color warning;
  final Color warningSoft;
  final Color success;
  final Color progress;
  final Color field;
  final Color shadow;
  final bool isDark;
  final Color? solidBg;

  static const light = Palette(
    bg: Color(0xFFF7F7F5),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    hover: Color(0x0A1C1C1E),
    pressed: Color(0x141C1C1E),
    selected: Color(0x1A3D63DD),
    border: Color(0x171C1C1E),
    divider: Color(0x0F1C1C1E),
    text: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF6B6B70),
    textTertiary: Color(0xFFA3A3A8),
    accent: Color(0xFF3D63DD),
    accentSoft: Color(0x143D63DD),
    onAccent: Color(0xFFFFFFFF),
    urgent: Color(0xFFDC3E42),
    urgentSoft: Color(0x14DC3E42),
    warning: Color(0xFFC2620A),
    warningSoft: Color(0x16E5850B),
    success: Color(0xFF2B9A66),
    progress: Color(0xFFD9822B),
    field: Color(0x0D1C1C1E),
    shadow: Color(0x1F000000),
    isDark: false,
  );

  static const dark = Palette(
    bg: Color(0xFF1C1C1E),
    surface: Color(0xFF242426),
    raised: Color(0xFF2C2C2E),
    hover: Color(0x0FFFFFFF),
    pressed: Color(0x1AFFFFFF),
    selected: Color(0x2E7093FF),
    border: Color(0x1AFFFFFF),
    divider: Color(0x10FFFFFF),
    text: Color(0xFFF2F2F4),
    textSecondary: Color(0xFFA0A0A6),
    textTertiary: Color(0xFF6C6C72),
    accent: Color(0xFF7093FF),
    accentSoft: Color(0x247093FF),
    onAccent: Color(0xFF0E1630),
    urgent: Color(0xFFFF6369),
    urgentSoft: Color(0x24FF6369),
    warning: Color(0xFFF1A10D),
    warningSoft: Color(0x22F1A10D),
    success: Color(0xFF3DD68C),
    progress: Color(0xFFF1A10D),
    field: Color(0x12FFFFFF),
    shadow: Color(0x66000000),
    isDark: true,
  );

  @override
  Palette copyWith() => this;

  /// Variant for the glass curtain: no page background (the native blur and a
  /// tint show through), translucent surfaces, solid menus and dialogs.
  Palette glass() => Palette(
    bg: const Color(0x00000000),
    surface: isDark ? const Color(0x47000000) : const Color(0x8CFFFFFF),
    raised: raised,
    hover: hover,
    pressed: pressed,
    selected: selected,
    border: isDark ? const Color(0x1FFFFFFF) : const Color(0x1A000000),
    divider: isDark ? const Color(0x17FFFFFF) : const Color(0x14000000),
    text: text,
    textSecondary: isDark ? const Color(0xFFB4B4BA) : const Color(0xFF55555B),
    textTertiary: isDark ? const Color(0xFF85858C) : const Color(0xFF85858B),
    accent: accent,
    accentSoft: accentSoft,
    onAccent: onAccent,
    urgent: urgent,
    urgentSoft: urgentSoft,
    warning: warning,
    warningSoft: warningSoft,
    success: success,
    progress: progress,
    field: isDark ? const Color(0x1AFFFFFF) : const Color(0x12000000),
    shadow: shadow,
    isDark: isDark,
    solidBg: bg,
  );

  /// Opaque page colour, also for sheets shown over the glass.
  Color get solid => solidBg ?? bg;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    return t < 0.5 ? this : other;
  }
}

/// Type scale tuned for a 400pt-wide panel (macOS body text is 13pt).
class Type {
  static const title = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  static const largeTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
  static const bodyStrong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );
  static const small = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
  static const caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.25,
  );
  static const captionStrong = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );
  static const section = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const number = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

ThemeData buildTheme(Palette p) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.isDark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      primary: p.accent,
      error: p.urgent,
      surface: p.surface,
    ),
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: p.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: p.hover,
    focusColor: p.accentSoft,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    extensions: [p],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: 0.28),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: Type.caption.copyWith(color: p.isDark ? p.text : Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF3A3A3C) : const Color(0xE61C1C1E),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: p.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: p.border),
      ),
      textStyle: Type.body.copyWith(color: p.text),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.all(
        p.textTertiary.withValues(alpha: 0.5),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
  );
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

/// Icons offered for companies. Stored by key so data never depends on code points.
const companyIcons = <String, IconData>{
  'apartment': Icons.apartment_rounded,
  'storefront': Icons.storefront_rounded,
  'rocket': Icons.rocket_launch_rounded,
  'person': Icons.person_rounded,
  'work': Icons.work_rounded,
  'code': Icons.code_rounded,
  'design': Icons.palette_rounded,
  'campaign': Icons.campaign_rounded,
  'school': Icons.school_rounded,
  'health': Icons.favorite_rounded,
  'home': Icons.home_rounded,
  'star': Icons.star_rounded,
  'bolt': Icons.bolt_rounded,
  'coffee': Icons.local_cafe_rounded,
  'flight': Icons.flight_rounded,
  'money': Icons.savings_rounded,
  'build': Icons.build_rounded,
  'chart': Icons.insights_rounded,
  'camera': Icons.photo_camera_rounded,
  'globe': Icons.public_rounded,
};

IconData companyIcon(String key) => companyIcons[key] ?? Icons.work_rounded;

/// Direction of the first strong character, or null for digits/symbols only.
/// Arabic task titles read right-to-left inside the English interface and
/// English ones left-to-right inside the Arabic interface.
TextDirection? strongDirection(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x0590 && rune <= 0x08FF) ||
        (rune >= 0xFB1D && rune <= 0xFEFC)) {
      return TextDirection.rtl;
    }
    if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        rune >= 0x00C0) {
      return TextDirection.ltr;
    }
  }
  return null;
}

/// Reading direction for a short label: its own script, else the interface's.
TextDirection dirOf(BuildContext context, String text) =>
    strongDirection(text) ?? Directionality.of(context);

TextDirection textDirectionFor(
  String text, {
  TextDirection fallback = TextDirection.ltr,
}) => strongDirection(text) ?? fallback;
