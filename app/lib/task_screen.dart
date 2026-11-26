import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';

const taskStatusLabel = {'active': 'กำลังทำ', 'blocked': 'ติดปัญหา', 'snoozed': 'เลื่อนไว้', 'finished': 'ครบตามที่คุณแจ้ง'};
const blockReasons = {'not_understood': 'ไม่เข้าใจขั้นตอน', 'missing_documents': 'เอกสารไม่ครบ', 'site_broken': 'เว็บใช้ไม่ได้', 'other': 'อื่นๆ'};
const snoozeOptions = {'tomorrow': 'พรุ่งนี้เช้า', 'in_3_days': 'อีก 3 วัน', 'next_week': 'สัปดาห์หน้า', 'never': 'ไม่ต้องเตือน'};
const outcomeOptions = {'received': 'ได้รับแล้ว', 'not_received': 'ยังไม่ได้รับ', 'rejected': 'ไม่ผ่าน', 'other': 'อื่นๆ'};

/// Pick a snooze time (popup P4). Returns the enum value or null.
Future<String?> pickSnooze(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('ให้เตือนอีกทีเมื่อไหร่', style: TextStyle(fontWeight: FontWeight.bold))),
          for (final e in snoozeOptions.entries) ListTile(title: Text(e.value), onTap: () => Navigator.pop(context, e.key)),
        ]),
      ),
    );

/// Send snooze and say what happened. Used by the home "ไว้ทีหลัง" button and the task screen.
Future<void> snoozeTask(BuildContext context, AppState app, String taskId) async {
  final until = await pickSnooze(context);
  if (until == null || !context.mounted) return;
  try {
    await app.api.taskEvent(taskId, {'type': 'snooze', 'until': until});
    app.bump();
    if (context.mounted) toast(context, 'ตกลง: ${snoozeOptions[until]}');
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
  }
}

/// One saved plan (ui-states.md S8). Every state change is a task event; progress is user-reported.
class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key, required this.app, required this.taskId});
  final AppState app;
  final String taskId;
  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  Map<String, dynamic>? t;
  String? error;
  bool busy = false;
  Api get api => widget.app.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await api.get('/v1/tasks/${widget.taskId}');
      setState(() { t = r; error = null; });
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _event(Map<String, Object?> e, {String? done, bool undoable = false}) async {
    setState(() => busy = true);
    try {
      final r = await api.taskEvent(widget.taskId, e);
      widget.app.bump();
      setState(() { t = r; busy = false; });
      if (!mounted || done == null) return;
      toast(context, done, onUndo: undoable ? () => _event({'type': 'undo'}, done: 'เลิกทำแล้ว') : null);
    } on ApiException catch (err) {
      setState(() => busy = false);
      if (mounted) toast(context, err.message);
    }
  }

  Future<void> _block() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('ไม่เป็นไร บอกเราหน่อยว่าติดตรงไหน', style: TextStyle(fontWeight: FontWeight.bold))),
          for (final e in blockReasons.entries) ListTile(title: Text(e.value), onTap: () => Navigator.pop(context, e.key)),
        ]),
      ),
    );
    if (reason != null) await _event({'type': 'block', 'reason': reason}, done: 'บันทึกว่าติดปัญหา: ${blockReasons[reason]}');
  }

  Future<void> _outcome() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('แจ้งผล (คุณเป็นผู้แจ้ง ไม่ใช่การยืนยันจากหน่วยงาน)', style: TextStyle(fontWeight: FontWeight.bold))),
          for (final e in outcomeOptions.entries) ListTile(title: Text(e.value), onTap: () => Navigator.pop(context, e.key)),
        ]),
      ),
    );
    if (result != null) await _event({'type': 'report_outcome', 'result': result}, done: 'บันทึกผลแล้ว (ผู้ใช้แจ้ง)');
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบแผนนี้?'),
        content: const Text('ความคืบหน้าของแผนนี้จะหายไป'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await api.delete('/v1/tasks/${widget.taskId}');
      widget.app.bump();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แผนของฉัน'), actions: [IconButton(onPressed: t == null ? null : _delete, icon: const Icon(Icons.delete_outline))]),
      body: SafeArea(
        child: error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), FilledButton(onPressed: _load, child: const Text('ลองใหม่'))]))
            : t == null
                ? const Center(child: CircularProgressIndicator())
                : _view(Theme.of(context).textTheme),
      ),
    );
  }

  Widget _view(TextTheme tt) {
    final task = t!;
    final steps = (task['steps'] as List).map((e) => '$e').toList();
    final done = (task['doneCount'] as num).toInt();
    final status = '${task['status']}';
    final outcome = task['outcome'] as Map<String, dynamic>?;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${task['title']}', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, children: [
        Chip(label: Text(taskStatusLabel[status] ?? status)),
        const Chip(label: Text('ผู้ใช้แจ้ง')),
        if (task['dueText'] != null) Chip(label: Text('${task['dueText']}')),
      ]),
      LinearProgressIndicator(value: steps.isEmpty ? 0 : done / steps.length, minHeight: 8),
      const SizedBox(height: 4),
      Text('ทำแล้ว $done จาก ${steps.length} ขั้น', style: tt.bodySmall),
      const SizedBox(height: 12),
      for (var i = 0; i < steps.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(i < done ? Icons.check_circle : (i == done ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              color: i < done ? const Color(0xFF0E9F6E) : null),
          title: Text(steps[i], style: TextStyle(fontWeight: i == done ? FontWeight.bold : FontWeight.normal)),
          subtitle: i == done && status != 'finished' ? const Text('ขั้นนี้') : null,
        ),
      if (status == 'blocked' && task['blockReason'] != null)
        Text('ติดปัญหา: ${blockReasons[task['blockReason']] ?? task['blockReason']}', style: const TextStyle(color: Color(0xFF9A3412))),
      const SizedBox(height: 12),
      if (status == 'active') ...[
        FilledButton(
          onPressed: busy ? null : () => _event({'type': 'complete_step'}, done: done + 1 >= steps.length ? '🎉 ครบทุกขั้นแล้ว (ตามที่คุณแจ้ง)' : 'บันทึกแล้ว ✓', undoable: true),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('✓ ทำขั้นนี้เสร็จแล้ว'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: busy ? null : _block, child: const Text('😟 ติดปัญหา'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: busy ? null : () => snoozeTask(context, widget.app, widget.taskId).then((_) => _load()), child: const Text('⏰ ไว้ทีหลัง'))),
        ]),
      ],
      if (status == 'blocked' || status == 'snoozed')
        FilledButton(onPressed: busy ? null : () => _event({'type': 'resume'}, done: 'กลับมาทำต่อแล้ว'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('ทำต่อ')),
      if (status == 'finished') ...[
        if (outcome != null) Text('ผลที่คุณแจ้ง: ${outcomeOptions[outcome['result']] ?? outcome['result']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        OutlinedButton(onPressed: busy ? null : _outcome, child: Text(outcome == null ? 'แจ้งผล: ได้เงินหรือยัง' : 'แก้ผลที่แจ้ง')),
      ],
      const SizedBox(height: 12),
      Text('สถานะในแผนนี้คุณเป็นผู้แจ้งเอง แอปไม่ได้ตรวจกับหน่วยงาน', style: tt.bodySmall),
    ]);
  }
}
