import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'connected_accounts.dart';
import 'opportunity_catalog.dart';
import 'profile_fact_details.dart';
import 'thaid.dart';

const skillChoices = [
  'ทำอาหาร',
  'ทำขนม/เบเกอรี่',
  'ขับรถยนต์',
  'ขับมอเตอร์ไซค์',
  'ส่งของ/ส่งอาหาร',
  'พิมพ์เอกสาร',
  'กรอกข้อมูล',
  'Excel/ตาราง',
  'สอนพิเศษ',
  'ภาษาอังกฤษ',
  'ภาษาจีน',
  'ดูแลผู้สูงอายุ',
  'เลี้ยงเด็ก',
  'ทำความสะอาด',
  'ช่างซ่อม',
  'ขายของออนไลน์',
  'ขายหน้าร้าน',
  'เย็บผ้า',
  'ตัดผม',
  'ทำสวน',
  'รปภ.',
];
const hourChoices = ['ไม่เกิน 10', '10-20', '20-40', 'เต็มเวลา'];
const _ageChoices = ['ต่ำกว่า 60', '60-69', '70-79', '80-89', '90 ขึ้นไป'];
const _profileFields = {
  'displayName',
  'district',
  'lat',
  'lng',
  'skills',
  'hoursPerWeek',
  'incomeGoalPerMonth',
  'goals',
  'constraints',
};

class PersonalProfile {
  const PersonalProfile(this.fields, this.facts);

  final Map<String, dynamic> fields, facts;

  static Future<Map<String, dynamic>> readFields(Api api) async {
    try {
      return await api.get('/v1/me/profile');
    } on ApiException catch (error) {
      if (error.status == 404) return {};
      rethrow;
    }
  }

  static Future<PersonalProfile> load(Api api) async {
    final [fields, facts] = await Future.wait([
      readFields(api),
      api.get('/v1/me/facts'),
    ]);
    return PersonalProfile(fields, facts);
  }

  String? get displayName => _manualText('displayName');
  String? get district => _manualText('district');
  String? get ageBand {
    final provenance = fields['factProvenance'];
    final detail = provenance is Map ? provenance['ageBand'] : null;
    if (detail is Map && detail['source'] == 'thaid') {
      return profileText(detail['userValue']);
    }
    return profileText(facts['ageBand']);
  }

  String? _manualText(String key) {
    final fromGov = fields['fromGov'];
    return fromGov is List && fromGov.contains(key)
        ? null
        : profileText(fields[key]);
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.app, this.onAccounts});
  final AppState app;
  final VoidCallback? onAccounts;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final skills = <String>{};
  final customSkills = <String>{};
  final name = TextEditingController();
  final goal = TextEditingController();
  final extra = TextEditingController();
  String? hours, district, ageBand, savedAgeBand;
  PersonalProfile? profile;
  String? saveError;
  bool loading = true, saving = false;
  Api get api => widget.app.api;

  @override
  void initState() {
    super.initState();
    widget.app.accounts.refresh();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    goal.dispose();
    extra.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await PersonalProfile.load(api);
      if (!mounted) return;
      name.text = data.displayName ?? '';
      district = data.district;
      savedAgeBand = ageBand = data.ageBand;
      final fields = data.fields;
      skills.addAll(
        (fields['skills'] as List? ?? const []).whereType<String>(),
      );
      customSkills.addAll(
        skills.where((skill) => !skillChoices.contains(skill)),
      );
      hours = profileText(fields['hoursPerWeek']);
      if (fields['incomeGoalPerMonth'] case final num amount) {
        goal.text = amount.toString();
      }
      setState(() => profile = data);
    } on ApiException {
      // Keep the form closed so a failed read cannot overwrite saved data.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    if (saving) return;
    final link = widget.app.accounts.value.thaid.status;
    if (link == AccountStatus.loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      if (!await ensureConsent(
            context,
            widget.app,
            why: 'เพื่อบันทึกโปรไฟล์ไว้ใช้ประเมินสิทธิ์ หางาน และวางแผนรายได้',
          ) ||
          !mounted) {
        return;
      }
      final current = await PersonalProfile.readFields(api);
      if (!mounted) return;
      final locked =
          link == AccountStatus.connected || current['fromGov'] is List;
      final latest = PersonalProfile(current, {});
      final displayName = locked ? latest.displayName : profileText(name.text);
      final workDistrict = locked ? latest.district : district;
      final target = num.tryParse(goal.text.replaceAll(RegExp(r'[^0-9.]'), ''));
      final body = <String, Object?>{
        ...Map.fromEntries(
          current.entries.where((entry) => _profileFields.contains(entry.key)),
        ),
        'skills': skills.toList(),
      };
      body.remove('displayName');
      body.remove('district');
      body.remove('hoursPerWeek');
      body.remove('incomeGoalPerMonth');
      if (displayName != null) body['displayName'] = displayName;
      if (workDistrict != null) body['district'] = workDistrict;
      if (workDistrict != current['district'] ||
          (locked && latest.district == null)) {
        body.remove('lat');
        body.remove('lng');
      }
      if (hours != null) body['hoursPerWeek'] = hours;
      if (target != null && target.isFinite && target > 0) {
        body['incomeGoalPerMonth'] = target;
      }
      await api.put('/v1/me/profile', body);
      if (!locked && ageBand != savedAgeBand) {
        await api.patch('/v1/me/facts', {'ageBand': ageBand});
      }
      widget.app.bump();
      if (!mounted) return;
      toast(context, 'บันทึกโปรไฟล์แล้ว');
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => saveError = error.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _addSkill() {
    final skill = extra.text.trim();
    if (skill.isEmpty) return;
    setState(() {
      if (!skillChoices.contains(skill)) customSkills.add(skill);
      skills.add(skill);
      extra.clear();
    });
  }

  Widget _choice(
    String label,
    String? value,
    Iterable<String> options,
    ValueChanged<String?> change,
  ) {
    return DropdownButtonFormField<String>(
      key: ValueKey(label),
      initialValue: value ?? '',
      isExpanded: true,
      menuMaxHeight: 340,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('เลือกภายหลัง')),
        for (final option in {?value, ...options})
          DropdownMenuItem(
            value: option,
            child: Text(option, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: saving
          ? null
          : (selected) => setState(() => change(profileText(selected))),
    );
  }

  Widget _personal(AccountsSnapshot accounts) {
    final link = accounts.thaid;
    final identity = link.identity;
    return _ProfileCard(
      title: 'ข้อมูลส่วนตัว',
      badge: switch (link.status) {
        AccountStatus.loading => null,
        AccountStatus.connected => link.mock ? 'ThaID · DEMO / MOCK' : 'ThaID',
        _ => 'คุณกรอกเอง',
      },
      linked: identity != null,
      children: [
        if (identity != null) ...[
          ThaidIdentityFields(identity: identity),
          const SizedBox(height: 12),
          const Text('ข้อมูลจาก ThaID อ่านได้อย่างเดียว'),
          if (widget.onAccounts case final open?)
            OutlinedButton(
              onPressed: open,
              child: const Text('ดูบัญชีที่เชื่อมต่อ'),
            ),
        ] else if (link.status == AccountStatus.loading)
          const Text('กำลังตรวจสถานะ ThaID…')
        else ...[
          TextField(
            controller: name,
            enabled: !saving,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'ชื่อที่ใช้ในแอป',
              hintText: 'เช่น ชื่อเล่น',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          _choice('ช่วงอายุ', ageBand, _ageChoices, (value) => ageBand = value),
          const SizedBox(height: 14),
          _choice(
            'เขตที่อาศัย',
            district,
            bangkokDistricts.values,
            (value) => district = value,
          ),
        ],
      ],
    );
  }

  Widget _work(TextTheme text) {
    final label = text.titleSmall?.copyWith(fontWeight: FontWeight.bold);
    return _ProfileCard(
      title: 'งานและรายได้',
      children: [
        Text('ทักษะ', style: label),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final skill in [...skillChoices, ...customSkills])
              FilterChip(
                label: Text(skill),
                selected: skills.contains(skill),
                onSelected: saving
                    ? null
                    : (selected) => setState(
                        () =>
                            selected ? skills.add(skill) : skills.remove(skill),
                      ),
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: extra,
                enabled: !saving,
                onSubmitted: (_) => _addSkill(),
                decoration: const InputDecoration(labelText: 'เพิ่มทักษะอื่น'),
              ),
            ),
            TextButton(
              onPressed: saving ? null : _addSkill,
              child: const Text('เพิ่ม'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('เวลาว่างต่อสัปดาห์ (ชั่วโมง)', style: label),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final option in {...hourChoices, ?hours})
              ChoiceChip(
                label: Text(option),
                selected: hours == option,
                onSelected: saving
                    ? null
                    : (selected) =>
                          setState(() => hours = selected ? option : null),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: goal,
          enabled: !saving,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'เป้ารายได้ต่อเดือน (บาท)',
            hintText: 'เช่น 10000',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : profile == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('โหลดโปรไฟล์ไม่ได้'),
                    OutlinedButton(
                      onPressed: () {
                        setState(() => loading = true);
                        _load();
                      },
                      child: const Text('ลองใหม่'),
                    ),
                  ],
                ),
              )
            : ValueListenableBuilder<AccountsSnapshot>(
                valueListenable: widget.app.accounts,
                builder: (context, accounts, _) => Column(
                  children: [
                    Expanded(
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        children: [
                          _personal(accounts),
                          const SizedBox(height: 12),
                          _work(text),
                          ProfileFactDetails(
                            profile: profile!.fields,
                            facts: profile!.facts,
                            hideMock: accounts.userMode,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (saveError case final message?)
                            Semantics(liveRegion: true, child: Text(message)),
                          FilledButton(
                            onPressed:
                                saving ||
                                    accounts.thaid.status ==
                                        AccountStatus.loading
                                ? null
                                : _save,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: Text(
                              saving ? 'กำลังบันทึก…' : 'บันทึกโปรไฟล์',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.title,
    this.badge,
    this.linked = false,
    required this.children,
  });

  final String title;
  final String? badge;
  final bool linked;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: linked ? const Color(0xFFEDF6F1) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: linked ? const Color(0xFFA7CBB9) : const Color(0xFFD9E5DD),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (badge case final label?)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFDFEEE5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: const Color(0xFF165A45),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class ThaidIdentityFields extends StatelessWidget {
  const ThaidIdentityFields({super.key, required this.identity});

  final ThaidProfileIdentity identity;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (label, value) in [
        ('ชื่อ–นามสกุล', identity.displayName),
        (
          identity.age == null && identity.ageBand != null
              ? 'ช่วงอายุ'
              : 'อายุ',
          identity.ageText,
        ),
        ('เขตตามทะเบียนบ้าน', identity.district),
      ])
        AccountDetailField(label, value ?? 'ไม่มีข้อมูลจาก ThaID'),
    ],
  );
}

class AccountDetailField extends StatelessWidget {
  const AccountDetailField(this.label, this.value, {super.key});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFDCE8E0))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF47675B),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text(value)),
        ],
      ),
    );
  }
}
