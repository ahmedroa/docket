import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../data/models.dart';
import '../controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/menus.dart';
import '../widgets/pickers.dart';
import '../widgets/task_row.dart';
import '../../l10n/l10n.dart';

/// Create a task (all fields, ⌘↵ to save) or edit one (every change saves itself).
class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({super.key, required String this.taskId, this.onClose})
    : companyId = null,
      status = null,
      initialTitle = '';

  const TaskEditorPage.create({
    super.key,
    this.companyId,
    this.status,
    this.initialTitle = '',
  }) : taskId = null,
       onClose = null;

  final String? taskId;
  final String? companyId;
  final TaskStatus? status;
  final String initialTitle;

  /// Shown as a close button when the editor is embedded (curtain side pane).
  final VoidCallback? onClose;

  bool get isNew => taskId == null;

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  late final Task _draft;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  final _update = TextEditingController();
  final _titleFocus = FocusNode();
  Timer? _saveDebounce;
  Timer? _clock;
  bool _titleError = false;
  late AppController _app;

  bool get _isNew => widget.isNew;

  Task? get _task => _isNew ? _draft : _app.store.task(widget.taskId);

  @override
  void initState() {
    super.initState();
    _app = context.app;
    final store = _app.store;
    if (_isNew) {
      _draft = store.draftTask(companyId: widget.companyId)
        ..status = widget.status ?? TaskStatus.todo;
      final parsed = widget.initialTitle.trim().isEmpty
          ? null
          : _parseInitial(widget.initialTitle);
      _title.text = parsed ?? '';
    } else {
      _draft = Task(
        id: '',
        companyId: '',
        title: '',
        sortOrder: 0,
        createdAt: DateTime(0),
        updatedAt: DateTime(0),
      );
      final t = store.task(widget.taskId);
      if (t != null) {
        _title.text = t.title;
        _description.text = t.description;
        _notes.text = t.notes;
        _app.activeTaskId = t.id;
      }
    }
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_task?.isTimerRunning ?? false) setState(() {});
    });
  }

  /// Applies quick-add syntax (! and #tags) carried over from the quick add bar.
  String _parseInitial(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    final kept = <String>[];
    for (final w in words) {
      if (w == '!' || w == '!!') {
        _draft.priority = Priority.urgent;
      } else if (w.length > 1 && w.startsWith('#')) {
        _draft.tags.add(w.substring(1));
      } else {
        kept.add(w);
      }
    }
    return kept.join(' ');
  }

  @override
  void dispose() {
    _flushText();
    _clock?.cancel();
    if (_app.activeTaskId == widget.taskId) _app.activeTaskId = null;
    _title.dispose();
    _description.dispose();
    _notes.dispose();
    _update.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  /// Applies an edit to the live task (saved) or to the draft.
  void _edit(void Function(Task t) change) {
    final t = _task;
    if (t == null) return;
    if (_isNew) {
      setState(() => change(t));
    } else {
      _app.store.updateTask(t, change);
    }
  }

  void _textChanged() {
    if (_isNew) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _flushText);
  }

  void _flushText() {
    _saveDebounce?.cancel();
    if (_isNew) return;
    final t = _app.store.task(widget.taskId);
    if (t == null) return;
    final title = _title.text.trim();
    if (t.title == title || title.isEmpty) {
      if (t.description == _description.text && t.notes == _notes.text) return;
    }
    _app.store.updateTask(t, (t) {
      if (title.isNotEmpty) t.title = title;
      t.description = _description.text;
      t.notes = _notes.text;
    });
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true);
      _titleFocus.requestFocus();
      return;
    }
    _draft
      ..title = title
      ..description = _description.text.trim()
      ..notes = _notes.text.trim();
    final subtasks = _draft.subtasks.map((s) => s.title).toList();
    _draft.subtasks = [];
    final saved = _app.store.addTask(_draft, subtasks: subtasks);
    final company = _app.store.company(saved.companyId);
    Navigator.of(context).maybePop();
    _app.toasts.show(
      tr('Added to {company}', {'company': company?.name ?? ''}),
      actionLabel: tr('Open'),
      onAction: () => _app.openTask(saved),
    );
  }

  Future<void> _menu(BuildContext anchorContext, Task t) async {
    final value = await showDocketMenu<String>(
      anchorContext,
      anchor: globalRect(anchorContext),
      width: 200,
      items: [
        MenuItemX(
          label: tr('Duplicate'),
          value: 'duplicate',
          icon: Icons.copy_rounded,
        ),
        if (t.isArchived)
          MenuItemX(
            label: tr('Unarchive'),
            value: 'unarchive',
            icon: Icons.unarchive_outlined,
          )
        else
          MenuItemX(
            label: tr('Archive'),
            value: 'archive',
            icon: Icons.archive_outlined,
          ),
        const MenuDivider(),
        MenuItemX(
          label: tr('Delete…'),
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (!mounted || value == null) return;
    _flushText();
    switch (value) {
      case 'duplicate':
        _app.duplicate(t, open: true);
      case 'archive':
        _app.archive(t, popAfter: true);
      case 'unarchive':
        _app.unarchive(t);
      case 'delete':
        await _app.deleteTask(context, t, popOnDelete: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return StoreBuilder(
      builder: (context) {
        final store = _app.store;
        final t = _task;
        if (t == null) {
          return PanelPage(
            title: tr('Task'),
            body: EmptyState(
              icon: Icons.delete_outline_rounded,
              title: tr('This task was deleted'),
            ),
          );
        }
        final company = store.company(t.companyId);
        final now = store.now;
        _app.contextCompanyId = t.companyId;

        final body = ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 20),
          children: [
            // Title
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isNew) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: StatusCircle(
                      task: t,
                      size: 19,
                      onTap: () => _app.toggleDone(t),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: DTextField(
                    controller: _title,
                    focusNode: _titleFocus,
                    autofocus: _isNew,
                    hint: _isNew ? tr('Task title') : tr('Untitled'),
                    maxLines: null,
                    style: Type.title.copyWith(fontSize: 16, height: 1.3),
                    onChanged: (_) {
                      if (_titleError) setState(() => _titleError = false);
                      _textChanged();
                    },
                  ),
                ),
              ],
            ),
            if (_titleError)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr('A title is required'),
                  style: Type.caption.copyWith(color: p.urgent),
                ),
              ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsetsDirectional.only(start: _isNew ? 0 : 29),
              child: DTextField(
                controller: _description,
                hint: tr('Add a description'),
                maxLines: null,
                style: Type.body.copyWith(color: p.textSecondary),
                onChanged: (_) => _textChanged(),
              ),
            ),
            const SizedBox(height: 16),

            // Properties
            _Prop(
              label: tr('Status'),
              child: Segmented<TaskStatus>(
                options: TaskStatus.values,
                value: t.status,
                height: 26,
                onChanged: (s) {
                  if (_isNew) {
                    _edit((t) => t.status = s);
                  } else {
                    _app.setStatus(t, s);
                  }
                },
                labels: (s, selected) => Text(
                  s.label,
                  style: Type.small.copyWith(
                    color: selected
                        ? switch (s) {
                            TaskStatus.todo => p.text,
                            TaskStatus.inProgress => p.progress,
                            TaskStatus.done => p.success,
                          }
                        : p.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            _Prop(
              label: tr('Priority'),
              child: Segmented<Priority>(
                options: Priority.values,
                value: t.priority,
                height: 26,
                onChanged: (pr) => _edit((t) => t.priority = pr),
                labels: (pr, selected) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (pr == Priority.urgent) ...[
                      Icon(
                        Icons.flag_rounded,
                        size: 12,
                        color: selected ? p.urgent : p.textTertiary,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      pr.label,
                      style: Type.small.copyWith(
                        color: selected
                            ? (pr == Priority.urgent ? p.urgent : p.text)
                            : p.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Prop(
              label: tr('Company'),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Builder(
                  builder: (context) => FieldButton(
                    label: company?.name ?? '—',
                    leading: company == null
                        ? null
                        : CompanyAvatar(company: company, size: 16),
                    trailingChevron: true,
                    onTap: () async {
                      final c = await pickCompany(
                        context,
                        anchor: globalRect(context),
                        current: t.companyId,
                      );
                      if (c == null) return;
                      if (_isNew) {
                        _edit((t) => t.companyId = c.id);
                      } else {
                        _app.moveTo(t, c);
                      }
                    },
                  ),
                ),
              ),
            ),
            _Prop(
              label: tr('Due'),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  DateField(
                    value: t.dueDate,
                    warn: t.isOverdue(now),
                    onChanged: (d) => _edit((t) {
                      t.dueDate = d;
                      if (d == null) t.dueMinutes = null;
                    }),
                  ),
                  if (t.dueDate != null)
                    TimeField(
                      minutes: t.dueMinutes,
                      onChanged: (m) => _edit((t) => t.dueMinutes = m),
                    ),
                ],
              ),
            ),
            if (t.status == TaskStatus.inProgress || t.expectedDate != null)
              _Prop(
                label: tr('Expected'),
                tooltip: tr('When you expect to finish'),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DateField(
                    value: t.expectedDate,
                    placeholder: tr('Set a target'),
                    onChanged: (d) => _edit((t) => t.expectedDate = d),
                  ),
                ),
              ),
            _Prop(
              label: tr('Repeat'),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Builder(
                  builder: (context) => FieldButton(
                    icon: Icons.repeat_rounded,
                    label: t.recurrence.label,
                    placeholder: t.recurrence == Recurrence.none,
                    trailingChevron: true,
                    onTap: () async {
                      final r = await showDocketMenu<Recurrence>(
                        context,
                        anchor: globalRect(context),
                        width: 170,
                        items: [
                          for (final r in Recurrence.values)
                            MenuItemX(
                              label: r.label,
                              value: r,
                              checked: t.recurrence == r,
                            ),
                        ],
                      );
                      if (r != null) _edit((t) => t.recurrence = r);
                    },
                  ),
                ),
              ),
            ),
            if (t.recurrence != Recurrence.none)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 86, bottom: 4),
                child: Text(
                  t.dueDate == null
                      ? tr('Completing it creates the next one.')
                      : tr('Completing it creates the next one, due {date}.', {
                          'date': formatShortDate(
                            t.recurrence.next(t.dueDate!),
                            now,
                          ),
                        }),
                  style: Type.caption.copyWith(color: p.textTertiary),
                ),
              ),
            _Prop(
              label: tr('Tags'),
              alignTop: true,
              child: _TagEditor(
                tags: t.tags,
                suggestions: store.allTags,
                onChanged: (tags) => _edit((t) => t.tags = tags),
              ),
            ),
            if (!_isNew &&
                (t.status != TaskStatus.todo || t.timeSpentSeconds > 0))
              _Prop(
                label: tr('Time'),
                child: _TimeTracker(task: t),
              ),

            // Subtasks
            const SizedBox(height: 8),
            _Subtasks(
              task: t,
              isDraft: _isNew,
              onDraftChanged: () => setState(() {}),
            ),

            // Notes
            const SizedBox(height: 14),
            _Label(tr('Notes')),
            const SizedBox(height: 6),
            DTextField(
              controller: _notes,
              filled: true,
              maxLines: null,
              minLines: 3,
              hint: tr('Anything worth remembering…'),
              padding: const EdgeInsets.all(10),
              onChanged: (_) => _textChanged(),
            ),

            // Updates
            if (!_isNew) ...[
              const SizedBox(height: 16),
              _Label(tr('Updates')),
              const SizedBox(height: 6),
              DTextField(
                controller: _update,
                filled: true,
                hint: tr('Log progress and press ↵'),
                prefix: Icon(
                  Icons.edit_note_rounded,
                  size: 16,
                  color: p.textTertiary,
                ),
                onSubmitted: (v) {
                  if (v.trim().isEmpty) return;
                  store.addUpdate(t, v);
                  _update.clear();
                },
              ),
              for (final u in t.liveUpdates) _UpdateRow(task: t, update: u),
              const SizedBox(height: 18),
              _Footer(task: t),
            ],
          ],
        );

        return PageShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
              if (_isNew) {
                _save();
              } else {
                _flushText();
                _app.toggleDone(t);
              }
            },
          },
          child: PanelPage(
            titleWidget: _isNew
                ? Text(
                    tr('New Task'),
                    style: Type.title.copyWith(color: p.text),
                  )
                : Row(
                    children: [
                      if (company != null)
                        Flexible(
                          child: CompanyChip(
                            company: company,
                            style: Type.small.copyWith(color: p.textSecondary),
                          ),
                        ),
                      if (t.isArchived) ...[
                        const SizedBox(width: 8),
                        Text(
                          tr('Archived'),
                          style: Type.captionStrong.copyWith(
                            color: p.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
            actions: [
              if (!_isNew)
                Builder(
                  builder: (context) => DIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: tr('More'),
                    onTap: () => _menu(context, t),
                  ),
                ),
              if (widget.onClose != null)
                DIconButton(
                  icon: Icons.close_rounded,
                  tooltip: tr('Close'),
                  onTap: () {
                    _flushText();
                    widget.onClose!();
                  },
                ),
            ],
            body: body,
            bottom: _isNew
                ? Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      12,
                      9,
                      12,
                      10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('! urgent  ·  #tag'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.caption.copyWith(color: p.textTertiary),
                          ),
                        ),
                        DButton(
                          label: tr('Cancel'),
                          kind: ButtonKind.ghost,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 6),
                        DButton(
                          label: tr('Add Task'),
                          hint: '⌘↵',
                          kind: ButtonKind.primary,
                          onTap: _save,
                        ),
                      ],
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Type.section.copyWith(color: context.palette.textSecondary),
  );
}

/// "Label    value" property row.
class _Prop extends StatelessWidget {
  const _Prop({
    required this.label,
    required this.child,
    this.alignTop = false,
    this.tooltip,
  });
  final String label;
  final Widget child;
  final bool alignTop;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget l = Text(label, style: Type.small.copyWith(color: p.textSecondary));
    if (tooltip != null) l = Tooltip(message: tooltip!, child: l);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: alignTop
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 86,
            child: Padding(
              padding: EdgeInsets.only(top: alignTop ? 5 : 0),
              child: l,
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({
    required this.tags,
    required this.suggestions,
    required this.onChanged,
  });
  final List<String> tags;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final tag = raw.trim().replaceAll('#', '').replaceAll(RegExp(r'\s+'), '-');
    if (tag.isEmpty || widget.tags.contains(tag)) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.tags, tag]);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = _controller.text.trim().toLowerCase();
    final suggestions = widget.suggestions
        .where(
          (s) =>
              !widget.tags.contains(s) &&
              (q.isEmpty || s.toLowerCase().contains(q)),
        )
        .take(6)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in widget.tags)
              Container(
                height: 24,
                padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#$tag',
                      textDirection: dirOf(context, tag),
                      style: Type.small.copyWith(color: p.accent),
                    ),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: () =>
                          widget.onChanged([...widget.tags]..remove(tag)),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: p.accent.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: 120,
              height: 24,
              // Backspace in an empty field removes the last tag; otherwise typing is untouched.
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace &&
                      _controller.text.isEmpty &&
                      widget.tags.isNotEmpty) {
                    widget.onChanged([...widget.tags]..removeLast());
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DTextField(
                    controller: _controller,
                    focusNode: _focus,
                    hint: widget.tags.isEmpty ? tr('Add tag') : tr('+ tag'),
                    style: Type.small,
                    onSubmitted: _add,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_focus.hasFocus && suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final s in suggestions)
                  Hoverable(
                    onTap: () => _add(s),
                    builder: (context, h, _) => Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: h ? p.pressed : p.field,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '#$s',
                        style: Type.caption.copyWith(color: p.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TimeTracker extends StatelessWidget {
  const _TimeTracker({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final store = context.store;
    final spent = task.timeSpent(store.now);
    final running = task.isTimerRunning;
    String clock(Duration d) {
      final h = d.inHours;
      final m = (d.inMinutes % 60).toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return h > 0 ? '$h:$m:$s' : '$m:$s';
    }

    return Row(
      children: [
        Text(
          running ? clock(spent) : formatDuration(spent),
          style: Type.bodyStrong.copyWith(
            color: running ? p.progress : p.text,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        DButton(
          label: running ? tr('Stop') : tr('Start timer'),
          icon: running ? Icons.pause_rounded : Icons.play_arrow_rounded,
          dense: true,
          onTap: () => running ? store.stopTimer(task) : store.startTimer(task),
        ),
        if (!running && task.timeSpentSeconds > 0) ...[
          const SizedBox(width: 4),
          DIconButton(
            icon: Icons.restart_alt_rounded,
            size: 24,
            iconSize: 15,
            tooltip: tr('Reset time'),
            onTap: () => store.resetTime(task),
          ),
        ],
      ],
    );
  }
}

class _Subtasks extends StatefulWidget {
  const _Subtasks({
    required this.task,
    required this.isDraft,
    required this.onDraftChanged,
  });
  final Task task;
  final bool isDraft;
  final VoidCallback onDraftChanged;

  @override
  State<_Subtasks> createState() => _SubtasksState();
}

class _SubtasksState extends State<_Subtasks> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String text) {
    final title = text.trim();
    if (title.isEmpty) return;
    final store = context.store;
    if (widget.isDraft) {
      final now = store.now;
      widget.task.subtasks.add(
        Subtask(
          id: newId(),
          taskId: widget.task.id,
          title: title,
          sortOrder: widget.task.subtasks.length.toDouble(),
          createdAt: now,
          updatedAt: now,
        ),
      );
      widget.onDraftChanged();
    } else {
      store.addSubtask(widget.task, title);
    }
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final store = context.store;
    final list = widget.task.liveSubtasks;
    final done = list.where((s) => s.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Label(tr('Subtasks')),
            if (list.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                '$done/${list.length}',
                style: Type.section.copyWith(color: p.textTertiary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: list.isEmpty ? 0 : done / list.length,
                    minHeight: 3,
                    backgroundColor: p.field,
                    color: done == list.length ? p.success : p.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: list.length,
          onReorderItem: (o, n) {
            if (widget.isDraft) {
              final l = widget.task.subtasks;
              l.insert(n, l.removeAt(o));
              for (var i = 0; i < l.length; i++) {
                l[i].sortOrder = i.toDouble();
              }
              widget.onDraftChanged();
            } else {
              store.reorderSubtasks(widget.task, o, n);
            }
          },
          proxyDecorator: (child, i, a) => Material(
            color: p.raised,
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: child,
          ),
          itemBuilder: (context, i) => _SubtaskRow(
            key: ValueKey(list[i].id),
            index: i,
            subtask: list[i],
            onToggle: () {
              if (widget.isDraft) {
                list[i].done = !list[i].done;
                widget.onDraftChanged();
              } else {
                store.toggleSubtask(widget.task, list[i]);
              }
            },
            onRename: (title) {
              if (widget.isDraft) {
                list[i].title = title;
                widget.onDraftChanged();
              } else {
                store.renameSubtask(widget.task, list[i], title);
              }
            },
            onDelete: () {
              if (widget.isDraft) {
                widget.task.subtasks.remove(list[i]);
                widget.onDraftChanged();
              } else {
                store.deleteSubtask(widget.task, list[i]);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.add_rounded, size: 15, color: p.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: DTextField(
                    controller: _controller,
                    focusNode: _focus,
                    hint: tr('Add subtask'),
                    style: Type.body,
                    onSubmitted: _add,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubtaskRow extends StatefulWidget {
  const _SubtaskRow({
    super.key,
    required this.index,
    required this.subtask,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

  final int index;
  final Subtask subtask;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  @override
  State<_SubtaskRow> createState() => _SubtaskRowState();
}

class _SubtaskRowState extends State<_SubtaskRow> {
  late final _controller = TextEditingController(text: widget.subtask.title);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  void _commit() {
    final v = _controller.text.trim();
    if (v.isEmpty) {
      _controller.text = widget.subtask.title;
    } else if (v != widget.subtask.title) {
      widget.onRename(v);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.subtask;
    return Hoverable(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered, _) => Container(
        decoration: BoxDecoration(
          color: hovered ? p.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: hovered
                  ? ReorderableDragStartListener(
                      index: widget.index,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 13,
                          color: p.textTertiary,
                        ),
                      ),
                    )
                  : null,
            ),
            GestureDetector(
              onTap: widget.onToggle,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: s.done ? p.success : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: s.done ? p.success : p.textTertiary,
                      width: 1.4,
                    ),
                  ),
                  child: s.done
                      ? const Icon(
                          Icons.check_rounded,
                          size: 11,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: DTextField(
                controller: _controller,
                focusNode: _focus,
                style: Type.body.copyWith(
                  color: s.done ? p.textTertiary : p.text,
                  decoration: s.done ? TextDecoration.lineThrough : null,
                  decorationColor: p.textTertiary,
                ),
                onSubmitted: (_) => _commit(),
              ),
            ),
            if (hovered)
              DIconButton(
                icon: Icons.close_rounded,
                size: 20,
                iconSize: 13,
                tooltip: tr('Remove'),
                onTap: widget.onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.task, required this.update});
  final Task task;
  final TaskUpdate update;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final store = context.store;
    return Hoverable(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered, _) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                top: 5,
                start: 4,
                end: 10,
              ),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: p.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoText(
                    update.body,
                    style: Type.body.copyWith(color: p.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatStamp(
                      update.createdAt,
                      store.now,
                      use24h: store.settings.use24h,
                    ),
                    style: Type.caption.copyWith(color: p.textTertiary),
                  ),
                ],
              ),
            ),
            if (hovered)
              DIconButton(
                icon: Icons.delete_outline_rounded,
                size: 22,
                iconSize: 14,
                tooltip: tr('Delete update'),
                onTap: () => store.deleteUpdate(task, update),
              ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final store = context.store;
    final now = store.now;
    final h24 = store.settings.use24h;
    final lines = [
      tr('Created {when}', {
        'when': formatStamp(task.createdAt, now, use24h: h24),
      }),
      if (task.startedAt != null)
        tr('Started {when}', {
          'when': formatStamp(task.startedAt!, now, use24h: h24),
        }),
      if (task.completedAt != null)
        tr('Completed {when}', {
          'when': formatStamp(task.completedAt!, now, use24h: h24),
        }),
      if (task.updatedAt.difference(task.createdAt).inSeconds > 5)
        tr('Edited {when}', {'when': formatAgo(task.updatedAt, now)}),
    ];
    return Text(
      lines.join('\n'),
      style: Type.caption.copyWith(color: p.textTertiary, height: 1.6),
    );
  }
}
