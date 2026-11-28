import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/plan_contact_screen.dart';
import 'package:money_anywhere/opp_tab.dart';
import 'package:money_anywhere/task_screen.dart';
import 'package:money_anywhere/thang_rot_theme.dart';

const _baseUrl = 'http://localhost:8080/notebook';
const _seniorGuide =
    '/docs/sources/thai-senior-benefits-2026-11-27.html#item-1';
const _jobTitle = 'งานแพ็คของ รายวัน (กะเช้า & กะบ่าย #2 + งานเสริม)';
const _listingTitle = 'ผู้ช่วยร้านอาหาร พาร์ตไทม์';
const _demoPage = '$_baseUrl/docs/mockups/job-application.html';
final _detailsDemoUrl =
    '$_demoPage#title=${Uri.encodeComponent(_listingTitle)}';
const _jobUrl = 'https://careers.company.test/apply';
const _bangkokInfo =
    'http://localhost:8080/docs/mockups/opportunity-info.html?id=job-1';

class _ContactApi extends Api {
  _ContactApi({
    required this.moneyPlan,
    this.jobUrl,
    this.listingMissing = false,
    this.mock = false,
    this.provider,
    this.category = 'job_part',
  }) : super(baseUrl: _baseUrl);

  final bool moneyPlan;
  final String? jobUrl;
  final bool listingMissing;
  final bool mock;
  final String? provider;
  final String category;
  int sourceReads = 0;

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
    switch (Uri.parse(path).path) {
      case '/v1/tasks/t1':
        return task;
      case '/v1/tasks':
        return {
          'items': [task],
        };
      case '/v1/opportunities/job-1':
        sourceReads++;
        if (listingMissing) throw ApiException(404, 'NOT_FOUND', 'ไม่พบประกาศ');
        return {
          'title': _listingTitle,
          'category': category,
          'provenance': {
            'dataStatus': mock ? 'mock' : 'curated',
            'sourceUrl': jobUrl,
            'provider': provider,
          },
        };
      case '/v1/money/old_age':
        return {
          'title': 'เบี้ยยังชีพผู้สูงอายุ',
          'status': 'likely',
          'amount': {'value': 600},
          'documents': [
            {'text': 'บัตรประจำตัว', 'ready': false},
          ],
          'channels': [
            {'title': 'สำนักงานเขตตามทะเบียนบ้าน', 'kind': 'office'},
          ],
          'contactGuide': _seniorGuide,
        };
      default:
        throw StateError('Unexpected path $path');
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
  Future<_ContactApi> openContact(
    WidgetTester tester, {
    required bool moneyPlan,
    String? jobUrl,
    bool listingMissing = false,
    bool mock = false,
    double textScale = 1,
  }) async {
    final api = _ContactApi(
      moneyPlan: moneyPlan,
      jobUrl: jobUrl,
      listingMissing: listingMissing,
      mock: mock,
    );
    addTearDown(api.close);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        theme: thangRotTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: TaskScreen(
          app: AppState(api)..startupDemoEnabled = true,
          taskId: 't1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ข้อมูลติดต่อ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ข้อมูลติดต่อ'));
    await tester.pumpAndSettle();
    return api;
  }

  Future<void> returnFromBrowser(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  List<String> recordLinks({bool Function(String)? launch}) {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

  Future<void> applyFromDetails(
    WidgetTester tester, {
    String? sourceUrl,
  }) async {
    final api = _ContactApi(moneyPlan: false, jobUrl: sourceUrl);
    addTearDown(api.close);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: OppScreen(
          app: AppState(api)..startupDemoEnabled = true,
          opportunityId: 'job-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายละเอียดงาน'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the job detail has a demo application button without a source URL',
    (tester) async {
      final opened = recordLinks();
      await applyFromDetails(tester);
      expect(opened, [_detailsDemoUrl]);
      await returnFromBrowser(tester);
      expect(find.text('กลับมาแล้ว 👋'), findsNothing);
    },
  );

  for (final category in ['job_part', 'grant']) {
    testWidgets(
      'Bangkok demo $category keeps the record link and opens the sample job form',
      (tester) async {
        final opened = recordLinks();
        final api = _ContactApi(
          moneyPlan: false,
          jobUrl: _bangkokInfo,
          mock: true,
          provider: 'mock_bangkok_catalogue',
          category: category,
        );
        addTearDown(api.close);
        final app = AppState(api)..startupDemoEnabled = true;
        await tester.pumpWidget(
          MaterialApp(
            home: OppScreen(app: app, opportunityId: 'job-1'),
          ),
        );
        await tester.pumpAndSettle();

        if (category == 'job_part') {
          await tester.tap(find.text('รายละเอียดงาน'));
          await tester.pumpAndSettle();
          expect(opened, [_detailsDemoUrl]);
          await returnFromBrowser(tester);
          opened.clear();
        }
        final link = find.text('ดูข้อมูลจำลอง');
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(opened, [_bangkokInfo]);
        await returnFromBrowser(tester);
        expect(find.text('กลับมาแล้ว 👋'), findsNothing);
      },
    );
  }

  testWidgets(
    'a broken link from job details opens the same demo HTML as a plan',
    (tester) async {
      final opened = recordLinks();
      await HttpOverrides.runZoned(
        () => applyFromDetails(tester, sourceUrl: _jobUrl),
        createHttpClient: (_) => _LinkClient(404),
      );
      expect(opened, [_detailsDemoUrl]);
    },
  );

  testWidgets(
    'a reachable link from job details opens the employer site directly',
    (tester) async {
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
    },
  );

  testWidgets('AC-11 a mock job opens its sample only after the user taps', (
    tester,
  ) async {
    final opened = recordLinks();
    final api = await openContact(tester, moneyPlan: false, mock: true);
    expect(opened, isEmpty);
    final sheet = find.byType(PlanContactScreen);
    for (final label in [_listingTitle, 'พาร์ตไทม์', 'DEMO / MOCK']) {
      expect(
        find.descendant(of: sheet, matching: find.text(label)),
        findsOneWidget,
      );
    }
    await tester.tap(find.text('ดูรายละเอียดงานตัวอย่าง'));
    await tester.pumpAndSettle();
    expect(opened, [_detailsDemoUrl]);
    await returnFromBrowser(tester);
    expect(find.text('กลับมาแล้ว 👋'), findsNothing);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('ทำแล้ว 0 จาก 1 ขั้น'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'ข้อมูลติดต่อ'),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    expect(api.sourceReads, 1);
  });

  testWidgets(
    'AC-12 a deleted source keeps the saved plan and shows a distinct empty state',
    (tester) async {
      final opened = recordLinks();
      await openContact(tester, moneyPlan: false, listingMissing: true);
      expect(opened, isEmpty);
      expect(
        find.descendant(
          of: find.byType(PlanContactScreen),
          matching: find.text(_jobTitle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PlanContactScreen),
          matching: find.text('ไม่พบประกาศหรือข้อมูลต้นทางแล้ว'),
        ),
        findsOneWidget,
      );
      expect(find.text('ยังไม่มีช่องทางติดต่อที่ตรวจสอบได้'), findsOneWidget);
      expect(find.text('ดูรายละเอียดงานตัวอย่าง'), findsNothing);
    },
  );

  testWidgets(
    'a real plan uses the supplied source link with no apply prompt on return',
    (tester) async {
      final opened = recordLinks();
      await openContact(tester, moneyPlan: false, jobUrl: _jobUrl);
      expect(opened, isEmpty);
      await tester.tap(find.text('เปิดเว็บไซต์'));
      await tester.pumpAndSettle();
      expect(opened, [_jobUrl]);
      await returnFromBrowser(tester);
      expect(find.text('กลับมาแล้ว 👋'), findsNothing);
    },
  );

  testWidgets(
    'a benefit plan keeps documents, contact guide and the original claim route',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = recordLinks();
      await openContact(tester, moneyPlan: true, textScale: 1.5);
      expect(find.byType(PlanContactScreen), findsOneWidget);
      expect(find.text('สำนักงานเขตตามทะเบียนบ้าน'), findsOneWidget);
      final sheetScroll = find.descendant(
        of: find.byType(PlanContactScreen),
        matching: find.byType(Scrollable),
      );
      final document = find.text('• บัตรประจำตัว');
      await tester.scrollUntilVisible(
        document.hitTestable(),
        200,
        scrollable: sheetScroll,
      );
      expect(document.hitTestable(), findsOneWidget);
      expect(opened, isEmpty);
      await tester.ensureVisible(find.text('อ่านคู่มือติดต่อหน่วยงาน'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('อ่านคู่มือติดต่อหน่วยงาน'));
      await tester.pumpAndSettle();
      expect(opened, ['$_baseUrl$_seniorGuide']);
      await returnFromBrowser(tester);
      expect(find.text('กลับมาแล้ว 👋'), findsNothing);
      await tester.ensureVisible(find.text('ดูวิธียื่นและติดตามผล'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ดูวิธียื่นและติดตามผล'));
      await tester.pumpAndSettle();
      expect(find.text('เส้นทางรับเงิน'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
