import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';

enum DemoSource {
  thaid(
    'thaid',
    'ThaID',
    'thaid.png',
    'อายุหรือช่วงอายุ และเขตตามทะเบียนบ้านจำลอง',
  ),
  thangRat(
    'tangRat',
    'ทางรัฐ',
    'thangrat.png',
    'สถานะบัตรประจำตัวคนพิการจำลอง',
  ),
  socialSecurity(
    'socialSecurity',
    'ประกันสังคม (SSO+)',
    'sso-plus.png',
    'มาตราผู้ประกันตนและประวัติส่งเงินสมทบจำลอง',
  ),
  dMyTax(
    'dMyTax',
    'D-MyTax',
    'd-mytax.png',
    'ปีภาษีและยอดหักภาษี ณ ที่จ่ายจำลอง',
  );

  const DemoSource(this.id, this.label, this.image, this.description);
  final String id, label, image, description;
}

enum DemoChoice { use, skip, skipRemaining }

enum AssessmentStatus { loading, ready, configUnavailable, failed }

class OpportunityAssessment {
  const OpportunityAssessment(
    this.status, {
    this.benefits = const [],
    this.income = const [],
    this.mock = false,
  });

  final AssessmentStatus status;
  final List<Map<String, dynamic>> benefits, income;
  final bool mock;

  static Future<OpportunityAssessment> load(
    Api api,
    List<DemoSource> sources,
  ) async {
    const timeout = Duration(seconds: 8);
    Future<Map<String, dynamic>> assessBenefits() async {
      if (sources.isEmpty) return api.get('/v1/money');
      final demo = api.forDemo('thang-rot-onboarding');
      try {
        final query = Uri(
          queryParameters: {'sources': sources.map((s) => s.id).join(',')},
        );
        final persona = await demo.post(
          '/v1/demo/personas/gov-prefill?${query.query}',
        );
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
      mock: sources.isNotEmpty,
    );
  }
}

List<Map<String, dynamic>> itemsOf(Map<String, dynamic>? response) =>
    response?['items'] is List
    ? (response!['items'] as List).whereType<Map<String, dynamic>>().toList()
    : [];

Future<DemoChoice?> showDemoSource(BuildContext context, DemoSource source) =>
    showDialog<DemoChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          scrollable: true,
          title: Text(source.label),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/thang-rot/${source.image}',
                width: 144,
                height: 60,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
              ),
              const SizedBox(height: 12),
              const DemoPill(),
              const SizedBox(height: 12),
              const Text('ใช้ข้อมูลจำลองเพื่อประเมินสิทธิ์และรายได้'),
              const SizedBox(height: 8),
              Text(source.description),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, DemoChoice.skipRemaining),
              child: const Text('ข้ามทั้งหมด'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, DemoChoice.skip),
              child: const Text('ข้าม'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, DemoChoice.use),
              child: const Text('เชื่อมต่อข้อมูลจำลอง'),
            ),
          ],
        ),
      ),
    );
