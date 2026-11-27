import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'job_application.dart';
import 'money.dart';
import 'opportunity_assessment.dart';
import 'opportunity_catalog.dart';

class OppScreen extends StatefulWidget {
  const OppScreen({
    super.key,
    required this.app,
    required String opportunityId,
    this.districtCode,
    this.summary,
  }) : id = opportunityId,
       isMoney = false,
       mockAssessment = false;

  const OppScreen.money({
    super.key,
    required this.app,
    required String moneyId,
    this.summary,
    this.mockAssessment = false,
  }) : id = moneyId,
       isMoney = true,
       districtCode = null;

  final AppState app;
  final String id;
  final String? districtCode;
  final bool isMoney, mockAssessment;
  final Map<String, dynamic>? summary;

  @override
  State<OppScreen> createState() => _OppScreenState();
}

class _OppScreenState extends State<OppScreen> {
  Map<String, dynamic>? item;
  bool loading = true, unavailable = false, loadFailed = false;
  bool saved = false,
      saving = false,
      opening = false,
      sourceUnavailable = false;
  int tasksRequest = 0;

  String get opportunityPath =>
      '/v1/opportunities/${Uri.encodeComponent(widget.id)}';

  @override
  void initState() {
    super.initState();
    widget.app.changed.addListener(_refreshSaved);
    _load();
    _refreshSaved();
  }

  @override
  void dispose() {
    widget.app.changed.removeListener(_refreshSaved);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadFailed = false;
    });
    try {
      final latest = await widget.app.api.get(
        widget.isMoney
            ? '/v1/money/${Uri.encodeComponent(widget.id)}'
            : opportunityPath,
      );
      if (!mounted) return;
      setState(() {
        unavailable = !widget.isMoney && opportunityExpired(latest);
        item = widget.isMoney && widget.mockAssessment
            ? {...latest, ...?widget.summary}
            : latest;
        loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        unavailable = error.status == 404 || error.status == 410;
        loadFailed = !unavailable;
        item ??= widget.summary;
        loading = false;
      });
    }
  }

  Future<void> _refreshSaved() async {
    final request = ++tasksRequest;
    try {
      final tasks = itemsOf(await widget.app.api.get('/v1/tasks'));
      if (!mounted || request != tasksRequest || saving) return;
      final key = widget.isMoney ? 'moneyId' : 'opportunityId';
      setState(() => saved = tasks.any((task) => task[key] == widget.id));
    } on ApiException {
      // The save endpoint also returns an existing task for the same ID.
    }
  }

  Future<void> _save() async {
    if (saving || saved) return;
    setState(() => saving = true);
    try {
      final ok = await saveToPlan(
        context,
        widget.app,
        moneyId: widget.isMoney ? widget.id : null,
        opportunityId: widget.isMoney ? null : widget.id,
        districtCode: widget.districtCode,
      );
      if (ok && mounted) {
        tasksRequest++;
        setState(() => saved = true);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _openJob(Map data, String title) async {
    setState(() {
      opening = true;
      sourceUnavailable = false;
    });
    try {
      final source = await reachableJobApplicationUrl(data);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (source != null) {
        final opened = await openExternal(
          context,
          widget.app,
          url: source.toString(),
          title: title,
          opportunityId: widget.id,
          showError: false,
        );
        if (opened || !mounted || ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
      }
      setState(() => sourceUnavailable = true);
      if (widget.app.allowsDemo) {
        await openExternal(
          context,
          widget.app,
          url: jobApplicationDemoUrl(widget.app.api.baseUrl, title),
          title: title,
          askAfterReturn: false,
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> _report() async {
    const reasons = {
      'suspicious': 'น่าสงสัย / มิจฉาชีพ',
      'wrong_info': 'ข้อมูลผิด',
      'expired': 'ปิดรับแล้ว',
      'other': 'อื่นๆ',
    };
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('รายงานประกาศนี้')),
            for (final entry in reasons.entries)
              ListTile(
                title: Text(entry.value),
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await widget.app.api.post('$opportunityPath/reports', {'reason': reason});
      if (mounted) toast(context, 'ขอบคุณ ส่งรายงานแล้ว');
    } on ApiException catch (error) {
      if (mounted) toast(context, error.message);
    }
  }

  void _returnToOpportunities() {
    widget.app.goTab(1);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final data = item;
    return Scaffold(
      appBar: AppBar(title: const Text('รายละเอียด')),
      bottomNavigationBar: !loading && !unavailable && data != null
          ? _actions(data)
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (loading)
              const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังโหลดรายละเอียด',
                ),
              )
            else if (unavailable) ...[
              const Text('ไม่พบรายการนี้หรือรายการหมดอายุแล้ว'),
              OutlinedButton(
                onPressed: _returnToOpportunities,
                child: const Text('กลับไปโอกาส'),
              ),
            ] else ...[
              if (loadFailed) ...[
                const Text('โหลดรายละเอียดล่าสุดไม่สำเร็จ'),
                OutlinedButton(onPressed: _load, child: const Text('ลองใหม่')),
              ],
              if (data != null) ..._details(context, data),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _details(BuildContext context, Map<String, dynamic> data) {
    final t = Theme.of(context).textTheme;
    final category = widget.isMoney
        ? OpportunityCategory.forMoney(widget.id)
        : OpportunityCategory.of(data);
    final color = category?.color ?? Theme.of(context).colorScheme.primary;
    final title = '${data['title'] ?? 'รายละเอียด'}';
    final provenance = (data['provenance'] as Map?) ?? const {};
    final dataStatus = data['dataStatus'] ?? provenance['dataStatus'];
    final source = provenance['attribution'] ?? provenance['provider'];
    final checked = data['checkedAt'] ?? provenance['linkCheckedAt'];
    final updated = provenance['updatedAt'];
    final expires = data['expiresAt'] ?? provenance['expiresAt'];
    final url = data['sourceUrl'] ?? provenance['sourceUrl'];
    final locations = OpportunityLocation.of(data);
    final matching = locations.where(
      (location) => location.districtCode == widget.districtCode,
    );
    final shown = widget.districtCode != null && matching.isNotEmpty
        ? matching
        : locations;
    final isJob = category?.isJob ?? data['mapGroup'] == 'job';
    final mock = widget.mockAssessment || dataStatus == 'mock';
    final organization = data['organization'] ?? data['payer'];
    final conditions = widget.isMoney
        ? [
            for (final reason
                in (data['reasons'] as List? ?? const []).whereType<Map>())
              if (reason['text'] != null) '${reason['text']}',
          ]
        : (data['conditions'] as List? ?? const [])
              .whereType<String>()
              .toList();

    return [
      Card(
        color: Color.alphaBlend(
          color.withValues(alpha: .09),
          Theme.of(context).colorScheme.surface,
        ),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (category != null)
                    Chip(
                      backgroundColor: color,
                      side: BorderSide.none,
                      label: Text(
                        category.label,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  if (mock) const DemoPill(),
                ],
              ),
              Text(
                title,
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (organization != null) Text('$organization'),
              const SizedBox(height: 8),
              if (benefitStatusLabel[data['status']] case final String status
                  when widget.isMoney)
                Text(status),
              Text(
                widget.isMoney ? benefitAmount(data) : oppMoney(data),
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (widget.isMoney &&
                  data['amount'] is Map &&
                  (data['amount'] as Map)['note'] != null)
                Text('${(data['amount'] as Map)['note']}'),
            ],
          ),
        ),
      ),
      if (data['description'] case final String description)
        ..._section(t, 'รายละเอียดประกาศ', [Text(description)]),
      if (conditions.isNotEmpty)
        ..._section(t, 'เงื่อนไข', [
          for (final line in conditions) Text('• $line'),
        ]),
      if (shown.any(
        (location) =>
            location.districtName != null ||
            location.address != null ||
            location.text != null ||
            location.travelInfo != null ||
            location.point != null,
      ))
        ..._section(t, 'พื้นที่และการเดินทาง', [
          for (final location in shown) ...[
            if (location.districtName case final district?)
              Text(district.startsWith('เขต') ? district : 'เขต$district'),
            if ((location.address ?? location.text) case final address?)
              Text(address),
            if (location.travelInfo case final travel?) Text(travel),
            if (location.point case final point?)
              Text('พิกัด ${point.latitude}, ${point.longitude}'),
          ],
        ]),
      if (expires != null) ..._section(t, 'วันหมดอายุ', [Text(_date(expires))]),
      if (data['contacts'] is List || data['channels'] is List)
        ..._section(t, 'ช่องทางติดต่อ', [
          for (final contact in (data['contacts'] as List? ?? const []))
            if (contact is String)
              Text(contact)
            else if (contact is Map && contact['label'] is String) ...[
              Text(contact['label'] as String),
              if (contact['instructions'] case final String instructions)
                Text(instructions),
            ],
          for (final channel
              in (data['channels'] as List? ?? const []).whereType<Map>()) ...[
            if (channel['title'] != null) Text('${channel['title']}'),
            if (channel['detail'] != null) Text('${channel['detail']}'),
            if (channel['url'] case final String link)
              _sourceLink(
                link,
                '${channel['title'] ?? title}',
                'เปิดช่องทางติดต่อ',
              ),
          ],
        ]),
      if (source != null ||
          checked != null ||
          updated != null ||
          data['sources'] is List)
        ..._section(t, 'แหล่งข้อมูล', [
          if (source != null) Text('$source'),
          if (!mock && dataStatus is String) Text(dataLabel(dataStatus)),
          if (checked != null)
            Text('ตรวจล่าสุด ${_date(checked)}')
          else if (updated != null)
            Text('อัปเดตล่าสุด ${_date(updated)}'),
          for (final entry
              in (data['sources'] as List? ?? const []).whereType<Map>()) ...[
            if (entry['title'] != null)
              Text(
                '${entry['title']}${entry['checkedAt'] == null ? '' : ' · ตรวจล่าสุด ${_date(entry['checkedAt'])}'}',
              ),
            if (entry['url'] case final String link)
              _sourceLink(
                link,
                '${entry['title'] ?? title}',
                'เปิดแหล่งข้อมูล',
              ),
          ],
        ]),
      if (!isJob && url is String && !mock)
        _sourceLink(url, title, 'ดูประกาศต้นทาง'),
      if (!widget.isMoney)
        TextButton(onPressed: _report, child: const Text('รายงานประกาศนี้')),
    ];
  }

  Widget _actions(Map<String, dynamic> data) {
    final provenance = (data['provenance'] as Map?) ?? const {};
    final isJob =
        !widget.isMoney &&
        (OpportunityCategory.of(data)?.isJob ?? data['mapGroup'] == 'job');
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isJob) ...[
                OutlinedButton.icon(
                  onPressed: opening
                      ? null
                      : () => _openJob({
                          ...provenance,
                          'sourceUrl':
                              data['sourceUrl'] ?? provenance['sourceUrl'],
                          'dataStatus':
                              data['dataStatus'] ?? provenance['dataStatus'],
                        }, '${data['title']}'),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(
                    opening ? 'กำลังเปิดประกาศต้นทาง' : 'รายละเอียดงาน',
                  ),
                ),
                if (sourceUnavailable)
                  Text(
                    widget.app.allowsDemo
                        ? 'เปิดประกาศต้นทางไม่ได้ มีหน้าตัวอย่าง DEMO / MOCK ให้ดู'
                        : 'เปิดประกาศต้นทางไม่ได้ ลองใหม่ได้',
                  ),
              ],
              FilledButton(
                onPressed: saved || saving ? null : _save,
                child: Text(
                  saved
                      ? 'บันทึกแล้ว'
                      : saving
                      ? 'กำลังบันทึก'
                      : 'บันทึกไว้ในแผนของฉัน',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceLink(String url, String title, String label) => TextButton.icon(
    onPressed: () => openExternal(
      context,
      widget.app,
      url: url,
      title: title,
      askAfterReturn: false,
    ),
    icon: const Icon(Icons.open_in_new),
    label: Text(label),
  );

  List<Widget> _section(
    TextTheme theme,
    String name,
    List<Widget> children,
  ) => [
    const SizedBox(height: 16),
    Text(name, style: theme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 4),
    ...children,
  ];

  String _date(Object value) => '$value'.split('T').first;
}
