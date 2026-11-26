import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'money.dart';
import 'route_screen.dart';

/// Quick money check: one question at a time via POST /v1/money/preview (nothing stored, no consent yet).
/// Stops as soon as there is a sourced amount to show; the rest can be asked afterwards.
class QuickCheckScreen extends StatefulWidget {
  const QuickCheckScreen({super.key, required this.app, this.knownFacts = const {}, this.consented = false});
  final AppState app;
  Api get api => app.api;

  /// Answers the person already gave (chat or an earlier check). Never asked again.
  final Map<String, Object?> knownFacts;

  /// Consent already recorded: each new answer is saved right away, and the route opens without asking again.
  final bool consented;

  @override
  State<QuickCheckScreen> createState() => _QuickCheckScreenState();
}

class _QuickCheckScreenState extends State<QuickCheckScreen> {
  final Map<String, Object?> facts = {};
  final Set<String> skipped = {};
  final TextEditingController numberInput = TextEditingController();
  Map<String, dynamic>? preview;
  String? error;
  bool loading = true, keepAsking = false;

  @override
  void initState() {
    super.initState();
    facts.addAll(widget.knownFacts);
    // Coming back with answers already given: go straight to the questions still open.
    keepAsking = widget.knownFacts.isNotEmpty;
    _refresh();
  }

  @override
  void dispose() {
    numberInput.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final r = await widget.api.post('/v1/money/preview', {'facts': facts});
      setState(() { preview = r; error = null; loading = false; });
    } on ApiException catch (e) {
      setState(() { error = e.message; loading = false; });
    }
  }

  void _answer(Map<String, dynamic> q, String raw) {
    final v = toFactValue(q, raw);
    if (v == null) return;
    facts[q['fact'] as String] = v;
    numberInput.clear();
    if (widget.consented) {
      widget.api.patch('/v1/me/facts', {q['fact'] as String: v}).then((_) => widget.app.bump()).catchError((_) {});
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เช็คเงินที่ควรได้')),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (loading && preview == null) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [Text(error!), const SizedBox(height: 12), FilledButton(onPressed: _refresh, child: const Text('ลองใหม่'))]),
      );
    }
    final items = (preview!['items'] as List).cast<Map<String, dynamic>>();
    final ranked = rankMoney(items);
    final q = nextQuestion(items, skipped);
    final hasAnswer = ranked.isNotEmpty && tierOf(ranked.first) <= 1;
    if (q != null && (!hasAnswer || keepAsking)) return _question(context, q);
    return _result(context, ranked, items, q);
  }

  Widget _question(BuildContext context, Map<String, dynamic> q) {
    final t = Theme.of(context).textTheme;
    final options = (q['options'] as List?)?.cast<String>() ?? const <String>[];
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('ตอบเท่าที่รู้ ข้ามได้ทุกข้อ', style: t.bodySmall),
      const SizedBox(height: 6),
      Text('${q['question']}', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      if (q['type'] == 'number')
        Row(children: [
          Expanded(child: TextField(controller: numberInput, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'เช่น 12000', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => _answer(q, numberInput.text), child: const Text('ตกลง')),
        ])
      else
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
              onPressed: () => _answer(q, o),
              child: Text(o, style: const TextStyle(fontSize: 16)),
            ),
          ),
      TextButton(onPressed: () => setState(() => skipped.add(q['fact'] as String)), child: const Text('ไม่แน่ใจ ข้ามข้อนี้')),
      const SizedBox(height: 8),
      Text('🔒 ยังไม่บันทึกอะไร คำตอบส่งไปคำนวณแล้วทิ้ง จนกว่าคุณจะกด "ดูวิธีไปรับเงิน" ไม่ถามชื่อ เลขบัตร หรือเลขบัญชี', style: t.bodySmall),
    ]);
  }

  Widget _result(BuildContext context, List<Map<String, dynamic>> ranked, List<Map<String, dynamic>> items, Map<String, dynamic>? q) {
    final t = Theme.of(context).textTheme;
    final top = ranked.where((i) => tierOf(i) <= 3).toList();
    final have = items.where((i) => i['alreadyReceiving'] == true).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (top.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(have.isEmpty ? 'จากคำตอบนี้ ยังไม่พบเงินที่น่าจะมีสิทธิ์' : 'จากคำตอบนี้ ยังไม่พบเงินก้อนใหม่',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
        )
      else ...[
        Text('สิ่งแรกที่ควรทำ', style: t.labelLarge),
        _MoneyCard(item: top.first, primary: true, onOpen: () => _openRoute(top.first)),
        if (top.length > 1) ...[
          const SizedBox(height: 6),
          Text('ถ้าทางแรกไม่ได้ ลองเช็คทางนี้', style: t.labelLarge),
          _MoneyCard(item: top[1], primary: false, onOpen: () => _openRoute(top[1])),
        ],
      ],
      for (final h in have)
        Card(
          color: const Color(0xFFF8FAFC),
          child: ListTile(
            title: Text('💡 ได้อยู่แล้ว: ${h['title']}'),
            subtitle: Text('ตรวจยอดให้ครบ ${(h['amount'] as Map)['value'] is num ? baht((h['amount'] as Map)['value'] as num) : ''} · ${(h['amount'] as Map)['note'] ?? ''}'),
          ),
        ),
      if (q != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton(onPressed: () => setState(() => keepAsking = true), child: const Text('เช็คเพิ่ม: อาจมีเงินก้อนอื่นอีก')),
        ),
      const SizedBox(height: 12),
      Text('ผลนี้เป็นการตรวจเบื้องต้นจากเกณฑ์ที่ประกาศและคำตอบของคุณ ยังไม่ได้ยืนยันกับหน่วยงาน แอปไม่ยื่นแทนคุณและไม่รับประกันว่าจะได้เงิน', style: t.bodySmall),
    ]);
  }

  void _openRoute(Map<String, dynamic> item) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RouteScreen(app: widget.app, moneyId: item['id'] as String, facts: facts)));
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.item, required this.primary, required this.onOpen});
  final Map<String, dynamic> item;
  final bool primary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final amount = item['amount'] as Map<String, dynamic>;
    final value = amount['value'];
    return Card(
      shape: primary ? RoundedRectangleBorder(side: const BorderSide(color: Color(0xFF0E9F6E), width: 2), borderRadius: BorderRadius.circular(14)) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item['icon'] ?? ''} ${item['title']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (value is num)
            Text('${baht(value)} ${amount['unit'] ?? ''}', style: TextStyle(fontSize: primary ? 30 : 20, fontWeight: FontWeight.w800))
          else
            const Text('ยังไม่ทราบยอด', style: TextStyle(fontWeight: FontWeight.bold)),
          if (amount['note'] != null) Text('${amount['note']}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            Chip(label: Text(statusLabel[item['status']] ?? '${item['status']}')),
            Chip(label: Text(dataLabel(item['dataStatus'] as String?))),
          ]),
          for (final r in (item['reasons'] as List? ?? const []).cast<Map<String, dynamic>>())
            Text('${r['ok'] == null ? '❔' : r['ok'] == true ? '✅' : '❌'} ${r['text']}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          primary
              ? FilledButton(onPressed: onOpen, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('ดูวิธีไปรับเงิน: ที่ไหน เอาอะไรไป'))
              : TextButton(onPressed: onOpen, child: const Text('ดูรายละเอียด ›')),
        ]),
      ),
    );
  }
}

// RouteScreen lives in route_screen.dart.
