import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'home_tab.dart';
import 'me_tab.dart';
import 'opp_tab.dart';
import 'plans_tab.dart';

void main() => runApp(MoneyAnywhereApp(app: AppState(Api())));

class MoneyAnywhereApp extends StatelessWidget {
  const MoneyAnywhereApp({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: app.largeText,
      builder: (_, large, _) => MaterialApp(
        title: 'Money Anywhere',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E9F6E)), useMaterial3: true),
        // Large-text setting (ฉัน > ตัวอักษรใหญ่) on top of the phone's own font size.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(data: mq.copyWith(textScaler: large ? TextScaler.linear(mq.textScaler.scale(1) * 1.3) : mq.textScaler), child: child!);
        },
        home: Shell(app: app),
      ),
    );
  }
}

/// Four bottom tabs, always visible on the tab roots (ui-states.md §1). Full-screen flows (quick check,
/// AI chat, route, plan, opportunity detail) are pushed on top and hide the bar; back returns to the tab.
class Shell extends StatelessWidget {
  const Shell({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: app.tab,
      builder: (context, i, _) => PopScope(
        // Android back on another tab goes to หน้าแรก first, then leaves the app.
        canPop: i == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) app.goTab(0);
        },
        child: Scaffold(
          body: IndexedStack(index: i, children: [HomeTab(app: app), OppTab(app: app), PlansTab(app: app), MeTab(app: app)]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: (n) {
              app.goTab(n);
              app.bump(); // a tab shows fresh data every time it is opened
            },
            destinations: const [
              NavigationDestination(icon: Text('🏠', style: TextStyle(fontSize: 22)), label: 'หน้าแรก'),
              NavigationDestination(icon: Text('✨', style: TextStyle(fontSize: 22)), label: 'โอกาส'),
              NavigationDestination(icon: Text('📋', style: TextStyle(fontSize: 22)), label: 'แผนของฉัน'),
              NavigationDestination(icon: Text('👤', style: TextStyle(fontSize: 22)), label: 'ฉัน'),
            ],
          ),
        ),
      ),
    );
  }
}
