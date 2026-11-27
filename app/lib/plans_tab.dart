import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'task_screen.dart';

typedef _SavedPlan = ({DemoChatProfile? demo, Map<String, dynamic> task});
typedef _PlanList = ({List<_SavedPlan> plans, ApiException? error});

/// Tab 📋 แผนของฉัน (ui-states.md S7): every saved plan with its status and progress.
class PlansTab extends StatefulWidget {
  const PlansTab({super.key, required this.app});
  final AppState app;
  @override
  State<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<PlansTab> {
  List<_SavedPlan>? plans;
  ApiException? error;
  int loadVersion = 0;

  @override
  void initState() {
    super.initState();
    widget.app.changed.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.app.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++loadVersion;
    final results = await Future.wait([
      _loadFrom(null),
      for (final demo in DemoChatProfile.values) _loadFrom(demo),
    ]);
    if (!mounted || version != loadVersion) return;
    setState(() {
      plans = [for (final result in results) ...result.plans];
      error = results.map((result) => result.error).nonNulls.firstOrNull;
    });
  }

  Future<_PlanList> _loadFrom(DemoChatProfile? demo) async {
    final api = demo == null ? widget.app.api : widget.app.api.forDemo(demo.deviceSuffix);
    try {
      final r = await api.get('/v1/tasks');
      final items = (r['items'] as List).cast<Map<String, dynamic>>();
      return (plans: [for (final task in items) (demo: demo, task: task)], error: null);
    } on ApiException catch (e) {
      return (plans: const <_SavedPlan>[], error: e);
    } finally {
      if (demo != null) api.close();
    }
  }

  Future<void> _openPlan(_SavedPlan plan) async {
    final demo = plan.demo;
    final app = demo == null ? widget.app : widget.app.forDemoChat(demo);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => TaskScreen(app: app, taskId: '${plan.task['id']}')));
    } finally {
      if (demo != null) app.api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = plans ?? const [];
    // Order: active first, then blocked, snoozed, finished (same rule as the home "next step").
    const order = {'active': 0, 'blocked': 1, 'snoozed': 2, 'finished': 3};
    final sorted = [...list]..sort((a, b) => (order[a.task['status']] ?? 9).compareTo(order[b.task['status']] ?? 9));
    return Scaffold(
      appBar: AppBar(title: const Text('แผนของฉัน')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (error != null && error!.isNetwork) OfflineCard(app: widget.app, onRetry: _load),
          if (error != null && !error!.isNetwork) Text(error!.message),
          if (plans == null && error == null) const Center(child: CircularProgressIndicator()),
          if (plans != null && error == null && list.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ยังไม่มีแผน', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Text('เช็คเงินที่ควรได้ แล้วกด "บันทึกเป็นแผน" หรือบันทึกงานจากแท็บ โอกาส'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: () => widget.app.goTab(0), child: const Text('ไปเช็คเงินที่หน้าแรก')),
                ]),
              ),
            ),
          for (final plan in sorted) _planCard(plan),
          const SizedBox(height: 8),
          Text('ยืนยันจากภายนอก: ยังไม่มี สถานะทั้งหมดคุณเป็นผู้แจ้ง', style: t.bodySmall),
        ]),
      ),
    );
  }

  Widget _planCard(_SavedPlan plan) {
    final task = plan.task;
    final done = task['doneCount'] as num;
    final stepCount = (task['steps'] as List).length;
    return Card(
      child: ListTile(
        title: Text('${task['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (plan.demo case final demo?) Text(demo.planLabel),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: stepCount == 0 ? 0 : done / stepCount),
          const SizedBox(height: 4),
          Text('${taskStatusLabel[task['status']] ?? task['status']} · ทำแล้ว $done/$stepCount ขั้น · ผู้ใช้แจ้ง'),
        ]),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openPlan(plan),
      ),
    );
  }
}
