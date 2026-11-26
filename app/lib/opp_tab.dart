import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'money.dart';
import 'opp_map.dart';

const oppGroups = {'all': 'ทั้งหมด', 'job': 'งาน', 'skill': 'ทักษะ', 'sell': 'ขายของ', 'money': 'เงิน/สิทธิ์'};

/// Money text for an opportunity: only numbers that came from the listing or an official source.
String oppMoney(Map<String, dynamic> o) {
  final m = o['money'] as Map<String, dynamic>;
  if (m['basis'] == 'none') return '${m['knownText'] ?? 'ไม่ทราบจำนวนเงิน'}';
  final min = m['min'], max = m['max'];
  String n(num x) => baht(x).replaceFirst('฿', '');
  final range = min is num && max is num && min != max ? '${n(min)}-${n(max)}' : n((min ?? max) as num);
  return '$range ${m['unit'] ?? ''} (${m['basis'] == 'official' ? 'ตามประกาศทางการ' : 'ตามประกาศ'})';
}

/// Tab ✨ โอกาส (ui-states.md S6): search + group chips + list. Map view is not in this Demo build.
class OppTab extends StatefulWidget {
  const OppTab({super.key, required this.app});
  final AppState app;
  @override
  State<OppTab> createState() => _OppTabState();
}

class _OppTabState extends State<OppTab> {
  final TextEditingController q = TextEditingController();
  Map<String, dynamic>? page;
  ApiException? error;
  bool mapView = false;

  @override
  void initState() {
    super.initState();
    widget.app.oppGroup.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.app.oppGroup.removeListener(_load);
    q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final g = widget.app.oppGroup.value;
    final query = <String, String>{'group': g, 'radiusKm': '50', 'limit': '100', if (q.text.trim().isNotEmpty) 'q': q.text.trim()};
    try {
      final r = await widget.app.api.get('/v1/opportunities?${Uri(queryParameters: query).query}');
      if (mounted) setState(() { page = r; error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ((page?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final g = widget.app.oppGroup.value;
    void open(Map<String, dynamic> o) => Navigator.push(context, MaterialPageRoute(builder: (_) => OppScreen(app: widget.app, opp: o)));
    return Scaffold(
      appBar: AppBar(title: const Text('โอกาส')),
      // One floating button switches list <-> map (navigation.md, ui-states.md S6).
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => mapView = !mapView),
        icon: Text(mapView ? '📋' : '🗺️', style: const TextStyle(fontSize: 18)),
        label: Text(mapView ? 'ดูรายการ' : 'ดูแผนที่'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(children: [
            TextField(
              controller: q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ค้นหา เช่น แม่บ้าน ขนม', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final e in oppGroups.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(e.value), selected: g == e.key, onSelected: (_) => widget.app.oppGroup.value = e.key),
                  ),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: mapView && page != null
              ? OppMap(items: items, onOpen: open, onShowList: () => setState(() => mapView = false))
              : _list(context, items, open),
        ),
      ]),
    );
  }

  Widget _list(BuildContext context, List<Map<String, dynamic>> items, void Function(Map<String, dynamic>) open) {
    final live = items.where((o) => (o['provenance'] as Map)['dataStatus'] == 'live').length;
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 80), children: [
          if (page != null && items.isNotEmpty)
            Text('${items.length} รายการ · ประกาศจริงจากแหล่งภายนอก $live รายการ · ที่เหลือเป็นตัวอย่าง (DEMO)', style: Theme.of(context).textTheme.bodySmall),
          if (error != null && error!.isNetwork) OfflineCard(app: widget.app, onRetry: _load),
          if (error != null && !error!.isNetwork) Text(error!.message),
          if (page == null && error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (page != null && items.isEmpty) ...[
            const Padding(padding: EdgeInsets.all(16), child: Text('ไม่พบรายการ', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final s in ((page!['suggestions'] as List?) ?? const []).cast<Map<String, dynamic>>())
              OutlinedButton(onPressed: () { q.clear(); widget.app.oppGroup.value = 'all'; _load(); }, child: Text('${s['label']}')),
          ],
          for (final o in items)
            Card(
              child: ListTile(
                title: Text('${o['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${o['organization'] ?? ''}\n${oppMoney(o)}'
                    '${(o['location'] as Map?)?['distanceKm'] is num ? ' · ${((o['location'] as Map)['distanceKm'] as num).toStringAsFixed(1)} กม.' : ''}'
                    '\n${dataLabel((o['provenance'] as Map)['dataStatus'] as String?)}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(o),
              ),
            ),
          if (page != null && (page!['hiddenSuspicious'] as num? ?? 0) > 0)
            Padding(padding: const EdgeInsets.all(8), child: Text('ซ่อนประกาศที่น่าสงสัยไว้ ${page!['hiddenSuspicious']} รายการ', style: Theme.of(context).textTheme.bodySmall)),
        ]),
    );
  }
}

/// Opportunity detail (ui-states.md S6b).
class OppScreen extends StatelessWidget {
  const OppScreen({super.key, required this.app, required this.opp});
  final AppState app;
  final Map<String, dynamic> opp;

  Future<void> _report(BuildContext context) async {
    const reasons = {'suspicious': 'น่าสงสัย / มิจฉาชีพ', 'wrong_info': 'ข้อมูลผิด', 'expired': 'ปิดรับแล้ว', 'other': 'อื่นๆ'};
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('รายงานประกาศนี้', style: TextStyle(fontWeight: FontWeight.bold))),
        for (final e in reasons.entries) ListTile(title: Text(e.value), onTap: () => Navigator.pop(context, e.key)),
      ])),
    );
    if (r == null || !context.mounted) return;
    try {
      await app.api.post('/v1/opportunities/${opp['id']}/reports', {'reason': r});
      if (context.mounted) toast(context, 'ขอบคุณ ส่งรายงานแล้ว');
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = opp['provenance'] as Map<String, dynamic>;
    final conditions = ((opp['conditions'] as List?) ?? const []).map((e) => '$e');
    final url = '${p['sourceUrl'] ?? ''}';
    return Scaffold(
      appBar: AppBar(title: const Text('รายละเอียด')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('${opp['title']}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          if (opp['organization'] != null) Text('${opp['organization']}'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [Chip(label: Text(oppGroups[opp['mapGroup']] ?? '${opp['mapGroup']}')), Chip(label: Text(dataLabel(p['dataStatus'] as String?)))]),
          Text(oppMoney(opp), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if ((opp['location'] as Map?)?['text'] != null) Text('📍 ${(opp['location'] as Map)['text']}'),
          const Divider(height: 24),
          if (conditions.isNotEmpty) ...[
            Text('เงื่อนไข', style: t.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            for (final c in conditions) Text('• $c'),
            const SizedBox(height: 8),
          ],
          Text('แหล่งข้อมูล: ${p['attribution'] ?? p['provider']}${p['ageDays'] is num ? ' · อัปเดต ${p['ageDays']} วันก่อน' : ''}', style: t.bodySmall),
          const SizedBox(height: 16),
          if (url.startsWith('http'))
            OutlinedButton(
              onPressed: () => openExternal(context, app, url: url, title: '${opp['title']}', opportunityId: '${opp['id']}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('ดูประกาศต้นทาง ↗'),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => saveToPlan(context, app, opportunityId: '${opp['id']}'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('＋ บันทึกไว้ในแผนของฉัน'),
          ),
          TextButton(onPressed: () => _report(context), child: const Text('รายงานประกาศนี้')),
          Text('แอปไม่รับประกันว่าจะได้งานหรือรายได้ ตรวจรายละเอียดกับผู้ประกาศก่อนสมัคร อย่าโอนเงินก่อนเริ่มงาน', style: t.bodySmall),
        ]),
      ),
    );
  }
}
