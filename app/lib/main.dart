import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'home_tab.dart';
import 'me_tab.dart';
import 'opp_tab.dart';
import 'opportunity_assessment.dart';
import 'plans_tab.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MoneyAnywhereStartup(
      initialize: () async {
        await binding.waitUntilFirstFrameRasterized;
        return AppState(await Api.open());
      },
    ),
  );
}

class MoneyAnywhereStartup extends StatefulWidget {
  const MoneyAnywhereStartup({super.key, required this.initialize});
  final Future<AppState> Function() initialize;

  @override
  State<MoneyAnywhereStartup> createState() => _MoneyAnywhereStartupState();
}

class _MoneyAnywhereStartupState extends State<MoneyAnywhereStartup> {
  late Future<AppState> startup = widget.initialize();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: startup,
      builder: (context, snapshot) {
        if (snapshot.data case final ready?) {
          return MoneyAnywhereApp(app: ready, runStartup: true);
        }
        return MaterialApp(
          title: 'ทางรอด',
          debugShowCheckedModeBanner: false,
          home: ThangRotSplash(
            onRetry: snapshot.hasError
                ? () => setState(() => startup = widget.initialize())
                : null,
          ),
        );
      },
    );
  }
}

class ThangRotSplash extends StatelessWidget {
  const ThangRotSplash({super.key, this.status, this.onRetry});
  final String? status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAFAFA),
    body: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/thang-rot/thang-rot-logo.png',
                    width: 136,
                    height: 136,
                    semanticLabel: 'ทางรอด',
                    fit: BoxFit.contain,
                  ),
                  if (status case final message?) ...[
                    const SizedBox(height: 16),
                    Text(message, textAlign: TextAlign.center),
                  ],
                  if (onRetry case final retry?) ...[
                    const Text('เปิดแอปไม่สำเร็จ'),
                    FilledButton(
                      onPressed: retry,
                      child: const Text('ลองใหม่'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class MoneyAnywhereApp extends StatelessWidget {
  const MoneyAnywhereApp({
    super.key,
    required this.app,
    this.runStartup = false,
  });
  final AppState app;
  final bool runStartup;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: app.largeText,
      builder: (_, large, _) => MaterialApp(
        title: 'ทางรอด',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E9F6E)),
          useMaterial3: true,
        ),
        // Large-text setting (ฉัน > ตัวอักษรใหญ่) on top of the phone's own font size.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: large
                  ? TextScaler.linear(mq.textScaler.scale(1) * 1.3)
                  : mq.textScaler,
            ),
            child: child!,
          );
        },
        home: runStartup ? _OpportunityStartup(app: app) : Shell(app: app),
        onGenerateRoute: (settings) {
          final uri = Uri.tryParse(settings.name ?? '');
          final segments = uri?.pathSegments;
          if (segments == null ||
              segments.length != 2 ||
              segments.first != 'opportunities') {
            return null;
          }
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => OppScreen(
              app: app,
              opportunityId: segments.last,
              districtCode: uri?.queryParameters['districtCode'],
            ),
          );
        },
      ),
    );
  }
}

class _OpportunityStartup extends StatefulWidget {
  const _OpportunityStartup({required this.app});
  final AppState app;

  @override
  State<_OpportunityStartup> createState() => _OpportunityStartupState();
}

class _OpportunityStartupState extends State<_OpportunityStartup> {
  OpportunityAssessment? assessment;
  bool busy = false;
  bool assessing = false;
  bool storageError = false;

  @override
  void initState() {
    super.initState();
    widget.app.dataCleared.addListener(_clearAssessment);
    widget.app.goTab(1, group: 'all');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadTextSetting();
        _run();
      }
    });
  }

  @override
  void dispose() {
    widget.app.dataCleared.removeListener(_clearAssessment);
    super.dispose();
  }

  void _clearAssessment() {
    setState(
      () => assessment = const OpportunityAssessment(AssessmentStatus.ready),
    );
  }

  Future<void> _loadTextSetting() async {
    final app = widget.app;
    try {
      final settings = await app.api.get('/v1/me/settings');
      if (mounted) app.largeText.value = settings['largeText'] == true;
    } on ApiException {
      // A device can still use its system text size when settings are unavailable.
    }
  }

  Future<void> _run() async {
    final app = widget.app;
    if (busy || app.deletingData) return;
    busy = true;
    final revision = app.dataCleared.value;
    bool current() =>
        mounted && revision == app.dataCleared.value && !app.deletingData;
    if (assessment != null) {
      setState(
        () =>
            assessment = const OpportunityAssessment(AssessmentStatus.loading),
      );
    }
    try {
      final config = await app.api
          .get('/v1/app-config')
          .timeout(const Duration(seconds: 5));
      if (!current()) {
        busy = false;
        return;
      }
      final flags = config['featureFlags'];
      if ((config['mode'] != 'demo' && config['mode'] != 'user') ||
          flags is! Map ||
          flags['demo'] is! bool) {
        throw ApiException(0, 'CONFIG', 'ตรวจโหมดแอปไม่ได้');
      }
      app.startupDemoEnabled = DemoSource.enabled(config);
    } on ApiException {
      if (current()) _unavailableConfig();
      busy = false;
      return;
    } on TimeoutException {
      if (current()) _unavailableConfig();
      busy = false;
      return;
    }
    final sources = <DemoSource>[];
    try {
      if (app.startupDemoEnabled) {
        var choices = app.api.onboardingChoices;
        if (choices.length > DemoSource.values.length ||
            !RegExp(r'^[ynd]*$').hasMatch(choices)) {
          choices = '';
        }
        while (mounted && choices.length < DemoSource.values.length) {
          if (!mounted) return;
          final choice = await showDemoSource(
            context,
            DemoSource.values[choices.length],
          );
          if (!current()) return;
          if (choice == null) continue;
          choices += switch (choice) {
            DemoChoice.use => 'y',
            DemoChoice.skip => 'n',
            DemoChoice.skipRemaining =>
              'n' * (DemoSource.values.length - choices.length),
          };
          app.api.saveOnboardingChoices(choices);
        }
        sources.addAll(
          DemoSource.values.where((source) => source.answer(choices) == 'y'),
        );
      }
      if (!current()) return;
      setState(() {
        assessing = true;
        storageError = false;
      });
      final result = await OpportunityAssessment.load(
        app.api,
        sources,
        trackDemoWrite: (request) => app.onboardingWrite = request.then<void>(
          (_) {},
          onError: (_, _) {},
        ),
      );
      if (current()) setState(() => assessment = result);
    } on FileSystemException {
      if (current()) setState(() => storageError = true);
    } on ApiException {
      if (current()) {
        setState(
          () =>
              assessment = const OpportunityAssessment(AssessmentStatus.failed),
        );
      }
    } on TimeoutException {
      if (current()) {
        setState(
          () =>
              assessment = const OpportunityAssessment(AssessmentStatus.failed),
        );
      }
    } finally {
      busy = false;
    }
  }

  void _unavailableConfig() {
    busy = false;
    widget.app.startupDemoEnabled = false;
    if (mounted) {
      setState(
        () => assessment = const OpportunityAssessment(
          AssessmentStatus.configUnavailable,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = assessment;
    if (result != null && !storageError) {
      return Shell(app: widget.app, assessment: result, retryAssessment: _run);
    }
    return ThangRotSplash(
      status: assessing ? 'กำลังประเมินสิทธิ์และรายได้' : null,
      onRetry: storageError ? _run : null,
    );
  }
}

/// Four bottom tabs, always visible on the tab roots (ui-states.md §1). Full-screen flows (quick check,
/// AI chat, route, plan, opportunity detail) are pushed on top and hide the bar; back returns to the tab.
class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.app,
    this.assessment,
    this.retryAssessment,
  });
  final AppState app;
  final OpportunityAssessment? assessment;
  final VoidCallback? retryAssessment;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final visitedTabs = <int>{};

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ValueListenableBuilder<int>(
      valueListenable: app.tab,
      builder: (context, i, _) {
        visitedTabs.add(i);
        return PopScope(
          // Android back on another tab goes to หน้าแรก first, then leaves the app.
          canPop: i == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) app.goTab(0);
          },
          child: Scaffold(
            body: IndexedStack(
              index: i,
              children: [
                if (visitedTabs.contains(0))
                  HomeTab(app: app)
                else
                  const SizedBox.shrink(),
                if (visitedTabs.contains(1))
                  OppTab(
                    app: app,
                    assessment: widget.assessment,
                    retryAssessment: widget.retryAssessment,
                  )
                else
                  const SizedBox.shrink(),
                if (visitedTabs.contains(2))
                  PlansTab(app: app)
                else
                  const SizedBox.shrink(),
                if (visitedTabs.contains(3))
                  MeTab(app: app)
                else
                  const SizedBox.shrink(),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: i,
              onDestinationSelected: (n) {
                app.goTab(n);
                app.bump(); // a tab shows fresh data every time it is opened
              },
              destinations: const [
                NavigationDestination(
                  icon: Text('🏠', style: TextStyle(fontSize: 22)),
                  label: 'หน้าแรก',
                ),
                NavigationDestination(
                  icon: Text('✨', style: TextStyle(fontSize: 22)),
                  label: 'โอกาส',
                ),
                NavigationDestination(
                  icon: Text('📋', style: TextStyle(fontSize: 22)),
                  label: 'แผนของฉัน',
                ),
                NavigationDestination(
                  icon: Text('👤', style: TextStyle(fontSize: 22)),
                  label: 'ฉัน',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
