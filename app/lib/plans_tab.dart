import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'task_screen.dart';

/// Tab 📋 แผนของฉัน (ui-states.md S7): every saved plan with its status and progress.
class PlansTab extends StatefulWidget {
  const PlansTab({super.key, required this.app});
  final AppState app;
  @override
  State<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<PlansTab> {
  List<Map<String, dynamic>>? tasks;
  ApiException? error;

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
    try {
      final r = await widget.app.api.get('/v1/tasks');
      if (mounted) setState(() { tasks = (r['items'] as List).cast<Map<String, dynamic>>(); error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = tasks ?? const [];
    // Order: active first, then blocked, snoozed, finished (same rule as the home "next step").
    const order = {'active': 0, 'blocked': 1, 'snoozed': 2, 'finished': 3};
    final sorted = [...list]..sort((a, b) => (order[a['status']] ?? 9).compareTo(order[b['status']] ?? 9));
    return Scaffold(
      appBar: AppBar(title: const Text('แผนของฉัน')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (error != null && error!.isNetwork) OfflineCard(app: widget.app, onRetry: _load),
          if (error != null && !error!.isNetwork) Text(error!.message),
          if (tasks == null && error == null) const Center(child: CircularProgressIndicator()),
          if (tasks != null && list.isEmpty)
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
          for (final x in sorted)
            Card(
              child: ListTile(
                title: Text('${x['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: (x['steps'] as List).isEmpty ? 0 : (x['doneCount'] as num) / (x['steps'] as List).length),
                  const SizedBox(height: 4),
                  Text('${taskStatusLabel[x['status']] ?? x['status']} · ทำแล้ว ${x['doneCount']}/${(x['steps'] as List).length} ขั้น · ผู้ใช้แจ้ง'),
                ]),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskScreen(app: widget.app, taskId: '${x['id']}'))),
              ),
            ),
          const SizedBox(height: 8),
          Text('ยืนยันจากภายนอก: ยังไม่มี สถานะทั้งหมดคุณเป็นผู้แจ้ง', style: t.bodySmall),
        ]),
      ),
    );
  }
}
