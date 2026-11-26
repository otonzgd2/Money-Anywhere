import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';

const purposeLabel = {'ai': 'ให้ AI ช่วยวิเคราะห์', 'reminders': 'เตือนงานค้าง', 'location': 'ใช้ตำแหน่งค้นหา'};

/// Tab 👤 ฉัน (ui-states.md S9): settings, consent (takes effect at once), AI memory, my data, delete, help, demo.
class MeTab extends StatefulWidget {
  const MeTab({super.key, required this.app});
  final AppState app;
  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  Map<String, bool>? purposes;
  int history = 0;
  List<Map<String, dynamic>> memory = [];
  ApiException? error;
  bool loaded = false;
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
    try {
      final c = await api.get('/v1/me/consents');
      final cur = c['current'] as Map<String, dynamic>?;
      final m = await api.get('/v1/me/memory');
      final s = await api.get('/v1/me/settings');
      widget.app.largeText.value = s['largeText'] == true;
      if (!mounted) return;
      setState(() {
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
        content: const Text('คำตอบ แผน ความยินยอม และสิ่งที่ AI จำไว้จะถูกลบ กู้คืนไม่ได้'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('ลบข้อมูล')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await api.delete('/v1/me');
      widget.app.chat.reset();
      widget.app.bump();
      widget.app.goTab(0);
      if (mounted) toast(context, 'ลบข้อมูลและถอนความยินยอมแล้ว');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
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
        _head('สำหรับสาธิต (DEMO)'),
        for (final p in const [['p1', 'สมชาย 65 ปี (เงินสวัสดิการ)'], ['p2', 'สุดา 28 ปี (หางาน)'], ['p3', 'มานี 40 ปี (รายได้จากทักษะ)']])
          ListTile(title: Text('โหลดผู้ใช้ตัวอย่าง: ${p[1]}'), leading: const Icon(Icons.person_outline), onTap: () => _persona(p[0], p[1])),
        ListTile(
          title: const Text('ที่อยู่ server'),
          subtitle: Text(api.baseUrl),
          trailing: const Icon(Icons.edit),
          onTap: () => editServer(context, widget.app, () { widget.app.bump(); setState(() {}); }),
        ),
        const Padding(padding: EdgeInsets.all(8), child: DemoPill(text: 'เวอร์ชันสาธิต · ผู้ใช้สมมติ · ไม่มีการเข้าสู่ระบบ')),
      ]),
    );
  }
}
