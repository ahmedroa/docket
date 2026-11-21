import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Everything the store loads at launch.
class Snapshot {
  Snapshot({
    List<Company>? companies,
    List<Task>? tasks,
    List<Subtask>? subtasks,
    List<TaskUpdate>? updates,
    List<SessionItem>? sessionItems,
  }) : companies = companies ?? [],
       tasks = tasks ?? [],
       subtasks = subtasks ?? [],
       updates = updates ?? [],
       sessionItems = sessionItems ?? [];

  final List<Company> companies;
  final List<Task> tasks;
  final List<Subtask> subtasks;
  final List<TaskUpdate> updates;
  final List<SessionItem> sessionItems;
}

/// The records touched by one user action, written in a single transaction.
class ChangeSet {
  final companies = <Company>{};
  final tasks = <Task>{};
  final subtasks = <Subtask>{};
  final updates = <TaskUpdate>{};
  final sessionItems = <SessionItem>{};

  bool get isEmpty =>
      companies.isEmpty &&
      tasks.isEmpty &&
      subtasks.isEmpty &&
      updates.isEmpty &&
      sessionItems.isEmpty;

  void addAll(ChangeSet other) {
    companies.addAll(other.companies);
    tasks.addAll(other.tasks);
    subtasks.addAll(other.subtasks);
    updates.addAll(other.updates);
    sessionItems.addAll(other.sessionItems);
  }
}

abstract class Persistence {
  Future<Snapshot> loadAll();
  Future<void> write(ChangeSet changes);
  Future<void> replaceAll(Snapshot snapshot);
  Future<Map<String, dynamic>?> loadSettings();
  Future<void> saveSettings(Map<String, dynamic> settings);

  /// Physically removes tombstones older than [before].
  Future<void> purgeDeleted(DateTime before);
  Future<void> close();
}

/// SQLite on disk (WAL mode). Each [write] is one transaction, so a crash or
/// power loss leaves the database at the last completed action.
class SqlitePersistence implements Persistence {
  SqlitePersistence._(this._db);

  final Database _db;
  /// 1: companies, tasks, subtasks, updates, settings. 2: session_items.
  static const schemaVersion = 2;

  static Future<SqlitePersistence> open(String path) async {
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final statement in _schema) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) await db.execute(_sessionItemsTable);
      },
    );
    return SqlitePersistence._(db);
  }

  static const _sessionItemsTable = '''CREATE TABLE session_items (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      done INTEGER NOT NULL DEFAULT 0,
      sort_order REAL NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      done_at INTEGER,
      deleted_at INTEGER
    )''';

  static const _schema = [
    '''CREATE TABLE companies (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      color INTEGER NOT NULL,
      icon TEXT NOT NULL,
      sort_order REAL NOT NULL,
      is_personal INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )''',
    '''CREATE TABLE tasks (
      id TEXT PRIMARY KEY,
      company_id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      priority TEXT NOT NULL,
      status TEXT NOT NULL,
      due_date TEXT,
      due_minutes INTEGER,
      expected_date TEXT,
      tags TEXT NOT NULL DEFAULT '',
      sort_order REAL NOT NULL,
      recurrence TEXT NOT NULL DEFAULT 'none',
      time_spent_sec INTEGER NOT NULL DEFAULT 0,
      timer_started_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      started_at INTEGER,
      completed_at INTEGER,
      archived_at INTEGER,
      deleted_at INTEGER
    )''',
    'CREATE INDEX idx_tasks_company ON tasks(company_id)',
    '''CREATE TABLE subtasks (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      title TEXT NOT NULL,
      done INTEGER NOT NULL DEFAULT 0,
      sort_order REAL NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )''',
    'CREATE INDEX idx_subtasks_task ON subtasks(task_id)',
    '''CREATE TABLE task_updates (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )''',
    'CREATE INDEX idx_updates_task ON task_updates(task_id)',
    _sessionItemsTable,
    '''CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )''',
  ];

  @override
  Future<Snapshot> loadAll() async {
    final companies = await _db.query('companies');
    final tasks = await _db.query('tasks');
    final subtasks = await _db.query('subtasks');
    final updates = await _db.query('task_updates');
    final session = await _db.query('session_items');
    return Snapshot(
      companies: companies.map(Company.fromMap).toList(),
      tasks: tasks.map(Task.fromMap).toList(),
      subtasks: subtasks.map(Subtask.fromMap).toList(),
      updates: updates.map(TaskUpdate.fromMap).toList(),
      sessionItems: session.map(SessionItem.fromMap).toList(),
    );
  }

  @override
  Future<void> write(ChangeSet changes) async {
    if (changes.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final c in changes.companies) {
        batch.insert(
          'companies',
          c.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final t in changes.tasks) {
        batch.insert(
          'tasks',
          t.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final s in changes.subtasks) {
        batch.insert(
          'subtasks',
          s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final u in changes.updates) {
        batch.insert(
          'task_updates',
          u.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final i in changes.sessionItems) {
        batch.insert(
          'session_items',
          i.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> replaceAll(Snapshot snapshot) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete('companies');
      batch.delete('tasks');
      batch.delete('subtasks');
      batch.delete('task_updates');
      batch.delete('session_items');
      for (final c in snapshot.companies) {
        batch.insert('companies', c.toMap());
      }
      for (final t in snapshot.tasks) {
        batch.insert('tasks', t.toMap());
      }
      for (final s in snapshot.subtasks) {
        batch.insert('subtasks', s.toMap());
      }
      for (final u in snapshot.updates) {
        batch.insert('task_updates', u.toMap());
      }
      for (final i in snapshot.sessionItems) {
        batch.insert('session_items', i.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<Map<String, dynamic>?> loadSettings() async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['app'],
    );
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    await _db.insert('settings', {
      'key': 'app',
      'value': jsonEncode(settings),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> purgeDeleted(DateTime before) async {
    final ms = before.millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      for (final table in const [
        'companies',
        'tasks',
        'subtasks',
        'task_updates',
        'session_items',
      ]) {
        await txn.delete(
          table,
          where: 'deleted_at IS NOT NULL AND deleted_at < ?',
          whereArgs: [ms],
        );
      }
    });
  }

  @override
  Future<void> close() => _db.close();
}

/// In-memory implementation for tests.
class MemoryPersistence implements Persistence {
  final companies = <String, Map<String, Object?>>{};
  final tasks = <String, Map<String, Object?>>{};
  final subtasks = <String, Map<String, Object?>>{};
  final updates = <String, Map<String, Object?>>{};
  final sessionItems = <String, Map<String, Object?>>{};
  Map<String, dynamic>? settings;
  int writes = 0;

  @override
  Future<Snapshot> loadAll() async => Snapshot(
    companies: companies.values.map(Company.fromMap).toList(),
    tasks: tasks.values.map(Task.fromMap).toList(),
    subtasks: subtasks.values.map(Subtask.fromMap).toList(),
    updates: updates.values.map(TaskUpdate.fromMap).toList(),
    sessionItems: sessionItems.values.map(SessionItem.fromMap).toList(),
  );

  @override
  Future<void> write(ChangeSet changes) async {
    writes++;
    for (final i in changes.sessionItems) {
      sessionItems[i.id] = i.toMap();
    }
    for (final c in changes.companies) {
      companies[c.id] = c.toMap();
    }
    for (final t in changes.tasks) {
      tasks[t.id] = t.toMap();
    }
    for (final s in changes.subtasks) {
      subtasks[s.id] = s.toMap();
    }
    for (final u in changes.updates) {
      updates[u.id] = u.toMap();
    }
  }

  @override
  Future<void> replaceAll(Snapshot snapshot) async {
    companies
      ..clear()
      ..addEntries(snapshot.companies.map((c) => MapEntry(c.id, c.toMap())));
    tasks
      ..clear()
      ..addEntries(snapshot.tasks.map((t) => MapEntry(t.id, t.toMap())));
    subtasks
      ..clear()
      ..addEntries(snapshot.subtasks.map((s) => MapEntry(s.id, s.toMap())));
    updates
      ..clear()
      ..addEntries(snapshot.updates.map((u) => MapEntry(u.id, u.toMap())));
    sessionItems
      ..clear()
      ..addEntries(
        snapshot.sessionItems.map((i) => MapEntry(i.id, i.toMap())),
      );
  }

  @override
  Future<Map<String, dynamic>?> loadSettings() async => settings;

  @override
  Future<void> saveSettings(Map<String, dynamic> s) async =>
      settings = jsonDecode(jsonEncode(s)) as Map<String, dynamic>;

  @override
  Future<void> purgeDeleted(DateTime before) async {
    bool old(Map<String, Object?> m) {
      final d = m['deleted_at'] as int?;
      return d != null && d < before.millisecondsSinceEpoch;
    }

    companies.removeWhere((_, m) => old(m));
    tasks.removeWhere((_, m) => old(m));
    subtasks.removeWhere((_, m) => old(m));
    updates.removeWhere((_, m) => old(m));
    sessionItems.removeWhere((_, m) => old(m));
  }

  @override
  Future<void> close() async {}
}
