import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'thaid.dart';

const skillChoices = [
  'ทำอาหาร', 'ทำขนม/เบเกอรี่', 'ขับรถยนต์', 'ขับมอเตอร์ไซค์', 'ส่งของ/ส่งอาหาร', 'พิมพ์เอกสาร', 'กรอกข้อมูล', 'Excel/ตาราง',
  'สอนพิเศษ', 'ภาษาอังกฤษ', 'ภาษาจีน', 'ดูแลผู้สูงอายุ', 'เลี้ยงเด็ก', 'ทำความสะอาด', 'ช่างซ่อม', 'ขายของออนไลน์',
  'ขายหน้าร้าน', 'เย็บผ้า', 'ตัดผม', 'ทำสวน', 'รปภ.',
];
const hourChoices = ['ไม่เกิน 10', '10-20', '20-40', 'เต็มเวลา'];
const districtChoices = [
  'ปทุมวัน', 'บางกะปิ', 'ลาดพร้าว', 'บางนา', 'จตุจักร', 'ดินแดง', 'ห้วยขวาง', 'คลองเตย',
  'บางรัก', 'สาทร', 'ธนบุรี', 'บางแค', 'มีนบุรี', 'ลาดกระบัง', 'ดอนเมือง', 'บางเขน',
];

/// ฉัน > โปรไฟล์และทักษะ (ui-states.md S10). Skills, free time and the monthly goal drive job ranking and
/// the income plan. No real name needed.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.app});
  final AppState app;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Set<String> skills = {};
  final TextEditingController goal = TextEditingController(), extra = TextEditingController();
  String? hours, district;
  Map<String, dynamic> rest = {};
  Map<String, dynamic>? identity; // ThaID claims when connected (GovIdentity)
  List<String> fromGov = const [];
  bool loading = true, saving = false;
  Api get api => widget.app.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    goal.dispose();
    extra.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await api.get('/v1/me/profile');
      rest = p;
      skills.addAll(((p['skills'] as List?) ?? const []).map((e) => '$e'));
      hours = p['hoursPerWeek'] as String?;
      district = p['district'] as String?;
      if (p['incomeGoalPerMonth'] is num) goal.text = '${(p['incomeGoalPerMonth'] as num).round()}';
      fromGov = ((p['fromGov'] as List?) ?? const []).map((e) => '$e').toList();
    } on ApiException {
      // no profile yet
    }
    identity = await govIdentity(api);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (!await ensureConsent(context, widget.app, why: 'เพื่อจำทักษะ เวลาว่าง และเป้ารายได้ ไว้ใช้หางานและวางแผนรายได้ให้คุณ')) return;
    setState(() => saving = true);
    final g = int.tryParse(goal.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final body = <String, Object?>{
      ...Map.fromEntries(rest.entries.where((e) => ['displayName', 'goals', 'constraints'].contains(e.key))),
      'skills': skills.toList(),
      if (hours != null) 'hoursPerWeek': hours,
      if (district != null) 'district': district,
      if (g != null && g > 0) 'incomeGoalPerMonth': g,
    };
    try {
      await api.put('/v1/me/profile', body);
      widget.app.bump();
      if (mounted) {
        toast(context, 'บันทึกโปรไฟล์แล้ว');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final all = {...skillChoices, ...skills}.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์และทักษะ')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (identity != null) ...[
                ThaidIdentityCard(identity: identity!),
                if (fromGov.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text('เติมจาก ThaID ให้แล้ว: ${fromGov.map((f) => const {'displayName': 'ชื่อที่ใช้ในแอป', 'district': 'เขตที่อยู่', 'ageBand': 'ช่วงอายุ'}[f] ?? f).join(', ')}', style: t.bodySmall),
                  ),
                const SizedBox(height: 8),
              ],
              Text('ทำอะไรเป็นบ้าง (เลือกได้หลายอย่าง)', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in all)
                  FilterChip(label: Text(s), selected: skills.contains(s), onSelected: (v) => setState(() => v ? skills.add(s) : skills.remove(s))),
              ]),
              Row(children: [
                Expanded(child: TextField(controller: extra, decoration: const InputDecoration(hintText: 'ทักษะอื่น พิมพ์เอง', isDense: true))),
                TextButton(
                  onPressed: () {
                    final s = extra.text.trim();
                    if (s.isNotEmpty) setState(() { skills.add(s); extra.clear(); });
                  },
                  child: const Text('เพิ่ม'),
                ),
              ]),
              const SizedBox(height: 16),
              Text('เวลาว่างต่อสัปดาห์ (ชั่วโมง)', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Wrap(spacing: 6, children: [for (final h in hourChoices) ChoiceChip(label: Text(h), selected: hours == h, onSelected: (_) => setState(() => hours = h))]),
              const SizedBox(height: 16),
              Text('อยากได้รายได้เดือนละเท่าไหร่ (บาท)', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              TextField(controller: goal, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'เช่น 10000', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              Text('อยู่แถวไหน (ใช้หางานใกล้บ้าน)', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Wrap(spacing: 6, children: [for (final d in districtChoices) ChoiceChip(label: Text(d), selected: district == d, onSelected: (_) => setState(() => district = d))]),
              Text(fromGov.contains('district') ? 'เลือกไว้ตามที่อยู่ใน ThaID เปลี่ยนได้ถ้าตอนนี้อยู่ที่อื่น' : 'Demo มีพิกัดกลางเขตโดยประมาณ 16 เขตในกรุงเทพ', style: t.bodySmall),
              const SizedBox(height: 20),
              FilledButton(onPressed: saving ? null : _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('บันทึก')),
              const SizedBox(height: 8),
              Text(identity != null ? 'ข้อมูลจาก ThaID แก้ในแอปไม่ได้ ยกเลิกการเชื่อมแล้วแอปลบข้อมูลนี้และคืนค่าที่เติมให้' : 'ไม่ต้องใส่ชื่อจริง เลขบัตร หรือเลขบัญชี ลบได้ทุกเมื่อที่ ฉัน > ลบข้อมูลทั้งหมด', style: t.bodySmall),
            ]),
    );
  }
}
