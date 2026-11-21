import 'dart:ui' show AppExitResponse, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/queries.dart';
import 'data/settings.dart';
import 'l10n/l10n.dart';
import 'ui/controller.dart';
import 'ui/pages/curtain_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme.dart';
import 'ui/widgets/toast.dart';

class DocketApp extends StatefulWidget {
  const DocketApp({super.key, required this.app});
  final AppController app;

  /// Root boundary, used by the screenshot harness.
  static final captureKey = GlobalKey();

  @override
  State<DocketApp> createState() => _DocketAppState();
}

class _DocketAppState extends State<DocketApp> {
  late final RouteTracker _tracker = RouteTracker(widget.app);
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Quit from anywhere (⌘Q, logout, shutdown): finish pending writes first.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.app.store.flush();
        await widget.app.store.flushSettings();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  String? _builtWording;

  /// Strings come from [tr], which widgets don't subscribe to, so a language
  /// switch rebuilds every element once (state and navigation are kept).
  void _rebuildEverything() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return AppScope(
      app: app,
      child: ListenableBuilder(
        listenable: app.store,
        builder: (context, _) {
          // Language or companies/projects wording changed: rebuild once.
          final s = app.store.settings;
          final wording = '${s.language.code}/${s.useProjects}';
          if (_builtWording != null && _builtWording != wording) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _rebuildEverything(),
            );
          }
          _builtWording = wording;
          return MaterialApp(
            title: 'Docket',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(
              app.isCurtain ? Palette.light.glass() : Palette.light,
            ),
            darkTheme: buildTheme(
              app.isCurtain ? Palette.dark.glass() : Palette.dark,
            ),
            themeMode: _themeMode(app.store.settings),
            locale: app.store.settings.language.locale,
            supportedLocales: [for (final l in AppLanguage.values) l.locale],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            themeAnimationDuration: const Duration(milliseconds: 150),
            navigatorKey: app.navigatorKey,
            navigatorObservers: [_tracker],
            home: const _RootPage(),
            builder: (context, child) => RepaintBoundary(
              key: DocketApp.captureKey,
              child: _PanelFrame(tracker: _tracker, child: child!),
            ),
          );
        },
      ),
    );
  }
}

/// In the curtain the glass tone (light/dark) decides the text colours.
ThemeMode _themeMode(AppSettings s) {
  if (!s.displayMode.isCurtain) return s.themeMode;
  return switch (s.curtainTone) {
    GlassTone.light => ThemeMode.light,
    GlassTone.dark => ThemeMode.dark,
    GlassTone.auto => s.themeMode,
  };
}

/// The drop-down home or the curtain, following the display mode.
class _RootPage extends StatelessWidget {
  const _RootPage();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: app.store,
      builder: (context, _) =>
          app.isCurtain ? const CurtainHome() : const HomePage(),
    );
  }
}

/// Lets screenshots show the glass over something, since the real desktop
/// behind the window isn't part of the Flutter picture.
class CurtainBackdrop {
  static bool debugPaint = false;
}

/// Background, hairline border, app-wide shortcuts and the toast layer.
class _PanelFrame extends StatelessWidget {
  const _PanelFrame({required this.child, required this.tracker});
  final Widget child;
  final RouteTracker tracker;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = AppScope.of(context);

    void escape() {
      // Close an open menu/dialog (or a sheet over the curtain) first;
      // otherwise close the panel.
      final nav = app.navigatorKey.currentState;
      if (tracker.topIsPopup || (app.isCurtain && (nav?.canPop() ?? false))) {
        nav?.maybePop();
      } else {
        app.hidePanel();
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): escape,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            app.newTask(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            app.openSearch,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            app.completeActive,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
            app.completeActive,
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
            app.openList(ListKind.all),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
            app.openList(ListKind.today),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () =>
            app.openList(ListKind.overdue),
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true):
            app.goHome,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            app.openSettings,
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            app.back,
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
            app.hidePanel,
        const SingleActivator(LogicalKeyboardKey.keyQ, meta: true): app.quit,
      },
      child: Focus(
        autofocus: true,
        child: app.isCurtain
            ? _CurtainFrame(
                toasts: ToastHost(controller: app.toasts),
                child: child,
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: p.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                position: DecorationPosition.background,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.isDark
                          ? const Color(0x24FFFFFF)
                          : const Color(0x1F000000),
                      width: 0.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(child: child),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 64,
                        child: Center(child: ToastHost(controller: app.toasts)),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// The curtain's own surface: a tint over the native blur (its strength is
/// the Transparency setting) and a handle at the bottom edge that closes it.
class _CurtainFrame extends StatelessWidget {
  const _CurtainFrame({required this.child, required this.toasts});
  final Widget child;
  final Widget toasts;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = context.app;
    final t = app.store.settings.curtainTransparency;
    // 0 → nearly solid, 1 → nearly clear.
    final alpha = (0.9 - 0.82 * t).clamp(0.05, 0.95);
    final tint = (p.isDark ? const Color(0xFF16161A) : const Color(0xFFF4F4F2))
        .withValues(alpha: alpha);
    return Stack(
      children: [
        if (CurtainBackdrop.debugPaint)
          const Positioned.fill(child: _DebugDesktop()),
        Positioned.fill(child: ColoredBox(color: tint)),
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          right: 0,
          bottom: 9,
          child: Center(
            // Above the navigator there is no Overlay, so no tooltip here.
            child: Semantics(
              label: tr('Close  esc'),
              button: true,
              child: GestureDetector(
                onTap: app.hidePanel,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 56,
                    height: 5,
                    decoration: BoxDecoration(
                      color: p.textTertiary.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 40,
          child: Center(child: toasts),
        ),
      ],
    );
  }
}

/// Stand-in for windows behind the curtain in harness screenshots (blurred like the real glass).
class _DebugDesktop extends StatelessWidget {
  const _DebugDesktop();

  @override
  Widget build(BuildContext context) {
    final blur = context.app.store.settings.curtainBlur * 30;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2B5876), Color(0xFF4E4376), Color(0xFFB06AB3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            for (final (l, t, w, h, c) in const [
              (0.05, 0.08, 0.38, 0.55, Color(0xFFFFFFFF)),
              (0.48, 0.15, 0.30, 0.70, Color(0xFF1E1E1E)),
              (0.70, 0.05, 0.25, 0.30, Color(0xFFF2C14E)),
              (0.20, 0.70, 0.35, 0.25, Color(0xFF3FA7D6)),
            ])
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment(l * 2 - 1 + w, t * 2 - 1 + h),
                  widthFactor: w,
                  heightFactor: h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
