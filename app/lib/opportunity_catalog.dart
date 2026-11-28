import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import 'money.dart';
import 'thang_rot_theme.dart';

enum OpportunityCategory {
  welfare('welfare', 'สวัสดิการรัฐ', Color(0xFF17644D)),
  refund('refund', 'เงินคืน', Color(0xFF146575)),
  owed('owed', 'เงินค้างจ่าย', Color(0xFF934622)),
  fullTime('job_full', 'งานประจำ', Color(0xFF1758AE)),
  partTime('job_part', 'พาร์ตไทม์', Color(0xFF5545A7)),
  freelance('freelance', 'ฟรีแลนซ์', Color(0xFF7B3F8D)),
  sell('sell', 'ขายสินค้า', Color(0xFF8A5317)),
  assets('assets', 'ใช้ทรัพย์สิน', Color(0xFF4E681E)),
  grant('grant', 'ทุนให้เปล่า', Color(0xFF8D4260)),
  skill('skill', 'ทักษะ', Color(0xFF136978));

  const OpportunityCategory(this.api, this.label, this.color);
  final String api, label;
  final Color color;

  bool get isJob => index >= fullTime.index && index <= freelance.index;
  bool get isBenefit => index <= owed.index;

  IconData get icon => switch (this) {
    welfare => Icons.volunteer_activism_outlined,
    refund => Icons.currency_exchange_outlined,
    owed => Icons.request_quote_outlined,
    fullTime => Icons.work_outline,
    partTime => Icons.schedule_outlined,
    freelance => Icons.laptop_mac_outlined,
    sell => Icons.storefront_outlined,
    assets => Icons.key_outlined,
    grant => Icons.account_balance_outlined,
    skill => Icons.build_outlined,
  };

  static OpportunityCategory? of(Map<String, dynamic> item) => values
      .where(
        (category) =>
            category.api == item['category'] ||
            category.index + 1 == item['categoryId'],
      )
      .firstOrNull;

  static OpportunityCategory? forMoney(String id) => switch (id) {
    'old_age' || 'unemployment' || 'child_support' || 'disability' => welfare,
    'tax_refund' => refund,
    'unpaid_wages' => owed,
    _ => null,
  };
}

class OpportunityArtwork extends StatelessWidget {
  const OpportunityArtwork({
    super.key,
    this.category,
    this.moneyId,
    this.size = 38,
  });

  final OpportunityCategory? category;
  final String? moneyId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = switch (moneyId) {
      'old_age' => 'benefit-senior',
      'unemployment' => 'benefit-unemployment',
      'child_support' => 'benefit-child',
      'disability' => 'benefit-disability',
      'tax_refund' => 'benefit-refund',
      'unpaid_wages' => 'benefit-wages',
      _ => null,
    };
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/thang-rot/$image.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: blueTint,
      foregroundColor: category?.color ?? brandDark,
      child: Icon(
        category?.icon ?? Icons.auto_awesome_outlined,
        size: size * .55,
      ),
    );
  }
}

// Names and order from the Bangkok scope handoff; codes from the official district register.
const bangkokDistricts = <String, String>{
  '1018': 'คลองสาน',
  '1046': 'คลองสามวา',
  '1033': 'คลองเตย',
  '1043': 'คันนายาว',
  '1030': 'จตุจักร',
  '1035': 'จอมทอง',
  '1036': 'ดอนเมือง',
  '1026': 'ดินแดง',
  '1002': 'ดุสิต',
  '1019': 'ตลิ่งชัน',
  '1048': 'ทวีวัฒนา',
  '1049': 'ทุ่งครุ',
  '1015': 'ธนบุรี',
  '1020': 'บางกอกน้อย',
  '1016': 'บางกอกใหญ่',
  '1006': 'บางกะปิ',
  '1021': 'บางขุนเทียน',
  '1031': 'บางคอแหลม',
  '1029': 'บางซื่อ',
  '1047': 'บางนา',
  '1050': 'บางบอน',
  '1025': 'บางพลัด',
  '1004': 'บางรัก',
  '1005': 'บางเขน',
  '1040': 'บางแค',
  '1027': 'บึงกุ่ม',
  '1007': 'ปทุมวัน',
  '1032': 'ประเวศ',
  '1008': 'ป้อมปราบศัตรูพ่าย',
  '1014': 'พญาไท',
  '1001': 'พระนคร',
  '1009': 'พระโขนง',
  '1022': 'ภาษีเจริญ',
  '1010': 'มีนบุรี',
  '1012': 'ยานนาวา',
  '1037': 'ราชเทวี',
  '1024': 'ราษฎร์บูรณะ',
  '1011': 'ลาดกระบัง',
  '1038': 'ลาดพร้าว',
  '1045': 'วังทองหลาง',
  '1039': 'วัฒนา',
  '1034': 'สวนหลวง',
  '1044': 'สะพานสูง',
  '1013': 'สัมพันธวงศ์',
  '1028': 'สาทร',
  '1042': 'สายไหม',
  '1003': 'หนองจอก',
  '1023': 'หนองแขม',
  '1041': 'หลักสี่',
  '1017': 'ห้วยขวาง',
};

class OpportunityLocation {
  OpportunityLocation(Map data)
    : districtName = _districtName(data),
      districtCode = _districtCode(data),
      address = data['address'] as String?,
      text = data['text'] as String?,
      travelInfo = data['travelInfo'] as String?,
      point = _point(data);

  final String? districtCode, districtName, address, text, travelInfo;
  final LatLng? point;

  static String? _districtName(Map data) =>
      data['districtName'] as String? ??
      data['district'] as String? ??
      bangkokDistricts['${data['districtCode']}'];

  static String? _districtCode(Map data) {
    if (data['districtCode'] case final Object code) return '$code';
    final name = _districtName(data)
        ?.trim()
        .replaceFirst(RegExp(r'^เขต\s*'), '');
    final province = (data['province'] as String?)?.toLowerCase().replaceAll(
      RegExp(r'[\s.]'),
      '',
    );
    if (province != null &&
        !{
          'กรุงเทพมหานคร',
          'กรุงเทพฯ',
          'กรุงเทพ',
          'กทม',
          'bangkok',
        }.contains(province)) {
      return null;
    }
    return bangkokDistricts.entries
        .where((entry) => entry.value == name)
        .firstOrNull
        ?.key;
  }

  static LatLng? _point(Map data) {
    final lat = data['lat'], lng = data['lng'];
    if (data['coordinateSource'] != 'database' ||
        data['precision'] != 'exact' ||
        data['workMode'] == 'remote' ||
        data['isRemote'] == true ||
        {
          'remote',
          'service',
          'service_area',
          'district',
        }.contains(data['areaType']) ||
        lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  static List<OpportunityLocation> of(Map<String, dynamic> item) {
    final locations = (item['locations'] is List
        ? (item['locations'] as List).whereType<Map>()
        : const <Map>[]);
    if (locations.isNotEmpty) {
      return locations.map(OpportunityLocation.new).toList();
    }
    return [if (item['location'] case final Map old) OpportunityLocation(old)];
  }
}

bool opportunityExpired(Map<String, dynamic> item) {
  final provenance = item['provenance'] as Map?;
  final expires = DateTime.tryParse(
    '${item['expiresAt'] ?? provenance?['expiresAt'] ?? ''}',
  );
  return {'closed', 'expired'}.contains(item['status']) ||
      {'closed', 'expired'}.contains(item['availability']) ||
      (expires != null && !expires.isAfter(DateTime.now()));
}

bool hasOpportunityIncome(Map<String, dynamic> item) {
  final money = item['money'] as Map?;
  return money?['basis'] != 'none' &&
      (money?['min'] is num || money?['max'] is num) &&
      money?['unit'] is String;
}

String oppMoney(Map<String, dynamic> item) {
  final money = item['money'] as Map?;
  final min = money?['min'], max = money?['max'];
  if (money?['basis'] == 'none' || (min is! num && max is! num)) {
    return '${money?['knownText'] ?? 'ไม่ทราบจำนวนเงิน'}';
  }
  String format(num value) => baht(value).replaceFirst('฿', '');
  final range = min is num && max is num && min != max
      ? '${format(min)}-${format(max)}'
      : format(min is num ? min : max as num);
  final basis = switch (money?['basis']) {
    'official' => 'ตามประกาศทางการ',
    'estimate' => 'ประมาณการ',
    _ => 'ตามประกาศ',
  };
  return '$range ${money?['unit'] ?? 'บาท'} ($basis)';
}

const benefitStatusLabel = {
  'verified': 'ยืนยันจากหน่วยงาน',
  'likely': 'น่าจะมีสิทธิ์',
  'check': 'ต้องตรวจสอบเพิ่มเติม',
  'need': 'ข้อมูลยังไม่พอประเมิน',
  'unlikely': 'ไม่น่ามีสิทธิ์ตามข้อมูลที่มี',
};

String benefitAmount(Map<String, dynamic> item) {
  final amount = item['amount'] as Map?;
  final value = amount?['value'];
  if (value is! num) return 'ตรวจสอบยอดกับหน่วยงาน';
  final basis = switch (amount?['basis']) {
    'verified' => 'จากหน่วยงาน',
    'calc' => 'ประมาณการตามเกณฑ์',
    _ => 'อัตราตามเกณฑ์',
  };
  return '${baht(value).substring(1)} ${amount?['unit'] ?? 'บาท'} ($basis)';
}
