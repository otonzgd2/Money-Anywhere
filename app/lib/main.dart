import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat.dart';
import 'common.dart';
import 'home_tab.dart';
import 'me_tab.dart';
import 'onboarding_screen.dart';
import 'opp_tab.dart';
import 'opportunity_assessment.dart';
import 'plans_tab.dart';
import 'thang_rot_theme.dart';

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
          theme: thangRotTheme(),
          home: ThangRotSplash(
            onRetry: snapshot.hasError
                ? () {
                    final request = widget.initialize();
                    setState(() {
                      startup = request;
                    });
                  }
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
    backgroundColor: Colors.white,
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
                  const BrandLogo(size: 136, wordmark: true),
                  if (status case final message?) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
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
        theme: thangRotTheme(),
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
  bool onboarding = false;
  bool acknowledged = false;
  int sourceIndex = 0;
  String choices = '';
  String? connectionError;
  ConnectionStage connectionStage = ConnectionStage.idle;

  @override
  void initState() {
    super.initState();
    widget.app.dataCleared.addListener(_clearAssessment);
    widget.app.goTab(AppTab.opportunities, group: 'all');
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
    setState(() {
      onboarding = false;
      assessment = const OpportunityAssessment(AssessmentStatus.ready);
    });
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
        choices = app.api.onboardingChoices;
        if (choices.length > DemoSource.values.length ||
            !RegExp(r'^[ynd]*$').hasMatch(choices)) {
          choices = '';
        }
        if (choices.length < DemoSource.values.length ||
            app.api.onboardingSummaryPending) {
          if (!current()) return;
          app.api.setOnboardingSummaryPending(true);
          setState(() {
            onboarding = true;
            storageError = false;
            sourceIndex = choices.length;
            connectionStage = ConnectionStage.idle;
          });
          return;
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

  void _record(String answer) {
    final next = choices.padRight(sourceIndex, 'n');
    final end = sourceIndex + answer.length;
    final saved =
        next.substring(0, sourceIndex) +
        answer +
        (end < next.length ? next.substring(end) : '');
    try {
      widget.app.api.saveOnboardingChoices(saved);
    } on FileSystemException {
      setState(() {
        connectionStage = ConnectionStage.failed;
        connectionError = 'บันทึกตัวเลือกไม่ได้ ลองอีกครั้ง';
      });
      return;
    }
    setState(() {
      choices = saved;
      sourceIndex = end;
      connectionStage = ConnectionStage.idle;
      connectionError = null;
    });
  }

  Future<void> _connect() async {
    final source = DemoSource.values[sourceIndex];
    setState(() {
      connectionError = null;
      connectionStage = ConnectionStage.connecting;
    });
    try {
      await source.loadPreview(widget.app.api);
      if (!mounted || !onboarding) return;
      setState(() => connectionStage = ConnectionStage.connected);
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (mounted && onboarding) _record('y');
    } on ApiException catch (error) {
      _connectionFailed(error.message);
    } on TimeoutException {
      _connectionFailed('ใช้เวลาเชื่อมต่อนานเกินไป ลองใหม่หรือเลือกไว้ภายหลัง');
    }
  }

  void _connectionFailed(String message) {
    if (!mounted || !onboarding) return;
    setState(() {
      connectionStage = ConnectionStage.failed;
      connectionError = message;
    });
  }

  void _startAssessment() {
    try {
      widget.app.api.setOnboardingSummaryPending(false);
    } on FileSystemException {
      setState(() => connectionError = 'บันทึกการรับทราบไม่ได้ ลองอีกครั้ง');
      return;
    }
    setState(() {
      onboarding = false;
      assessment = null;
      assessing = true;
    });
    unawaited(_run());
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
    if (onboarding) {
      return OnboardingScreen(
        app: widget.app,
        index: sourceIndex,
        choices: choices,
        stage: connectionStage,
        acknowledged: acknowledged,
        error: connectionError,
        onBack: () => setState(() {
          sourceIndex--;
          connectionStage = ConnectionStage.idle;
          connectionError = null;
        }),
        onConnect: _connect,
        onSkip: () => _record('n'),
        onSkipAll: () =>
            _record('n' * (DemoSource.values.length - sourceIndex)),
        onAcknowledge: (value) => setState(() => acknowledged = value),
        onStart: _startAssessment,
      );
    }
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

/// Keep visited tabs mounted so search, scroll and chat drafts survive navigation.
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
  final visitedTabs = <AppTab>{};
  final jobMenu = MenuController();

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ValueListenableBuilder<AppTab>(
      valueListenable: app.tab,
      builder: (context, i, _) {
        visitedTabs.add(i);
        return PopScope(
          // Android back on another tab goes to หน้าแรก first, then leaves the app.
          canPop: i == AppTab.home,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (jobMenu.isOpen) {
              jobMenu.close();
            } else {
              app.goTab(AppTab.home);
            }
          },
          child: Scaffold(
            body: IndexedStack(
              index: i.index,
              children: [
                for (final tab in AppTab.values)
                  if (visitedTabs.contains(tab))
                    TickerMode(
                      enabled: i == tab,
                      child: ExcludeFocus(
                        excluding: i != tab,
                        child: _page(tab),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              height:
                  64 +
                  (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(
                        0.0,
                        22.0,
                      ) *
                      2,
              selectedIndex: i.index,
              onDestinationSelected: (n) {
                FocusManager.instance.primaryFocus?.unfocus();
                if (jobMenu.isOpen) jobMenu.close();
                app.goTab(AppTab.values[n]);
                app.bump(); // a tab shows fresh data every time it is opened
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'หน้าแรก',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'คุยกับ AI',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  label: 'โอกาส',
                ),
                NavigationDestination(
                  icon: Icon(Icons.assignment_outlined),
                  selectedIcon: Icon(Icons.assignment),
                  label: 'แผนของฉัน',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_circle_outlined),
                  selectedIcon: Icon(Icons.account_circle),
                  label: 'บัญชี',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _page(AppTab tab) {
    final app = widget.app;
    return switch (tab) {
      AppTab.home => HomeTab(app: app, assessment: widget.assessment),
      AppTab.chat => ValueListenableBuilder<AppState?>(
        valueListenable: app.demoChat,
        builder: (context, demo, _) => ChatScreen(
          key: ObjectKey(demo ?? app),
          app: demo ?? app,
          session: (demo ?? app).chat,
          title: demo == null ? null : 'คุยกับ AI · DEMO',
        ),
      ),
      AppTab.opportunities => OppTab(
        app: app,
        assessment: widget.assessment,
        retryAssessment: widget.retryAssessment,
        jobMenu: jobMenu,
      ),
      AppTab.plans => PlansTab(app: app),
      AppTab.account => MeTab(app: app),
    };
  }
}
