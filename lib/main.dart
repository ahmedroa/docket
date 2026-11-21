import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/native.dart';
import 'data/backup.dart';
import 'data/persistence.dart';
import 'data/store.dart';
import 'harness/harness.dart';
import 'l10n/l10n.dart';
import 'services/hotkeys.dart';
import 'services/reminders.dart';
import 'ui/controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final native = Native.instance..listen();

  // DOCKET_HARNESS runs screenshot/self-test scenarios against a separate,
  // throwaway data folder — never the real database.
  final harness = Platform.environment['DOCKET_HARNESS'];
  final support =
      await native.appSupportDirectory() ??
      '${Directory.systemTemp.path}/docket';
  final dataDir = Directory(harness == null ? support : '$support/harness');
  if (harness == 'snapshot' || harness == 'selftest1') {
    if (await dataDir.exists()) await dataDir.delete(recursive: true);
  }
  await dataDir.create(recursive: true);

  final persistence = await SqlitePersistence.open(
    '${dataDir.path}/docket.sqlite',
  );
  final store = TaskStore(persistence);
  await store.load();
  L10n.current = store.settings.language;
  store.localizeDefaultNames(L10n.current);

  final app = AppController(
    store: store,
    backups: BackupService(store, Directory('${dataDir.path}/Backups')),
    reminders: ReminderService(store),
    hotkeys: HotKeyService(store),
  )..start();

  runApp(DocketApp(app: app));

  if (harness == 'activation') {
    // Proves clicks reach Flutter (the native side sends one synthetic click).
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      // ignore: avoid_print
      if (event is PointerDownEvent) print('DOCKET_DART_POINTER_DOWN ${event.position}');
    });
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final previous = dispatcher.onPointerDataPacket;
    dispatcher.onPointerDataPacket = (packet) {
      for (final d in packet.data) {
        // ignore: avoid_print
        print('DOCKET_DART_PACKET ${d.change.name} view=${d.viewId} at=${d.physicalX},${d.physicalY}');
      }
      previous?.call(packet);
    };
    Timer.periodic(const Duration(milliseconds: 700), (_) {
      for (final v in dispatcher.views) {
        // ignore: avoid_print
        print('DOCKET_DART_VIEW id=${v.viewId} size=${v.physicalSize} dpr=${v.devicePixelRatio}');
      }
    });
  }
  if (harness != null) {
    unawaited(runHarness(harness, app, dataDir));
    return;
  }

  app.reminders.start();
  unawaited(app.hotkeys.apply());
  unawaited(_startupChores(app));
}

Future<void> _startupChores(AppController app) async {
  final store = app.store;
  try {
    await app.backups.autoBackupIfDue();
    await store.purgeOldTombstones();
  } catch (e) {
    debugPrint('Startup maintenance failed: $e');
  }

  // First run of an installed build: stay in the menu bar across restarts,
  // and ask once for notification permission.
  if (!store.settings.launchAtLoginInitialized && kReleaseMode) {
    final status = await app.native.launchAtLogin();
    if (status == 'disabled') await app.native.setLaunchAtLogin(true);
    store.updateSettings((s) => s.launchAtLoginInitialized = true);
  }
  if (store.settings.notificationsEnabled &&
      await app.native.notificationStatus() == 'notDetermined') {
    await app.native.requestNotificationPermission();
  }
}
