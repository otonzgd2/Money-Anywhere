import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'money.dart';
import 'plan_info.dart';
import 'task_screen.dart';
import 'thang_rot_theme.dart';

/// Claim route for one money item (ui-states.md S5). The route is computed from the saved answers, so the
/// first time it opens the consent sheet (P1). Declining goes back; nothing is saved.
class RouteScreen extends StatefulWidget {
  const RouteScreen({
    super.key,
    required this.app,
    required this.moneyId,
    this.facts = const {},
  });
  final AppState app;
  final String moneyId;

  /// Answers from the quick check that are not saved yet. Saved right after consent.
  final Map<String, Object?> facts;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  Map<String, dynamic>? route;
  Map<String, dynamic>? task;
  String? error;
  bool saving = false;
  Api get api => widget.app.api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    final ok = await ensureConsent(
      context,
      widget.app,
      why: 'เส้นทางรับเงินคิดจากคำตอบของคุณ จึงต้องบันทึกคำตอบไว้ก่อน คุณลบข้อมูลได้ในแท็บบัญชี',
    );
    if (!mounted) return;
    if (!ok) {
      Navigator.pop(context);
      return;
    }
    await _load(saveFacts: true);
  }

  Future<void> _load({bool saveFacts = false}) async {
    try {
      final f = Map<String, Object?>.fromEntries(
        widget.facts.entries.where((e) => e.value != null),
      );
      if (saveFacts && f.isNotEmpty) {
        await api.patch('/v1/me/facts', f);
        widget.app.bump();
      }
      final r = await api.get('/v1/money/${widget.moneyId}');
      final tasks = ((await api.get('/v1/tasks'))['items'] as List)
          .cast<Map<String, dynamic>>();
      final mine = tasks.where((t) => t['moneyId'] == widget.moneyId).toList();
      if (!mounted) return;
      setState(() {
        route = r;
        task = mine.isEmpty ? null : mine.first;
        error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _savePlan() async {
    setState(() => saving = true);
    final ok = await saveToPlan(context, widget.app, moneyId: widget.moneyId);
    if (ok) await _load();
    if (mounted) setState(() => saving = false);
  }

  void _openTask() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => TaskScreen(app: widget.app, taskId: '${task!['id']}'),
    ),
  ).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.app.demo ? 'เส้นทางรับเงิน · DEMO' : 'เส้นทางรับเงิน',
        ),
      ),
      body: SafeArea(
        child: error != null
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('ลองใหม่')),
                ],
              )
            : route == null
            ? const Center(child: CircularProgressIndicator())
            : _routeView(Theme.of(context).textTheme),
      ),
    );
  }

  Widget _routeView(TextTheme t) {
    final r = route!;
    final amount = r['amount'] as Map<String, dynamic>;
    final docs = (r['documents'] as List).cast<Map<String, dynamic>>();
    final channels = (r['channels'] as List).cast<Map<String, dynamic>>();
    final sources = (r['sources'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['title']}',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    Chip(label: Text(statusLabel[r['status']] ?? '')),
                    Chip(label: Text(dataLabel(r['dataStatus'] as String?))),
                  ],
                ),
                Text(
                  amount['value'] is num
                      ? '${baht(amount['value'] as num)} ${amount['unit'] ?? ''}'
                      : 'ยังไม่ทราบยอด',
                  style: t.headlineSmall?.copyWith(
                    color: brandDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (amount['note'] != null)
                  Text('${amount['note']}', style: t.bodySmall),
                Text('จ่ายโดย ${r['payer']}', style: t.bodySmall),
              ],
            ),
          ),
        ),
        PlanSection('เอกสารที่ต้องเตรียม', [
          if (docs.isEmpty) const Text('ยังไม่มีรายการเอกสาร'),
          ClaimChecklist(
            app: widget.app,
            moneyId: widget.moneyId,
            documents: docs,
            onUpdated: (updated) => setState(() {
              route = updated;
            }),
          ),
        ]),
        PlanSection('ไปยื่นที่ไหน', [
          if (channels.isEmpty && r['contactGuide'] == null)
            const Text('ยังไม่มีช่องทางที่ตรวจสอบได้'),
          if (r['contactGuide'] case final String guide)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: const Text('คู่มือติดต่อและยื่นเรื่อง'),
              subtitle: const Text('ดูจุดติดต่อและแหล่งอ้างอิงของรายการนี้'),
              onTap: () => openExternal(
                context,
                widget.app,
                url: '${api.baseUrl}$guide',
                title: '${r['title']}',
                askAfterReturn: false,
              ),
              trailing: const Icon(Icons.open_in_new, color: brandDark),
            ),
          for (final c in channels)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                c['kind'] == 'online'
                    ? Icons.language_outlined
                    : Icons.place_outlined,
                color: brandDark,
              ),
              title: Text('${c['title']}'),
              subtitle: Text('${c['detail'] ?? ''}'),
              onTap: c['url'] is String
                  ? () => openExternal(
                      context,
                      widget.app,
                      url: c['url'] as String,
                      title: '${r['title']}',
                      moneyId: widget.moneyId,
                      askAfterReturn: c['kind'] == 'online',
                    )
                  : null,
              trailing: c['url'] is String
                  ? const Icon(Icons.open_in_new, color: brandDark)
                  : null,
            ),
        ]),
        if (r['after'] != null || r['ifNo'] != null)
          PlanSection('หลังยื่น', [
            if (r['after'] case final String after) Text(after),
            if (r['ifNo'] case final String ifNo) Text('ถ้าไม่ผ่าน · $ifNo'),
          ]),
        const SizedBox(height: 12),
        if (task == null)
          FilledButton(
            onPressed: saving ? null : _savePlan,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('เริ่มเลย: บันทึกเป็นแผนทีละขั้น'),
          )
        else
          FilledButton.tonal(
            onPressed: _openTask,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              'อยู่ในแผนของฉันแล้ว · ทำแล้ว ${task!['doneCount']}/${(task!['steps'] as List).length} ขั้น ›',
            ),
          ),
        if (sources.isNotEmpty || r['sourceNote'] != null)
          PlanSection('แหล่งข้อมูล', [
            for (final s in sources)
              Text(
                '• ${s['title']} (ตรวจ ${s['checkedAt']})',
                style: t.bodySmall,
              ),
            const SizedBox(height: 8),
            if (r['sourceNote'] != null)
              Text('${r['sourceNote']}', style: t.bodySmall),
          ]),
        const SizedBox(height: 12),
        Text(
          'แอปไม่ยื่นแทนคุณและไม่รับประกันว่าจะได้เงิน หน่วยงานเป็นผู้ยืนยันสิทธิ์',
          style: t.bodySmall,
        ),
      ],
    );
  }
}
