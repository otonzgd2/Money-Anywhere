import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/connected_accounts.dart' show AccountStatus;
import 'package:money_anywhere/demo_sources_screen.dart';
import 'package:money_anywhere/me_tab.dart';
import 'package:money_anywhere/opportunity_assessment.dart';
import 'package:money_anywhere/profile_overview_screen.dart';

const _demoResponse = <String, dynamic>{
  'dataStatus': 'mock',
  'profile': {'displayName': 'นายสมศักดิ์ สมมติ', 'district': 'ปทุมวัน'},
  'identity': {
    'dataStatus': 'mock',
    'pidMasked': 'X-XXXX-XXXXX-12-3',
    'claims': {
      'name': 'นายสมศักดิ์ สมมติ',
      'address': {
        'formatted': '12 ซอยทดสอบ เขตปทุมวัน กรุงเทพมหานคร',
        'locality': 'ปทุมวัน',
      },
      'date_of_issuance': '2023-01-10',
      'date_of_expiry': '2031-04-11',
    },
    'derived': {'age': 65, 'ageBand': '60-69'},
  },
  'sources': [
    {'field': 'identity', 'label': 'ThaID', 'value': 'อายุ 65 ปี'},
    {'field': 'disabilityCard', 'label': 'ทางรัฐ', 'value': 'มีบัตร'},
    {
      'field': 'ss33',
      'label': 'ประกันสังคม',
      'value': 'ส่งเงินสมทบ 8 จาก 15 เดือน',
    },
    {
      'field': 'taxWithheld',
      'label': 'D-MyTax',
      'value': '1,250 บาท · ปีภาษี 2569',
    },
  ],
};

class _ProfileApi extends Api {
  _ProfileApi({
    this.profile,
    this.unavailable = false,
    this.demoEnabled = false,
    this.userMode = false,
    this.identity,
    this.choices = 'nnnn',
  });
  Map<String, dynamic>? profile;
  bool unavailable;
  final bool demoEnabled;
  final bool userMode;
  Map<String, dynamic>? identity;
  String choices;
  final reads = <String>[];
  final facts = <String, dynamic>{};
  final deletes = <String>[];
  bool failAge = false;

  @override
  String get onboardingChoices => choices;

  @override
  void saveOnboardingChoices(String choices) => this.choices = choices;

  @override
  Future<Map<String, dynamic>> get(String path) async {
    reads.add(path);
    switch (path) {
      case '/v1/me/profile':
        if (unavailable) throw ApiException(0, 'NETWORK', 'Offline');
        return profile ?? (throw ApiException(404, 'NOT_FOUND', 'Empty'));
      case '/v1/me/facts':
        return Map.of(facts);
      case '/v1/me/gov-link':
        return identity == null
            ? {'status': 'not_connected'}
            : {'status': 'connected', 'identity': identity};
      case '/v1/me/memory':
        return {'items': []};
      case '/v1/me/settings':
        return {'largeText': false};
      case '/v1/app-config':
        return {
          'mode': userMode ? 'user' : 'demo',
          if (userMode) ...{
            'governmentConnections': {
              'thaid': 'approval_required',
              'tangRat': 'access_required',
            },
          },
          'featureFlags': {'demo': demoEnabled},
          'routes': {
            'me': {
              'sections': [
                {
                  'id': 'demo.gov-prefill',
                  'items': [
                    {
                      'label': 'ทดลองเชื่อมแหล่งข้อมูล (DEMO)',
                      'sub': 'ข้อมูลตัวอย่าง',
                      'onTap': {
                        'action': 'demo.load',
                        'params': {'id': 'gov-prefill'},
                        'then': {'route': 'me.profile'},
                      },
                    },
                  ],
                },
              ],
            },
          },
          'actions': {
            'demo.load': {'path': '/v1/demo/personas/{id}'},
          },
        };
      case '/v1/me/consents':
        return {
          'current': {
            'purposes': {'core': true},
          },
        };
      default:
        throw StateError('Unexpected GET $path');
    }
  }

  @override
  Future<Map<String, dynamic>> put(String path, Object body) async {
    expect(path, '/v1/me/profile');
    return profile = Map<String, dynamic>.from(body as Map);
  }

  @override
  Future<Map<String, dynamic>> patch(String path, Object body) async {
    expect(path, '/v1/me/facts');
    if (failAge) throw ApiException(503, 'TEST', 'บันทึกช่วงอายุไม่ได้');
    final value = (body as Map)['ageBand'];
    if (value == null) {
      facts.remove('ageBand');
    } else {
      facts['ageBand'] = value;
    }
    return facts;
  }

  @override
  Future<Map<String, dynamic>> delete(String path) async {
    deletes.add(path);
    if (path == '/v1/me/gov-link') identity = null;
    return {};
  }
}

class _SelectableDemoApi extends _ProfileApi {
  _SelectableDemoApi({super.choices}) : super(demoEnabled: true);

  final previews = <Uri>[];
  final chatSelections = <Uri>[];
  bool missingTangRat = false;
  Completer<Map<String, dynamic>>? pending;

  @override
  Future<Map<String, dynamic>> get(String path) async {
    final uri = Uri.parse(path);
    if (uri.path == '/v1/demo/personas/gov-prefill' && uri.hasQuery) {
      previews.add(uri);
      if (pending case final request?) return request.future;
      final sources = uri.queryParameters['sources']!.split(',');
      const fields = {
        'thaid': 'identity',
        'tangRat': 'disabilityCard',
        'socialSecurity': 'ss33',
        'dMyTax': 'taxWithheld',
      };
      return {
        'dataStatus': 'mock',
        'profile': sources.contains('thaid') ? _demoResponse['profile'] : {},
        if (sources.contains('thaid')) 'identity': _demoResponse['identity'],
        'sources': [
          for (final row in (_demoResponse['sources'] as List).cast<Map>())
            if (sources.any((source) => fields[source] == row['field']) &&
                !(missingTangRat && row['field'] == 'disabilityCard'))
              row,
        ],
      };
    }
    return super.get(path);
  }

  @override
  Api forDemo(String name) {
    expect(name, 'gov-prefill-selection');
    return _SelectionChatApi(chatSelections);
  }
}

class _SelectionChatApi extends Api {
  _SelectionChatApi(this.selections);

  final List<Uri> selections;

  @override
  Future<void> consent({required bool ai}) async => expect(ai, isTrue);

  @override
  Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) async {
    if (path == '/v1/ai/conversations') {
      expect(body, {'mode': 'guided'});
      return {'conversationId': 'selected-demo', 'greeting': 'เริ่มทดสอบแชต'};
    }
    final uri = Uri.parse(path);
    expect(uri.path, '/v1/demo/personas/gov-prefill');
    expect(uri.queryParameters['keepPlans'], 'true');
    selections.add(uri);
    return _demoResponse;
  }
}

Future<void> _openProfile(
  WidgetTester tester,
  Api api, {
  ProfileDemo? demo,
}) async {
  tester.view.physicalSize = const Size(800, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileOverviewScreen(app: AppState(api), demo: demo),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'connected accounts opens the demo previews and a fresh chat per selection',
    (tester) async {
      final api = _SelectableDemoApi();
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: MeTab(app: AppState(api))));
      await tester.pumpAndSettle();
      expect(find.text('บัญชีที่เชื่อมต่อ'), findsOneWidget);
      expect(find.text('1,250 บาท · ปีภาษี 2569'), findsNothing);
      expect(api.previews, isEmpty);
      final menu = find.text('ทดลองเชื่อมแหล่งข้อมูล (DEMO)');
      expect(
        tester.getTopLeft(menu).dy,
        greaterThan(tester.getTopLeft(find.text('บัญชีที่เชื่อมต่อ')).dy),
      );
      expect(
        tester.getTopLeft(menu).dy,
        lessThan(tester.getTopLeft(find.text('การใช้งาน')).dy),
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();

      expect(find.text('เลือก 4 จาก 4 แหล่ง'), findsOneWidget);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == true),
        isTrue,
      );
      await tester.tap(find.text('ดูโปรไฟล์ตัวอย่าง'));
      await tester.pumpAndSettle();
      expect(find.text('นายสมศักดิ์ สมมติ'), findsOneWidget);
      expect(find.text('1,250 บาท · ปีภาษี 2569'), findsNothing);
      expect(
        api.previews.single.queryParameters['sources'],
        'thaid,tangRat,socialSecurity,dMyTax',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('D-MyTax'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ดูบัญชีที่เชื่อมต่อ'));
      await tester.pumpAndSettle();
      expect(find.text('บัญชีที่เชื่อมต่อ'), findsOneWidget);
      expect(find.text('บัตรประจำตัวคนพิการ'), findsOneWidget);
      expect(find.text('D-MyTax'), findsNothing);
      expect(find.text('นายสมศักดิ์ สมมติ'), findsNothing);
      expect(
        api.previews.last.queryParameters['sources'],
        'thaid,tangRat,socialSecurity',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('D-MyTax'));
      await tester.pumpAndSettle();

      for (final source in ['D-MyTax', 'ประกันสังคม', 'ทางรัฐ']) {
        await tester.tap(find.text(source));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ทดสอบแชต'));
        await tester.pumpAndSettle();
        expect(find.text('เริ่มทดสอบแชต'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(api.chatSelections.map((uri) => uri.queryParameters['sources']), [
        'thaid,tangRat,socialSecurity',
        'thaid,tangRat',
        'thaid',
      ]);
      expect(find.text('เลือก 1 จาก 4 แหล่ง'), findsOneWidget);
    },
  );

  testWidgets(
    'the Me tab shows live provider availability and hides demo connections in user mode',
    (tester) async {
      final api = _ProfileApi(
        userMode: true,
        demoEnabled: true,
        choices: 'yyyy',
        identity: _demoResponse['identity'] as Map<String, dynamic>,
      );
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: MeTab(app: AppState(api))));
      await tester.pumpAndSettle();

      expect(find.text('ThaID'), findsOneWidget);
      expect(find.text('ทางรัฐ'), findsOneWidget);
      expect(find.text('รอกรมการปกครองอนุมัติการเชื่อมต่อ'), findsOneWidget);
      expect(
        find.text('รอสิทธิ์เข้าถึงข้อมูลจากหน่วยงานเจ้าของบริการ'),
        findsOneWidget,
      );
      expect(find.text('เชื่อม ThaID'), findsNothing);
      expect(find.text('สำหรับสาธิต (DEMO)'), findsNothing);
      expect(find.text('ทดลองเชื่อมแหล่งข้อมูล (DEMO)'), findsNothing);
      expect(find.text('1,250 บาท · ปีภาษี 2569'), findsNothing);
      expect(find.text('เชื่อมแล้ว 0 จาก 4 บริการ'), findsOneWidget);
      expect(
        api.reads.where((path) => path.startsWith('/v1/demo/personas')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'AC-18 edits all manual fields without loading a persona and retries a partial save',
    (tester) async {
      final api = _SelectableDemoApi()
        ..profile = {
          'goals': ['หางาน'],
          'district': 'บางนา',
          'lat': 13.66,
          'lng': 100.60,
        }
        ..failAge = true;
      final app = AppState(api);
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: MeTab(app: app)));
      await tester.pumpAndSettle();
      expect(find.text('เชื่อมแล้ว 0 จาก 4 บริการ'), findsOneWidget);

      await tester.tap(find.text('โปรไฟล์'));
      await tester.pumpAndSettle();
      final name = find.widgetWithText(TextField, 'ชื่อที่ใช้ในแอป');
      await tester.enterText(name, 'มาลี');
      await tester.tap(find.byKey(const ValueKey('ช่วงอายุ')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('70-79').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ทำอาหาร'));
      await tester.tap(find.text('บันทึกโปรไฟล์'));
      await tester.pumpAndSettle();
      expect(find.text('บันทึกช่วงอายุไม่ได้'), findsOneWidget);
      expect(find.text('บันทึกโปรไฟล์แล้ว'), findsNothing);
      expect(api.facts, isEmpty);

      api.failAge = false;
      await tester.tap(find.text('บันทึกโปรไฟล์'));
      await tester.pumpAndSettle();
      expect(api.profile, containsPair('displayName', 'มาลี'));
      expect(api.profile, containsPair('district', 'บางนา'));
      expect(api.profile, containsPair('lat', 13.66));
      expect(api.profile, containsPair('skills', ['ทำอาหาร']));
      expect(api.profile, containsPair('goals', ['หางาน']));
      expect(api.facts, containsPair('ageBand', '70-79'));
      expect(api.previews, isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: MeTab(key: const ValueKey('reopen'), app: AppState(api)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('โปรไฟล์'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(name).controller?.text, 'มาลี');
      expect(find.text('70-79'), findsOneWidget);
    },
  );

  testWidgets('AC-19 uses the confirmed ThaID result for both screens', (
    tester,
  ) async {
    final api = _SelectableDemoApi(choices: 'yynn');
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home: MeTab(app: AppState(api))));
    await tester.pumpAndSettle();
    expect(api.previews.single.queryParameters['sources'], 'thaid,tangRat');
    expect(
      find.text('เชื่อมแล้ว 2 จาก 4 บริการ · ข้อมูลจำลอง'),
      findsOneWidget,
    );
    expect(
      find.byType(ExpansionTile),
      findsNWidgets(3),
    ); // Two services and AI memory.

    await tester.tap(find.text('โปรไฟล์'));
    await tester.pumpAndSettle();
    expect(find.text('นายสมศักดิ์ สมมติ'), findsOneWidget);
    expect(find.text('65 ปี'), findsOneWidget);
    expect(find.text('เขตตามทะเบียนบ้าน'), findsOneWidget);
    expect(find.text('ข้อมูลจาก ThaID อ่านได้อย่างเดียว'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'ชื่อที่ใช้ในแอป'), findsNothing);
    expect(find.text('เลขบัตรประชาชน'), findsNothing);
    await tester.tap(find.text('ดูบัญชีที่เชื่อมต่อ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ทางรัฐ'));
    await tester.pumpAndSettle();
    expect(find.text('มีบัตร'), findsOneWidget);
    expect(api.previews, hasLength(1));
  });

  testWidgets(
    'AC-20 shows SSO+ and the tax year and amount without locking the profile',
    (tester) async {
      final api = _SelectableDemoApi(choices: 'nnyy');
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: MeTab(app: AppState(api))));
      await tester.pumpAndSettle();
      expect(
        api.previews.single.queryParameters['sources'],
        'socialSecurity,dMyTax',
      );
      await tester.tap(find.text('ประกันสังคม (SSO+)'));
      await tester.tap(find.text('D-MyTax'));
      await tester.pumpAndSettle();
      expect(find.text('ส่งเงินสมทบ 8 จาก 15 เดือน'), findsOneWidget);
      expect(find.text('ปีภาษี'), findsOneWidget);
      expect(find.text('2569'), findsOneWidget);
      expect(find.text('1,250 บาท'), findsOneWidget);
      await tester.tap(find.text('โปรไฟล์'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'ชื่อที่ใช้ในแอป'), findsOneWidget);
    },
  );

  testWidgets(
    'AC-21 shows missing claims and restores the manual fields after disconnect',
    (tester) async {
      final api = _ProfileApi(
        demoEnabled: true,
        profile: {
          'displayName': 'มาลี',
          'district': 'บางนา',
          'skills': ['ทำอาหาร'],
        },
        identity: {
          'dataStatus': 'mock',
          'claims': {'name': 'ชื่อจากผู้ให้บริการ'},
          'derived': {'ageBand': '70-79'},
        },
      )..facts['ageBand'] = 'ต่ำกว่า 60';
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: MeTab(app: AppState(api))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('โปรไฟล์'));
      await tester.pumpAndSettle();
      expect(find.text('ชื่อจากผู้ให้บริการ'), findsOneWidget);
      expect(find.text('70-79'), findsOneWidget);
      expect(find.text('ไม่มีข้อมูลจาก ThaID'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ชื่อที่ใช้ในแอป'), findsNothing);
      await tester.tap(find.text('กรอกข้อมูล'));
      await tester.tap(find.text('บันทึกโปรไฟล์'));
      await tester.pumpAndSettle();
      expect(api.profile, containsPair('displayName', 'มาลี'));
      expect(api.profile, containsPair('skills', ['ทำอาหาร', 'กรอกข้อมูล']));
      await tester.tap(find.text('ThaID'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิกการเชื่อม ThaID'));
      await tester.pumpAndSettle();
      expect(api.deletes, ['/v1/me/gov-link']);
      await tester.tap(find.text('โปรไฟล์'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'ชื่อที่ใช้ในแอป'),
      );
      expect(field.controller?.text, 'มาลี');
      expect(find.text('ต่ำกว่า 60'), findsOneWidget);
      expect(find.text('บางนา'), findsOneWidget);
    },
  );

  test(
    'AC-22 retries a missing row and discards responses that predate deletion',
    () async {
      final api = _SelectableDemoApi(choices: 'yynn')..missingTangRat = true;
      addTearDown(api.close);
      final accounts = AppState(api).accounts;
      addTearDown(accounts.dispose);
      await accounts.refresh();
      expect(accounts.value.connectedCount, 1);
      expect(accounts.value[DemoSource.thangRat].status, AccountStatus.failed);
      api.missingTangRat = false;
      await accounts.refresh(retry: DemoSource.thangRat);
      expect(api.previews.last.queryParameters['sources'], 'tangRat');
      expect(accounts.value.connectedCount, 2);

      final delayed = Completer<Map<String, dynamic>>();
      api.pending = delayed;
      final request = accounts.refresh(force: true);
      await Future<void>.delayed(Duration.zero);
      expect(api.previews.last.queryParameters['sources'], 'thaid,tangRat');
      accounts.beginDelete();
      api.saveOnboardingChoices('');
      accounts.endDelete();
      await accounts.refresh(force: true);
      delayed.complete(_demoResponse);
      await request;
      expect(accounts.value.connectedCount, 0);
      expect(
        accounts.value[DemoSource.thangRat].status,
        AccountStatus.disconnected,
      );
    },
  );

  testWidgets(
    'marks the demo profile and leaves source labels to connected accounts',
    (tester) async {
      await _openProfile(
        tester,
        _ProfileApi(),
        demo: ProfileDemo.fromResponse(_demoResponse)!,
      );

      expect(find.text('นายสมศักดิ์ สมมติ'), findsOneWidget);
      expect(find.text('DEMO / MOCK'), findsOneWidget);
      expect(find.text('ข้อมูลส่วนตัว'), findsOneWidget);
      for (final source in ['ThaID', 'ทางรัฐ', 'ประกันสังคม', 'D-MyTax']) {
        expect(find.text(source), findsNothing);
      }
      expect(find.text('แก้ไขโปรไฟล์'), findsNothing);
    },
  );

  final sourceRows = (_demoResponse['sources'] as List)
      .cast<Map<String, String>>();
  for (var mask = 0; mask < (1 << sourceRows.length); mask++) {
    final selected = [
      for (var i = 0; i < sourceRows.length; i++)
        if ((mask & (1 << i)) != 0) sourceRows[i],
    ];
    final hasIdentity = selected.any((source) => source['field'] == 'identity');
    final labels = selected.map((source) => source['label']).toSet();
    testWidgets(
      'renders selected demo sources only: ${labels.join(', ')} ($mask)',
      (tester) async {
        final demo = ProfileDemo.fromResponse({
          'dataStatus': 'mock',
          'profile': hasIdentity
              ? _demoResponse['profile']
              : <String, dynamic>{},
          if (hasIdentity) 'identity': _demoResponse['identity'],
          'sources': selected,
        });
        await _openProfile(tester, _ProfileApi(), demo: demo!);
        expect(find.text('DEMO / MOCK'), findsOneWidget);
        expect(
          find.text('เลขบัตรประชาชน'),
          hasIdentity ? findsOneWidget : findsNothing,
        );
        for (final row in sourceRows) {
          expect(find.text(row['label']!), findsNothing);
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: DemoConnectionDetails(demo: demo)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('DEMO / MOCK'), findsOneWidget);
        for (final row in sourceRows) {
          final label = row['label']!;
          expect(
            find.text(label),
            labels.contains(label) ? findsOneWidget : findsNothing,
          );
        }
        expect(find.text('เลขบัตรประชาชน'), findsNothing);
      },
    );
  }

  testWidgets('omits unavailable identity fields on an empty profile', (
    tester,
  ) async {
    await _openProfile(tester, _ProfileApi());

    expect(find.widgetWithText(TextField, 'ชื่อที่ใช้ในแอป'), findsOneWidget);
    expect(find.text('อายุ'), findsNothing);
    expect(find.text('เลขบัตรประชาชน'), findsNothing);
    expect(find.text('บันทึกโปรไฟล์'), findsOneWidget);
  });

  testWidgets('shows a retry button when the backend is unavailable', (
    tester,
  ) async {
    final api = _ProfileApi(unavailable: true);
    await _openProfile(tester, api);

    expect(find.text('โหลดโปรไฟล์ไม่ได้'), findsOneWidget);
    api.unavailable = false;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'ชื่อที่ใช้ในแอป'), findsOneWidget);
  });
}
