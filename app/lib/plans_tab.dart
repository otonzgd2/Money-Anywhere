import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'opportunity_catalog.dart';
import 'task_screen.dart';
import 'thang_rot_theme.dart';

typedef _SavedPlan = ({DemoChatProfile? demo, Map<String, dynamic> task});
typedef _PlanList = ({List<_SavedPlan> plans, ApiException? error});

const _accent = brandBlue;
const _secondaryText = mutedInk;
const _cardShape = RoundedRectangleBorder(
  side: BorderSide(color: cardBorder),
  borderRadius: BorderRadius.all(Radius.circular(18)),
);

enum _PlanStatus {
  active('active', brandDark, blueTint),
  blocked('blocked', Color(0xFF852F1B), Color(0xFFFBECE5)),
  snoozed('snoozed', Color(0xFF624F1C), Color(0xFFF8F0DC)),
  finished('finished', Color(0xFF3B554A), Color(0xFFEDF2EE)),
  unknown(null, Color(0xFF3B554A), Color(0xFFEDF2EE));

  const _PlanStatus(this.api, this.foreground, this.background);

  final String? api;
  final Color foreground, background;

  String get label => taskStatusLabel[api] ?? 'ไม่ระบุสถานะ';

  static _PlanStatus of(Object? value) =>
      values.where((status) => status.api == value).firstOrNull ?? unknown;
}

/// Shows the status and progress of plans saved across all profiles.
class PlansTab extends StatefulWidget {
  const PlansTab({super.key, required this.app});
  final AppState app;
  @override
  State<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<PlansTab> {
  List<_SavedPlan>? plans;
  ApiException? error;
  int loadVersion = 0;

  @override
  void initState() {
    super.initState();
    widget.app.changed.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.app.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++loadVersion;
    final results = await Future.wait([
      _loadFrom(null),
      for (final demo in DemoChatProfile.values) _loadFrom(demo),
    ]);
    if (!mounted || version != loadVersion) return;
    setState(() {
      plans = [for (final result in results) ...result.plans];
      error = results.map((result) => result.error).nonNulls.firstOrNull;
    });
  }

  Future<_PlanList> _loadFrom(DemoChatProfile? demo) async {
    final api = demo == null
        ? widget.app.api
        : widget.app.api.forDemo(demo.deviceSuffix);
    try {
      final r = await api.get('/v1/tasks');
      final items = (r['items'] as List).cast<Map<String, dynamic>>();
      return (
        plans: [for (final task in items) (demo: demo, task: task)],
        error: null,
      );
    } on ApiException catch (e) {
      return (plans: const <_SavedPlan>[], error: e);
    } finally {
      if (demo != null) api.close();
    }
  }

  Future<void> _openPlan(_SavedPlan plan) async {
    final demo = plan.demo;
    final app = demo == null ? widget.app : widget.app.forDemoChat(demo);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TaskScreen(app: app, taskId: '${plan.task['id']}'),
        ),
      );
    } finally {
      if (demo != null) app.api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = plans ?? const <_SavedPlan>[];
    final failure = error;
    final byStatus = {
      for (final status in _PlanStatus.values) status: <_SavedPlan>[],
    };
    for (final plan in list) {
      byStatus[_PlanStatus.of(plan.task['status'])]!.add(plan);
    }
    final groups = [
      (label: 'กำลังทำ', plans: byStatus[_PlanStatus.active]!),
      (
        label: 'รอดำเนินการ',
        plans: [
          ...byStatus[_PlanStatus.blocked]!,
          ...byStatus[_PlanStatus.snoozed]!,
        ],
      ),
      (label: 'เสร็จแล้ว', plans: byStatus[_PlanStatus.finished]!),
      (label: 'ไม่ระบุสถานะ', plans: byStatus[_PlanStatus.unknown]!),
    ].where((group) => group.plans.isNotEmpty).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          key: const PageStorageKey('saved-plans'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(list.length)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(13, 14, 13, 20),
              sliver: SliverList.list(
                children: [
                  if (failure != null) ...[
                    _loadError(failure),
                    if (list.isNotEmpty) const SizedBox(height: 14),
                  ] else if (plans == null)
                    const Center(child: CircularProgressIndicator())
                  else if (list.isEmpty)
                    _emptyCard(),
                  for (final (index, group) in groups.indexed) ...[
                    if (index > 0) const SizedBox(height: 18),
                    if (groups.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Semantics(
                          header: true,
                          child: Text(
                            group.label,
                            style: const TextStyle(
                              color: brandInk,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    for (final (position, plan) in group.plans.indexed) ...[
                      if (position > 0) const SizedBox(height: 9),
                      _planCard(plan),
                    ],
                  ],
                  if (list.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 11, 4, 0),
                      child: Text(
                        'สถานะและความคืบหน้าอิงจากที่คุณแจ้ง',
                        style: TextStyle(color: mutedInk, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadError(ApiException failure) {
    if (failure.isNetwork) return OfflineCard(app: widget.app, onRetry: _load);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(failure.message),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('ลองใหม่')),
          ],
        ),
      ),
    );
  }

  Widget _header(int count) => BrandHeader(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'แผนของฉัน',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (count > 0) ...[
          const SizedBox(height: 4),
          Text(
            '$count แผนที่บันทึก',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ],
    ),
  );

  Widget _emptyCard() => Material(
    color: Colors.white,
    shape: _cardShape,
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text(
              'ยังไม่มีแผน',
              style: TextStyle(
                color: brandInk,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'บันทึกสิทธิ์หรืองานที่สนใจ แล้วกลับมาติดตามความคืบหน้าที่นี่',
            style: TextStyle(color: _secondaryText),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
            ),
            onPressed: () => widget.app.goTab(AppTab.home),
            child: const Text(
              'ไปเช็คเงินที่หน้าแรก',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _planCard(_SavedPlan plan) {
    final task = plan.task;
    final status = _PlanStatus.of(task['status']);
    final category =
        OpportunityCategory.of(task) ??
        OpportunityCategory.forMoney(task['moneyId'] as String? ?? '');
    final steps = task['steps'] as List;
    final doneCount = (task['doneCount'] as num?)?.toInt() ?? 0;
    final done = doneCount.clamp(0, steps.length);
    final next =
        status != _PlanStatus.finished &&
            doneCount >= 0 &&
            doneCount < steps.length
        ? steps[doneCount] as String
        : null;
    return MergeSemantics(
      key: ValueKey((plan.demo, task['id'])),
      child: Semantics(
        button: true,
        child: Material(
          color: Colors.white,
          elevation: 1,
          shadowColor: cardBorder,
          shape: _cardShape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openPlan(plan),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Column(
                spacing: 7,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (category != null) ...[
                        OpportunityArtwork(
                          category: category,
                          moneyId: task['moneyId'] as String?,
                          size: 36,
                        ),
                        const SizedBox(width: 7),
                      ],
                      Expanded(
                        child: category == null
                            ? const SizedBox.shrink()
                            : Text(
                                category.label,
                                style: TextStyle(
                                  color: category.color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: status.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              child: Text(
                                status.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: status.foreground,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${task['title']}',
                          style: const TextStyle(
                            color: brandInk,
                            fontSize: 16,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: brandDark,
                      ),
                    ],
                  ),
                  if (plan.demo case final demo?)
                    Text(
                      demo.planLabel,
                      style: const TextStyle(
                        color: _secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  if (next != null && next.isNotEmpty)
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'ขั้นถัดไป ',
                            style: TextStyle(
                              color: brandDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: next),
                        ],
                      ),
                      style: const TextStyle(
                        color: _secondaryText,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  if (steps.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: ExcludeSemantics(
                            child: LinearProgressIndicator(
                              value: done / steps.length,
                              minHeight: 5,
                              color: _accent,
                              backgroundColor: blueTint,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(3),
                              ),
                              trackGap: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          '$done/${steps.length} ขั้น',
                          semanticsLabel:
                              'ทำแล้ว $done จาก ${steps.length} ขั้น',
                          style: const TextStyle(
                            color: _secondaryText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
