import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/task_screen.dart';

const _baseUrl = 'http://localhost:8080/notebook';
const _seniorGuide = '/docs/sources/thai-senior-benefits-2026-11-27.html#item-1';

class _ContactApi extends Api {
  _ContactApi({required this.moneyPlan}) : super(baseUrl: _baseUrl);

  final bool moneyPlan;

  Map<String, dynamic> get task => {
    'id': 't1',
    'title': moneyPlan ? 'เบี้ยยังชีพผู้สูงอายุ' : 'งานตัวอย่าง',
    if (moneyPlan) 'moneyId': 'old_age' else 'opportunityId': 'job-1',
    'steps': ['เตรียมเอกสาร'],
    'doneCount': 0,
    'status': 'active',
  };

  @override
  Future<Map<String, bool>?> currentPurposes() async => {'core': true};

  @override
  Future<Map<String, dynamic>> get(String path) async {
    switch (path) {
      case '/v1/tasks/t1': return task;
      case '/v1/tasks': return {'items': [task]};
      case '/v1/opportunities/job-1': return {
        'title': 'งานตัวอย่าง', 'mapGroup': 'job', 'provenance': {'dataStatus': 'curated'},
      };
      case '/v1/money/old_age': return {
        'title': 'เบี้ยยังชีพผู้สูงอายุ', 'status': 'likely', 'amount': {'value': 600},
        'documents': [], 'channels': [{'title': 'สำนักงานเขตตามทะเบียนบ้าน', 'kind': 'office'}],
        'contactGuide': _seniorGuide,
      };
      default: throw StateError('Unexpected path $path');
    }
  }
}

void main() {
  Future<void> openContact(WidgetTester tester, {required bool moneyPlan}) async {
    final api = _ContactApi(moneyPlan: moneyPlan);
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home: TaskScreen(app: AppState(api), taskId: 't1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ข้อมูลติดต่อ'));
    await tester.pumpAndSettle();
  }

  testWidgets('a job without a real URL shows a labelled application example', (tester) async {
    await openContact(tester, moneyPlan: false);
    expect(find.text('ข้อมูลสมัครงาน'), findsOneWidget);
    expect(find.text('DEMO / MOCK'), findsOneWidget);
    expect(find.text('เปิดหน้าสมัครงาน'), findsNothing);
  });

  testWidgets('a benefit plan opens the contact channels of that exact benefit', (tester) async {
    await openContact(tester, moneyPlan: true);
    expect(find.text('เส้นทางรับเงิน'), findsOneWidget);
    expect(find.text('สำนักงานเขตตามทะเบียนบ้าน'), findsOneWidget);
    expect(find.text('ข้อมูลสมัครงาน'), findsNothing);
  });

  testWidgets('contact opens the project HTML at the correct row without asking whether a claim was filed', (tester) async {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final opened = <String>[];
    messenger.setMockMethodCallHandler(launcher, (call) async {
      expect(call.method, 'launch');
      opened.add((call.arguments as Map)['url'] as String);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));

    await openContact(tester, moneyPlan: true);
    await tester.tap(find.text('ติดต่อ ↗'));
    await tester.pumpAndSettle();
    expect(opened, ['$_baseUrl$_seniorGuide']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('กลับมาแล้ว 👋'), findsNothing);
    expect(find.text('เส้นทางรับเงิน'), findsOneWidget);
  });
}
