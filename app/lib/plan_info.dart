import 'package:material_ui/material_ui.dart';

import 'common.dart';
import 'opportunity_catalog.dart';

enum PlanLayout {
  claim('สิทธิ์และเงิน'),
  job('ข้อมูลงาน'),
  income('ช่องทางหารายได้'),
  grant('ข้อมูลรอบทุน');

  const PlanLayout(this.label);
  final String label;

  static PlanLayout? of(OpportunityCategory? category) => switch (category) {
    OpportunityCategory.welfare ||
    OpportunityCategory.refund ||
    OpportunityCategory.owed => claim,
    OpportunityCategory.fullTime ||
    OpportunityCategory.partTime ||
    OpportunityCategory.freelance => job,
    OpportunityCategory.sell ||
    OpportunityCategory.assets ||
    OpportunityCategory.skill => income,
    OpportunityCategory.grant => grant,
    null => null,
  };
}

enum PlanSourceState { loading, available, missing, failed }

String? planText(Object? value) => switch (value) {
  String text when text.trim().isNotEmpty => text.trim(),
  num value => '$value',
  List values when values.isNotEmpty =>
    values.map(planText).nonNulls.join(' · '),
  _ => null,
};

String? planDate(Object? value) {
  final text = planText(value);
  if (text == null) return null;
  final time = DateTime.tryParse(text);
  if (time == null) return text;
  final zone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);
  if (!text.contains('T') || !zone.hasMatch(text)) return text;
  final thailand = time.toUtc().add(const Duration(hours: 7));
  String two(int number) => '$number'.padLeft(2, '0');
  return '${two(thailand.day)}/${two(thailand.month)}/${thailand.year + 543} ${two(thailand.hour)}:${two(thailand.minute)} น. (เวลาไทย)';
}

Uri? planWebUri(Object? value) {
  final text = planText(value);
  if (text == null) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  if (uri.host.endsWith('.example') ||
      {
        'example.com',
        'example.org',
        'example.net',
      }.any((domain) => uri.host == domain || uri.host.endsWith('.$domain'))) {
    return null;
  }
  return uri;
}

class PlanContact {
  PlanContact(Map data, {required bool isJob, required bool legacy})
    : label = planText(data['label'] ?? data['title']) ?? '',
      purpose =
          planText(data['purpose']) ??
          (legacy && data['kind'] == 'online' ? 'submit' : null),
      type =
          planText(data['type']) ??
          (data['url'] != null ? 'website' : planText(data['kind'])),
      hours = planText(data['hoursText']),
      instructions = planText(data['instructions'] ?? data['detail']),
      districtCode = planText(data['districtCode']),
      checkedAt = planDate(data['checkedAt']),
      source = planWebUri(data['sourceUrl']),
      takesApplications = _applies(data, isJob, legacy),
      destination = _destination(data);

  final String label;
  final String? purpose, type, hours, instructions, districtCode, checkedAt;
  final Uri? destination, source;
  final bool takesApplications;

  static bool _applies(Map data, bool isJob, bool legacy) =>
      {
        'apply',
        'submit',
        'สมัครงาน',
        'สมัคร',
        'ยื่นเรื่อง',
      }.contains(data['purpose']) ||
      (legacy && (isJob || data['kind'] == 'online'));

  static Uri? _destination(Map data) {
    if (data['linkStatus'] == 'broken') return null;
    final destination = planText(
      data['destination'] ?? data['url'] ?? data['phone'],
    );
    if (destination == null) return null;
    switch (data['type'] ?? (data['url'] == null ? data['kind'] : 'website')) {
      case 'phone':
      case 'tel':
        final phone = destination
            .replaceFirst('tel:', '')
            .replaceAll(RegExp(r'[\s()-]'), '');
        return RegExp(r'^\+?\d{3,15}$').hasMatch(phone)
            ? Uri(scheme: 'tel', path: phone)
            : null;
      case 'email':
        final email = destination.replaceFirst('mailto:', '');
        return RegExp(r'^[^\s?&#@]+@[^\s?&#@]+\.[^\s?&#@]+$').hasMatch(email)
            ? Uri(scheme: 'mailto', path: email)
            : null;
      case 'map':
      case 'website':
      case 'online':
        return planWebUri(destination);
      default:
        return null;
    }
  }

  String? get purposeLabel => switch (purpose) {
    'apply' => 'สมัครงาน',
    'submit' => 'ยื่นเรื่อง',
    'ask' || 'ask_before_visit' => 'ถามก่อนเดินทาง',
    'follow_up' || 'followUp' => 'ติดตามผล',
    _ => purpose,
  };

  String get action => switch (destination?.scheme) {
    'tel' => 'โทร ${destination!.path}',
    'mailto' => 'ส่งอีเมล',
    _ when type == 'map' => 'เปิดแผนที่',
    _ => 'เปิดเว็บไซต์',
  };
}

class PlanInfo {
  PlanInfo(this.task, this.entry, this.state);
  final Map<String, dynamic> task, entry;
  final PlanSourceState state;

  String get title =>
      planText(entry['title']) ?? planText(task['title']) ?? 'รายละเอียดแผน';
  String? get moneyId => task['moneyId'] as String?;
  String? get districtCode => planText(task['districtCode']);
  OpportunityCategory? get category => moneyId == null
      ? OpportunityCategory.of(entry) ?? OpportunityCategory.of(task)
      : OpportunityCategory.forMoney(moneyId!);
  PlanLayout? get layout => PlanLayout.of(category);
  Map get provenance => (entry['provenance'] as Map?) ?? const {};
  Map get details => switch (layout) {
    PlanLayout.claim => (entry['claim'] as Map?) ?? const {},
    PlanLayout.job => (entry['job'] as Map?) ?? const {},
    PlanLayout.income => (entry['income'] as Map?) ?? const {},
    PlanLayout.grant => (entry['grant'] as Map?) ?? const {},
    null => const {},
  };
  String? get organization => planText(entry['organization'] ?? entry['payer']);
  String? get summary => planText(entry['summary'] ?? entry['description']);
  String? get dataStatus =>
      planText(entry['dataStatus'] ?? provenance['dataStatus']);
  bool get mock => dataStatus == 'mock';
  Object? get closingTime =>
      entry['expiresAt'] ??
      provenance['expiresAt'] ??
      (layout == PlanLayout.grant ? details['closesAt'] : null);
  bool get closed =>
      opportunityExpired(entry) ||
      (DateTime.tryParse('${closingTime ?? ''}')?.isBefore(DateTime.now()) ??
          false);
  String? get availability => closed
      ? 'ปิดรับแล้ว'
      : switch (entry['availability'] ??
            (moneyId == null ? entry['status'] : null)) {
          'open' || 'active' => 'เปิดรับ',
          'upcoming' => 'ยังไม่เปิดรับ',
          'paused' => 'พักรับชั่วคราว',
          _ => null,
        };
  String? get amount {
    if (state != PlanSourceState.available) return null;
    if (moneyId != null) return benefitAmount(entry);
    if (entry['money'] is Map) return oppMoney(entry);
    final amount = entry['amount'];
    if (amount is! Map) return null;
    return amount['value'] is num
        ? benefitAmount(entry)
        : oppMoney({'money': amount});
  }

  String? get contactGuide {
    final guide = planText(entry['contactGuide']);
    return guide != null && guide.startsWith('/docs/') ? guide : null;
  }

  Uri? get source => mock || provenance['linkStatus'] == 'broken'
      ? null
      : planWebUri(entry['sourceUrl'] ?? provenance['sourceUrl']);
  bool get sampleApplication =>
      state == PlanSourceState.available &&
      !closed &&
      mock &&
      layout == PlanLayout.job;

  Iterable<Map> get references =>
      (entry['sources'] as List? ?? const []).whereType<Map>();
  String? get attribution =>
      planText(provenance['attribution'] ?? provenance['provider']);
  String? get checkedAt =>
      planDate(entry['checkedAt'] ?? provenance['linkCheckedAt']);

  List<String> get conditions => [
    ...((entry['conditions'] as List?) ?? const []).whereType<String>(),
    for (final item in (entry['reasons'] as List? ?? const []).whereType<Map>())
      ?planText(item['text']),
  ];

  List<String> get documents => [
    for (final document in (entry['documents'] as List? ?? const []))
      ?planText(document is Map ? document['text'] : document),
  ];

  List<OpportunityLocation> get locations {
    final all = OpportunityLocation.of(entry);
    if (districtCode == null) return all;
    return all
        .where((location) => location.districtCode == districtCode)
        .toList();
  }

  Iterable<PlanContact> get contacts sync* {
    final legacy = (entry['channels'] as List?) ?? const [];
    final supplied = (entry['contacts'] as List?) ?? const [];
    for (final item in [...supplied, ...legacy]) {
      final contact = PlanContact(
        item is Map ? item : {'label': item},
        isJob: layout == PlanLayout.job,
        legacy: legacy.contains(item),
      );
      if (contact.label.isNotEmpty &&
          (districtCode == null ||
              contact.districtCode == null ||
              contact.districtCode == districtCode)) {
        yield contact;
      }
    }
    if (supplied.isEmpty && legacy.isEmpty && source != null && !closed) {
      yield PlanContact(
        {
          'label': organization ?? 'เว็บไซต์ผู้เผยแพร่',
          'type': 'website',
          'destination': source.toString(),
          if (layout == PlanLayout.job) 'purpose': 'apply',
        },
        isJob: layout == PlanLayout.job,
        legacy: false,
      );
    }
  }

  List<(String, String)> get facts {
    final fields = switch (layout) {
      PlanLayout.claim => const {
        'paymentCycle': 'รอบการจ่าย',
        'refundType': 'ประเภทเงินคืน',
        'counterparty': 'คู่กรณีหรือผู้จ่าย',
        'taxYear': 'ปีภาษี',
        'referencePeriod': 'ช่วงอ้างอิง',
        'owedPeriod': 'ช่วงที่ค้าง',
        'calculation': 'วิธีคำนวณ',
        'evidence': 'หลักฐาน',
        'deadline': 'กรอบเวลา',
      },
      PlanLayout.job => const {
        'workMode': 'รูปแบบการทำงาน',
        'workHours': 'เวลาทำงาน',
        'shift': 'กะ',
        'workDays': 'วันทำงาน',
        'benefits': 'สวัสดิการ',
        'meetingPoint': 'จุดนัด',
        'deliverables': 'สิ่งที่ส่งมอบ',
        'dueAt': 'กำหนดส่ง',
        'paymentTerms': 'งวดและเงื่อนไขจ่าย',
      },
      PlanLayout.income => const {
        'productType': 'ประเภทสินค้า',
        'acceptedItems': 'สินค้าที่รับ',
        'fees': 'ค่าธรรมเนียม',
        'appointment': 'เวลานัด',
        'assetType': 'ประเภททรัพย์สิน',
        'rentalModel': 'รูปแบบการให้เช่า',
        'costs': 'ต้นทุน',
        'deposit': 'ค่ามัดจำ',
        'handover': 'การส่งมอบและคืน',
        'skills': 'ทักษะที่จะได้',
        'classSchedule': 'รอบเรียนและเวลา',
        'tuition': 'ค่าเรียน',
        'services': 'งานที่รับ',
        'assumptions': 'สมมติฐาน',
      },
      PlanLayout.grant => const {
        'round': 'รอบทุน',
        'opensAt': 'เปิดรับ',
        'announcementAt': 'ประกาศผล',
        'eligibility': 'คุณสมบัติ',
      },
      null => const <String, String>{},
    };
    final status = moneyId == null ? null : benefitStatusLabel[entry['status']];
    final cycle = switch (entry['kind']) {
      'monthly' => 'รายเดือน',
      'once' => 'ครั้งเดียว',
      _ => null,
    };
    final workMode = switch ((details['workMode'] ??
        (entry['location'] as Map?)?['workMode'])) {
      'onsite' => 'ที่สถานที่ทำงาน',
      'hybrid' => 'ผสมผสาน',
      'remote' => 'ทำงานทางไกล',
      final String value => value,
      _ => null,
    };
    return [
      if (status != null) ('ผลประเมิน', status),
      if (cycle != null && details['paymentCycle'] == null)
        ('รอบการจ่าย', cycle),
      if (workMode != null && layout == PlanLayout.job)
        ('รูปแบบการทำงาน', workMode),
      if (category == OpportunityCategory.skill &&
          details['type'] == 'training')
        ('รูปแบบ', 'อบรม'),
      if (category == OpportunityCategory.skill &&
          details['type'] == 'paid_service')
        ('รูปแบบ', 'งานจากทักษะ'),
      for (final field in fields.entries)
        if (field.key != 'workMode')
          if (({
                    'dueAt',
                    'opensAt',
                    'announcementAt',
                    'deadline',
                  }.contains(field.key)
                  ? planDate(details[field.key])
                  : planText(details[field.key]))
              case final value?)
            (field.value, value),
      if (planDate(closingTime) case final date?) ('ปิดรับ', date),
    ];
  }
}

class PlanHeading extends StatelessWidget {
  const PlanHeading({
    super.key,
    required this.info,
    this.demo = false,
    this.showAmount = false,
    this.action,
  });
  final PlanInfo info;
  final bool demo, showAmount;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = info.category?.color ?? theme.colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      color: Color.alphaBlend(
        color.withValues(alpha: .09),
        theme.colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (info.category case final category?)
                  Chip(
                    backgroundColor: color,
                    side: BorderSide.none,
                    label: Text(
                      category.label,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                if (demo || info.mock) const DemoPill(),
              ],
            ),
            Semantics(
              header: true,
              child: Text(
                info.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (info.organization case final organization?) Text(organization),
            if (info.availability case final status?)
              Text(status, style: theme.textTheme.titleSmall),
            if (showAmount && info.amount != null)
              Text(info.amount!, style: theme.textTheme.titleMedium),
            ?action,
          ],
        ),
      ),
    );
  }
}

class PlanSection extends StatelessWidget {
  const PlanSection(this.title, this.children, {super.key});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      const SizedBox(height: 6),
      ...children,
    ],
  );
}

List<Widget> planArea(PlanInfo info) => [
  if (info.districtCode case final code?)
    if (bangkokDistricts[code] case final name?) Text('เขต$name'),
  for (final location in info.locations) ...[
    if (location.districtName case final name? when info.districtCode == null)
      Text(name),
    if ((location.address ?? location.text) case final address?) Text(address),
    if (location.travelInfo case final trip?) Text(trip),
    if (location.point case final point?)
      Text('พิกัด ${point.latitude}, ${point.longitude}'),
  ],
];

String? planSourceMessage(PlanSourceState state) => switch (state) {
  PlanSourceState.missing => 'ไม่พบประกาศหรือข้อมูลต้นทางแล้ว',
  PlanSourceState.failed => 'โหลดรายละเอียดต้นทางไม่สำเร็จ',
  _ => null,
};
