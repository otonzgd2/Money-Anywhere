import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';

/// ThaID link state from GET /v1/me/gov-link. `disabled` = the server runs with the mode off.
enum GovState { disabled, notConnected, connected }

Future<GovState> govState(Api api) async {
  try {
    final r = await api.get('/v1/me/gov-link');
    return r['status'] == 'connected' ? GovState.connected : GovState.notConnected;
  } on ApiException catch (e) {
    if (e.status == 404 || e.status == 403) return e.code == 'FEATURE_DISABLED' ? GovState.disabled : GovState.notConnected;
    rethrow;
  }
}

/// Connect ThaID (ui-states.md P11). Real ThaID needs an agreement with the identity provider, so the Demo
/// bypasses the sign-in step: it asks the same consent, runs the same API calls (start -> callback), and the
/// server's ThaID mock returns sample records labelled mock. The person is told this before and after.
Future<bool> connectThaid(BuildContext context, AppState app) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('🪪 เชื่อม ThaID ดึงสิทธิ์จากรัฐ'),
      content: const Text('ThaID จะส่งข้อมูลตัวตนให้แอป: ชื่อ-นามสกุล (ไทย/อังกฤษ), วันเกิด, เพศ, ที่อยู่ตามทะเบียนบ้าน, วันออกบัตรและวันหมดอายุ '
          'เลขบัตรประชาชนแอปเห็นแค่แบบปิดบัง\n\n'
          'แอปใช้ข้อมูลนี้เติมโปรไฟล์และช่วงอายุให้ และขอข้อมูลสิทธิ์และเงินจากหน่วยงานเพื่อยืนยันผลแทนการตอบคำถามเอง\n\n'
          'โหมดสาธิต: ยังเชื่อม ThaID จริงไม่ได้ (ต้องมีข้อตกลงกับผู้ให้บริการ) แอปจะข้ามขั้นยืนยันตัวตนและใช้ข้อมูลจำลองที่ทำงานเหมือนเชื่อมได้ ทุกรายการติดป้าย DEMO / MOCK\n\n'
          'ยกเลิกการเชื่อมได้ทุกเมื่อที่แท็บ ฉัน'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ไม่ใช่ตอนนี้')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ยินยอมและเชื่อม')),
      ],
    ),
  );
  if (yes != true || !context.mounted) return false;
  if (!await ensureConsent(context, app, why: 'เพื่อเก็บผลที่ได้จาก ThaID ไว้ในแอป')) return false;
  try {
    final cur = await app.api.currentPurposes() ?? {};
    await app.api.setConsent({...cur, 'core': true, 'gov': true});
    final s = await app.api.post('/v1/me/gov-link');
    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text('กำลังยืนยันตัวตนกับ ThaID (จำลอง)...'))])),
      );
    }
    // Bypass: a real app opens s['authUrl'] in the ThaID app and receives the code on the redirect.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await app.api.post('/v1/me/gov-link/callback', {'state': s['state'], 'code': 'demo-bypass'});
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    app.bump();
    if (context.mounted) toast(context, 'เชื่อม ThaID แล้ว (ข้อมูลจำลอง) เติมโปรไฟล์ให้แล้ว เงินที่หน่วยงานมีข้อมูลจะขึ้นว่า ยืนยันจากหน่วยงาน');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).popUntil((r) => r is! DialogRoute);
      toast(context, e.code == 'FEATURE_DISABLED' ? 'server ปิดโหมด ThaID อยู่ (ตั้ง GOV_CONNECTED=1)' : e.message);
    }
    return false;
  }
}

Future<void> disconnectThaid(BuildContext context, AppState app) async {
  try {
    await app.api.delete('/v1/me/gov-link');
    app.bump();
    if (context.mounted) toast(context, 'ยกเลิกการเชื่อม ThaID และลบข้อมูลจากหน่วยงานแล้ว');
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
  }
}

/// ThaID identity (GovIdentity in openapi.yaml) when connected, otherwise null. Claim names follow ThaID.
Future<Map<String, dynamic>?> govIdentity(Api api) async {
  try {
    final r = await api.get('/v1/me/gov-link');
    final id = r['identity'];
    return r['status'] == 'connected' && id is Map ? Map<String, dynamic>.from(id) : null;
  } on ApiException {
    return null;
  }
}

const _claimRows = <(String, String)>[
  ('name', 'ชื่อ-นามสกุล'), ('name_en', 'ชื่อ (อังกฤษ)'), ('birthdate', 'วันเกิด'), ('gender', 'เพศ'),
  ('address', 'ที่อยู่ตามทะเบียนบ้าน'), ('date_of_issuance', 'วันออกบัตร'), ('date_of_expiry', 'วันบัตรหมดอายุ'), ('ial', 'ระดับยืนยันตัวตน'),
];
const _thaiMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

String _show(String key, Object? v) {
  if (v == null || '$v'.isEmpty) return '-';
  if (key == 'address' && v is Map) return '${v['formatted'] ?? '-'}';
  if (key == 'gender') return v == 'male' ? 'ชาย' : v == 'female' ? 'หญิง' : '$v';
  final d = DateTime.tryParse('$v');
  if (d != null && '$v'.length == 10) return '${d.day} ${_thaiMonths[d.month - 1]} ${d.year + 543}';
  return '$v';
}

/// Profile block "ข้อมูลจาก ThaID": every claim the link returned, read-only, with the DEMO / MOCK label.
class ThaidIdentityCard extends StatelessWidget {
  const ThaidIdentityCard({super.key, required this.identity});
  final Map<String, dynamic> identity;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Map<String, dynamic>.from((identity['claims'] as Map?) ?? const {});
    final d = Map<String, dynamic>.from((identity['derived'] as Map?) ?? const {});
    final mock = identity['dataStatus'] != 'live';
    return Card(
      color: const Color(0xFFECFDF5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🪪', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(child: Text('ข้อมูลจาก ThaID', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
            if (mock) const Chip(label: Text('DEMO / MOCK'), visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 6),
          _row(t, 'เลขบัตรประชาชน', '${identity['pidMasked'] ?? '-'}'),
          for (final (k, label) in _claimRows) _row(t, label, _show(k, c[k])),
          if (d['age'] != null) _row(t, 'อายุ (คิดจากวันเกิด)', '${d['age']} ปี'),
          const SizedBox(height: 6),
          Text(mock ? 'ข้อมูลสังเคราะห์ ไม่ใช่ข้อมูลจริงจากรัฐ แก้ในแอปไม่ได้ ยกเลิกการเชื่อมได้ที่แท็บ ฉัน' : 'ข้อมูลจากกรมการปกครอง แก้ในแอปไม่ได้', style: t.bodySmall),
        ]),
      ),
    );
  }

  Widget _row(TextTheme t, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label, style: t.bodySmall)),
          Expanded(child: Text(value, style: t.bodyMedium)),
        ]),
      );
}

/// Home card: "connect" before, a small connected strip after. Hidden when the server runs with the mode off.
class ThaidCard extends StatelessWidget {
  const ThaidCard({super.key, required this.app, required this.state});
  final AppState app;
  final GovState state;

  @override
  Widget build(BuildContext context) {
    if (state == GovState.disabled) return const SizedBox.shrink();
    if (state == GovState.connected) {
      return Card(
        color: const Color(0xFFECFDF5),
        child: ListTile(
          dense: true,
          leading: const Text('🪪', style: TextStyle(fontSize: 22)),
          title: const Text('เชื่อม ThaID แล้ว', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('เงินที่หน่วยงานมีข้อมูลแสดงว่า ยืนยันจากหน่วยงาน · ข้อมูลจำลอง (DEMO)'),
        ),
      );
    }
    return Card(
      color: const Color(0xFFEFF6FF),
      child: ListTile(
        minVerticalPadding: 12,
        leading: const Text('🪪', style: TextStyle(fontSize: 30)),
        title: const Text('เชื่อม ThaID ดึงสิทธิ์จากรัฐอัตโนมัติ', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('ไม่ต้องตอบคำถามเอง เห็นเงินที่ได้อยู่และเงินรอรับ · โหมดสาธิตใช้ข้อมูลจำลอง'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => connectThaid(context, app),
      ),
    );
  }
}
