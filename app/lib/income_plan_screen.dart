import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'money.dart';
import 'money_check.dart';
import 'opp_tab.dart';
import 'profile_screen.dart';
import 'thang_rot_theme.dart';
import 'route_screen.dart';

/// แผนรายได้ (ui-states.md S11): "I want X baht a month" -> GET /v1/plans/goal. Shows every part with its
/// range and where the number came from, the total, the gap, and what is still unknown. Never a promise.
class IncomePlanScreen extends StatefulWidget {
  const IncomePlanScreen({super.key, required this.app, this.target});
  final AppState app;
  final int? target;
  @override
  State<IncomePlanScreen> createState() => _IncomePlanScreenState();
}

const _kindIcon = {'benefit': '💰', 'job': '💼', 'skill': '🛠️'};
const _kindLabel = {
  'benefit': 'เงินจากรัฐ',
  'job': 'งาน',
  'skill': 'รายได้จากทักษะ',
};
const _sourceLabel = {
  'official': 'อัตราทางการ',
  'listing': 'ตามประกาศ',
  'estimate': 'ประมาณการ',
  'none': 'ไม่มีตัวเลข',
};

String _range(List r) => r[0] == r[1]
    ? baht(r[0] as num)
    : '${baht(r[0] as num)}-${baht(r[1] as num).replaceFirst('฿', '')}';

class _IncomePlanScreenState extends State<IncomePlanScreen> {
  final TextEditingController target = TextEditingController();
  Map<String, dynamic>? plan;
  String? error;
  bool busy = false;
  Api get api => widget.app.api;

  @override
  void initState() {
    super.initState();
    if (widget.target != null) {
      target.text = '${widget.target}';
      _run();
    } else {
      _fromProfile();
    }
  }

  @override
  void dispose() {
    target.dispose();
    super.dispose();
  }

  Future<void> _fromProfile() async {
    try {
      final p = await api.get('/v1/me/profile');
      if (p['incomeGoalPerMonth'] is num) {
        target.text = '${(p['incomeGoalPerMonth'] as num).round()}';
        await _run();
      }
    } on ApiException {
      // no profile yet: the person types a goal
    }
  }

  Future<void> _run() async {
    final n = int.tryParse(target.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n == null || n <= 0) {
      setState(() => error = 'ใส่จำนวนเงินต่อเดือน เช่น 10000');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await api.get('/v1/plans/goal?target=$n');
      setState(() {
        plan = r;
        busy = false;
      });
    } on ApiException catch (e) {
      setState(() {
        error = e.message;
        busy = false;
      });
    }
  }

  Future<void> _open(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    widget.app.bump();
    await _run();
  }

  Future<void> _openAction(Map<String, dynamic> part) async {
    final a = part['action'] as Map?;
    if (a == null) return;
    if (a['type'] == 'money_route') {
      return _open(RouteScreen(app: widget.app, moneyId: '${a['id']}'));
    }
    if (a['type'] == 'opportunity') {
      return _open(OppScreen(app: widget.app, opportunityId: '${a['id']}'));
    }
  }

  void _missing(String id) {
    if (id == 'money_check') {
      _open(QuickCheckScreen(app: widget.app, consented: true));
    }
    if (id == 'skills' || id == 'hours') _open(ProfileScreen(app: widget.app));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = plan;
    return Scaffold(
      appBar: AppBar(title: const Text('แผนรายได้')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'อยากได้เดือนละเท่าไหร่',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: target,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _run(),
                    decoration: const InputDecoration(
                      labelText: 'รายได้เป้าหมาย (บาท/เดือน)',
                      hintText: 'เช่น 10000',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: busy ? null : _run,
                    child: const Text('วางแผน'),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (p != null && !busy) ...[
            const SizedBox(height: 14),
            Card(
              color: p['reach'] == 'likely'
                  ? const Color(0xFFECFDF5)
                  : p['reach'] == 'maybe'
                  ? const Color(0xFFFFFBEB)
                  : const Color(0xFFFEF2F2),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'รวมประมาณ ${_range(p['total'] as List)} ต่อเดือน',
                      style: const TextStyle(
                        color: brandDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(switch (p['reach']) {
                      'likely' =>
                        'ถึงเป้า ${baht(p['target'] as num)} ถ้าทำตามแผน',
                      'maybe' =>
                        'อาจถึงเป้า ${baht(p['target'] as num)} ถ้าได้ช่วงบน',
                      _ => 'ยังขาดจากเป้าอีกราว ${baht(p['gap'] as num)}',
                    }),
                  ],
                ),
              ),
            ),
            for (final part
                in ((p['parts'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>())
              Card(
                child: ListTile(
                  leading: Text(
                    _kindIcon[part['kind']] ?? '•',
                    style: const TextStyle(fontSize: 26),
                  ),
                  title: Text(
                    '${part['title']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    [
                      '${_range(part['net'] as List)} ต่อเดือน · ${_kindLabel[part['kind']]}',
                      '${_sourceLabel[part['numberSource']] ?? part['numberSource']} · ${dataLabel(part['dataStatus'] as String?)}',
                      if ((part['matched'] as List?)?.isNotEmpty == true)
                        'ตรงทักษะ: ${(part['matched'] as List).join(', ')}',
                      ...((part['assumptions'] as List?) ?? const []).map(
                        (a) => 'สมมติ: $a',
                      ),
                      '${part['why']}',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing:
                      part['action'] != null &&
                          (part['action'] as Map)['type'] != 'idea'
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: () => _openAction(part),
                ),
              ),
            if (((p['parts'] as List?) ?? const []).isEmpty)
              const Card(
                child: ListTile(title: Text('ยังไม่มีทางที่คิดเป็นตัวเลขได้')),
              ),
            for (final m
                in ((p['missing'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>())
              ListTile(
                leading: const Text('❔', style: TextStyle(fontSize: 22)),
                title: Text('${m['text']}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _missing('${m['id']}'),
              ),
            const SizedBox(height: 8),
            Text('${p['note']}', style: t.bodySmall),
          ],
        ],
      ),
    );
  }
}
