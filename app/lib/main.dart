import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat.dart';
import 'money.dart';
import 'money_check.dart';

void main() => runApp(MoneyAnywhereApp(api: Api()));

class MoneyAnywhereApp extends StatelessWidget {
  const MoneyAnywhereApp({super.key, required this.api});
  final Api api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Money Anywhere',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E9F6E)), useMaterial3: true),
      home: WelcomeScreen(api: api),
    );
  }
}

/// Money-first home (docs/design/navigation.md). Before any answer: the big AI button leads, the manual check follows.
/// After answers: the result and the plan come first, the AI button continues the same chat, and the manual
/// check only offers the questions that are still open (it disappears when nothing is left to ask).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.api});
  final Api api;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final ChatSession chat = ChatSession();
  Map<String, Object?> facts = {};
  Map<String, dynamic>? overview;
  List<Map<String, dynamic>> tasks = [];
  bool consented = false;

  Api get api => widget.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reload what the person already has. Errors keep the first-time home (the server may be off).
  Future<void> _load() async {
    try {
      final f = (await api.get('/v1/me/facts')).cast<String, Object?>();
      final c = await api.get('/v1/me/consents');
      final current = c['current'] as Map<String, dynamic>?;
      final ok = current != null && (current['purposes'] as Map?)?['core'] == true;
      Map<String, dynamic>? m;
      var t = <Map<String, dynamic>>[];
      if (f.isNotEmpty) m = await api.get('/v1/money');
      if (ok) t = ((await api.get('/v1/tasks'))['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() { facts = f; overview = m; tasks = t; consented = ok; });
    } on ApiException {
      // keep what is shown
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = ((overview?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final found = rankMoney(items).where((i) => tierOf(i) <= 3).toList();
    final openQuestions = items.where((i) => i['status'] == 'need').length;
    final started = facts.isNotEmpty || tasks.isNotEmpty || chat.started;
    final active = tasks.where((x) => x['status'] == 'active').toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFFFEDD5), borderRadius: BorderRadius.circular(10)),
                  child: const Text('DEMO / MOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9A3412))),
                ),
              ),
              const SizedBox(height: 8),
              if (!started) ...[
                const Text('💸', textAlign: TextAlign.center, style: TextStyle(fontSize: 44)),
                Text('เงินฉันอยู่ไหน?', textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('ตอบไม่กี่ข้อ รู้เลยว่ามีเงินก้อนไหนที่ควรได้ ได้เท่าไหร่ และต้องไปเอาที่ไหน', textAlign: TextAlign.center, style: t.bodyMedium),
                const SizedBox(height: 18),
              ] else ...[
                Text('เงินของฉัน', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _Summary(overview: overview, found: found, onOpen: (i) => _open(RouteScreen(api: api, moneyId: i['id'] as String, facts: facts, consented: consented))),
                if (tasks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('📋 แผนของฉัน (${tasks.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        for (final x in (active.isNotEmpty ? active : tasks).take(3))
                          Text('• ${x['title']} · ทำแล้ว ${x['doneCount'] ?? 0}/${(x['steps'] as List?)?.length ?? 0} ขั้น'),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
              ],
              _AiHero(
                title: chat.started ? 'คุยกับ AI ต่อ' : 'ให้ AI หาเงินให้ฉัน',
                subtitle: chat.started
                    ? 'คุยต่อจากเดิม ถามได้ เช่น ต้องทำอะไรต่อ ขอลิงก์ติดต่อ เอกสารที่ยังขาด'
                    : 'กดครั้งเดียว AI ถามทีละข้อ แล้วพาไปจนรู้ว่าต้องไปรับเงินที่ไหน เอาอะไรไป',
                button: chat.started ? 'คุยต่อ ›' : 'เริ่มคุยเลย ›',
                showConsent: !chat.started,
                onTap: () => _open(ChatScreen(api: api, session: chat)),
              ),
              // Manual check: first time = full check; later = only what is still open; nothing open = hidden.
              if (!started || openQuestions > 0) ...[
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    minVerticalPadding: 14,
                    leading: const Text('💰', style: TextStyle(fontSize: 30)),
                    title: Text(started ? 'ตอบเพิ่มอีก $openQuestions เรื่อง อาจเจอเงินก้อนอื่น' : 'เช็คเงินที่ควรได้ เอง',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(started
                        ? 'ไม่ใช้ AI · ถามเฉพาะข้อที่ยังไม่ได้ตอบ'
                        : 'ไม่ใช้ AI · เบี้ยผู้สูงอายุ เงินว่างงาน เงินเลี้ยงดูเด็ก เบี้ยความพิการ คืนภาษี ค่าจ้างค้าง'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(QuickCheckScreen(api: api, knownFacts: facts, consented: consented)),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('แอปไม่รับประกันว่าจะได้เงินหรือได้งาน ผลเป็นการตรวจเบื้องต้นจากเกณฑ์ที่ประกาศ ต้องยืนยันกับหน่วยงานทางการ',
                  textAlign: TextAlign.center, style: t.bodySmall),
              const SizedBox(height: 6),
              Text('server: ${api.baseUrl}', textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.overview, required this.found, required this.onOpen});
  final Map<String, dynamic>? overview;
  final List<Map<String, dynamic>> found;
  final void Function(Map<String, dynamic>) onOpen;

  @override
  Widget build(BuildContext context) {
    final s = (overview?['summary'] as Map?) ?? const {};
    final monthly = s['monthly'] is num ? s['monthly'] as num : 0;
    final once = s['once'] is num ? s['once'] as num : 0;
    return Card(
      shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFF0E9F6E), width: 2), borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (monthly > 0 || once > 0) ...[
            const Text('เงินที่น่าจะได้ (จากคำตอบของคุณ)'),
            if (monthly > 0) Text('${baht(monthly)} บาท/เดือน', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            if (once > 0) Text('${baht(once)} บาท ครั้งเดียว', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(s['allVerified'] == true ? 'ยืนยันจากหน่วยงาน' : 'ประมาณจากเกณฑ์ที่ประกาศ ยังไม่ยืนยันกับหน่วยงาน',
                style: Theme.of(context).textTheme.bodySmall),
          ] else
            const Text('ยังไม่พบเงินที่นับยอดได้ ลองตอบเพิ่ม หรือถาม AI', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final i in found.take(4))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Text('${i['icon'] ?? '💰'}', style: const TextStyle(fontSize: 22)),
              title: Text('${i['title']}'),
              subtitle: Text('${statusLabel[i['status']] ?? i['status']} · ${dataLabel(i['dataStatus'] as String?)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(i),
            ),
        ]),
      ),
    );
  }
}

class _AiHero extends StatelessWidget {
  const _AiHero({required this.onTap, required this.title, required this.subtitle, required this.button, required this.showConsent});
  final VoidCallback onTap;
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
          child: Column(
            children: [
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
                const Text('กด = ยืนยันว่าอายุ 20 ปีขึ้นไป และยินยอมให้ส่งคำตอบ (ไม่มีชื่อ ไม่มีเลขบัตร) ให้ AI ช่วยวิเคราะห์ ถอนได้ทุกเมื่อ',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
