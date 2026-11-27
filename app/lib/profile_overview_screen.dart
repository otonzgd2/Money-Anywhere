import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'money.dart';
import 'profile_screen.dart';
import 'thaid.dart';

typedef _DemoField = ({String field, String source, String value});

class ProfileDemo {
  const ProfileDemo._(this._profile, this.identity, this._fields);

  final Map<String, dynamic> _profile;
  final ThaidProfileIdentity identity;
  final List<_DemoField> _fields;

  static ProfileDemo? fromResponse(Map<String, dynamic> response) {
    if (response case {
      'dataStatus': 'mock',
      'profile': final Map<String, dynamic> profile,
      'identity': final Map<String, dynamic> identity,
      'sources': final List sources,
    }) {
      if (identity['dataStatus'] != 'mock') return null;
      return ProfileDemo._(profile, ThaidProfileIdentity(identity), [
        for (final source in sources)
          if (source case {
            'field': final String field,
            'label': final String label,
            'value': final String value,
          })
            (field: field, source: label, value: value),
      ]);
    }
    return null;
  }
}

class ProfileSnapshot {
  const ProfileSnapshot._(
    this._profile, {
    this.identity,
    this.example,
    this.sample,
  });

  final Map<String, dynamic> _profile;
  final ThaidProfileIdentity? identity;
  final ProfileDemo? example;
  final ProfileDemo? sample;

  factory ProfileSnapshot.demo(ProfileDemo demo) =>
      ProfileSnapshot._(demo._profile, identity: demo.identity, sample: demo);

  String? get displayName =>
      identity?.displayName ?? _text(_profile['displayName']);
  String? get district => identity?.district ?? _text(_profile['district']);
  int? get age => identity?.age;
  bool get mock => identity?.mock == true;

  static Future<ProfileSnapshot> load(
    Api api, {
    Map<String, Object?>? knownFacts,
  }) async {
    final identityRequest = govIdentity(api);
    final exampleRequest = _loadExample(api);
    final [profile, facts] = await Future.wait<Map<String, Object?>>([
      api.get('/v1/me/profile').onError<ApiException>((error, stack) {
        if (error.status == 404) return {};
        Error.throwWithStackTrace(error, stack);
      }),
      knownFacts == null ? api.get('/v1/me/facts') : Future.value(knownFacts),
    ]);
    final linked = await identityRequest;
    final example = await exampleRequest;
    if (linked == null &&
        example != null &&
        facts.isEmpty &&
        !_hasSavedProfile(profile)) {
      return ProfileSnapshot.demo(example);
    }
    return ProfileSnapshot._(
      profile,
      identity: linked == null ? null : ThaidProfileIdentity(linked),
      example: example,
    );
  }

  static Future<ProfileDemo?> _loadExample(Api api) async {
    try {
      return ProfileDemo.fromResponse(
        await api.get('/v1/demo/personas/gov-prefill'),
      );
    } on ApiException {
      return null;
    }
  }

  static bool _hasSavedProfile(Map<String, Object?> profile) =>
      [
        'displayName',
        'district',
        'hoursPerWeek',
        'constraints',
      ].any((key) => _text(profile[key]) != null) ||
      ['skills', 'goals'].any((key) => _texts(profile[key]).isNotEmpty) ||
      (profile['incomeGoalPerMonth'] is num &&
          (profile['incomeGoalPerMonth'] as num) > 0);
}

class ProfileOverviewScreen extends StatefulWidget {
  const ProfileOverviewScreen({super.key, required this.app, this.demo});
  final AppState app;
  final ProfileDemo? demo;

  @override
  State<ProfileOverviewScreen> createState() => _ProfileOverviewScreenState();
}

class _ProfileOverviewScreenState extends State<ProfileOverviewScreen> {
  late Future<ProfileSnapshot> snapshot;

  @override
  void initState() {
    super.initState();
    snapshot = widget.demo == null
        ? ProfileSnapshot.load(widget.app.api)
        : Future.value(ProfileSnapshot.demo(widget.demo!));
  }

  void _reload() {
    final next = ProfileSnapshot.load(widget.app.api);
    setState(() {
      snapshot = next;
    });
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProfileScreen(app: widget.app)),
    );
    if (saved == true && mounted) _reload();
  }

  void _openExample(ProfileDemo example) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfileOverviewScreen(app: widget.app, demo: example),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.demo == null ? 'โปรไฟล์ของฉัน' : 'โปรไฟล์ตัวอย่าง'),
      ),
      body: SafeArea(
        child: FutureBuilder<ProfileSnapshot>(
          future: snapshot,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = state.data;
            if (data == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 36),
                      const SizedBox(height: 12),
                      const Text('โหลดโปรไฟล์ไม่ได้'),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _reload,
                        child: const Text('ลองใหม่'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final example = data.example;
            return _ProfileDetails(
              data: data,
              onEdit: widget.demo == null ? _edit : null,
              onExample: example == null ? null : () => _openExample(example),
            );
          },
        ),
      ),
    );
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

List<String> _texts(Object? value) => [
  if (value is List)
    for (final item in value) ?_text(item),
];

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({required this.data, this.onEdit, this.onExample});
  final ProfileSnapshot data;
  final VoidCallback? onEdit;
  final VoidCallback? onExample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final profile = data._profile;
    final identity = data.identity;
    final nickname = _text(profile['displayName']);
    final jobDistrict = _text(profile['district']);
    final hours = _text(profile['hoursPerWeek']);
    final target = profile['incomeGoalPerMonth'];
    final skills = _texts(profile['skills']);
    final goals = _texts(profile['goals']);
    final constraints = _text(profile['constraints']);
    final targetText = target is num && target > 0
        ? '${baht(target)} ต่อเดือน'
        : null;
    final registryAddress = identity?.address;
    final registryDistrict = identity?.district;
    final registeredName = identity?.displayName;
    final personalRows = <Widget>[
      if (data.age case final age?)
        _ProfileRow(icon: Icons.cake_outlined, label: 'อายุ', value: '$age ปี'),
      if (registryAddress case final address?)
        _ProfileRow(
          icon: Icons.home_outlined,
          label: 'ที่อยู่ตามทะเบียนบ้าน',
          value: address,
        )
      else if (data.district case final district?)
        _ProfileRow(
          icon: Icons.location_on_outlined,
          label: 'เขตที่อยู่',
          value: district,
        ),
      if (identity?.maskedId case final id?)
        _ProfileRow(
          icon: Icons.badge_outlined,
          label: 'เลขบัตรประชาชน',
          value: id,
        ),
      if (registeredName != null &&
          nickname != null &&
          nickname != registeredName)
        _ProfileRow(
          icon: Icons.person_outline,
          label: 'ชื่อที่ใช้ในแอป',
          value: nickname,
        ),
      if (registryDistrict != null &&
          jobDistrict != null &&
          registryDistrict != jobDistrict)
        _ProfileRow(
          icon: Icons.work_outline,
          label: 'เขตสำหรับหางาน',
          value: jobDistrict,
        ),
    ];
    final importedRows = <Widget>[
      for (final field in data.sample?._fields ?? const <_DemoField>[])
        if (field.field != 'identity')
          switch (field.field) {
            'disabilityCard' => _ProfileRow(
              icon: Icons.accessible_forward,
              label: 'บัตรประจำตัวคนพิการ',
              value: field.value,
              source: field.source,
            ),
            'ss33' => _ProfileRow(
              icon: Icons.shield_outlined,
              label: 'การส่งเงินสมทบ',
              value: field.value,
              source: field.source,
            ),
            'taxWithheld' => _ProfileRow(
              icon: Icons.receipt_long_outlined,
              label: 'ภาษีหัก ณ ที่จ่าย',
              value: field.value,
              source: field.source,
            ),
            _ => const SizedBox.shrink(),
          },
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: colors.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  child: const Icon(Icons.person_outline),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        registeredName == null
                            ? 'ชื่อที่ใช้ในแอป'
                            : 'ชื่อ–นามสกุล',
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(
                        data.displayName ?? 'ยังไม่ได้ตั้งชื่อ',
                        style: theme.textTheme.titleLarge,
                      ),
                      if (data.mock) ...[
                        const SizedBox(height: 6),
                        const DemoPill(text: 'DEMO / MOCK'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (personalRows.isNotEmpty || importedRows.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ข้อมูลส่วนตัว',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (identity != null)
                Text('ThaID', style: theme.textTheme.labelMedium),
            ],
          ),
          ...personalRows,
          if (importedRows.isNotEmpty) const Divider(height: 16),
          ...importedRows,
        ],
        if (hours != null ||
            targetText != null ||
            goals.isNotEmpty ||
            constraints != null) ...[
          const Divider(height: 28),
          Text('งานและรายได้', style: theme.textTheme.titleMedium),
          if (hours != null)
            _ProfileRow(
              icon: Icons.schedule_outlined,
              label: 'เวลาว่าง',
              value: hours == 'เต็มเวลา' ? hours : '$hours ชม./สัปดาห์',
            ),
          if (targetText != null)
            _ProfileRow(
              icon: Icons.flag_outlined,
              label: 'เป้ารายได้',
              value: targetText,
            ),
          if (goals.isNotEmpty)
            _ProfileRow(
              icon: Icons.checklist_outlined,
              label: 'เป้าหมาย',
              value: goals.join(', '),
            ),
          if (constraints != null)
            _ProfileRow(
              icon: Icons.info_outline,
              label: 'ข้อจำกัด',
              value: constraints,
            ),
        ],
        if (skills.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('ทักษะ', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [for (final skill in skills) Chip(label: Text(skill))],
          ),
        ],
        if (onEdit case final edit?) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: edit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('แก้ไขโปรไฟล์'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
        if (onExample case final example?)
          TextButton(
            onPressed: example,
            child: const Text('ดูโปรไฟล์ตัวอย่าง'),
          ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    this.source,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? source;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 24,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      trailing: source == null
          ? null
          : Text(source!, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
