import 'dart:async';

import 'api.dart';

enum DemoSource {
  thaid(
    'thaid',
    'identity',
    'ThaID',
    'thaid.png',
    'อายุหรือช่วงอายุ และเขตตามทะเบียนบ้านจำลอง',
  ),
  thangRat(
    'tangRat',
    'disabilityCard',
    'ทางรัฐ',
    'thangrat.png',
    'สถานะบัตรประจำตัวคนพิการจำลอง',
  ),
  socialSecurity(
    'socialSecurity',
    'ss33',
    'ประกันสังคม (SSO+)',
    'sso-plus.png',
    'มาตราผู้ประกันตนและประวัติส่งเงินสมทบจำลอง',
  ),
  dMyTax(
    'dMyTax',
    'taxWithheld',
    'D-MyTax',
    'd-mytax.png',
    'ปีภาษีและยอดหักภาษี ณ ที่จ่ายจำลอง',
  );

  const DemoSource(
    this.id,
    this.field,
    this.label,
    this.image,
    this.description,
  );
  final String id, field, label, image, description;

  String answer(String choices) => choices.length > index ? choices[index] : '';

  Map<String, String> get previewFields => switch (this) {
    thaid => const {
      'name': 'ชื่อ-นามสกุล',
      'age': 'อายุหรือช่วงอายุ',
      'district': 'เขตตามทะเบียนบ้าน',
    },
    thangRat => const {'card': 'บัตรประจำตัวคนพิการ'},
    socialSecurity => const {
      'section': 'มาตราผู้ประกันตน',
      'contributions': 'ประวัติส่งเงินสมทบ',
    },
    dMyTax => const {'taxYear': 'ปีภาษี', 'withholding': 'ภาษีหัก ณ ที่จ่าย'},
  };

  Future<Map<String, String>> loadPreview(Api api) async {
    final sample = await api
        .get(personaPath([this]))
        .timeout(const Duration(seconds: 8));
    final sources = sample['sources'];
    final row = sources is List
        ? sources
              .whereType<Map>()
              .where((row) => row['field'] == field)
              .firstOrNull
        : null;
    if (sample['dataStatus'] != 'mock' || row == null) {
      throw ApiException(0, 'DEMO_DATA', 'ข้อมูลจำลองของบริการนี้ไม่พร้อม');
    }
    final preview = row['preview'];
    if (preview is Map) {
      return {
        for (final key in previewFields.keys)
          if (preview[key] case final String value when value.trim().isNotEmpty)
            key: value,
      };
    }
    // Older servers provide the synthetic identity and a source summary.
    if (this == thaid) {
      final profile = sample['profile'];
      return {
        if (profile case {'displayName': final String name}) 'name': name,
        if (profile case {'district': final String district})
          'district': district,
        if (row['value'] case final String age) 'age': age,
      };
    }
    return {
      if (row['value'] case final String value)
        (this == thangRat ? 'card' : 'summary'): value,
    };
  }

  static bool enabled(Map<String, dynamic> config) =>
      config['mode'] == 'demo' &&
      config['featureFlags'] is Map &&
      config['featureFlags']['demo'] == true;

  static String personaPath(Iterable<DemoSource> sources) => Uri(
    path: '/v1/demo/personas/gov-prefill',
    queryParameters: {'sources': sources.map((source) => source.id).join(',')},
  ).toString();
}

const onboardingDemoDevice = 'thang-rot-onboarding';

enum AssessmentStatus { loading, ready, configUnavailable, failed }

class OpportunityAssessment {
  const OpportunityAssessment(
    this.status, {
    this.benefits = const [],
    this.income = const [],
    this.moneyOverview,
    this.mock = false,
  });

  final AssessmentStatus status;
  final List<Map<String, dynamic>> benefits, income;
  final Map<String, dynamic>? moneyOverview;
  final bool mock;

  static Future<OpportunityAssessment> load(
    Api api,
    List<DemoSource> sources, {
    void Function(Future<Map<String, dynamic>>)? trackDemoWrite,
  }) async {
    const timeout = Duration(seconds: 8);
    Future<Map<String, dynamic>> assessBenefits() async {
      if (sources.isEmpty) return api.get('/v1/money');
      final demo = api.forDemo(onboardingDemoDevice);
      try {
        final request = demo.post(DemoSource.personaPath(sources));
        trackDemoWrite?.call(request);
        final persona = await request;
        final facts = persona['facts'];
        if (persona['dataStatus'] != 'mock' || facts is! Map<String, dynamic>) {
          throw ApiException(0, 'DEMO_DATA', 'โหลดข้อมูลจำลองไม่ได้');
        }
        return await api.post('/v1/money/preview', {'facts': facts});
      } finally {
        demo.close();
      }
    }

    Future<Map<String, dynamic>?> assessIncome() async {
      try {
        return await api.get('/v1/plans/options').timeout(timeout);
      } on ApiException {
        return null;
      } on TimeoutException {
        return null;
      }
    }

    final incomeRequest = assessIncome();
    final benefits = await assessBenefits().timeout(timeout);
    final income = await incomeRequest;
    return OpportunityAssessment(
      AssessmentStatus.ready,
      benefits: itemsOf(benefits),
      income: itemsOf(income),
      moneyOverview: benefits,
      mock: sources.isNotEmpty,
    );
  }
}

List<Map<String, dynamic>> itemsOf(Map<String, dynamic>? response) =>
    response?['items'] is List
    ? (response!['items'] as List).whereType<Map<String, dynamic>>().toList()
    : [];
