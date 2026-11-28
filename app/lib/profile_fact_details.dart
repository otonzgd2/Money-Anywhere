import 'package:material_ui/material_ui.dart';

import 'connected_accounts.dart';

const _factLabels = {
  'ageBand': 'ช่วงอายุ',
  'nationality': 'สัญชาติไทย',
  'registryDistrict': 'เขตหรืออำเภอตามทะเบียนบ้าน',
  'registryProvince': 'จังหวัดตามทะเบียนบ้าน',
  'govPension': 'เงินประจำจากรัฐ',
  'oldAgeGets': 'ได้รับเบี้ยผู้สูงอายุ',
  'disabilityCard': 'บัตรคนพิการที่ใช้ได้',
  'disabilityGets': 'ได้รับเบี้ยความพิการ',
  'welfareCard': 'บัตรสวัสดิการแห่งรัฐ',
  'work': 'สถานะการทำงาน',
  'ss33': 'สมทบ ม.33 ครบ 6 เดือนใน 15 เดือนก่อนออกงาน',
  'wage': 'ค่าจ้างล่าสุด',
  'taxWithheld': 'ภาษีหัก ณ ที่จ่าย',
  'coverageEnded': 'สิ้นสุดสถานะผู้ประกันตน',
  'lifetimePaidMonths33And39': 'เดือนสมทบสะสม ม.33 และ ม.39',
};

const _factSources = {
  'user': 'คุณกรอกเอง',
  'demo_answers': 'คำตอบตัวอย่าง',
  'thaid': 'ThaID',
  'tangRat': 'ทางรัฐ',
  'socialSecurity': 'ประกันสังคม',
  'dMyTax': 'D-MyTax',
};

String _factValue(Object? value) => switch (value) {
  true => 'ใช่',
  false => 'ไม่มี / ไม่ใช่',
  null => 'ยังไม่มีข้อมูล',
  _ => '$value',
};

class ProfileFactDetails extends StatelessWidget {
  const ProfileFactDetails({
    super.key,
    required this.profile,
    required this.facts,
    this.hideMock = false,
  });

  final Map<String, dynamic> profile, facts;
  final bool hideMock;

  @override
  Widget build(BuildContext context) {
    final provenance = profile['factProvenance'] as Map? ?? const {};
    if (facts.isEmpty && provenance.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (final entry in _factLabels.entries) {
      final detail = provenance[entry.key] as Map?;
      if (detail?['source'] == 'thaid' ||
          (hideMock &&
              (detail?['dataStatus'] == 'mock' ||
                  detail?['source'] == 'demo_answers'))) {
        continue;
      }
      if (facts.containsKey(entry.key) ||
          detail != null ||
          const {'disabilityCard', 'ss33', 'taxWithheld'}.contains(entry.key)) {
        rows.add(_factRow(entry.value, facts[entry.key], detail));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('ข้อมูลที่ใช้คัดกรอง'),
      children: rows,
    );
  }

  Widget _factRow(String label, Object? value, Map? detail) {
    final year = detail?['taxYear'];
    final date = checkedDate(profileText(detail?['checkedAt']));
    return ProfileDetailRow(
      icon: Icons.fact_check_outlined,
      label: year is int ? '$label · ปีภาษี ${year + 543}' : label,
      value: [
        if (detail?['status'] == 'conflict')
          'รอยืนยัน · ค่าจากแหล่งข้อมูล ${_factValue(detail?['value'])} · คุณตอบ ${_factValue(detail?['userValue'])}'
        else if (detail?['status'] == 'stale')
          'ข้อมูลเก่า ${_factValue(detail?['value'])} · รอตรวจข้อมูลปัจจุบัน'
        else
          _factValue(value),
        if (detail?['confirmed'] == true)
          'คุณยืนยัน'
        else if (_factSources[detail?['source']] case final source?)
          source
        else if (value != null)
          'คำตอบในโปรไฟล์',
        if (date != null) 'ตรวจล่าสุด $date',
        if (detail?['dataStatus'] == 'mock') 'DEMO / MOCK',
      ].join(' · '),
    );
  }
}

class ProfileDetailRow extends StatelessWidget {
  const ProfileDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 24,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
