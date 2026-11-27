import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/demo_sources_screen.dart';
import 'package:money_anywhere/me_tab.dart';
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
  });
  Map<String, dynamic>? profile;
  bool unavailable;
  final bool demoEnabled;
  final bool userMode;
  final Map<String, dynamic>? identity;

  @override
  Future<Map<String, dynamic>> get(String path) async {
    switch (path) {
      case '/v1/me/profile':
        if (unavailable) throw ApiException(0, 'NETWORK', 'Offline');
        return profile ?? (throw ApiException(404, 'NOT_FOUND', 'Empty'));
      case '/v1/me/facts':
        return {};
      case '/v1/me/gov-link':
        return identity == null
            ? {'status': 'not_connected'}
            : {'status': 'connected', 'identity': identity};
      case '/v1/demo/personas/gov-prefill':
        if (!demoEnabled) {
          throw ApiException(404, 'NOT_FOUND', 'Demo unavailable');
        }
        return _demoResponse;
      case '/v1/me/memory':
        return {'items': []};
      case '/v1/me/settings':
        return {'largeText': false};
      case '/v1/app-config':
        return {
          if (userMode) ...{
            'mode': 'user',
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
}

class _SelectableDemoApi extends _ProfileApi {
  _SelectableDemoApi() : super(demoEnabled: true);

  final previews = <Uri>[];
  final chatSelections = <Uri>[];

  @override
  Future<Map<String, dynamic>> get(String path) async {
    final uri = Uri.parse(path);
    if (uri.path == '/v1/demo/personas/gov-prefill' && uri.hasQuery) {
      previews.add(uri);
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
            if (sources.any((source) => fields[source] == row['field'])) row,
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
      expect(find.text('1,250 บาท · ปีภาษี 2569'), findsOneWidget);
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
      final api = _ProfileApi(userMode: true);
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
    },
  );

  testWidgets(
    'the Me profile keeps the saved details and opens the example separately',
    (tester) async {
      final api = _ProfileApi(
        profile: {'displayName': 'มาลี', 'district': 'ปทุมวัน'},
        demoEnabled: true,
      );
      final app = AppState(api);
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: MeTab(app: app)));
      await tester.pumpAndSettle();
      expect(find.text('มาลี\nเขตที่อยู่ ปทุมวัน'), findsOneWidget);

      api.profile = {...api.profile!, 'displayName': 'มาลี แก้ไข'};
      app.bump();
      await tester.pumpAndSettle();
      expect(find.text('มาลี แก้ไข\nเขตที่อยู่ ปทุมวัน'), findsOneWidget);

      await tester.tap(find.text('โปรไฟล์ของฉัน'));
      await tester.pumpAndSettle();
      expect(find.text('มาลี แก้ไข'), findsOneWidget);
      expect(find.text('บัตรประจำตัวคนพิการ'), findsNothing);
      await tester.tap(find.text('ดูโปรไฟล์ตัวอย่าง'));
      await tester.pumpAndSettle();
      expect(find.text('มาลี แก้ไข'), findsNothing);
      expect(find.text('ข้อมูลส่วนตัว'), findsOneWidget);
      expect(find.text('นายสมศักดิ์ สมมติ'), findsOneWidget);
      expect(find.text('DEMO / MOCK'), findsOneWidget);
      expect(find.text('1,250 บาท · ปีภาษี 2569'), findsNothing);
      expect(api.profile?['displayName'], 'มาลี แก้ไข');
    },
  );

  testWidgets(
    'an empty saved profile displays personal identity from the demo without connection details',
    (tester) async {
      await _openProfile(tester, _ProfileApi(demoEnabled: true));

      expect(find.text('นายสมศักดิ์ สมมติ'), findsOneWidget);
      expect(find.text('ข้อมูลส่วนตัว'), findsOneWidget);
      expect(find.text('65 ปี'), findsOneWidget);
      expect(find.text('ที่อยู่ตามทะเบียนบ้าน'), findsOneWidget);
      expect(find.text('XXX123'), findsOneWidget);
      expect(find.text('1,250 บาท · ปีภาษี 2569'), findsNothing);
      expect(find.text('ยังไม่ได้ตั้งชื่อ'), findsNothing);
      expect(find.textContaining('60-69'), findsNothing);
      expect(find.text('วันออกบัตร'), findsNothing);
      expect(find.text('วันบัตรหมดอายุ'), findsNothing);
      expect(find.text('เขตที่อยู่'), findsNothing);
    },
  );

  testWidgets(
    'combines matching ThaID and saved profile details in one section',
    (tester) async {
      await _openProfile(
        tester,
        _ProfileApi(
          profile: {'displayName': 'มาลี สมมติ', 'district': 'บางนา'},
          identity: {
            'dataStatus': 'mock',
            'pidMasked': 'X-XXXX-XXXXX-45-6',
            'claims': {
              'birthdate': '${DateTime.now().year - 75}-01-01',
              'address': {
                'formatted': '99 ซอยทดสอบ เขตบางนา กรุงเทพมหานคร',
                'locality': 'บางนา',
              },
              'date_of_issuance': '2021-04-12',
            },
            'derived': {
              'displayName': 'มาลี สมมติ',
              'ageBand': '70-79',
              'district': 'บางนา',
            },
          },
        ),
      );

      expect(find.text('ข้อมูลส่วนตัว'), findsOneWidget);
      expect(find.text('มาลี สมมติ'), findsOneWidget);
      expect(find.text('75 ปี'), findsOneWidget);
      expect(find.text('99 ซอยทดสอบ เขตบางนา กรุงเทพมหานคร'), findsOneWidget);
      expect(find.text('XXX456'), findsOneWidget);
      expect(find.text('DEMO / MOCK'), findsOneWidget);
      expect(find.text('70-79'), findsNothing);
      expect(find.text('วันออกบัตร'), findsNothing);
      expect(find.text('D-MyTax'), findsNothing);
    },
  );

  testWidgets('shows stored profile and refreshes after editing', (
    tester,
  ) async {
    final api = _ProfileApi(
      profile: {
        'displayName': 'มาลี (สมมติ)',
        'district': 'ปทุมวัน',
        'skills': ['ทำอาหาร'],
        'hoursPerWeek': '10-20',
        'incomeGoalPerMonth': 12000,
        'fromGov': ['ageBand'],
      },
    );
    await _openProfile(tester, api);

    expect(find.text('มาลี (สมมติ)'), findsOneWidget);
    expect(find.text('ปทุมวัน'), findsOneWidget);
    expect(find.text('อายุ'), findsNothing);
    expect(find.text('ทำอาหาร'), findsOneWidget);
    expect(find.text('DEMO / MOCK'), findsNothing);
    expect(find.text('D-MyTax'), findsNothing);
    expect(find.textContaining('12,000'), findsOneWidget);

    await tester.tap(find.text('แก้ไขโปรไฟล์'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'ชื่อที่ใช้ในแอป'),
      'ชื่อเล่นตัวอย่าง',
    );
    await tester.ensureVisible(find.text('บันทึก'));
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();

    expect(api.profile?['displayName'], 'ชื่อเล่นตัวอย่าง');
    expect(api.profile?['skills'], ['ทำอาหาร']);
    expect(find.text('ชื่อเล่นตัวอย่าง'), findsOneWidget);
  });

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

    expect(find.text('ยังไม่ได้ตั้งชื่อ'), findsOneWidget);
    expect(find.text('อายุ'), findsNothing);
    expect(find.text('เลขบัตรประชาชน'), findsNothing);
    expect(find.text('แก้ไขโปรไฟล์'), findsOneWidget);
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
    expect(find.text('ยังไม่ได้ตั้งชื่อ'), findsOneWidget);
  });
}
