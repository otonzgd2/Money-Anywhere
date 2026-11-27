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
          'แอปใช้ข้อมูลนี้เติมโปรไฟล์และช่วยตรวจสิทธิ์จากหน่วยงาน\n\n'
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
    app.chat.reset();
    app.bump();
    if (context.mounted) toast(context, 'เชื่อม ThaID แล้ว (ข้อมูลจำลอง) เพิ่มข้อมูลยืนยันตัวตนในโปรไฟล์แล้ว');
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
    app.chat.reset();
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

class ThaidProfileIdentity {
  ThaidProfileIdentity(Map<String, dynamic> data)
      : _data = data,
        _claims = data['claims'] is Map ? data['claims'] as Map : const {},
        _derived = data['derived'] is Map ? data['derived'] as Map : const {};

  final Map<String, dynamic> _data;
  final Map<dynamic, dynamic> _claims;
  final Map<dynamic, dynamic> _derived;

  bool get mock => _data['dataStatus'] != 'live';
  String? get displayName => _thaidText(_claims['name']) ?? _thaidText(_derived['displayName']);
  String? get district => _thaidText(_address['locality']) ?? _thaidText(_derived['district']);

  String? get maskedId {
    final tail = RegExp(r'(\d{2})-?(\d)$').firstMatch(_thaidText(_data['pidMasked']) ?? '');
    return tail == null ? null : 'XXX${tail[1]}${tail[2]}';
  }

  int? get age {
    final birthday = DateTime.tryParse(_thaidText(_claims['birthdate']) ?? '');
    if (birthday != null) {
      final today = DateTime.now();
      if (birthday.isAfter(today)) return null;
      final beforeBirthday = today.month < birthday.month ||
          (today.month == birthday.month && today.day < birthday.day);
      return today.year - birthday.year - (beforeBirthday ? 1 : 0);
    }
    final age = _derived['age'];
    return age is int && age >= 0 ? age : null;
  }

  Map<dynamic, dynamic> get _address => _claims['address'] is Map ? _claims['address'] as Map : const {};

  String? get address {
    final formatted = _thaidText(_address['formatted']);
    if (formatted != null) return formatted;
    final parts = [
      for (final field in ['street_address', 'locality', 'region', 'postal_code'])
        ?_thaidText(_address[field]),
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }
}

String? _thaidText(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

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
          subtitle: const Text('ใช้ช่วงอายุและพื้นที่ตามทะเบียนช่วยตรวจเกณฑ์ · ข้อมูลจำลอง (DEMO)'),
        ),
      );
    }
    return Card(
      color: const Color(0xFFEFF6FF),
      child: ListTile(
        minVerticalPadding: 12,
        leading: const Text('🪪', style: TextStyle(fontSize: 30)),
        title: const Text('เชื่อม ThaID เพื่อเติมข้อมูลยืนยันตัวตน', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('ไม่ต้องตอบคำถามเอง เห็นเงินที่ได้อยู่และเงินรอรับ · โหมดสาธิตใช้ข้อมูลจำลอง'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => connectThaid(context, app),
      ),
    );
  }
}
