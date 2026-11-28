import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat.dart';
import 'chat_composer.dart';
import 'common.dart';
import 'income_plan_screen.dart';
import 'money.dart';
import 'money_check.dart';
import 'opportunity_assessment.dart';
import 'opportunity_catalog.dart';
import 'opp_screen.dart';
import 'route_screen.dart';
import 'task_screen.dart';
import 'thaid.dart';
import 'thang_rot_theme.dart';

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
  const HomeTab({super.key, required this.app, this.assessment});
  final AppState app;
  final OpportunityAssessment? assessment;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, Object?> facts = {};
  Map<String, dynamic>? overview;
  List<Map<String, dynamic>> tasks = [];
  bool consented = false, loaded = false;
  bool hasDemoProfile = false, personalChat = false, openingDemo = false;
  bool submittingChat = false;
  final personalChatDraft = TextEditingController();
  final demoChatDraft = TextEditingController();
  GovState gov = GovState.disabled;
  ApiException? error;
  int loadRevision = 0;

  AppState get app => widget.app;
  Api get api => app.api;
  bool get usesDemoChat => hasDemoProfile && !personalChat;
  TextEditingController get chatDraft =>
      usesDemoChat ? demoChatDraft : personalChatDraft;

  @override
  void initState() {
    super.initState();
    app.changed.addListener(_load);
    app.dataCleared.addListener(_clearChatDrafts);
    _load();
  }

  @override
  void dispose() {
    app.changed.removeListener(_load);
    app.dataCleared.removeListener(_clearChatDrafts);
    personalChatDraft.dispose();
    demoChatDraft.dispose();
    super.dispose();
  }

  void _clearChatDrafts() {
    personalChatDraft.clear();
    demoChatDraft.clear();
  }

  Future<void> _load() async {
    final revision = ++loadRevision;
    try {
      final f = (await api.get('/v1/me/facts')).cast<String, Object?>();
      final cur = await api.currentPurposes();
      final ok = cur?['core'] == true;
      final m = f.isNotEmpty ? await api.get('/v1/money') : null;
      final t = ok
          ? ((await api.get('/v1/tasks'))['items'] as List)
                .cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final g = await govState(api);
      final choices = api.onboardingChoices;
      final canOpenDemo =
          f.isEmpty &&
          g != GovState.connected &&
          (choices.isEmpty || choices.contains('y')) &&
          await _hasDemoEntry();
      // Connected ThaID: show the money overview even before any answer (the agency data fills it).
      final m2 =
          m ?? (g == GovState.connected ? await api.get('/v1/money') : null);
      if (!mounted || revision != loadRevision) return;
      setState(() {
        facts = f;
        overview = m2;
        tasks = t;
        consented = ok;
        gov = g;
        hasDemoProfile = canOpenDemo;
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted && revision == loadRevision) {
        setState(() {
          error = e;
          loaded = true;
        });
      }
    }
  }

  Future<bool> _hasDemoEntry() async {
    try {
      if (!DemoSource.enabled(await api.get('/v1/app-config'))) return false;
    } on ApiException {
      return false;
    }
    try {
      final profile = await api.get('/v1/me/profile');
      return !['displayName', 'district', 'hoursPerWeek', 'constraints'].any(
            (key) =>
                profile[key] is String &&
                (profile[key] as String).trim().isNotEmpty,
          ) &&
          !['skills', 'goals'].any(
            (key) => profile[key] is List && (profile[key] as List).isNotEmpty,
          ) &&
          (profile['incomeGoalPerMonth'] is! num ||
              profile['incomeGoalPerMonth'] <= 0);
    } on ApiException catch (error) {
      return error.status == 404;
    }
  }

  /// Quick check, route and task details reload the home data when they close.
  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => screen));
    app.bump();
  }

  void _openPersonalChat() {
    if (submittingChat) return;
    setState(() => personalChat = true);
    app.openChat();
  }

  Future<void> _sendChat(String text) async {
    if (submittingChat || openingDemo || app.deletingData) return;
    final draft = chatDraft;
    final prepared = app.preparedDemoChat;
    final existingDemo = prepared?.api.baseUrl == api.baseUrl ? prepared : null;
    final demo = usesDemoChat
        ? existingDemo ?? app.forDemoChat(DemoChatProfile.connected)
        : null;
    final target = demo ?? app;
    final newDemo = demo != null && demo != existingDemo;
    var dispatched = false;
    setState(() => submittingChat = true);
    try {
      final result = await target.chat.submit(
        target,
        text,
        confirmConsent: () => confirmChatConsent(context, app),
        prepare: newDemo ? () => _seedDemo(target.api) : null,
        onDispatch: () {
          if (!mounted) return;
          dispatched = true;
          if (draft.text == text) draft.clear();
          app.openChat(demo: demo);
        },
      );
      if (!mounted || result != ChatSubmission.failed) return;
      if (!dispatched && draft.text.isEmpty) draft.text = text;
      if (target.chat.error case final String message when !dispatched) {
        toast(context, message);
      }
    } finally {
      if (newDemo && !dispatched) target.api.close();
      if (mounted) setState(() => submittingChat = false);
    }
  }

  Future<void> _openQuickCheck({bool personal = false}) async {
    if (openingDemo) return;
    if (personal || !hasDemoProfile) {
      await _open(
        QuickCheckScreen(app: app, knownFacts: facts, consented: consented),
      );
      return;
    }

    await _openDemo((demoApp) async {
      final known = await demoApp.api.get('/v1/me/facts');
      final purposes = await demoApp.api.currentPurposes();
      return QuickCheckScreen(
        app: demoApp,
        knownFacts: known,
        consented: purposes?['core'] == true,
      );
    });
  }

  Future<void> _openDemo(Future<Widget> Function(AppState) buildScreen) async {
    setState(() => openingDemo = true);
    final demoApp = app.forDemoChat(DemoChatProfile.connected);
    final demoApi = demoApp.api;
    try {
      await _seedDemo(demoApi);
      if (!mounted) return;
      final screen = await buildScreen(demoApp);
      if (mounted) await _open(screen);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      demoApi.close();
      if (mounted) setState(() => openingDemo = false);
    }
  }

  Future<void> _seedDemo(Api client) async {
    final answers = api.onboardingChoices;
    final selected = DemoSource.values
        .where((source) => source.answer(answers) == 'y')
        .toList();
    final selection =
        '${api.baseUrl}|${selected.map((source) => source.id).join(',')}';
    bool needsSample =
        selected.isNotEmpty && api.chatSampleSelection != selection;
    try {
      await client.get('/v1/me/profile');
    } on ApiException catch (error) {
      if (error.status != 404) rethrow;
      needsSample = true;
    }
    if (!needsSample) return;
    final path = selected.isEmpty
        ? '/v1/demo/personas/gov-prefill'
        : '${DemoSource.personaPath(selected)}&keepPlans=true';
    final sample = await client.post(path);
    if (sample['dataStatus'] != 'mock') {
      throw ApiException(0, 'DEMO_DATA', 'โหลดโปรไฟล์ DEMO ไม่ได้');
    }
    if (selected.isNotEmpty) api.saveChatSampleSelection(selection);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mockOverview = widget.assessment?.mock == true && overview == null
        ? widget.assessment?.moneyOverview
        : null;
    final money = overview ?? mockOverview;
    final items = ((money?['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final found = rankMoney(items).where((i) => tierOf(i) <= 3).toList();
    final openQuestions = items.where((i) => i['status'] == 'need').length;
    // Returning layout only when there is something to show: an answer, a plan, or a real chat.
    // Consent alone (pressing the AI button and leaving) keeps the new-person layout.
    final started =
        facts.isNotEmpty ||
        mockOverview != null ||
        tasks.isNotEmpty ||
        app.chat.talked ||
        gov == GovState.connected;
    final talked = usesDemoChat
        ? app.preparedDemoChat?.chat.talked == true
        : app.chat.talked;
    final next = nextTask(tasks);
    final others = tasks
        .where((x) => x['status'] != 'finished' && x != next)
        .length;
    final planned = tasks.map((x) => x['moneyId']).whereType<String>().toSet();
    final firstThing = found.where((i) => !planned.contains(i['id'])).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            BrandHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BrandLogo(size: 30, decorative: true),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'ทางรอด',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (app.allowsDemo) const DemoPill(),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: brandButton,
                        ),
                        onPressed: () => app.goTab(AppTab.opportunities),
                        tooltip: 'ค้นหาโอกาส',
                        icon: const Icon(Icons.search),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    started ? 'เงินของฉัน' : 'เงินฉันอยู่ไหน?',
                    style: t.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (money != null)
                    _Summary(overview: money, mock: mockOverview != null)
                  else if (loaded)
                    const Text(
                      'เช็คสิทธิ์ที่อาจได้รับ หาโอกาสสร้างรายได้ และติดตามแผนของคุณ',
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null && error!.isNetwork)
                    OfflineCard(app: app, onRetry: _load),
                  if (error != null && !error!.isNetwork)
                    Card(
                      child: ListTile(
                        title: Text(error!.message),
                        trailing: TextButton(
                          onPressed: _load,
                          child: const Text('ลองใหม่'),
                        ),
                      ),
                    ),
                  if (!loaded)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (loaded && started) ...[
                    // 1) unfinished plan → its next step; 2) otherwise the first money item not yet planned; 3) all done.
                    if (next != null)
                      _NextStepCard(
                        task: next,
                        onOpen: () => _open(
                          TaskScreen(app: app, taskId: '${next['id']}'),
                        ),
                        onLater: () =>
                            snoozeTask(context, app, '${next['id']}'),
                      )
                    else if (firstThing.isNotEmpty)
                      _FirstThingCard(
                        item: firstThing.first,
                        mock: mockOverview != null,
                        onOpen: () {
                          final item = firstThing.first;
                          final id = '${item['id']}';
                          _open(
                            mockOverview == null
                                ? RouteScreen(app: app, moneyId: id)
                                : OppScreen.money(
                                    app: app,
                                    moneyId: id,
                                    summary: item,
                                    mockAssessment: true,
                                  ),
                          );
                        },
                      )
                    else if (tasks.isNotEmpty)
                      const Card(
                        child: ListTile(
                          title: Text('🎉 ไม่มีงานค้าง'),
                          subtitle: Text('ทำครบทุกแผนแล้ว (ตามที่คุณแจ้ง)'),
                        ),
                      ),
                    if (others > 0)
                      ListTile(
                        title: Text('งานอื่นที่ทำอยู่ $others รายการ'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => app.goTab(AppTab.plans),
                      ),
                    const SizedBox(height: 10),
                    if (tasks.isNotEmpty)
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.assignment_turned_in_outlined,
                            color: brandDark,
                          ),
                          title: const Text('ความคืบหน้า'),
                          subtitle: Text(
                            'ทำแล้ว ${tasks.where((task) => task['status'] == 'finished').length} จาก ${tasks.length} แผน',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => app.goTab(AppTab.plans),
                        ),
                      ),
                  ],
                  if (loaded)
                    _AiHero(
                      title: talked ? 'คุยกับ AI ต่อ' : 'ให้ AI หาเงินให้ฉัน',
                      subtitle: usesDemoChat
                          ? 'ใช้ข้อมูลจากโปรไฟล์ DEMO เพื่อข้ามคำถามที่มีคำตอบแล้ว'
                          : talked
                          ? 'คุยต่อจากเดิม ถามได้ เช่น ต้องทำอะไรต่อ ขอลิงก์ติดต่อ เอกสารที่ยังขาด'
                          : 'ถามเรื่องสิทธิ์ เอกสาร หรือรายได้ที่เหมาะกับคุณ',
                      composer: ChatComposer(
                        controller: chatDraft,
                        hint: 'พิมพ์คำถาม หรือแตะไมค์',
                        busy: submittingChat || openingDemo,
                        onSend: _sendChat,
                      ),
                      onContinue: talked
                          ? () => app.openChat(
                              demo: usesDemoChat ? app.preparedDemoChat : null,
                            )
                          : null,
                    ),
                  if (usesDemoChat)
                    TextButton(
                      onPressed: submittingChat ? null : _openPersonalChat,
                      child: const Text('เริ่มคุยด้วยข้อมูลของฉัน'),
                    ),
                  if (loaded) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFEFF6FF),
                      child: ListTile(
                        minVerticalPadding: 12,
                        leading: const Text(
                          '📈',
                          style: TextStyle(fontSize: 30),
                        ),
                        title: const Text(
                          'แผนรายได้: อยากได้เดือนละเท่าไหร่',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'บอกเป้า แล้วดูว่าเงินจากรัฐ งาน และทักษะของคุณ รวมได้เท่าไหร่ ยังขาดเท่าไหร่',
                        ),
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
                      onTap: () => _open(
                        QuickCheckScreen(
                          app: app,
                          consented: consented,
                          askAll: true,
                        ),
                      ),
                    ),
                  if (loaded && (facts.isEmpty || openQuestions > 0)) ...[
                    const SizedBox(height: 14),
                    Card(
                      child: ListTile(
                        minVerticalPadding: 14,
                        leading: const Text(
                          '💰',
                          style: TextStyle(fontSize: 30),
                        ),
                        title: Text(
                          facts.isNotEmpty
                              ? 'ตอบเพิ่มอีก $openQuestions เรื่อง อาจเจอเงินก้อนอื่น'
                              : 'เช็คเงินที่ควรได้ เอง',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          hasDemoProfile
                              ? 'ไม่ใช้ AI · ใช้ข้อมูลจากโปรไฟล์ DEMO'
                              : facts.isNotEmpty
                              ? 'ไม่ใช้ AI · ถามเฉพาะข้อที่ยังไม่ได้ตอบ'
                              : 'ไม่ใช้ AI · เบี้ยผู้สูงอายุ เงินว่างงาน เงินเลี้ยงดูเด็ก เบี้ยความพิการ คืนภาษี ค่าจ้างค้าง',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openQuickCheck,
                      ),
                    ),
                    if (hasDemoProfile)
                      TextButton(
                        onPressed: openingDemo
                            ? null
                            : () => _openQuickCheck(personal: true),
                        child: const Text('เช็คด้วยข้อมูลของฉัน'),
                      ),
                  ],
                  if (loaded && !started) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _SmallCard(
                            icon: '🔎',
                            text: 'หางาน',
                            onTap: () =>
                                app.goTab(AppTab.opportunities, group: 'job'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SmallCard(
                            icon: '🍳',
                            text: 'รายได้จากทักษะ',
                            onTap: () =>
                                app.goTab(AppTab.opportunities, group: 'skill'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (loaded && started)
                    ListTile(
                      title: const Text('✨ ดูงานและรายได้จากทักษะ'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          app.goTab(AppTab.opportunities, group: 'all'),
                    ),
                  if (loaded) ThaidCard(app: app, state: gov),
                  const SizedBox(height: 16),
                  Text(
                    'แอปไม่รับประกันว่าจะได้เงินหรือได้งาน ผลเป็นการตรวจเบื้องต้นจากเกณฑ์ที่ประกาศ ต้องยืนยันกับหน่วยงานทางการ',
                    textAlign: TextAlign.center,
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.overview, required this.mock});
  final Map<String, dynamic>? overview;
  final bool mock;

  @override
  Widget build(BuildContext context) {
    final s = (overview?['summary'] as Map?) ?? const {};
    final monthly = s['monthly'] is num ? s['monthly'] as num : 0;
    final once = s['once'] is num ? s['once'] as num : 0;
    final pending = s['pending'] is num ? s['pending'] as num : 0;
    return Card(
      color: const Color(0xFFEEF4FF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mock) const DemoPill(),
            if (monthly > 0 || once > 0) ...[
              const Text(
                'เงินที่คาดว่าจะได้รับ',
                style: TextStyle(color: brandDark, fontWeight: FontWeight.bold),
              ),
              if (monthly > 0)
                Text(
                  '${baht(monthly)} ต่อเดือน',
                  style: const TextStyle(
                    color: brandButton,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (once > 0)
                Text(
                  '${baht(once)} ครั้งเดียว',
                  style: const TextStyle(
                    color: brandButton,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                s['allVerified'] == true
                    ? 'ยืนยันจากหน่วยงาน'
                    : 'ประมาณจากเกณฑ์ที่ประกาศ ยังไม่ยืนยันกับหน่วยงาน',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              const Text(
                'ยังไม่พบเงินที่นับยอดได้',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            if (pending > 0)
              Text(
                'อีก $pending รายการต้องเช็คหรือตอบเพิ่ม',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _FirstThingCard extends StatelessWidget {
  const _FirstThingCard({
    required this.item,
    required this.onOpen,
    required this.mock,
  });
  final Map<String, dynamic> item;
  final VoidCallback onOpen;
  final bool mock;
  @override
  Widget build(BuildContext context) {
    final a = (item['amount'] as Map?) ?? const {};
    return Card(
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: cardBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('สิ่งแรกที่ควรทำ'),
            const SizedBox(height: 5),
            Row(
              children: [
                OpportunityArtwork(moneyId: item['id'] as String?),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${item['title']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              a['value'] is num
                  ? '${baht(a['value'] as num)} ${a['unit'] ?? ''}'
                  : 'ยังไม่ทราบยอด',
            ),
            Text(
              '${statusLabel[item['status']] ?? item['status']} · ${mock ? 'DEMO / MOCK' : dataLabel(item['dataStatus'] as String?)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('ดูวิธีไปรับเงิน: ที่ไหน เอาอะไรไป'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({
    required this.task,
    required this.onOpen,
    required this.onLater,
  });
  final Map<String, dynamic> task;
  final VoidCallback onOpen, onLater;
  @override
  Widget build(BuildContext context) {
    final steps = (task['steps'] as List).map((e) => '$e').toList();
    final done = (task['doneCount'] as num).toInt();
    final status = '${task['status']}';
    return Card(
      color: blueTint,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ขั้นต่อไปของคุณ'),
            Text(
              '${task['title']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (done < steps.length)
              Text('ขั้นที่ ${done + 1} จาก ${steps.length}: ${steps[done]}'),
            if (status != 'active')
              Text(
                taskStatusLabel[status] ?? status,
                style: const TextStyle(color: Color(0xFF9A3412)),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onOpen,
                    child: const Text('ทำต่อ'),
                  ),
                ),
                if (status == 'active') ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onLater,
                      child: const Text('ไว้ทีหลัง'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallCard extends StatelessWidget {
  const _SmallCard({
    required this.icon,
    required this.text,
    required this.onTap,
  });
  final String icon, text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ),
  );
}

class _AiHero extends StatelessWidget {
  const _AiHero({
    required this.title,
    required this.subtitle,
    required this.composer,
    this.onContinue,
  });
  final String title, subtitle;
  final Widget composer;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: brandGradient,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_outlined, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 12),
        composer,
        if (onContinue != null)
          TextButton(
            onPressed: onContinue,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('ดูบทสนทนา'),
          ),
      ],
    ),
  );
}
