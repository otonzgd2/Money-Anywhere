// Shared app state, the consent sheet, the "came back from an outside link" prompt and small widgets.
// State rules are written down in docs/design/ui-states.md; keep the two in step.
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'chat.dart';

enum DemoChatProfile {
  connected('gov-prefill-chat', 'DEMO · โปรไฟล์เชื่อม 4 แหล่ง'),
  sources('gov-prefill-selection', 'DEMO · ทดลองเชื่อมแหล่งข้อมูล'),
  tax('dmytax', 'DEMO · D-MyTax');

  const DemoChatProfile(this.deviceSuffix, this.planLabel);
  final String deviceSuffix, planLabel;
}

/// One object for the whole app. [changed] is bumped after anything that changes server data
/// (answers, consent, tasks, delete); every tab listens and reloads (ui-states.md §5).
class AppState {
  AppState(this.api) : demo = false, changed = ValueNotifier(0);
  AppState._demo(this.api, this.changed) : demo = true;

  final Api api;
  final bool demo;
  bool startupDemoEnabled = false;
  bool get allowsDemo => demo || startupDemoEnabled;
  final ChatSession chat = ChatSession();
  final ValueNotifier<int> changed;
  final ValueNotifier<bool> largeText = ValueNotifier(false);

  /// Switch the bottom tab (0 หน้าแรก, 1 โอกาส, 2 แผนของฉัน, 3 ฉัน) and optional opportunity group filter.
  final ValueNotifier<int> tab = ValueNotifier(0);
  final ValueNotifier<String> oppGroup = ValueNotifier('all');

  AppState forDemoChat(DemoChatProfile profile) => AppState._demo(api.forDemo(profile.deviceSuffix), changed);

  void bump() => changed.value++;
  void goTab(int i, {String? group}) {
    if (group != null) oppGroup.value = group;
    tab.value = i;
  }
}

void toast(BuildContext context, String text, {String? undoLabel, VoidCallback? onUndo}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    duration: Duration(seconds: onUndo != null ? 5 : 2),
    action: onUndo != null ? SnackBarAction(label: undoLabel ?? 'เลิกทำ', onPressed: onUndo) : null,
  ));
}

/// Consent sheet (ui-states.md §4, popup P1). Asked only at the first action that saves something:
/// opening a claim route (it needs the saved answers), saving an opportunity, answering "ยื่นแล้ว".
/// Returns true when core consent exists (already or just given).
Future<bool> ensureConsent(BuildContext context, AppState app, {required String why}) async {
  try {
    final cur = await app.api.currentPurposes();
    if (cur != null && cur['core'] == true) return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return false;
  }
  if (!context.mounted) return false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ConsentSheet(app: app, why: why),
  );
  if (ok == true) app.bump();
  return ok == true;
}

class _ConsentSheet extends StatefulWidget {
  const _ConsentSheet({required this.app, required this.why});
  final AppState app;
  final String why;
  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  bool ai = false, reminders = false, adult = false, busy = false;
  String? error;

  Future<void> _accept() async {
    setState(() => busy = true);
    try {
      await widget.app.api.setConsent({'core': true, 'ai': ai, 'reminders': reminders, 'location': false});
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() { error = e.message; busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ก่อนบันทึก: ข้อมูลของคุณ', style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(widget.why),
          const SizedBox(height: 8),
          const SwitchListTile(value: true, onChanged: null, title: Text('ข้อมูลที่จำเป็น (บังคับ)'), subtitle: Text('คำตอบและแผนของคุณ ไม่เก็บชื่อจริง เลขบัตร หรือเลขบัญชี')),
          SwitchListTile(value: ai, onChanged: (v) => setState(() => ai = v), title: const Text('ให้ AI ช่วยวิเคราะห์'), subtitle: const Text('ส่งคำตอบ (ไม่มีชื่อ) ให้ผู้ให้บริการ AI')),
          SwitchListTile(value: reminders, onChanged: (v) => setState(() => reminders = v), title: const Text('เตือนงานค้าง')),
          CheckboxListTile(value: adult, onChanged: (v) => setState(() => adult = v == true), title: const Text('ฉันอายุ 20 ปีขึ้นไป หรือผู้ปกครองยินยอมแล้ว')),
          TextButton(onPressed: () => showNotice(context, widget.app), child: const Text('อ่านประกาศความเป็นส่วนตัว')),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: adult && !busy ? _accept : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('ยอมรับและไปต่อ'),
          ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ไม่ใช่ตอนนี้')),
        ]),
      ),
    );
  }
}

/// Privacy notice from GET /v1/privacy/notice (draft, labelled as such by the server).
Future<void> showNotice(BuildContext context, AppState app) async {
  Map<String, dynamic>? n;
  try {
    n = await app.api.get('/v1/privacy/notice');
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return;
  }
  if (!context.mounted) return;
  final sections = ((n['sections'] as List?) ?? const []).cast<Map<String, dynamic>>();
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('ประกาศความเป็นส่วนตัว (${n!['version']})'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (n['note'] != null) Text('${n['note']}', style: const TextStyle(color: Color(0xFF9A3412))),
          for (final s in sections) ...[
            const SizedBox(height: 8),
            Text('${s['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${s['text']}'),
          ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด'))],
    ),
  );
}

/// Open an official link outside the app. For an application link, ask on return whether the person
/// applied (ui-states.md popup P6). Guide and contact links can skip the prompt.
Future<bool> openExternal(BuildContext context, AppState app, {required String url, required String title, String? moneyId, String? opportunityId, bool showError = true, bool askAfterReturn = true}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  AppLifecycleListener? listener;
  if (askAfterReturn) {
    var left = false;
    listener = AppLifecycleListener(
      onHide: () => left = true,
      onResume: () {
        if (!left) return;
        listener?.dispose();
        if (context.mounted) _askApplied(context, app, title: title, moneyId: moneyId, opportunityId: opportunityId);
      },
    );
  }
  bool ok;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception {
    ok = false;
  }
  if (!ok) {
    listener?.dispose();
    if (showError && context.mounted) toast(context, 'เปิดลิงก์ไม่ได้: $url');
  }
  return ok;
}

Future<void> _askApplied(BuildContext context, AppState app, {required String title, String? moneyId, String? opportunityId}) async {
  final answer = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('กลับมาแล้ว 👋'),
      content: Text('คุณได้สมัครหรือยื่นเรื่อง "$title" แล้วหรือยัง'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, 'none'), child: const Text('ไม่ต้องบันทึก')),
        TextButton(onPressed: () => Navigator.pop(context, 'saved'), child: const Text('ยังไม่ได้ยื่น แต่สนใจ')),
        FilledButton(onPressed: () => Navigator.pop(context, 'applied'), child: const Text('✓ ยื่น/สมัครแล้ว')),
      ],
    ),
  );
  if (answer == null || answer == 'none' || !context.mounted) return;
  await saveToPlan(context, app, moneyId: moneyId, opportunityId: opportunityId, applied: answer == 'applied');
}

/// Create (or reuse) the task for a money item or an opportunity. With [applied], the steps up to
/// "ยื่น/ติดต่อ" are marked done as reported by the person.
Future<bool> saveToPlan(BuildContext context, AppState app, {String? moneyId, String? opportunityId, String? districtCode, bool applied = false}) async {
  if (!await ensureConsent(context, app, why: 'เพื่อบันทึกเป็นแผนทีละขั้นและติดตามความคืบหน้า')) return false;
  try {
    var t = await app.api.post('/v1/tasks', moneyId != null ? {'moneyId': moneyId} : {
      'opportunityId': opportunityId, 'districtCode': ?districtCode,
    });
    if (applied) {
      final steps = (t['steps'] as List).length;
      final target = steps > 2 ? 2 : steps - 1;
      while ((t['doneCount'] as num) < target) {
        t = await app.api.taskEvent('${t['id']}', {'type': 'complete_step'});
      }
    }
    app.bump();
    if (context.mounted) toast(context, applied ? 'บันทึกแล้ว: ยื่นแล้ว (คุณเป็นผู้แจ้ง)' : 'บันทึกในแผนของฉันแล้ว');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
    return false;
  }
}

/// "DEMO / MOCK" pill shown on every screen that can contain mock data.
class DemoPill extends StatelessWidget {
  const DemoPill({super.key, this.text = 'DEMO / MOCK'});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFFFEDD5), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9A3412))),
      );
}

/// Shown instead of content when the server cannot be reached (ui-states.md §6).
class OfflineCard extends StatelessWidget {
  const OfflineCard({super.key, required this.app, required this.onRetry});
  final AppState app;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFFEF2F2),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📡 ต่อ server ไม่ได้', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('ตอนนี้ใช้ ${app.api.baseUrl}\nสาย USB: เสียบสาย แล้วบนคอมสั่ง adb reverse tcp:8080 tcp:8080\nWi-Fi: ${app.api.wifiBaseUrl ?? 'ใส่ IP ของคอมที่เปิดเซิร์ฟเวอร์'}'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton(onPressed: onRetry, child: const Text('ลองใหม่')),
              OutlinedButton(onPressed: () => editServer(context, app, onRetry), child: const Text('เปลี่ยนที่อยู่ server')),
            ]),
          ]),
        ),
      );
}

Future<void> editServer(BuildContext context, AppState app, VoidCallback after) async {
  final c = TextEditingController(text: app.api.baseUrl);
  final wifi = app.api.wifiBaseUrl;
  final v = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('ที่อยู่ server'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: c, keyboardType: TextInputType.url),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          ActionChip(label: const Text('USB 127.0.0.1'), onPressed: () => c.text = usbApiBaseUrl),
          if (wifi != null)
            ActionChip(
              label: Text('Wi-Fi ${Uri.tryParse(wifi)?.host ?? wifi}'),
              onPressed: () => c.text = wifi,
            ),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('บันทึก')),
      ],
    ),
  );
  c.dispose();
  if (v != null && v.trim().isNotEmpty) {
    app.api.setBaseUrl(v);
    after();
  }
}
