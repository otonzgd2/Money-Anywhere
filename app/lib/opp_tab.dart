import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'money.dart';
import 'opp_map.dart';
import 'opp_screen.dart';
import 'opportunity_assessment.dart';
import 'opportunity_catalog.dart';
import 'profile_screen.dart';
import 'thang_rot_theme.dart';

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
  other('other', 'อื่น ๆ', [
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

  IconData get icon => switch (this) {
    all => Icons.grid_view_outlined,
    benefits => Icons.volunteer_activism_outlined,
    jobs => Icons.work_outline,
    sales => Icons.storefront_outlined,
    other => Icons.more_horiz,
  };
}

class OppTab extends StatefulWidget {
  const OppTab({
    super.key,
    required this.app,
    this.assessment,
    this.retryAssessment,
    this.jobMenu,
  });
  final AppState app;
  final OpportunityAssessment? assessment;
  final VoidCallback? retryAssessment;
  final MenuController? jobMenu;

  @override
  State<OppTab> createState() => _OppTabState();
}

class _OppTabState extends State<OppTab> {
  final search = TextEditingController();
  Timer? searchDelay;
  final listScroll = ScrollController();
  late final jobMenu = widget.jobMenu ?? MenuController();
  final jobTypes = <OpportunityCategory>{};
  final items = <String, Map<String, dynamic>>{};
  final cursors = <OpportunityCategory?, String?>{};
  final completeMapCategories = <OpportunityCategory?>{};
  List<DistrictPin>? districtPins;
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
    searchDelay?.cancel();
    search.dispose();
    listScroll.dispose();
    super.dispose();
  }

  void _changeLane() => _reload();

  Iterable<OpportunityCategory?> get _categories => switch (lane) {
    OpportunityLane.all => [null],
    OpportunityLane.jobs when jobTypes.isNotEmpty =>
      OpportunityLane.jobs.categories.where(jobTypes.contains),
    OpportunityLane.other when group == 'skill' => [OpportunityCategory.skill],
    _ => lane.categories,
  };

  Future<void> _reload() {
    generation++;
    if (listScroll.hasClients) listScroll.jumpTo(0);
    setState(() {
      items.clear();
      completeMapCategories.clear();
      districtPins = null;
      cursors
        ..clear()
        ..addEntries(_categories.map((category) => MapEntry(category, null)));
      error = null;
      loading = false;
      noPins = false;
      bySkill = false;
      rank = {};
    });
    return _loadPages(allPages: mapView);
  }

  Future<Map<String, dynamic>> _searchPage({
    required OpportunityCategory? category,
    required int limit,
    String? cursor,
    bool includeDistrictPins = false,
  }) {
    final code = district;
    final scoped = bangkokDistricts[code];
    final query = Uri(
      queryParameters: {
        'area': 'bangkok',
        'limit': '$limit',
        if (category != null) 'category': category.api,
        'cursor': ?cursor,
        if (submitted.isNotEmpty) 'q': submitted,
        if (code != null && scoped != null) ...{
          'districtCode': code,
          'district': scoped,
        },
        if (includeDistrictPins) 'includeDistrictPins': 'true',
      },
    );
    return widget.app.api.get('/v1/opportunities?${query.query}');
  }

  Future<List<DistrictPin>> _loadDistrictPins() async {
    final pages = await Future.wait(
      _categories.map(
        (category) => _searchPage(
          category: category,
          limit: 1,
          includeDistrictPins: true,
        ),
      ),
    );
    final totals = <String, DistrictPin>{};
    for (final page in pages) {
      final values = page['districtPins'];
      if (values is! List) continue;
      for (final value in values) {
        if (value case {
          'district': final String name,
          'lat': final num lat,
          'lng': final num lng,
          'count': final int count,
        }) {
          totals[name] = (
            district: name,
            point: LatLng(lat.toDouble(), lng.toDouble()),
            count: (totals[name]?.count ?? 0) + count,
          );
        }
      }
    }
    return totals.values.toList();
  }

  Future<void> _loadPages({bool allPages = false}) async {
    if (loading) return;
    final request = generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (allPages && districtPins == null) {
        final pins = await _loadDistrictPins();
        if (!mounted || request != generation) return;
        setState(() => districtPins = pins);
      }
      do {
        final pages = await Future.wait(
          cursors.entries
              .where(
                (entry) =>
                    !allPages || !completeMapCategories.contains(entry.key),
              )
              .map(
                (entry) async => MapEntry(
                  entry.key,
                  await _searchPage(
                    category: entry.key,
                    cursor: entry.value,
                    limit: allPages ? 100 : 24,
                  ),
                ),
              ),
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
      if (mapView && _hasNoPins) {
        setState(() {
          mapView = false;
          noPins = true;
        });
      }
    } on ApiException catch (failure) {
      if (mounted && request == generation) {
        setState(() {
          error = failure;
          if (mapView && _hasNoPins) {
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

  bool get _hasNoPins => (districtPins?.isEmpty ?? true) && _pins().isEmpty;

  void _openDistrict(String name) {
    final code = bangkokDistricts.entries
        .where((entry) => entry.value == name)
        .firstOrNull
        ?.key;
    if (code == null) return;
    setState(() {
      district = code;
      mapView = false;
    });
    _reload();
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
    searchDelay?.cancel();
    final query = value.trim();
    if (query == submitted) return;
    submitted = query;
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
    final demoPins = districtPins ?? const <DistrictPin>[];
    return Scaffold(
      body: Column(
        children: [
          _header(),
          Expanded(
            child: mapView
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          [
                            '${pins.length} พิกัดที่ยืนยันได้',
                            if (demoPins.isNotEmpty)
                              'DEMO · ${demoPins.length} เขต',
                            if (error != null) 'โหลดได้บางส่วน',
                          ].join(' · '),
                          style: const TextStyle(color: mutedInk),
                        ),
                      ),
                      Expanded(
                        child: loading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  semanticsLabel: 'กำลังโหลดพิกัด',
                                ),
                              )
                            : pins.isNotEmpty || demoPins.isNotEmpty
                            ? OppMap(
                                key: ValueKey(generation),
                                pins: pins,
                                districtPins: demoPins,
                                onOpen: (pin) =>
                                    _open(pin.id, code: pin.districtCode),
                                onOpenDistrict: _openDistrict,
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

  Widget _header() => BrandHeader(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'โอกาส',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: loading && !mapView ? null : _toggleMap,
              icon: Icon(
                mapView ? Icons.view_list_outlined : Icons.map_outlined,
              ),
              label: Text(mapView ? 'ดูรายการ' : 'ดูแผนที่'),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                style: const TextStyle(color: brandInk),
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                onChanged: (value) {
                  searchDelay?.cancel();
                  searchDelay = Timer(
                    const Duration(milliseconds: 300),
                    () => _submit(value),
                  );
                },
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'ค้นหา',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  suffixIconConstraints: const BoxConstraints(),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: search,
                    builder: (_, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            tooltip: 'ล้างคำค้น',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              search.clear();
                              _submit('');
                            },
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 145),
                child: TextButton(
                  style: TextButton.styleFrom(backgroundColor: Colors.white),
                  onPressed: _chooseDistrict,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.place_outlined, size: 17),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          district == null
                              ? 'ทุกเขตในกรุงเทพฯ'
                              : 'เขต${bangkokDistricts[district]}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (_, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final choice in OpportunityLane.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _laneButton(
                      choice,
                      compact: constraints.maxWidth < 410,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (lane == OpportunityLane.jobs)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MenuAnchor(
                controller: jobMenu,
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
                builder: (context, controller, _) => TextButton.icon(
                  style: TextButton.styleFrom(backgroundColor: Colors.white),
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
                backgroundColor: Colors.white,
                selected: bySkill,
                onSelected: ranking ? null : (_) => _rankBySkill(),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _laneButton(OpportunityLane choice, {required bool compact}) {
    final selected = lane == choice;
    final count = lane == OpportunityLane.all || selected
        ? items.values
                  .where(
                    (item) =>
                        choice == OpportunityLane.all ||
                        choice.categories.contains(
                          OpportunityCategory.of(item),
                        ),
                  )
                  .length +
              (choice == OpportunityLane.all ||
                      choice == OpportunityLane.benefits
                  ? _visibleBenefits.length
                  : 0)
        : null;
    return Semantics(
      selected: selected,
      label: [
        choice.label,
        if (count != null) '$count รายการที่แสดง',
      ].join(', '),
      button: true,
      child: TextButton(
        onPressed: () => widget.app.oppGroup.value = choice.group,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.padded,
          foregroundColor: selected ? brandButton : Colors.white,
          backgroundColor: selected ? Colors.white : const Color(0x264AABFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: ExcludeSemantics(
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(choice.icon, size: 20),
                  if (count != null) ...[
                    const SizedBox(width: 4),
                    Text('$count', style: const TextStyle(fontSize: 11)),
                  ],
                ],
              ),
              Text(
                compact && choice == OpportunityLane.benefits
                    ? 'สิทธิ์'
                    : choice.label,
                style: const TextStyle(fontSize: 11),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _visibleBenefits => [
    for (final item
        in widget.assessment?.benefits ?? const <Map<String, dynamic>>[])
      if (OpportunityCategory.forMoney('${item['id']}') != null &&
          (submitted.isEmpty ||
              '${item['title']} ${item['payer']}'.contains(submitted)))
        item,
  ];

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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            sliver: SliverList.list(
              children: [
                Text(
                  '${shown.length + (lane == OpportunityLane.all || lane == OpportunityLane.benefits ? _visibleBenefits.length : 0)} รายการที่แสดง',
                  style: const TextStyle(color: mutedInk),
                ),
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
                if (shown.isEmpty &&
                    !loading &&
                    error == null &&
                    (lane != OpportunityLane.all &&
                            lane != OpportunityLane.benefits ||
                        _visibleBenefits.isEmpty))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('ไม่พบรายการตรงตัวกรอง'),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList.list(
              children: [
                if (lane == OpportunityLane.all)
                  for (final group in OpportunityLane.values.skip(1)) ...[
                    if (shown.any(
                      (item) => group.categories.contains(
                        OpportunityCategory.of(item),
                      ),
                    )) ...[
                      _sectionHeader(
                        group.label,
                        onTap: () => widget.app.oppGroup.value = group.group,
                      ),
                      for (final item in shown.where(
                        (item) => group.categories.contains(
                          OpportunityCategory.of(item),
                        ),
                      ))
                        _card(context, item),
                    ],
                  ]
                else
                  for (final item in shown) _card(context, item),
                if (lane == OpportunityLane.all)
                  for (final item in shown.where(
                    (item) => OpportunityCategory.of(item) == null,
                  ))
                    _card(context, item),
              ],
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

  Widget _sectionHeader(String title, {VoidCallback? onTap}) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      if (onTap != null)
        TextButton(onPressed: onTap, child: const Text('ดูทั้งหมด ›')),
    ],
  );

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        leading: OpportunityArtwork(category: category),
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
            Text(
              oppMoney(item),
              style: const TextStyle(
                color: brandDark,
                fontWeight: FontWeight.w800,
              ),
            ),
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
    final shown = _visibleBenefits;
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
              Text(
                'รายเดือน ${total('monthly')}',
                style: const TextStyle(
                  color: brandDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              Text(
                'ครั้งเดียว ${total('once')}',
                style: const TextStyle(
                  color: brandDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (pending > 0) Text('ต้องตรวจต่อ $pending รายการ'),
              if (counted.isNotEmpty)
                const Text('ยอดประเมินตามเกณฑ์และข้อมูลที่มี'),
            ],
          ),
          children: [
            for (final category in OpportunityLane.benefits.categories)
              if (shown.any(
                (item) =>
                    OpportunityCategory.forMoney('${item['id']}') == category,
              )) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _sectionHeader(category.label),
                ),
                for (final item in shown.where(
                  (item) =>
                      OpportunityCategory.forMoney('${item['id']}') == category,
                ))
                  ListTile(
                    leading: OpportunityArtwork(
                      category: category,
                      moneyId: item['id'] as String?,
                    ),
                    title: Text('${item['title']}'),
                    subtitle: Text(
                      '${OpportunityCategory.forMoney('${item['id']}')!.label} · ${benefitStatusLabel[item['status']] ?? ''}\n${benefitAmount(item)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openBenefit(item),
                  ),
              ],
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
