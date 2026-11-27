import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat.dart';
import 'common.dart';
import 'profile_overview_screen.dart';

const _sources = {
  'thaid': (label: 'ThaID', details: 'ชื่อ อายุ และที่อยู่ตามทะเบียนบ้าน'),
  'tangRat': (label: 'ทางรัฐ', details: 'สถานะบัตรประจำตัวคนพิการ'),
  'socialSecurity': (label: 'ประกันสังคม', details: 'ประวัติการส่งเงินสมทบ'),
  'dMyTax': (label: 'D-MyTax', details: 'ภาษีหัก ณ ที่จ่าย'),
};

enum _DemoDestination { chat, profile, accounts }

class DemoSourcesScreen extends StatefulWidget {
  const DemoSourcesScreen({
    super.key,
    required this.app,
    required this.personaPath,
  });

  final AppState app;
  final String personaPath;

  @override
  State<DemoSourcesScreen> createState() => _DemoSourcesScreenState();
}

class _DemoSourcesScreenState extends State<DemoSourcesScreen> {
  final Set<String> selected = {..._sources.keys};
  bool opening = false;

  Future<void> _open(_DemoDestination destination) async {
    if (opening) return;
    setState(() => opening = true);
    final chat = destination == _DemoDestination.chat;
    final demoApp = chat
        ? widget.app.forDemoChat(DemoChatProfile.sources)
        : null;
    final path = Uri.parse(widget.personaPath)
        .replace(
          queryParameters: {
            'sources': _sources.keys.where(selected.contains).join(','),
            if (chat) 'keepPlans': 'true',
          },
        )
        .toString();
    try {
      final data = demoApp == null
          ? await widget.app.api.get(path)
          : await demoApp.api.post(path);
      final demo = ProfileDemo.fromResponse(data);
      if (demo == null) {
        throw ApiException(0, 'DEMO_DATA', 'โหลดข้อมูลจำลองไม่ได้');
      }
      if (!mounted) return;
      final screen = switch (destination) {
        _DemoDestination.chat => ChatScreen(
          app: demoApp!,
          session: demoApp.chat,
          title: 'ทดสอบแชต · DEMO',
        ),
        _DemoDestination.profile => ProfileOverviewScreen(
          app: widget.app,
          demo: demo,
        ),
        _DemoDestination.accounts => Scaffold(
          appBar: AppBar(title: const Text('บัญชีที่เชื่อมต่อ')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [DemoConnectionDetails(demo: demo)],
            ),
          ),
        ),
      };
      await Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => screen));
    } on ApiException catch (error) {
      if (mounted) toast(context, error.message);
    } finally {
      demoApp?.api.close();
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ทดลองเชื่อมแหล่งข้อมูล')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Align(alignment: Alignment.centerLeft, child: DemoPill()),
            const SizedBox(height: 12),
            Text(
              'เลือก ${selected.length} จาก ${_sources.length} แหล่ง',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final source in _sources.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(source.value.label),
                subtitle: Text(source.value.details),
                value: selected.contains(source.key),
                onChanged: opening
                    ? null
                    : (checked) => setState(() {
                        if (checked == true) {
                          selected.add(source.key);
                        } else {
                          selected.remove(source.key);
                        }
                      }),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: opening ? null : () => _open(_DemoDestination.chat),
              child: const Text('ทดสอบแชต'),
            ),
            OutlinedButton(
              onPressed: opening ? null : () => _open(_DemoDestination.profile),
              child: const Text('ดูโปรไฟล์ตัวอย่าง'),
            ),
            OutlinedButton(
              onPressed: opening
                  ? null
                  : () => _open(_DemoDestination.accounts),
              child: const Text('ดูบัญชีที่เชื่อมต่อ'),
            ),
            if (opening)
              const LinearProgressIndicator(
                semanticsLabel: 'กำลังโหลดข้อมูลจำลอง',
              ),
          ],
        ),
      ),
    );
  }
}

class DemoConnectionDetails extends StatelessWidget {
  const DemoConnectionDetails({
    super.key,
    required this.demo,
    this.onConnectThaid,
  });

  final ProfileDemo demo;
  final VoidCallback? onConnectThaid;

  static const _fields = {
    'identity': (icon: Icons.badge_outlined, label: 'ข้อมูลยืนยันตัวตน'),
    'disabilityCard': (
      icon: Icons.accessible_forward,
      label: 'บัตรประจำตัวคนพิการ',
    ),
    'ss33': (icon: Icons.shield_outlined, label: 'การส่งเงินสมทบ'),
    'taxWithheld': (
      icon: Icons.receipt_long_outlined,
      label: 'ภาษีหัก ณ ที่จ่าย',
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: DemoPill(),
        ),
        if (demo.connections.isEmpty)
          const ListTile(title: Text('ยังไม่ได้เลือกแหล่งข้อมูล')),
        for (final connection in demo.connections)
          ListTile(
            leading: Icon(_fields[connection.field]?.icon ?? Icons.link),
            title: Text(connection.source),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_fields[connection.field] case final field?)
                  Text(field.label),
                Text(connection.value),
              ],
            ),
            isThreeLine: _fields.containsKey(connection.field),
            trailing: connection.field == 'identity' && onConnectThaid != null
                ? TextButton(
                    onPressed: onConnectThaid,
                    child: const Text('เชื่อม ThaID'),
                  )
                : null,
          ),
      ],
    );
  }
}
