import 'dart:convert';
import 'dart:io';

import '../core/dates.dart';
import '../l10n/l10n.dart';
import 'models.dart';
import 'persistence.dart';
import 'settings.dart';
import 'store.dart';

class BackupFile {
  BackupFile(this.file, this.createdAt, this.size);
  final File file;
  final DateTime createdAt;
  final int size;
}

class BackupFormatException implements Exception {
  BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// JSON export/import and rolling automatic backups.
class BackupService {
  BackupService(this.store, this.directory);

  final TaskStore store;

  /// `<Application Support>/Backups`
  final Directory directory;

  static const format = 1;

  String encode({bool includeSettings = true}) {
    final s = store.snapshot();
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'Docket',
      'format': format,
      'exportedAt': store.now.toUtc().toIso8601String(),
      'companies': s.companies.map((c) => c.toMap()).toList(),
      'tasks': s.tasks.map((t) => t.toMap()).toList(),
      'subtasks': s.subtasks.map((x) => x.toMap()).toList(),
      'updates': s.updates.map((u) => u.toMap()).toList(),
      'sessionItems': s.sessionItems.map((i) => i.toMap()).toList(),
      if (includeSettings) 'settings': store.settings.toJson(),
    });
  }

  static (Snapshot, Map<String, dynamic>?) decode(String json) {
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      throw BackupFormatException(tr('This file is not valid JSON.'));
    }
    if (data is! Map<String, dynamic> || data['app'] != 'Docket') {
      throw BackupFormatException(tr("This file isn't a Docket backup."));
    }
    final version = data['format'];
    if (version is! int || version > format) {
      throw BackupFormatException(
        tr('This backup was made by a newer version of Docket.'),
      );
    }
    final map = data;
    List<Map<String, Object?>> rows(String key) => [
      for (final r in (map[key] as List? ?? const []))
        if (r is Map) Map<String, Object?>.from(r),
    ];
    try {
      final snapshot = Snapshot(
        companies: rows('companies').map(Company.fromMap).toList(),
        tasks: rows('tasks').map(Task.fromMap).toList(),
        subtasks: rows('subtasks').map(Subtask.fromMap).toList(),
        updates: rows('updates').map(TaskUpdate.fromMap).toList(),
        sessionItems: rows('sessionItems').map(SessionItem.fromMap).toList(),
      );
      final settings = map['settings'];
      return (
        snapshot,
        settings is Map ? Map<String, dynamic>.from(settings) : null,
      );
    } catch (e) {
      throw BackupFormatException(
        tr('The backup is damaged ({error}).', {'error': e}),
      );
    }
  }

  /// Writes straight to [path]: the sandbox only grants access to the exact
  /// file chosen in the save panel, so no temp-file-and-rename here.
  Future<void> exportTo(String path) async {
    await store.flush();
    await File(path).writeAsString(encode(), flush: true);
  }

  /// Merges a backup into the current data (nothing is lost).
  Future<ImportResult> importFrom(String path) async {
    final (snapshot, _) = decode(await File(path).readAsString());
    await backupNow(reason: 'before-import');
    return store.merge(snapshot);
  }

  /// Replaces all data with a backup, after saving a safety copy of the current state.
  Future<void> restore(File file) async {
    final (snapshot, settings) = decode(await file.readAsString());
    await backupNow(reason: 'before-restore');
    await store.replaceAll(snapshot);
    if (settings != null) {
      final restored = AppSettings.fromJson(settings);
      store.updateSettings((s) {
        // Keep machine-specific state; bring back preferences.
        restored
          ..lastBackupAt = s.lastBackupAt
          ..launchAtLoginInitialized = s.launchAtLoginInitialized;
        s
          ..themeMode = restored.themeMode
          ..use24h = restored.use24h
          ..sortMode = restored.sortMode
          ..badgeMode = restored.badgeMode
          ..displayMode = restored.displayMode
          ..curtainTransparency = restored.curtainTransparency
          ..curtainBlur = restored.curtainBlur
          ..curtainHeight = restored.curtainHeight
          ..curtainAnimation = restored.curtainAnimation
          ..curtainTone = restored.curtainTone
          ..showSummary = restored.showSummary
          ..showCompanies = restored.showCompanies
          ..showToday = restored.showToday
          ..notificationsEnabled = restored.notificationsEnabled
          ..notifyAtDue = restored.notifyAtDue
          ..remindBefore = restored.remindBefore
          ..dailyDigest = restored.dailyDigest
          ..digestMinutes = restored.digestMinutes
          ..urgentNudgeHours = restored.urgentNudgeHours;
      });
    }
  }

  Future<File> backupNow({String reason = 'auto'}) async {
    await store.flush();
    await directory.create(recursive: true);
    final t = store.now;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${ymd(t)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final suffix = reason == 'auto' ? '' : '-$reason';
    final file = File('${directory.path}/docket-$stamp$suffix.json');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encode(), flush: true);
    await tmp.rename(file.path);
    store.updateSettings((s) => s.lastBackupAt = t);
    await prune();
    return file;
  }

  /// Runs at most once a day.
  Future<File?> autoBackupIfDue() async {
    if (!store.settings.autoBackup) return null;
    final last = store.settings.lastBackupAt;
    if (last != null &&
        store.now.difference(last) < const Duration(hours: 23)) {
      return null;
    }
    if (store.allTasks.isEmpty) return null;
    return backupNow();
  }

  Future<List<BackupFile>> list() async {
    if (!await directory.exists()) return [];
    final files = <BackupFile>[];
    await for (final e in directory.list()) {
      if (e is File && e.path.endsWith('.json')) {
        final stat = await e.stat();
        files.add(BackupFile(e, stat.modified, stat.size));
      }
    }
    files.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return files;
  }

  /// Keeps the newest [AppSettings.backupKeep] automatic backups; safety copies
  /// made before an import/restore are kept for 30 days.
  Future<void> prune() async {
    final all = await list();
    final auto = all.where((b) => !b.file.path.contains('-before-')).toList();
    final keep = store.settings.backupKeep.clamp(1, 365);
    for (final b in auto.skip(keep)) {
      await b.file.delete();
    }
    final cutoff = store.now.subtract(const Duration(days: 30));
    for (final b in all.where((b) => b.file.path.contains('-before-'))) {
      if (b.createdAt.isBefore(cutoff)) await b.file.delete();
    }
  }
}
