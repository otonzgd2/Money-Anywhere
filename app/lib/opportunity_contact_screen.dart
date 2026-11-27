import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'opp_tab.dart';

class OpportunityContactScreen extends StatefulWidget {
  const OpportunityContactScreen({super.key, required this.app, required this.opportunityId, required this.title});

  final AppState app;
  final String opportunityId, title;

  @override
  State<OpportunityContactScreen> createState() => _OpportunityContactScreenState();
}

class _OpportunityContactScreenState extends State<OpportunityContactScreen> {
  Map<String, dynamic>? opportunity;
  Uri? applicationUrl;
  String? fallbackReason;
  bool loading = true;
  bool opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final item = await widget.app.api.get('/v1/opportunities/${Uri.encodeComponent(widget.opportunityId)}');
      if (!mounted) return;
      final provenance = item['provenance'] as Map?;
      final uri = _realApplicationUrl(provenance);
      final isJob = item['mapGroup'] == 'job';
      final reachable = isJob && uri != null && await _canOpen(uri);
      if (!mounted) return;
      setState(() {
        opportunity = item;
        loading = false;
        applicationUrl = reachable ? uri : null;
        fallbackReason = uri == null ? 'รายการนี้ยังไม่มีลิงก์สมัครงานจริง' : 'เปิดลิงก์สมัครงานต้นทางไม่ได้';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        fallbackReason = error.status == 404 ? 'ไม่พบประกาศต้นทางแล้ว' : 'โหลดประกาศต้นทางไม่ได้ในขณะนี้';
      });
    }
  }

  Uri? _realApplicationUrl(Map? provenance) {
    if (provenance == null || provenance['dataStatus'] == 'mock') return null;
    final uri = Uri.tryParse(provenance['sourceUrl']?.toString().trim() ?? '');
    if (uri == null || !{'https', 'http'}.contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    if ({'example.org', 'example.com', 'example.net'}.contains(uri.host) || uri.host.endsWith('.example')) return null;
    return uri;
  }

  Future<bool> _canOpen(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final response = await client.getUrl(uri).then((request) => request.close()).timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Exception {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openApplication(Uri uri) async {
    setState(() => opening = true);
    await openExternal(context, widget.app, url: uri.toString(), title: widget.title, opportunityId: widget.opportunityId,
      onUnavailable: () => setState(() {
        applicationUrl = null;
        fallbackReason = 'เปิดลิงก์สมัครงานต้นทางไม่ได้';
      }));
    if (mounted) setState(() => opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final item = opportunity;
    if (item != null && item['mapGroup'] != 'job') return OppScreen(app: widget.app, opp: item);

    final url = applicationUrl;
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ข้อมูลสมัครงาน')),
      body: SafeArea(
        child: loading ? const Center(child: CircularProgressIndicator(semanticsLabel: 'กำลังตรวจลิงก์สมัครงาน')) : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.title, style: theme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (url != null) ...[
              if (item?['organization'] case final String organization) Text(organization),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.language), title: const Text('ประกาศต้นทาง'), subtitle: Text(url.host)),
              FilledButton.icon(
                onPressed: opening ? null : () => _openApplication(url),
                icon: const Icon(Icons.open_in_new), label: const Text('เปิดหน้าสมัครงาน'),
              ),
            ] else ...[
              Align(alignment: Alignment.centerLeft, child: Chip(label: const Text('DEMO / MOCK'), backgroundColor: Theme.of(context).colorScheme.secondaryContainer)),
              Text(fallbackReason ?? 'ยังไม่มีลิงก์สมัครงานที่เปิดได้'),
              const Text('ข้อมูลตัวอย่างสำหรับดูขั้นตอนการสมัคร'),
              const SizedBox(height: 12),
              const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.person_outline), title: Text('ผู้ติดต่อ (ตัวอย่าง)'), subtitle: Text('ฝ่ายบุคคล · apply@example.org')),
              const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.description_outlined), title: Text('สิ่งที่ควรเตรียม'), subtitle: Text('ประวัติย่อและข้อมูลสำหรับติดต่อกลับ')),
              const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.checklist), title: Text('ขั้นตอนตัวอย่าง'), subtitle: Text('กรอกใบสมัครกับผู้ประกาศ แนบประวัติย่อ แล้วติดตามผลการนัดสัมภาษณ์')),
            ],
          ],
        ),
      ),
    );
  }
}
