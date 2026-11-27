import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat.dart';
import 'common.dart';
import 'demo_sources_screen.dart';
import 'income_plan_screen.dart';
import 'profile_overview_screen.dart';
import 'profile_screen.dart';
import 'thaid.dart';

const purposeLabel = {'ai': 'ให้ AI ช่วยวิเคราะห์', 'reminders': 'เตือนงานค้าง', 'location': 'ใช้ตำแหน่งค้นหา'};

/// Tab 👤 ฉัน (ui-states.md S9): settings, consent (takes effect at once), AI memory, my data, delete, help, demo.
class MeTab extends StatefulWidget {
  const MeTab({super.key, required this.app});
  final AppState app;
  @override
  State<MeTab> createState() => _MeTabState();
}

typedef _DemoCase = ({String label, String subtitle, String path, String route});

class _MeTabState extends State<MeTab> {
  Map<String, bool>? purposes;
  int history = 0;
  String? profileRoute;
  Future<ProfileSnapshot?>? profileSummary;
  List<_DemoCase> demoCases = const [];
  bool openingDemo = false;
  List<Map<String, dynamic>> memory = [];
  ApiException? error;
  bool loaded = false;
  bool userMode = false;
  Map<String, dynamic>? governmentConnections;
  GovState gov = GovState.disabled;
  Api get api => widget.app.api;

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
    final Future<ProfileSnapshot?> summary = ProfileSnapshot.load(api);
    setState(() {
      profileSummary = summary.onError<ApiException>((_, _) => null);
    });
    try {
      final c = await api.get('/v1/me/consents');
      final cur = c['current'] as Map<String, dynamic>?;
      final m = await api.get('/v1/me/memory');
      final s = await api.get('/v1/me/settings');
      if (!mounted) return;
      widget.app.largeText.value = s['largeText'] == true;
      gov = await govState(api);
      final config = await api.get('/v1/app-config').onError<ApiException>((_, _) => const <String, dynamic>{});
      if (!mounted) return;
      setState(() {
        if (config.isNotEmpty) {
          userMode = config['mode'] == 'user';
          governmentConnections = config['governmentConnections'] as Map<String, dynamic>?;
          profileRoute = _profileRoute(config);
          demoCases = _demoCases(config);
        }
        purposes = cur == null ? null : (cur['purposes'] as Map).map((k, v) => MapEntry('$k', v == true));
        history = ((c['items'] as List?) ?? const []).length;
        memory = (m['items'] as List).cast<Map<String, dynamic>>();
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { error = e; loaded = true; });
    }
  }

  Future<void> _togglePurpose(String id, bool v) async {
    try {
      await api.setConsent({...?purposes, id: v});
      widget.app.bump();
      if (id == 'ai' && !v) widget.app.chat.reset(); // withdrawing AI clears the chat and AI memory (server does too)
      if (mounted) toast(context, v ? 'ยินยอมแล้ว' : 'ถอนความยินยอมแล้ว มีผลทันที');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _largeText(bool v) async {
    widget.app.largeText.value = v;
    try {
      await api.patch('/v1/me/settings', {'largeText': v});
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _forget(String id) async {
    try {
      await api.delete('/v1/me/memory/$id');
      await _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _myData() async {
    try {
      final x = await api.get('/v1/me/export');
      if (!mounted) return;
      final f = x['facts'] as Map? ?? const {};
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('ข้อมูลที่เก็บไว้'),
          content: SingleChildScrollView(child: Text(
              'คำตอบ: ${f.isEmpty ? 'ไม่มี' : f.entries.map((e) => '${e.key}=${e.value}').join(', ')}\n'
              'แผน: ${(x['tasks'] as List?)?.length ?? 0} รายการ\n'
              'AI จำไว้: ${(x['memory'] as List?)?.length ?? 0} รายการ\n'
              'ความยินยอม: ${(x['consents'] as List?)?.length ?? 0} ครั้ง\n\n'
              'ไม่เก็บ: ${((x['notStored'] as List?) ?? const []).join(', ')}')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด'))],
        ),
      );
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _deleteAll() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบข้อมูลทั้งหมด?'),
        content: const Text('คำตอบ แผนรวมถึงแผน DEMO ความยินยอม และสิ่งที่ AI จำไว้จะถูกลบ กู้คืนไม่ได้'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('ลบข้อมูล')),
        ],
      ),
    );
    if (yes != true) return;
    final demoApis = [for (final profile in DemoChatProfile.values) api.forDemo(profile.deviceSuffix)];
    try {
      await Future.wait([for (final client in [api, ...demoApis]) client.delete('/v1/me')]);
      widget.app.chat.reset();
      widget.app.goTab(0);
      if (mounted) toast(context, 'ลบข้อมูลและถอนความยินยอมแล้ว');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      for (final client in demoApis) {
        client.close();
      }
      widget.app.bump();
    }
  }

  Future<void> _persona(String id, String label) async {
    try {
      await api.post('/v1/demo/personas/$id');
      widget.app.chat.reset();
      widget.app.bump();
      widget.app.goTab(0);
      if (mounted) toast(context, 'โหลดผู้ใช้ตัวอย่าง: $label (DEMO)');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  String? _profileRoute(Map<String, dynamic> config) {
    if (config case {'routes': {'me': {'sections': final List sections}}}) {
      for (final section in sections) {
        if (section case {'type': 'profile_card', 'onTap': {'route': final String route}}) return route;
      }
    }
    return null;
  }

  List<_DemoCase> _demoCases(Map<String, dynamic> config) {
    if (config case {
      'featureFlags': {'demo': true},
      'routes': {'me': {'sections': final List sections}},
      'actions': {'demo.load': {'path': final String path}},
    }) {
      return [
        for (final section in sections)
          if (section case {'id': 'demo.gov-prefill' || 'demo.dmytax', 'items': final List items})
            for (final item in items)
              if (item case {
                'label': final String label,
                'sub': final String subtitle,
                'onTap': {
                  'action': 'demo.load',
                  'params': {'id': final String id},
                  'then': {'route': final String route},
                },
              } when route == 'me.profile' || route == 'assistant')
                (
                  label: label,
                  subtitle: subtitle,
                  path: path.replaceAll('{id}', Uri.encodeComponent(id)),
                  route: route,
                ),
      ];
    }
    return const [];
  }

  Future<void> _openDemo(_DemoCase scenario) async {
    if (openingDemo) return;
    if (scenario.route == 'me.profile') {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => DemoSourcesScreen(app: widget.app, personaPath: scenario.path),
      ));
      return;
    }
    setState(() => openingDemo = true);
    final demoApp = widget.app.forDemoChat(DemoChatProfile.tax);
    try {
      final loaded = await demoApp.api.post('${scenario.path}?keepPlans=true');
      if (loaded['dataStatus'] != 'mock') throw ApiException(0, 'DEMO_DATA', 'โหลดข้อมูลจำลองไม่ได้');
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => ChatScreen(app: demoApp, session: demoApp.chat, title: 'D-MyTax · DEMO / MOCK'),
      ));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      demoApp.api.close();
      if (mounted) setState(() => openingDemo = false);
    }
  }

  Widget _demoTile(_DemoCase scenario) => ListTile(
        leading: Icon(scenario.route == 'me.profile' ? Icons.link : Icons.receipt_long),
        title: Text(scenario.label),
        subtitle: Text(scenario.subtitle),
        trailing: const Icon(Icons.chevron_right),
        enabled: !openingDemo,
        onTap: () => _openDemo(scenario),
      );

  Widget _demoAccounts() {
    return FutureBuilder<ProfileSnapshot?>(
      future: profileSummary,
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final sample = state.data?.sample;
        if (sample != null && sample.connections.isNotEmpty && gov != GovState.connected) {
          return DemoConnectionDetails(
            demo: sample,
            onConnectThaid: gov == GovState.notConnected ? () => connectThaid(context, widget.app) : null,
          );
        }
        return switch (gov) {
          GovState.disabled => const ListTile(
            title: Text('ThaID'),
            subtitle: Text('server ปิดโหมดนี้อยู่'),
          ),
          GovState.notConnected => ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('เชื่อม ThaID'),
            subtitle: const Text('โหมดสาธิต ใช้ข้อมูลจำลอง'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => connectThaid(context, widget.app),
          ),
          GovState.connected => ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('ThaID เชื่อมแล้ว (ข้อมูลจำลอง)'),
            trailing: TextButton(onPressed: () => disconnectThaid(context, widget.app), child: const Text('ยกเลิก')),
          ),
        };
      },
    );
  }

  Widget _profileTile() {
    return ListTile(
      leading: const Text('🧑', style: TextStyle(fontSize: 22)),
      title: const Text('โปรไฟล์ของฉัน'),
      subtitle: FutureBuilder<ProfileSnapshot?>(
        future: profileSummary,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Text('กำลังโหลดข้อมูลส่วนตัว…');
          }
          final profile = state.data;
          if (profile == null) return const Text('โหลดข้อมูลส่วนตัวไม่ได้');
          final facts = [
            if (profile.age case final age?) 'อายุ $age ปี',
            if (profile.district case final district?) 'เขตที่อยู่ $district',
          ];
          final summary = [
            ?profile.displayName,
            if (facts.isNotEmpty) facts.join(' · '),
            if (profile.mock) 'DEMO / MOCK',
          ];
          return Text(summary.isEmpty ? 'แตะเพื่อเพิ่มข้อมูลส่วนตัว' : summary.join('\n'));
        },
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => profileRoute == 'intake.manual'
            ? ProfileScreen(app: widget.app)
            : ProfileOverviewScreen(app: widget.app)),
      ),
    );
  }

  void _info(String title, String text) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(title: Text(title), content: Text(text), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('เข้าใจแล้ว'))]),
      );

  Widget _head(String s) => Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 4), child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF065F46))));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ฉัน')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (error != null && error!.isNetwork) OfflineCard(app: widget.app, onRetry: _load),
        _head('ข้อมูลของฉัน'),
        _profileTile(),
        ListTile(
          leading: const Text('📈', style: TextStyle(fontSize: 22)),
          title: const Text('แผนรายได้'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IncomePlanScreen(app: widget.app))),
        ),
        _head('บัญชีที่เชื่อมต่อ'),
        if (userMode) ...[
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('ThaID'),
            subtitle: Text(governmentConnections?['thaid'] == 'approval_required'
                ? 'รอกรมการปกครองอนุมัติการเชื่อมต่อ'
                : 'ยังไม่เปิดการเชื่อมต่อ'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('ทางรัฐ'),
            subtitle: Text(governmentConnections?['tangRat'] == 'access_required'
                ? 'รอสิทธิ์เข้าถึงข้อมูลจากหน่วยงานเจ้าของบริการ'
                : 'ยังไม่เปิดการเชื่อมต่อ'),
          ),
        ] else ...[
          _demoAccounts(),
          for (final scenario in demoCases)
            if (scenario.route == 'me.profile') _demoTile(scenario),
        ],
        ListTile(
          leading: const Text('🔌', style: TextStyle(fontSize: 22)),
          title: const Text('แหล่งข้อมูลที่เชื่อมต่อ'),
          subtitle: const Text('API ภาครัฐ เอกชน ข้อมูลจริง และข้อมูลจำลอง'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SourcesScreen(app: widget.app))),
        ),
        _head('การใช้งาน'),
        ValueListenableBuilder<bool>(
          valueListenable: widget.app.largeText,
          builder: (_, v, _) => SwitchListTile(value: v, onChanged: _largeText, title: const Text('ตัวอักษรใหญ่')),
        ),
        _head('ความเป็นส่วนตัวและข้อมูลของฉัน'),
        if (loaded && purposes == null)
          const ListTile(title: Text('ยังไม่ได้ให้ความยินยอม'), subtitle: Text('จะถามเมื่อคุณกดบันทึกครั้งแรก หรือกดปุ่ม AI ที่หน้าแรก')),
        if (purposes != null) ...[
          const SwitchListTile(value: true, onChanged: null, title: Text('ข้อมูลที่จำเป็น (บังคับ)'), subtitle: Text('ถอนได้ด้วย "ลบข้อมูลทั้งหมด"')),
          for (final e in purposeLabel.entries)
            SwitchListTile(value: purposes![e.key] == true, onChanged: (v) => _togglePurpose(e.key, v), title: Text(e.value)),
          ListTile(title: Text('ประวัติการให้ความยินยอม $history ครั้ง'), dense: true),
        ],
        ListTile(title: const Text('ประกาศความเป็นส่วนตัว'), trailing: const Icon(Icons.chevron_right), onTap: () => showNotice(context, widget.app)),
        ExpansionTile(
          title: Text('AI จำอะไรเกี่ยวกับฉัน (${memory.length})'),
          children: [
            if (memory.isEmpty) const ListTile(title: Text('ยังไม่มี')),
            for (final m in memory)
              ListTile(title: Text('${m['text']}'), subtitle: Text(m['source'] == 'ai' ? 'AI จำไว้' : 'คุณเพิ่มเอง'),
                  trailing: TextButton(onPressed: () => _forget('${m['id']}'), child: const Text('ลบ'))),
          ],
        ),
        ListTile(title: const Text('ดูข้อมูลที่เก็บไว้'), trailing: const Icon(Icons.chevron_right), onTap: _myData),
        ListTile(title: const Text('ลบข้อมูลทั้งหมด', style: TextStyle(color: Colors.red)), onTap: _deleteAll),
        _head('ช่วยเหลือ'),
        ListTile(
          title: const Text('วิธีใช้แอป'),
          onTap: () => _info('ใช้แอปใน 3 ขั้น', '1. กดปุ่ม AI หรือเช็คเงินเอง ตอบทีละข้อ\n2. ดูเงินที่น่าจะได้ ที่ยื่น และเอกสาร\n3. กดบันทึกเป็นแผน แล้วทำทีละขั้นในแท็บ แผนของฉัน'),
        ),
        ListTile(
          title: const Text('รู้ทันมิจฉาชีพ'),
          onTap: () => _info('สัญญาณเตือน', '• ให้โอนเงินก่อน ค่ามัดจำ ค่าธรรมเนียม\n• ขอเลขบัตร รหัสผ่าน OTP ทางแชท\n• รายได้สูงผิดปกติ งานง่ายเกินจริง\n• เงินกู้คือหนี้ ไม่ใช่รายได้\nสงสัยโทรสายด่วนตำรวจไซเบอร์ 1441'),
        ),
        if (!userMode) ...[
          _head('สำหรับสาธิต (DEMO)'),
          for (final scenario in demoCases)
            if (scenario.route == 'assistant') _demoTile(scenario),
          for (final p in const [
            ['p1', 'สมชาย 65 ปี ยังไม่ได้เบี้ยผู้สูงอายุ'],
            ['p2', 'สุดา 28 ปี ถูกเลิกจ้าง หางาน'],
            ['p3', 'มานี 40 ปี อาชีพอิสระ รายได้จากทักษะ'],
            ['p4', 'วิชัย 45 ปี ถูกเลิกจ้าง นายจ้างค้างค่าจ้าง'],
            ['p5', 'นิด 32 ปี แม่เลี้ยงเดี่ยว ลูก 3 ขวบ'],
            ['p6', 'สมศักดิ์ 52 ปี ผู้พิการ มีบัตรสวัสดิการ'],
            ['p7', 'ต้น 20 ปี นักศึกษา หางานพาร์ตไทม์'],
            ['p8', 'ยายบุญมี 78 ปี ได้เบี้ยอยู่แล้ว อยากมีรายได้เสริม'],
          ])
            ListTile(title: Text('โหลดผู้ใช้ตัวอย่าง: ${p[1]}'), leading: const Icon(Icons.person_outline), onTap: () => _persona(p[0], p[1])),
        ],
        ListTile(
          title: const Text('ที่อยู่ server'),
          subtitle: Text(api.baseUrl),
          trailing: const Icon(Icons.edit),
          onTap: () => editServer(context, widget.app, () { widget.app.bump(); setState(() {}); }),
        ),
        if (!userMode)
          const Padding(padding: EdgeInsets.all(8), child: DemoPill(text: 'เวอร์ชันสาธิต · ผู้ใช้สมมติ · ไม่มีการเข้าสู่ระบบ')),
      ]),
    );
  }
}

/// ฉัน > แหล่งข้อมูลที่เชื่อมต่อ: every source the server uses, what kind it is, and its state (GET /v1/sources).
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key, required this.app});
  final AppState app;
  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  List<Map<String, dynamic>>? items;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.app.api.get('/v1/sources');
      setState(() => items = (r['items'] as List).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  static String _kind(Map<String, dynamic> s) {
    final p = '${s['provider']}';
    if (p.startsWith('mock') || p.endsWith('_mock')) return '🧪 ข้อมูลจำลอง รอต่อ API จริง';
    if (s['direction'] == 'pull') return '🌐 ดึงจาก API จริง';
    if (p == 'official') return '🏛️ ลิงก์หน่วยงานรัฐ (ตรวจด้วยมือ)';
    return '📄 ${s['kind'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แหล่งข้อมูลที่เชื่อมต่อ')),
      body: error != null
          ? Center(child: Text(error!))
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final s in items!)
                    Card(
                      child: ListTile(
                        title: Text('${s['name'] ?? s['provider']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${_kind(s)}\nสถานะ: ${s['state']}${s['itemCount'] != null ? ' · ${s['itemCount']} รายการ' : ''}'),
                        isThreeLine: true,
                      ),
                    ),
                  Text('ข้อมูลจำลองแทนระบบที่ยังต่อไม่ได้ (ต้องมีข้อตกลงหรือ API key) ทุกรายการจากแหล่งนี้ติดป้าย DEMO / MOCK ในแอป', style: Theme.of(context).textTheme.bodySmall),
                ]),
    );
  }
}
