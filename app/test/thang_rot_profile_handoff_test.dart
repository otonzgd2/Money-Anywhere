import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/profile_overview_screen.dart';

class _ProvenanceApi extends Api {
  @override
  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String>? headers,
  ]) async {
    switch (path) {
      case '/v1/me/gov-link':
        return {'status': 'not_connected'};
      case '/v1/app-config':
        return {
          'mode': 'demo',
          'featureFlags': {'demo': true},
        };
      case '/v1/me/facts':
        return {'disabilityCard': true, 'nationality': false};
      case '/v1/me/profile':
        return {
          'displayName': 'ทดสอบข้อมูลของฉัน',
          'dataStatus': 'mock',
          'factProvenance': {
            'disabilityCard': {
              'value': true,
              'source': 'tangRat',
              'dataStatus': 'mock',
              'checkedAt': '2026-11-27',
            },
            'nationality': {
              'value': false,
              'source': 'user',
              'checkedAt': '2026-11-27T18:00:00Z',
            },
          },
        };
      default:
        throw StateError('Unexpected GET $path');
    }
  }
}

void main() {
  testWidgets(
    'MAN-21 profile shows dated sources and distinguishes unknown from no',
    (tester) async {
      final api = _ProvenanceApi();
      addTearDown(api.close);
      tester.view.physicalSize = const Size(800, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ProfileOverviewScreen(app: AppState(api))),
      );
      await tester.pumpAndSettle();

      final screening = find.text('ข้อมูลที่ใช้คัดกรอง');
      final form = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(screening, 100, scrollable: form);
      await tester.tap(screening);
      await tester.pumpAndSettle();
      final datedCard = find.text(
        'ใช่ · ทางรัฐ · ตรวจล่าสุด 27/11/2569 · DEMO / MOCK',
      );
      await tester.scrollUntilVisible(datedCard, 100, scrollable: form);
      expect(datedCard.hitTestable(), findsOneWidget);
      expect(
        find.text('ไม่มี / ไม่ใช่ · คุณกรอกเอง · ตรวจล่าสุด 28/11/2569'),
        findsOneWidget,
      );

      final noTaxRecord = find.ancestor(
        of: find.text('ภาษีหัก ณ ที่จ่าย'),
        matching: find.byType(ListTile),
      );
      await tester.scrollUntilVisible(noTaxRecord, 100, scrollable: form);
      expect(
        find.descendant(of: noTaxRecord, matching: find.text('ยังไม่มีข้อมูล')),
        findsOneWidget,
      );
    },
  );
}
