import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat.dart';
import 'common.dart';
import 'income_plan_screen.dart';
import 'money.dart';
import 'money_check.dart';
import 'route_screen.dart';
import 'task_screen.dart';
import 'thaid.dart';

/// Which saved plan the home "ขั้นต่อไป" card shows: active first, then snoozed, then blocked.
/// Finished plans never show. Returns null when nothing is unfinished (ui-states.md §3).
Map<String, dynamic>? nextTask(List<Map<String, dynamic>> tasks) {
  for (final s in const ['active', 'snoozed', 'blocked']) {
    for (final t in tasks) {
      if (t['status'] == s) return t;
    }
  }
  return null;
}

/// Tab 🏠 หน้าแรก (ui-states.md S1/S2). New person: AI button first, then the manual check and the two
/// small lane cards. Once anything is saved (consent, an answer, a plan) or a chat started: money summary,
/// next step, then "คุยกับ AI ต่อ", and the manual check only while questions are still open.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.app});
  final AppState app;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, Object?> facts = {};
  Map<String, dynamic>? overview;
  List<Map<String, dynamic>> tasks = [];
  bool consented = false, loaded = false;
  GovState gov = GovState.disabled;
  ApiException? error;

  AppState get app => widget.app;
  Api get api => app.api;

  @override
  void initState() {
    super.initState();
    app.changed.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    app.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final f = (await api.get('/v1/me/facts')).cast<String, Object?>();
      final cur = await api.currentPurposes();
      final ok = cur?['core'] == true;
      final m = f.isNotEmpty ? await api.get('/v1/money') : null;
      final t = ok ? ((await api.get('/v1/tasks'))['items'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      final g = await govState(api);
      // Connected ThaID: show the money overview even before any answer (the agency data fills it).
      final m2 = m ?? (g == GovState.connected ? await api.get('/v1/money') : null);
      if (!mounted) return;
      setState(() { facts = f; overview = m2; tasks = t; consented = ok; gov = g; error = null; loaded = true; });
    } on ApiException catch (e) {
      if (mounted) setState(() { error = e; loaded = true; });
    }
  }

  /// Full-screen flows (quick check, chat, route, task) hide the tab bar; data is reloaded when they close.
  Future<void> _open(Widget screen) async {
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => screen));
    app.bump();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = ((overview?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final found = rankMoney(items).where((i) => tierOf(i) <= 3).toList();
    final openQuestions = items.where((i) => i['status'] == 'need').length;
    // Returning layout only when there is something to show: an answer, a plan, or a real chat.
    // Consent alone (pressing the AI button and leaving) keeps the new-person layout.
    final started = facts.isNotEmpty || tasks.isNotEmpty || app.chat.talked || gov == GovState.connected;
    final talked = app.chat.talked;
    final next = nextTask(tasks);
    final others = tasks.where((x) => x['status'] != 'finished' && x != next).length;
    final planned = tasks.map((x) => x['moneyId']).whereType<String>().toSet();
    final firstThing = found.where((i) => !planned.contains(i['id'])).toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              const Align(alignment: Alignment.centerRight, child: DemoPill()),
              const SizedBox(height: 8),
              if (error != null && error!.isNetwork) OfflineCard(app: app, onRetry: _load),
              if (!loaded) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (loaded) ThaidCard(app: app, state: gov),
              if (loaded && !started) ...[
                const Text('💸', textAlign: TextAlign.center, style: TextStyle(fontSize: 44)),
                Text('เงินฉันอยู่ไหน?', textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('ตอบไม่กี่ข้อ รู้เลยว่ามีเงินก้อนไหนที่ควรได้ ได้เท่าไหร่ และต้องไปเอาที่ไหน', textAlign: TextAlign.center, style: t.bodyMedium),
                const SizedBox(height: 18),
              ],
              if (loaded && started) ...[
                Text('เงินของฉัน', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (overview != null) _Summary(overview: overview),
                // 1) unfinished plan → its next step; 2) otherwise the first money item not yet planned; 3) all done.
                if (next != null)
                  _NextStepCard(
                    task: next,
                    onOpen: () => _open(TaskScreen(app: app, taskId: '${next['id']}')),
                    onLater: () => snoozeTask(context, app, '${next['id']}'),
                  )
                else if (firstThing.isNotEmpty)
                  _FirstThingCard(item: firstThing.first, onOpen: () => _open(RouteScreen(app: app, moneyId: '${firstThing.first['id']}')))
                else if (tasks.isNotEmpty)
                  const Card(child: ListTile(title: Text('🎉 ไม่มีงานค้าง'), subtitle: Text('ทำครบทุกแผนแล้ว (ตามที่คุณแจ้ง)'))),
                if (others > 0)
                  ListTile(
                    title: Text('งานอื่นที่ทำอยู่ $others รายการ'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => app.goTab(2),
                  ),
                const SizedBox(height: 10),
              ],
              if (loaded)
                _AiHero(
                  title: talked ? 'คุยกับ AI ต่อ' : 'ให้ AI หาเงินให้ฉัน',
                  subtitle: talked
                      ? 'คุยต่อจากเดิม ถามได้ เช่น ต้องทำอะไรต่อ ขอลิงก์ติดต่อ เอกสารที่ยังขาด'
                      : 'กดครั้งเดียว AI ถามทีละข้อ แล้วพาไปจนรู้ว่าต้องไปรับเงินที่ไหน เอาอะไรไป',
                  button: talked ? 'คุยต่อ ›' : 'เริ่มคุยเลย ›',
                  showConsent: !talked,
                  onTap: () => _open(ChatScreen(api: api, session: app.chat)),
                  onNotice: () => showNotice(context, app),
                ),
              if (loaded) ...[
                const SizedBox(height: 12),
                Card(
                  color: const Color(0xFFEFF6FF),
                  child: ListTile(
                    minVerticalPadding: 12,
                    leading: const Text('📈', style: TextStyle(fontSize: 30)),
                    title: const Text('แผนรายได้: อยากได้เดือนละเท่าไหร่', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('บอกเป้า แล้วดูว่าเงินจากรัฐ งาน และทักษะของคุณ รวมได้เท่าไหร่ ยังขาดเท่าไหร่'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(IncomePlanScreen(app: app)),
                  ),
                ),
              ],
              // Manual check is always reachable: full check with no answers, "ตอบเพิ่ม" while questions are open,
              // "แก้คำตอบของฉัน" once everything is answered.
              if (loaded && facts.isNotEmpty && openQuestions == 0)
                ListTile(
                  leading: const Text('✏️', style: TextStyle(fontSize: 22)),
                  title: const Text('แก้คำตอบของฉันเอง (ไม่ใช้ AI)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(QuickCheckScreen(app: app, consented: consented, askAll: true)),
                ),
              if (loaded && (facts.isEmpty || openQuestions > 0)) ...[
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    minVerticalPadding: 14,
                    leading: const Text('💰', style: TextStyle(fontSize: 30)),
                    title: Text(facts.isNotEmpty ? 'ตอบเพิ่มอีก $openQuestions เรื่อง อาจเจอเงินก้อนอื่น' : 'เช็คเงินที่ควรได้ เอง',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(facts.isNotEmpty
                        ? 'ไม่ใช้ AI · ถามเฉพาะข้อที่ยังไม่ได้ตอบ'
                        : 'ไม่ใช้ AI · เบี้ยผู้สูงอายุ เงินว่างงาน เงินเลี้ยงดูเด็ก เบี้ยความพิการ คืนภาษี ค่าจ้างค้าง'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(QuickCheckScreen(app: app, knownFacts: facts, consented: consented)),
                  ),
                ),
              ],
              if (loaded && !started) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _SmallCard(icon: '🔎', text: 'หางาน', onTap: () => app.goTab(1, group: 'job'))),
                  const SizedBox(width: 8),
                  Expanded(child: _SmallCard(icon: '🍳', text: 'รายได้จากทักษะ', onTap: () => app.goTab(1, group: 'skill'))),
                ]),
              ],
              if (loaded && started)
                ListTile(title: const Text('✨ ดูงานและรายได้จากทักษะ'), trailing: const Icon(Icons.chevron_right), onTap: () => app.goTab(1, group: 'all')),
              const SizedBox(height: 16),
              Text('แอปไม่รับประกันว่าจะได้เงินหรือได้งาน ผลเป็นการตรวจเบื้องต้นจากเกณฑ์ที่ประกาศ ต้องยืนยันกับหน่วยงานทางการ',
                  textAlign: TextAlign.center, style: t.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.overview});
  final Map<String, dynamic>? overview;

  @override
  Widget build(BuildContext context) {
    final s = (overview?['summary'] as Map?) ?? const {};
    final monthly = s['monthly'] is num ? s['monthly'] as num : 0;
    final once = s['once'] is num ? s['once'] as num : 0;
    final pending = s['pending'] is num ? s['pending'] as num : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (monthly > 0 || once > 0) ...[
            const Text('💰 เงินที่น่าจะได้ (จากคำตอบของคุณ)'),
            if (monthly > 0) Text('${baht(monthly)} ต่อเดือน', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            if (once > 0) Text('${baht(once)} ครั้งเดียว', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(s['allVerified'] == true ? 'ยืนยันจากหน่วยงาน' : 'ประมาณจากเกณฑ์ที่ประกาศ ยังไม่ยืนยันกับหน่วยงาน', style: Theme.of(context).textTheme.bodySmall),
          ] else
            const Text('ยังไม่พบเงินที่นับยอดได้', style: TextStyle(fontWeight: FontWeight.bold)),
          if (pending > 0) Text('อีก $pending รายการต้องเช็คหรือตอบเพิ่ม', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _FirstThingCard extends StatelessWidget {
  const _FirstThingCard({required this.item, required this.onOpen});
  final Map<String, dynamic> item;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final a = item['amount'] as Map<String, dynamic>;
    return Card(
      shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFF0E9F6E), width: 2), borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('สิ่งแรกที่ควรทำ'),
          Text('${item['icon'] ?? ''} ${item['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(a['value'] is num ? '${baht(a['value'] as num)} ${a['unit'] ?? ''}' : 'ยังไม่ทราบยอด'),
          Text('${statusLabel[item['status']] ?? item['status']} · ${dataLabel(item['dataStatus'] as String?)}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          FilledButton(onPressed: onOpen, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('ดูวิธีไปรับเงิน: ที่ไหน เอาอะไรไป')),
        ]),
      ),
    );
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.task, required this.onOpen, required this.onLater});
  final Map<String, dynamic> task;
  final VoidCallback onOpen, onLater;
  @override
  Widget build(BuildContext context) {
    final steps = (task['steps'] as List).map((e) => '$e').toList();
    final done = (task['doneCount'] as num).toInt();
    final status = '${task['status']}';
    return Card(
      color: const Color(0xFFECFDF5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ขั้นต่อไปของคุณ'),
          Text('${task['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (done < steps.length) Text('ขั้นที่ ${done + 1} จาก ${steps.length}: ${steps[done]}'),
          if (status != 'active') Text(taskStatusLabel[status] ?? status, style: const TextStyle(color: Color(0xFF9A3412))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: FilledButton(onPressed: onOpen, child: const Text('ทำต่อ'))),
            if (status == 'active') ...[
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: onLater, child: const Text('ไว้ทีหลัง'))),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _SmallCard extends StatelessWidget {
  const _SmallCard({required this.icon, required this.text, required this.onTap});
  final String icon, text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [Text(icon, style: const TextStyle(fontSize: 26)), Text(text, style: const TextStyle(fontWeight: FontWeight.bold))]),
          ),
        ),
      );
}

class _AiHero extends StatelessWidget {
  const _AiHero({required this.onTap, required this.onNotice, required this.title, required this.subtitle, required this.button, required this.showConsent});
  final VoidCallback onTap, onNotice;
  final String title, subtitle, button;
  final bool showConsent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF065F46), Color(0xFF0E9F6E), Color(0xFF34D399)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: const [BoxShadow(color: Color(0x59065F46), blurRadius: 26, offset: Offset(0, 10))],
          ),
          child: Column(children: [
            const Text('🤖', style: TextStyle(fontSize: 46)),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
              child: Text(button, style: const TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w800, fontSize: 17)),
            ),
            if (showConsent) ...[
              const SizedBox(height: 10),
              const Text('กด = ยืนยันว่าอายุ 20 ปีขึ้นไป และยินยอมให้ส่งคำตอบ (ไม่มีชื่อ ไม่มีเลขบัตร) ให้ AI ช่วยวิเคราะห์ ถอนได้ทุกเมื่อที่แท็บ ฉัน',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 11)),
              TextButton(onPressed: onNotice, child: const Text('อ่านประกาศ', style: TextStyle(color: Colors.white, decoration: TextDecoration.underline))),
            ],
          ]),
        ),
      ),
    );
  }
}
