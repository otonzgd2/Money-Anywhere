import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'job_application.dart';
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
  String? loadError;
  bool loading = true;
  bool opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final item = await widget.app.api.get('/v1/opportunities/${Uri.encodeComponent(widget.opportunityId)}');
      if (!mounted) return;
      if (item['mapGroup'] != 'job') {
        setState(() {
          opportunity = item;
          loading = false;
        });
        return;
      }
      final uri = await reachableJobApplicationUrl(item['provenance'] as Map?);
      if (!mounted) return;
      if (uri == null) {
        await _openDemo();
        return;
      }
      setState(() {
        opportunity = item;
        loading = false;
        applicationUrl = uri;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.status == 404) {
        await _openDemo();
        return;
      }
      setState(() {
        loading = false;
        loadError = 'โหลดประกาศต้นทางไม่ได้ในขณะนี้';
      });
    }
  }

  Future<void> _openApplication(Uri uri) async {
    setState(() => opening = true);
    final opened = await openExternal(context, widget.app, url: uri.toString(), title: widget.title, opportunityId: widget.opportunityId,
      showError: false);
    if (!mounted) return;
    if (!opened) {
      await _openDemo();
      return;
    }
    setState(() => opening = false);
  }

  Future<void> _openDemo() async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    setState(() {
      applicationUrl = null;
      loading = true;
      opening = false;
    });
    final opened = await openExternal(context, widget.app,
      url: jobApplicationDemoUrl(widget.app.api.baseUrl, widget.title),
      title: widget.title,
      askAfterReturn: false,
      showError: false,
    );
    if (!mounted) return;
    if (opened && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => loading = false);
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
            ] else if (loadError case final String message) ...[
              Text(message),
              FilledButton(onPressed: _load, child: const Text('ลองโหลดประกาศอีกครั้ง')),
            ] else ...[
              const Text('เปิดหน้าสมัครงานจำลองไม่ได้'),
              FilledButton.icon(onPressed: _openDemo, icon: const Icon(Icons.open_in_new), label: const Text('ลองเปิดหน้าสมัครงานจำลองอีกครั้ง')),
            ],
          ],
        ),
      ),
    );
  }
}
