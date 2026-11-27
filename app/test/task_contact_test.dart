import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/opp_tab.dart';
import 'package:money_anywhere/task_screen.dart';

const _baseUrl = 'http://localhost:8080/notebook';
const _seniorGuide = '/docs/sources/thai-senior-benefits-2026-11-27.html#item-1';
const _jobTitle = 'งานแพ็คของ รายวัน (กะเช้า & กะบ่าย #2 + งานเสริม)';
const _listingTitle = 'ผู้ช่วยร้านอาหาร พาร์ตไทม์';
const _demoPage = '$_baseUrl/docs/mockups/job-application.html';
final _demoUrl = '$_demoPage#title=${Uri.encodeComponent(_jobTitle)}';
final _detailsDemoUrl = '$_demoPage#title=${Uri.encodeComponent(_listingTitle)}';
const _jobUrl = 'https://careers.company.test/apply';

class _ContactApi extends Api {
  _ContactApi({required this.moneyPlan, this.jobUrl, this.listingMissing = false}) : super(baseUrl: _baseUrl);

  final bool moneyPlan;
  final String? jobUrl;
  final bool listingMissing;

  Map<String, dynamic> get task => {
    'id': 't1',
    'title': moneyPlan ? 'เบี้ยยังชีพผู้สูงอายุ' : _jobTitle,
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
      case '/v1/opportunities/job-1':
        if (listingMissing) throw ApiException(404, 'NOT_FOUND', 'ไม่พบประกาศ');
        return {'title': _listingTitle, 'mapGroup': 'job', 'provenance': {'dataStatus': 'curated', 'sourceUrl': jobUrl}};
      case '/v1/money/old_age': return {
        'title': 'เบี้ยยังชีพผู้สูงอายุ', 'status': 'likely', 'amount': {'value': 600},
        'documents': [], 'channels': [{'title': 'สำนักงานเขตตามทะเบียนบ้าน', 'kind': 'office'}],
        'contactGuide': _seniorGuide,
      };
      default: throw StateError('Unexpected path $path');
    }
  }
}

class _LinkClient implements HttpClient {
  _LinkClient(this.statusCode);

  final int statusCode;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    expect(url.toString(), _jobUrl);
    return _LinkRequest(statusCode);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LinkRequest implements HttpClientRequest {
  _LinkRequest(this.statusCode);

  final int statusCode;

  @override
  Future<HttpClientResponse> close() async => _LinkResponse(statusCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LinkResponse implements HttpClientResponse {
  _LinkResponse(this.statusCode);

  @override
  final int statusCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> openContact(WidgetTester tester, {required bool moneyPlan, String? jobUrl, bool listingMissing = false}) async {
    final api = _ContactApi(moneyPlan: moneyPlan, jobUrl: jobUrl, listingMissing: listingMissing);
    addTearDown(api.close);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: TaskScreen(app: AppState(api), taskId: 't1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ข้อมูลติดต่อ'));
    await tester.pumpAndSettle();
  }

  Future<void> returnFromBrowser(WidgetTester tester) async {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  List<String> recordLinks({bool Function(String)? launch}) {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final opened = <String>[];
    messenger.setMockMethodCallHandler(launcher, (call) async {
      expect(call.method, 'launch');
      final url = (call.arguments as Map)['url'] as String;
      opened.add(url);
      return launch?.call(url) ?? true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
    return opened;
  }

  Future<void> applyFromDetails(WidgetTester tester, {String? sourceUrl}) async {
    final api = _ContactApi(moneyPlan: false);
    addTearDown(api.close);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: OppScreen(app: AppState(api), opp: {
      'id': 'job-1', 'title': _listingTitle, 'mapGroup': 'job', 'money': {'basis': 'none'},
      'provenance': {'dataStatus': 'curated', 'sourceUrl': sourceUrl},
    })));
    await tester.tap(find.text('สมัครงาน ↗'));
    await tester.pumpAndSettle();
  }

  testWidgets('the job detail has a demo application button without a source URL', (tester) async {
    final opened = recordLinks();
    await applyFromDetails(tester);
    expect(opened, [_detailsDemoUrl]);
    await returnFromBrowser(tester);
    expect(find.text('กลับมาแล้ว 👋'), findsNothing);
  });

  testWidgets('a broken link from job details opens the same demo HTML as a plan', (tester) async {
    final opened = recordLinks();
    await HttpOverrides.runZoned(
      () => applyFromDetails(tester, sourceUrl: _jobUrl),
      createHttpClient: (_) => _LinkClient(404),
    );
    expect(opened, [_detailsDemoUrl]);
  });

  testWidgets('a reachable link from job details opens the employer site directly', (tester) async {
    final opened = recordLinks();
    await HttpOverrides.runZoned(
      () => applyFromDetails(tester, sourceUrl: _jobUrl),
      createHttpClient: (_) => _LinkClient(200),
    );
    expect(opened, [_jobUrl]);
    await returnFromBrowser(tester);
    expect(find.text('กลับมาแล้ว 👋'), findsOneWidget);
    await tester.tap(find.text('ไม่ต้องบันทึก'));
    await tester.pumpAndSettle();
  });

  testWidgets('a job without a real URL opens the demo HTML directly from the plan', (tester) async {
    final opened = recordLinks();
    await openContact(tester, moneyPlan: false);
    expect(opened, [_demoUrl]);
    expect(find.text('ข้อมูลติดต่อ'), findsOneWidget);

    await returnFromBrowser(tester);
    expect(find.text('กลับมาแล้ว 👋'), findsNothing);
  });

  testWidgets('a deleted job posting opens the demo HTML from the saved plan', (tester) async {
    final opened = recordLinks();
    await openContact(tester, moneyPlan: false, listingMissing: true);
    expect(opened, [_demoUrl]);
  });

  testWidgets('an application URL returning 404 opens the demo HTML immediately', (tester) async {
    final opened = recordLinks();
    await HttpOverrides.runZoned(
      () => openContact(tester, moneyPlan: false, jobUrl: _jobUrl),
      createHttpClient: (_) => _LinkClient(404),
    );
    expect(opened, [_demoUrl]);
  });

  testWidgets('a reachable application URL opens the employer site', (tester) async {
    final opened = recordLinks();
    await HttpOverrides.runZoned(
      () => openContact(tester, moneyPlan: false, jobUrl: _jobUrl),
      createHttpClient: (_) => _LinkClient(200),
    );
    expect(opened, isEmpty);
    await tester.tap(find.text('เปิดหน้าสมัครงาน'));
    await tester.pumpAndSettle();
    expect(opened, [_jobUrl]);

    await returnFromBrowser(tester);
    expect(find.text('กลับมาแล้ว 👋'), findsOneWidget);
    await tester.tap(find.text('ไม่ต้องบันทึก'));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed browser launch of a reachable job URL opens the demo HTML', (tester) async {
    final opened = recordLinks(launch: (url) => url == _demoUrl);
    await HttpOverrides.runZoned(
      () => openContact(tester, moneyPlan: false, jobUrl: _jobUrl),
      createHttpClient: (_) => _LinkClient(200),
    );
    await tester.tap(find.text('เปิดหน้าสมัครงาน'));
    await tester.pumpAndSettle();
    expect(opened, [_jobUrl, _demoUrl]);
  });

  testWidgets('a failed browser launch of the demo gives the user a retry', (tester) async {
    var allowLaunch = false;
    final opened = recordLinks(launch: (_) => allowLaunch);
    await openContact(tester, moneyPlan: false);
    expect(find.text('เปิดหน้าสมัครงานจำลองไม่ได้'), findsOneWidget);
    allowLaunch = true;
    await tester.tap(find.text('ลองเปิดหน้าสมัครงานจำลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(opened, [_demoUrl, _demoUrl]);
    expect(find.text('ข้อมูลติดต่อ'), findsOneWidget);
  });

  testWidgets('a benefit plan opens the contact channels of that exact benefit', (tester) async {
    await openContact(tester, moneyPlan: true);
    expect(find.text('เส้นทางรับเงิน'), findsOneWidget);
    expect(find.text('สำนักงานเขตตามทะเบียนบ้าน'), findsOneWidget);
    expect(find.text('ข้อมูลสมัครงาน'), findsNothing);
  });

  testWidgets('contact opens the project HTML at the correct row without asking whether a claim was filed', (tester) async {
    final opened = recordLinks();

    await openContact(tester, moneyPlan: true);
    await tester.tap(find.text('ติดต่อ ↗'));
    await tester.pumpAndSettle();
    expect(opened, ['$_baseUrl$_seniorGuide']);

    await returnFromBrowser(tester);
    expect(find.text('กลับมาแล้ว 👋'), findsNothing);
    expect(find.text('เส้นทางรับเงิน'), findsOneWidget);
  });
}
