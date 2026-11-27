import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'money.dart';
import 'opp_map.dart';
import 'opp_screen.dart';
import 'opportunity_assessment.dart';
import 'opportunity_catalog.dart';
import 'profile_screen.dart';

export 'opp_screen.dart' show OppScreen;
export 'opportunity_catalog.dart' show oppMoney;

enum OpportunityLane {
  all('all', 'ทั้งหมด', []),
  benefits('money', 'สิทธิ์และสวัสดิการ', [
    OpportunityCategory.welfare,
    OpportunityCategory.refund,
    OpportunityCategory.owed,
  ]),
  jobs('job', 'หางาน', [
    OpportunityCategory.fullTime,
    OpportunityCategory.partTime,
    OpportunityCategory.freelance,
  ]),
  sales('sell', 'ขายสินค้า', [OpportunityCategory.sell]),
  other('other', 'อื่นๆ', [
    OpportunityCategory.assets,
    OpportunityCategory.grant,
    OpportunityCategory.skill,
  ]);

  const OpportunityLane(this.group, this.label, this.categories);
  final String group, label;
  final List<OpportunityCategory> categories;

  static OpportunityLane forGroup(String group) => group == 'skill'
      ? other
      : values.firstWhere((lane) => lane.group == group, orElse: () => all);
}

class OppTab extends StatefulWidget {
  const OppTab({
    super.key,
    required this.app,
    this.assessment,
    this.retryAssessment,
  });
  final AppState app;
  final OpportunityAssessment? assessment;
  final VoidCallback? retryAssessment;

  @override
  State<OppTab> createState() => _OppTabState();
}

class _OppTabState extends State<OppTab> {
  final search = TextEditingController();
  final listScroll = ScrollController();
  final lanesScroll = ScrollController();
  final jobTypes = <OpportunityCategory>{};
  final items = <String, Map<String, dynamic>>{};
  final cursors = <OpportunityCategory?, String?>{};
  final completeMapCategories = <OpportunityCategory?>{};
  final laneKeys = {
    for (final lane in OpportunityLane.values) lane: GlobalKey(),
  };
  String submitted = '';
  String? district;
  ApiException? error;
  bool loading = false,
      mapView = false,
      noPins = false,
      bySkill = false,
      ranking = false;
  int generation = 0;
  Map<String, Map<String, dynamic>> rank = {};

  String get group => widget.app.oppGroup.value;
  OpportunityLane get lane => OpportunityLane.forGroup(group);

  @override
  void initState() {
    super.initState();
    widget.app.oppGroup.addListener(_changeLane);
    _reload();
  }

  @override
  void dispose() {
    widget.app.oppGroup.removeListener(_changeLane);
    search.dispose();
    listScroll.dispose();
    lanesScroll.dispose();
    super.dispose();
  }

  void _changeLane() {
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final laneContext = laneKeys[lane]?.currentContext;
      if (laneContext == null) return;
      Scrollable.ensureVisible(
        laneContext,
        duration: const Duration(milliseconds: 180),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  Future<void> _reload() {
    generation++;
    if (listScroll.hasClients) listScroll.jumpTo(0);
    final Iterable<OpportunityCategory?> categories = switch (lane) {
      OpportunityLane.all => [null],
      OpportunityLane.jobs when jobTypes.isNotEmpty =>
        OpportunityLane.jobs.categories.where(jobTypes.contains),
      OpportunityLane.other when group == 'skill' => [
        OpportunityCategory.skill,
      ],
      _ => lane.categories,
    };
    setState(() {
      items.clear();
      completeMapCategories.clear();
      cursors
        ..clear()
        ..addEntries(categories.map((category) => MapEntry(category, null)));
      error = null;
      loading = false;
      noPins = false;
      bySkill = false;
      rank = {};
    });
    return _loadPages(allPages: mapView);
  }

  Future<void> _loadPages({bool allPages = false}) async {
    if (loading) return;
    final request = generation;
    final q = submitted;
    final code = district;
    final scoped = bangkokDistricts[code];
    setState(() {
      loading = true;
      error = null;
    });
    try {
      do {
        final pages = await Future.wait(
          cursors.entries
              .where(
                (entry) =>
                    !allPages || !completeMapCategories.contains(entry.key),
              )
              .map((entry) async {
                final query = Uri(
                  queryParameters: {
                    'area': 'bangkok',
                    'limit': allPages ? '100' : '24',
                    if (entry.key case final category?)
                      'category': category.api,
                    'cursor': ?entry.value,
                    if (q.isNotEmpty) 'q': q,
                    if (code != null && scoped != null) ...{
                      'districtCode': code,
                      'district': scoped,
                    },
                  },
                );
                return MapEntry(
                  entry.key,
                  await widget.app.api.get('/v1/opportunities?${query.query}'),
                );
              }),
        );
        if (!mounted || request != generation) return;
        setState(() {
          for (final entry in pages) {
            if (entry.value['hasMoreMapLocations'] == false) {
              completeMapCategories.add(entry.key);
            }
            final cursor = entry.value['nextCursor'];
            if (cursor is String &&
                cursor.isNotEmpty &&
                cursor != cursors[entry.key]) {
              cursors[entry.key] = cursor;
            } else {
              cursors.remove(entry.key);
            }
            for (final item in itemsOf(entry.value)) {
              if (item['id'] case final String id
                  when !opportunityExpired(item)) {
                items.putIfAbsent(id, () => item);
              }
            }
          }
        });
      } while (allPages &&
          mapView &&
          cursors.keys.any(
            (category) => !completeMapCategories.contains(category),
          ));
      if (mapView && _pins().isEmpty) {
        setState(() {
          mapView = false;
          noPins = true;
        });
      }
    } on ApiException catch (failure) {
      if (mounted && request == generation) {
        setState(() {
          error = failure;
          if (mapView && _pins().isEmpty) {
            mapView = false;
            noPins = true;
          }
        });
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> _rankBySkill() async {
    if (bySkill) {
      setState(() {
        bySkill = false;
        rank = {};
      });
      return;
    }
    final request = generation;
    setState(() => ranking = true);
    try {
      final api = widget.app.api;
      final profile = await api.get('/v1/me/profile');
      if ((profile['skills'] as List? ?? const []).isEmpty) {
        throw ApiException(404, 'NO_SKILLS', '');
      }
      if (!mounted || request != generation) return;
      final ids = items.values
          .where((item) => item['suspicious'] != true)
          .map((item) => item['id'])
          .take(50)
          .toList();
      if (ids.isEmpty) return;
      final response = await api.post('/v1/ai/rankings', {
        'opportunityIds': ids,
      });
      if (!mounted || request != generation) return;
      final ranked = (response['ranked'] as List? ?? const [])
          .whereType<Map<String, dynamic>>();
      setState(() {
        bySkill = true;
        rank = {for (final item in ranked) '${item['opportunityId']}': item};
      });
    } on ApiException catch (failure) {
      if (!mounted || request != generation) return;
      if (failure.status == 404) {
        toast(context, 'บอกทักษะของคุณก่อน แล้วจะเรียงงานให้ตรงทักษะ');
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfileScreen(app: widget.app)),
        );
      } else {
        toast(context, failure.message);
      }
    } finally {
      if (mounted) setState(() => ranking = false);
    }
  }

  List<OpportunityPin> _pins() {
    final pins = <(String, String?), OpportunityPin>{};
    for (final item in items.values) {
      if ((item['provenance'] as Map?)?['dataStatus'] == 'mock' ||
          item['dataStatus'] == 'mock') {
        continue;
      }
      final id = item['id'] as String;
      for (final location in OpportunityLocation.of(item)) {
        final code = location.districtCode;
        if (district != null && code != district) continue;
        if (location.point case final point?) {
          pins.putIfAbsent(
            (id, code),
            () => (
              id: id,
              districtCode: code,
              title: '${item['title']}',
              point: point,
              category: OpportunityCategory.of(item),
            ),
          );
        }
      }
    }
    return pins.values.toList();
  }

  void _toggleMap() {
    if (mapView) {
      setState(() => mapView = false);
      return;
    }
    setState(() {
      mapView = true;
      noPins = false;
    });
    _loadPages(allPages: true);
  }

  void _submit(String value) {
    submitted = value.trim();
    _reload();
  }

  void _open(String id, {String? code}) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => OppScreen(
        app: widget.app,
        opportunityId: id,
        districtCode: code,
        summary: items[id],
      ),
    ),
  );

  void _openBenefit(Map<String, dynamic> item) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => OppScreen.money(
        app: widget.app,
        moneyId: '${item['id']}',
        summary: item,
        mockAssessment: widget.assessment?.mock == true,
      ),
    ),
  );

  Future<void> _chooseDistrict() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DistrictPicker(selected: district),
    );
    if (!mounted || code == null) return;
    district = code.isEmpty ? null : code;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final pins = mapView ? _pins() : <OpportunityPin>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('โอกาส'),
        actions: [
          TextButton.icon(
            onPressed: loading && !mapView ? null : _toggleMap,
            icon: Icon(mapView ? Icons.view_list_outlined : Icons.map_outlined),
            label: Text(mapView ? 'ดูรายการ' : 'ดูแผนที่'),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            controller: lanesScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final choice in OpportunityLane.values)
                  Padding(
                    key: laneKeys[choice],
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(choice.label),
                      selected: lane == choice,
                      onSelected: (_) =>
                          widget.app.oppGroup.value = choice.group,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: mapView
                ? Column(
                    children: [
                      _filters(),
                      if (error != null) const Text('โหลดพิกัดได้บางส่วน'),
                      Expanded(
                        child: loading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  semanticsLabel: 'กำลังโหลดพิกัด',
                                ),
                              )
                            : pins.isNotEmpty
                            ? OppMap(
                                key: ValueKey(generation),
                                pins: pins,
                                onOpen: (pin) =>
                                    _open(pin.id, code: pin.districtCode),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  )
                : _list(context),
          ),
        ],
      ),
    );
  }

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: 'ค้นหาโอกาส',
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'ล้างคำค้น',
              icon: const Icon(Icons.close),
              onPressed: () {
                search.clear();
                _submit('');
              },
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _chooseDistrict,
              icon: const Icon(Icons.place_outlined),
              label: Text(
                district == null
                    ? 'ทุกเขตในกรุงเทพฯ'
                    : 'เขต${bangkokDistricts[district]}',
              ),
            ),
            if (lane == OpportunityLane.jobs) ...[
              MenuAnchor(
                menuChildren: [
                  for (final category in OpportunityLane.jobs.categories)
                    CheckboxMenuButton(
                      closeOnActivate: false,
                      value: jobTypes.contains(category),
                      onChanged: (selected) {
                        selected == true
                            ? jobTypes.add(category)
                            : jobTypes.remove(category);
                        _reload();
                      },
                      child: Text(category.label),
                    ),
                ],
                builder: (context, controller, _) => OutlinedButton.icon(
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  icon: const Icon(Icons.arrow_drop_down),
                  label: Text(
                    jobTypes.isEmpty
                        ? 'ประเภทงาน'
                        : 'ประเภทงาน (${jobTypes.length})',
                  ),
                ),
              ),
              FilterChip(
                label: const Text('ตรงทักษะของฉัน'),
                selected: bySkill,
                onSelected: ranking ? null : (_) => _rankBySkill(),
              ),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _list(BuildContext context) {
    final shown = [
      for (final id in rank.keys) ?items[id],
      ...items.values.where((item) => !rank.containsKey(item['id'])),
    ];
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        controller: listScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _filters()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            sliver: SliverList.list(
              children: [
                if (noPins)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('ยังไม่มีพิกัดสำหรับตัวกรองนี้'),
                  ),
                if (lane == OpportunityLane.all ||
                    lane == OpportunityLane.benefits)
                  ..._assessment(context),
                if (error case final failure?)
                  if (failure.isNetwork)
                    OfflineCard(app: widget.app, onRetry: () => _loadPages())
                  else
                    ListTile(
                      title: Text(failure.message),
                      trailing: TextButton(
                        onPressed: _loadPages,
                        child: const Text('ลองใหม่'),
                      ),
                    ),
                if (shown.isEmpty && !loading && error == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('ไม่พบรายการตรงตัวกรอง'),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) => _card(context, shown[index]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: loading
                    ? const CircularProgressIndicator(
                        semanticsLabel: 'กำลังโหลดโอกาส',
                      )
                    : cursors.isNotEmpty && error == null
                    ? OutlinedButton(
                        onPressed: _loadPages,
                        child: const Text('โหลดเพิ่ม'),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> item) {
    final id = item['id'] as String;
    final category = OpportunityCategory.of(item);
    final locations = OpportunityLocation.of(item);
    final location = district == null
        ? locations.firstOrNull
        : locations.where((l) => l.districtCode == district).firstOrNull;
    final province = location?.districtName;
    final source =
        item['dataStatus'] ?? (item['provenance'] as Map?)?['dataStatus'];
    final fit = rank[id];
    return Card(
      child: ListTile(
        title: Text(
          '${item['title']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (category != null)
              Text(
                category.label,
                style: TextStyle(
                  color: category.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (item['organization'] case final String name) Text(name),
            Text(oppMoney(item)),
            if (province != null)
              Text(province.startsWith('เขต') ? province : 'เขต$province'),
            if (source is String)
              Text(
                dataLabel(source),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (fit?['reason'] case final String reason) Text(reason),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(
          id,
          code:
              district ??
              (locations.length == 1 ? location?.districtCode : null),
        ),
      ),
    );
  }

  List<Widget> _assessment(BuildContext context) {
    final assessment = widget.assessment;
    if (assessment == null) return [];
    switch (assessment.status) {
      case AssessmentStatus.loading:
        return [const ListTile(title: Text('กำลังประเมินสิทธิ์และรายได้'))];
      case AssessmentStatus.configUnavailable:
      case AssessmentStatus.failed:
        return [
          Card(
            child: ListTile(
              title: Text(
                assessment.status == AssessmentStatus.failed
                    ? 'ยังประเมินไม่สำเร็จ'
                    : 'ตรวจโหมดแอปไม่ได้',
              ),
              trailing: TextButton(
                onPressed: widget.retryAssessment,
                child: const Text('ลองใหม่'),
              ),
            ),
          ),
        ];
      case AssessmentStatus.ready:
        break;
    }
    final benefits = assessment.benefits
        .where((item) => OpportunityCategory.forMoney('${item['id']}') != null)
        .toList();
    final shown = benefits.where(
      (item) =>
          submitted.isEmpty ||
          '${item['title']} ${item['payer']}'.contains(submitted),
    );
    final counted = benefits.where(
      (item) =>
          {'likely', 'verified'}.contains(item['status']) &&
          (item['amount'] as Map?)?['value'] is num,
    );
    final pending = benefits
        .where(
          (item) =>
              {'need', 'check'}.contains(item['status']) ||
              (item['status'] == 'likely' &&
                  (item['amount'] as Map?)?['value'] is! num),
        )
        .length;
    String total(String kind) {
      final values = counted
          .where((item) => item['kind'] == kind)
          .map((item) => (item['amount'] as Map)['value'] as num);
      return values.isEmpty
          ? 'ยังไม่ทราบยอด'
          : '${baht(values.fold<num>(0, (sum, value) => sum + value)).substring(1)} บาท';
    }

    final missing =
        benefits.isEmpty || benefits.every((item) => item['status'] == 'need');
    return [
      Card(
        child: ExpansionTile(
          initiallyExpanded: lane == OpportunityLane.benefits,
          title: const Text('ผลประเมินสิทธิ์และสวัสดิการ'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (assessment.mock) const DemoPill(),
              if (missing) const Text('ข้อมูลยังไม่พอประเมิน'),
              Text('รายเดือน ${total('monthly')}'),
              Text('ครั้งเดียว ${total('once')}'),
              if (pending > 0) Text('ต้องตรวจต่อ $pending รายการ'),
              if (counted.isNotEmpty)
                const Text('ยอดประเมินตามเกณฑ์และข้อมูลที่มี'),
            ],
          ),
          children: [
            for (final item in shown)
              ListTile(
                title: Text('${item['title']}'),
                subtitle: Text(
                  '${OpportunityCategory.forMoney('${item['id']}')!.label} · ${benefitStatusLabel[item['status']] ?? ''}\n${benefitAmount(item)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openBenefit(item),
              ),
          ],
        ),
      ),
      if (lane == OpportunityLane.all) _incomeSummary(assessment),
    ];
  }

  Widget _incomeSummary(OpportunityAssessment assessment) {
    final wages = items.values.where(
      (item) =>
          OpportunityCategory.of(item)?.isBenefit == false &&
          hasOpportunityIncome(item),
    );
    final estimates = assessment.income.where(
      (item) =>
          {'B', 'C'}.contains(item['track']) &&
          item['netPerMonth'] is List &&
          (widget.app.allowsDemo ||
              {'live', 'curated', 'open_data'}.contains(item['dataStatus'])) &&
          ((district == null && submitted.isEmpty) ||
              items.containsKey(item['opportunityId'])),
    );
    return Card(
      child: ExpansionTile(
        title: const Text('รายได้จากงานและอาชีพ'),
        subtitle: Text(
          wages.isEmpty && estimates.isEmpty
              ? 'ยังไม่มีข้อมูลรายได้'
              : wages.isNotEmpty
              ? 'ดูค่าตอบแทนตามประกาศ'
              : 'ดูรายได้สุทธิโดยประมาณ',
        ),
        children: [
          for (final item in wages.take(3))
            ListTile(
              title: Text('${item['title']}'),
              subtitle: Text(
                '${oppMoney(item)}\n${dataLabel((item['provenance'] as Map?)?['dataStatus'] as String?)}',
              ),
              onTap: () => _open('${item['id']}', code: district),
            ),
          for (final item in estimates)
            if (item['netPerMonth'] case [final num low, final num high])
              ListTile(
                title: Text('${item['title']}'),
                subtitle: Text(
                  '${baht(low)} ถึง ${baht(high)} ต่อเดือน (ประมาณการ)\n'
                  '${(item['assumptions'] as List? ?? const []).join(' · ')}\n${dataLabel(item['dataStatus'] as String?)}',
                ),
              ),
        ],
      ),
    );
  }
}

class _DistrictPicker extends StatefulWidget {
  const _DistrictPicker({required this.selected});
  final String? selected;

  @override
  State<_DistrictPicker> createState() => _DistrictPickerState();
}

class _DistrictPickerState extends State<_DistrictPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .82,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'ค้นหาเขต',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(
                () => query = value.trim().replaceFirst(RegExp(r'^เขต\s*'), ''),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  title: const Text('ทุกเขตในกรุงเทพฯ'),
                  selected: widget.selected == null,
                  onTap: () => Navigator.pop(context, ''),
                ),
                for (final entry in bangkokDistricts.entries.where(
                  (entry) => entry.value.contains(query),
                ))
                  ListTile(
                    title: Text('เขต${entry.value}'),
                    selected: widget.selected == entry.key,
                    onTap: () => Navigator.pop(context, entry.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
