import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat.dart';
import 'common.dart';
import 'connected_accounts.dart';
import 'connected_account_row.dart';
import 'demo_sources_screen.dart';
import 'income_plan_screen.dart';
import 'opportunity_assessment.dart';
import 'profile_overview_screen.dart';
import 'profile_screen.dart';
import 'thaid.dart';
import 'thang_rot_theme.dart';

const purposeLabel = {
  'ai': 'ให้ AI ช่วยวิเคราะห์',
  'reminders': 'เตือนงานค้าง',
  'location': 'ใช้ตำแหน่งค้นหา',
  'gov': 'ใช้ข้อมูลจาก ThaID',
};

/// Tab 👤 ฉัน (ui-states.md S9): settings, consent (takes effect at once), AI memory, my data, delete, help, demo.
class MeTab extends StatefulWidget {
  const MeTab({super.key, required this.app});
  final AppState app;
  @override
  State<MeTab> createState() => _MeTabState();
}

typedef _DemoCase = ({
  String label,
  String subtitle,
  String path,
  String route,
});

class _MeTabState extends State<MeTab> {
  Map<String, bool>? purposes;
  int history = 0;
  Future<PersonalProfile?>? profileSummary;
  final accountsHeading = GlobalKey();
  final accountsFocus = FocusNode();
  int loadGeneration = 0;
  bool openingDemo = false;
  List<Map<String, dynamic>> memory = [];
  ApiException? error;
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
    accountsFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.app.deletingData) return;
    final generation = ++loadGeneration;
    unawaited(widget.app.accounts.refresh(force: true));
    final Future<PersonalProfile?> summary = PersonalProfile.load(api);
    final profile = summary.onError<ApiException>((_, _) => null);
    setState(() {
      profileSummary = profile;
    });
    try {
      final c = await api.get('/v1/me/consents');
      final cur = c['current'] as Map<String, dynamic>?;
      final m = await api.get('/v1/me/memory');
      final s = await api.get('/v1/me/settings');
      if (!mounted || generation != loadGeneration) return;
      widget.app.largeText.value = s['largeText'] == true;
      setState(() {
        purposes = cur == null
            ? null
            : (cur['purposes'] as Map).map((k, v) => MapEntry('$k', v == true));
        history = ((c['items'] as List?) ?? const []).length;
        memory = (m['items'] as List).cast<Map<String, dynamic>>();
        error = null;
      });
    } on ApiException catch (e) {
      if (mounted && generation == loadGeneration) {
        setState(() {
          error = e;
        });
      }
    }
  }

  Future<void> _togglePurpose(String id, bool v) async {
    try {
      await api.setConsent({...?purposes, id: v});
      if (id == 'gov' && !v && widget.app.accounts.value.demoEnabled) {
        widget.app.accounts.forgetDemoThaid();
      }
      widget.app.bump();
      if (id == 'ai' && !v) widget.app.resetConversations();
      if (mounted) {
        toast(context, v ? 'ยินยอมแล้ว' : 'ถอนความยินยอมแล้ว มีผลทันที');
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } on FileSystemException {
      widget.app.bump();
      if (mounted) toast(context, 'บันทึกการยกเลิกการเชื่อมไม่ได้ ลองใหม่');
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
          content: SingleChildScrollView(
            child: Text(
              'คำตอบ: ${f.isEmpty ? 'ไม่มี' : f.entries.map((e) => '${e.key}=${e.value}').join(', ')}\n'
              'แผน: ${(x['tasks'] as List?)?.length ?? 0} รายการ\n'
              'AI จำไว้: ${(x['memory'] as List?)?.length ?? 0} รายการ\n'
              'ความยินยอม: ${(x['consents'] as List?)?.length ?? 0} ครั้ง\n\n'
              'ไม่เก็บ: ${((x['notStored'] as List?) ?? const []).join(', ')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _deleteAll() async {
    final app = widget.app;
    if (app.deletingData) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบข้อมูลทั้งหมด?'),
        content: const Text(
          'คำตอบ แผนรวมถึงแผน DEMO ความยินยอม และสิ่งที่ AI จำไว้จะถูกลบ กู้คืนไม่ได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบข้อมูล'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || app.deletingData) return;
    app.deletingData = true;
    loadGeneration++;
    app.accounts.beginDelete();
    final demoApis = [
      for (final profile in DemoChatProfile.values)
        api.forDemo(profile.deviceSuffix),
      api.forDemo(onboardingDemoDevice),
    ];
    try {
      api.saveOnboardingChoices('');
      await app.onboardingWrite;
      await Future.wait([
        for (final client in [api, ...demoApis]) client.delete('/v1/me'),
      ]);
      app.dataCleared.value++;
      app.resetConversations();
      app.goTab(AppTab.home);
      if (mounted) toast(context, 'ลบข้อมูลและถอนความยินยอมแล้ว');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } on FileSystemException {
      if (mounted) {
        toast(context, 'ล้างตัวเลือกบนเครื่องไม่ได้ ลองลบข้อมูลอีกครั้ง');
      }
    } finally {
      for (final client in demoApis) {
        client.close();
      }
      app.deletingData = false;
      app.accounts.endDelete();
      app.bump();
    }
  }

  Future<void> _persona(String id, String label) async {
    try {
      await api.post('/v1/demo/personas/$id');
      widget.app.resetConversations();
      widget.app.bump();
      widget.app.goTab(AppTab.home);
      if (mounted) toast(context, 'โหลดผู้ใช้ตัวอย่าง: $label (DEMO)');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  List<_DemoCase> _demoCases(Map<String, dynamic> config) {
    if (config case {
      'featureFlags': {'demo': true},
      'routes': {'me': {'sections': final List sections}},
      'actions': {'demo.load': {'path': final String path}},
    }) {
      return [
        for (final section in sections)
          if (section case {
            'id': 'demo.gov-prefill' || 'demo.dmytax',
            'items': final List items,
          })
            for (final item in items)
              if (item
                  case {
                    'label': final String label,
                    'sub': final String subtitle,
                    'onTap': {
                      'action': 'demo.load',
                      'params': {'id': final String id},
                      'then': {'route': final String route},
                    },
                  }
                  when route == 'me.profile' || route == 'assistant')
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
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              DemoSourcesScreen(app: widget.app, personaPath: scenario.path),
        ),
      );
      return;
    }
    setState(() => openingDemo = true);
    final demoApp = widget.app.forDemoChat(DemoChatProfile.tax);
    try {
      final loaded = await demoApp.api.post('${scenario.path}?keepPlans=true');
      if (loaded['dataStatus'] != 'mock') {
        throw ApiException(0, 'DEMO_DATA', 'โหลดข้อมูลจำลองไม่ได้');
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            app: demoApp,
            session: demoApp.chat,
            title: 'D-MyTax · DEMO / MOCK',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      demoApp.api.close();
      if (mounted) setState(() => openingDemo = false);
    }
  }

  Widget _accounts(AccountsSnapshot snapshot) {
    final theme = Theme.of(context);
    final availability = snapshot.config['governmentConnections'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          key: accountsHeading,
          focusNode: accountsFocus,
          child: Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 3),
              child: Text(
                'บัญชีที่เชื่อมต่อ',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            'เชื่อมแล้ว ${snapshot.connectedCount} จาก ${DemoSource.values.length} บริการ'
            '${snapshot.hasMock ? ' · ข้อมูลจำลอง' : ''}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        for (final source in DemoSource.values)
          ConnectedAccountRow(
            key: ValueKey(source),
            source: source,
            account: snapshot[source],
            availability: availability is Map ? availability[source.id] : null,
            onRetry: () => widget.app.accounts.refresh(retry: source),
            onConnect:
                source == DemoSource.thaid &&
                    snapshot.govAvailable &&
                    const {
                      AccountStatus.disconnected,
                      AccountStatus.skipped,
                    }.contains(snapshot.thaid.status)
                ? () => connectThaid(context, widget.app)
                : null,
            onDisconnect:
                source == DemoSource.thaid &&
                    (snapshot.demoEnabled || snapshot.govLinked)
                ? () => disconnectThaid(context, widget.app)
                : null,
          ),
      ],
    );
  }

  void _showAccounts() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final heading = accountsHeading.currentContext;
      if (heading == null || !mounted) return;
      Scrollable.ensureVisible(
        heading,
        duration: const Duration(milliseconds: 240),
      );
      accountsFocus.requestFocus();
    });
  }

  Widget _profileTile(AccountsSnapshot snapshot) {
    return ListTile(
      key: const ValueKey('account-profile'),
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: Colors.white,
        foregroundColor: brandDark,
        child: Icon(Icons.person_outline),
      ),
      textColor: Colors.white,
      iconColor: Colors.white,
      title: FutureBuilder<PersonalProfile?>(
        future: profileSummary,
        builder: (context, state) => Text(
          snapshot.thaid.identity?.displayName ??
              state.data?.displayName ??
              'โปรไฟล์',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      subtitle: FutureBuilder<PersonalProfile?>(
        future: profileSummary,
        builder: (context, state) {
          if (snapshot.thaid.status == AccountStatus.connected) {
            return Text(
              snapshot.thaid.mock
                  ? 'ข้อมูลส่วนตัวจาก ThaID · DEMO / MOCK'
                  : 'ข้อมูลส่วนตัวจาก ThaID',
            );
          }
          if (widget.app.deletingData ||
              state.connectionState != ConnectionState.done) {
            return const Text('กำลังโหลดข้อมูลส่วนตัว…');
          }
          final profile = state.data;
          if (profile == null) return const Text('โหลดข้อมูลส่วนตัวไม่ได้');
          final summary = [
            ?profile.displayName,
            if (profile.district case final district?) 'เขตที่อาศัย $district',
          ];
          return Text(
            summary.isEmpty ? 'แตะเพื่อเพิ่มข้อมูลส่วนตัว' : summary.join('\n'),
          );
        },
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: widget.app.deletingData
          ? null
          : () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileOverviewScreen(
                  app: widget.app,
                  onAccounts: _showAccounts,
                ),
              ),
            ),
    );
  }

  void _info(String title, String text) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('เข้าใจแล้ว'),
        ),
      ],
    ),
  );

  Widget _head(String s) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
    child: Semantics(
      header: true,
      child: Text(
        s,
        style: const TextStyle(fontWeight: FontWeight.w800, color: brandInk),
      ),
    ),
  );

  Future<void> _privacy() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, refresh) {
            Future<void> change(Future<void> operation) async {
              await operation;
              await _load();
              if (context.mounted) refresh(() {});
            }

            return Scaffold(
              appBar: AppBar(title: const Text('ความเป็นส่วนตัว')),
              body: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _head('ความยินยอม'),
                  if (purposes == null)
                    const ListTile(
                      title: Text('ยังไม่ได้ให้ความยินยอม'),
                      subtitle: Text(
                        'ทางรอดจะถามเมื่อคุณกดบันทึกหรือเริ่มคุยกับ AI',
                      ),
                    ),
                  if (purposes != null) ...[
                    const SwitchListTile(
                      value: true,
                      onChanged: null,
                      title: Text('ข้อมูลที่จำเป็น (บังคับ)'),
                      subtitle: Text('ถอนได้เมื่อใช้เมนูลบข้อมูลทั้งหมด'),
                    ),
                    for (final e in purposeLabel.entries)
                      if (e.key != 'gov' || purposes!.containsKey('gov'))
                        SwitchListTile(
                          value: purposes![e.key] == true,
                          onChanged: (value) =>
                              change(_togglePurpose(e.key, value)),
                          title: Text(e.value),
                        ),
                    ListTile(
                      title: Text('ประวัติการให้ความยินยอม $history ครั้ง'),
                      dense: true,
                    ),
                  ],
                  _head('ข้อมูลของฉัน'),
                  ExpansionTile(
                    leading: const Icon(
                      Icons.smart_toy_outlined,
                      color: brandDark,
                    ),
                    title: Text('AI จำอะไรเกี่ยวกับฉัน (${memory.length})'),
                    children: [
                      if (memory.isEmpty)
                        const ListTile(title: Text('ยังไม่มี')),
                      for (final m in memory)
                        ListTile(
                          title: Text('${m['text']}'),
                          subtitle: Text(
                            m['source'] == 'ai' ? 'AI จำไว้' : 'คุณเพิ่มเอง',
                          ),
                          trailing: TextButton(
                            onPressed: () => change(_forget('${m['id']}')),
                            child: const Text('ลบ'),
                          ),
                        ),
                    ],
                  ),
                  ListTile(
                    title: const Text('ดูข้อมูลที่เก็บไว้'),
                    leading: const Icon(
                      Icons.description_outlined,
                      color: brandDark,
                    ),
                    onTap: _myData,
                  ),
                  ListTile(
                    title: const Text('ประกาศความเป็นส่วนตัว'),
                    leading: const Icon(Icons.lock_outline, color: brandDark),
                    onTap: () => showNotice(context, widget.app),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  ListTile _serverTile() => ListTile(
    title: const Text('ที่อยู่ server'),
    subtitle: Text(api.baseUrl),
    leading: const Icon(Icons.language_outlined, color: brandDark),
    trailing: const Icon(Icons.edit_outlined),
    onTap: () => editServer(context, widget.app, () {
      widget.app.resetConversations();
      widget.app.bump();
      setState(() {});
    }),
  );

  Future<void> _demoTools(List<_DemoCase> cases) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .88,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            _head('สำหรับสาธิต (DEMO)'),
            for (final scenario in cases)
              ListTile(
                title: Text(scenario.label),
                subtitle: Text(scenario.subtitle),
                leading: const Icon(Icons.science_outlined, color: brandDark),
                onTap: () {
                  Navigator.pop(sheet);
                  _openDemo(scenario);
                },
              ),
            for (final (id, label) in const [
              ('p1', 'สมชาย 65 ปี ยังไม่ได้เบี้ยผู้สูงอายุ'),
              ('p2', 'สุดา 28 ปี ถูกเลิกจ้าง หางาน'),
              ('p3', 'มานี 40 ปี อาชีพอิสระ รายได้จากทักษะ'),
              ('p4', 'วิชัย 45 ปี ถูกเลิกจ้าง นายจ้างค้างค่าจ้าง'),
              ('p5', 'นิด 32 ปี แม่เลี้ยงเดี่ยว ลูก 3 ขวบ'),
              ('p6', 'สมศักดิ์ 52 ปี ผู้พิการ มีบัตรสวัสดิการ'),
              ('p7', 'ต้น 20 ปี นักศึกษา หางานพาร์ตไทม์'),
              ('p8', 'ยายบุญมี 78 ปี ได้เบี้ยอยู่แล้ว อยากมีรายได้เสริม'),
            ])
              ListTile(
                title: Text('โหลดผู้ใช้ตัวอย่าง · $label'),
                leading: const Icon(Icons.person_outline, color: brandDark),
                onTap: () {
                  Navigator.pop(sheet);
                  _persona(id, label);
                },
              ),
            _serverTile(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AccountsSnapshot>(
        valueListenable: widget.app.accounts,
        builder: _buildMe,
      );

  Widget _buildMe(
    BuildContext context,
    AccountsSnapshot snapshot,
    Widget? child,
  ) {
    final demoCases = snapshot.demoEnabled
        ? _demoCases(snapshot.config)
        : const <_DemoCase>[];
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          BrandHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'บัญชี',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                _profileTile(snapshot),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null && error!.isNetwork)
                  OfflineCard(app: widget.app, onRetry: _load),
                _accounts(snapshot),
                _head('การตั้งค่า'),
                ValueListenableBuilder<bool>(
                  valueListenable: widget.app.largeText,
                  builder: (_, v, _) => SwitchListTile(
                    value: v,
                    onChanged: _largeText,
                    title: const Text('ตัวอักษรใหญ่'),
                    secondary: const Icon(Icons.text_fields, color: brandDark),
                  ),
                ),
                ListTile(
                  title: const Text('ความเป็นส่วนตัวและความยินยอม'),
                  subtitle: Text(
                    purposes?['ai'] == true
                        ? 'เปิดให้ AI ช่วยวิเคราะห์'
                        : 'จัดการข้อมูลและสิทธิ์ที่ให้ไว้',
                  ),
                  leading: const Icon(Icons.shield_outlined, color: brandDark),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _privacy,
                ),
                ListTile(
                  leading: const Icon(
                    Icons.insights_outlined,
                    color: brandDark,
                  ),
                  title: const Text('แผนรายได้'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IncomePlanScreen(app: widget.app),
                    ),
                  ),
                ),
                _head('ช่วยเหลือ'),
                ListTile(
                  leading: const Icon(
                    Icons.library_books_outlined,
                    color: brandDark,
                  ),
                  title: const Text('แหล่งข้อมูลของแอป'),
                  subtitle: const Text('ที่มาของโอกาสและประกาศ'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SourcesScreen(app: widget.app),
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('วิธีใช้แอป'),
                  leading: const Icon(Icons.help_outline, color: brandDark),
                  onTap: () => _info(
                    'ใช้แอปใน 3 ขั้น',
                    '1. กดปุ่ม AI หรือเช็คเงินเอง ตอบทีละข้อ\n2. ดูเงินที่น่าจะได้ ที่ยื่น และเอกสาร\n3. กดบันทึกเป็นแผน แล้วทำทีละขั้นในแท็บ แผนของฉัน',
                  ),
                ),
                ListTile(
                  title: const Text('รู้ทันมิจฉาชีพ'),
                  leading: const Icon(
                    Icons.verified_user_outlined,
                    color: brandDark,
                  ),
                  onTap: () => _info(
                    'สัญญาณเตือน',
                    '• ให้โอนเงินก่อน ค่ามัดจำ ค่าธรรมเนียม\n• ขอเลขบัตร รหัสผ่าน OTP ทางแชท\n• รายได้สูงผิดปกติ งานง่ายเกินจริง\n• เงินกู้คือหนี้ ไม่ใช่รายได้\nสงสัยโทรสายด่วนตำรวจไซเบอร์ 1441',
                  ),
                ),
                if (snapshot.demoEnabled)
                  ListTile(
                    title: const Text('สำหรับสาธิต (DEMO)'),
                    subtitle: const Text('ผู้ใช้ตัวอย่างและที่อยู่เซิร์ฟเวอร์'),
                    leading: const Icon(
                      Icons.science_outlined,
                      color: brandDark,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _demoTools(demoCases),
                  )
                else
                  _serverTile(),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'ลบข้อมูลทั้งหมด',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: _deleteAll,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ฉัน > แหล่งข้อมูลของแอป: every source the server uses, what kind it is, and its state (GET /v1/sources).
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
    if (p.startsWith('mock') || p.endsWith('_mock')) {
      return '🧪 ข้อมูลจำลอง รอต่อ API จริง';
    }
    if (s['direction'] == 'pull') return '🌐 ดึงจาก API จริง';
    if (p == 'official') return '🏛️ ลิงก์หน่วยงานรัฐ (ตรวจด้วยมือ)';
    return '📄 ${s['kind'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แหล่งข้อมูลของแอป')),
      body: error != null
          ? Center(child: Text(error!))
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final s in items!)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${s['name'] ?? s['provider']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${_kind(s)}\nสถานะ: ${s['state']}${s['itemCount'] != null ? ' · ${s['itemCount']} รายการ' : ''}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                Text(
                  'ข้อมูลจำลองแทนระบบที่ยังต่อไม่ได้ (ต้องมีข้อตกลงหรือ API key) ทุกรายการจากแหล่งนี้ติดป้าย DEMO / MOCK ในแอป',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
