import 'package:material_ui/material_ui.dart';

import 'common.dart';
import 'connected_accounts.dart';
import 'money.dart';
import 'profile_fact_details.dart';
import 'profile_screen.dart';
import 'thang_rot_theme.dart';

export 'connected_accounts.dart' show ProfileDemo;

class ProfileOverviewScreen extends StatelessWidget {
  const ProfileOverviewScreen({
    super.key,
    required this.app,
    this.demo,
    this.onAccounts,
  });

  final AppState app;
  final ProfileDemo? demo;
  final VoidCallback? onAccounts;

  @override
  Widget build(BuildContext context) {
    final sample = demo;
    if (sample == null) {
      return _PersonalOverview(app: app, onAccounts: onAccounts);
    }
    final profile = sample.profile;
    final identity = sample.identity;
    final skills = (profile['skills'] as List? ?? const []).whereType<String>();
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์ตัวอย่าง')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Align(alignment: Alignment.centerLeft, child: DemoPill()),
            const SizedBox(height: 12),
            if (identity != null) ...[
              Text(
                'ข้อมูลส่วนตัว',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ThaidIdentityFields(identity: identity),
              if (identity.maskedId case final masked?)
                ProfileDetailRow(
                  icon: Icons.badge_outlined,
                  label: 'เลขบัตรประชาชน',
                  value: masked,
                ),
            ],
            if (skills.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('ทักษะ'),
              Wrap(
                spacing: 8,
                children: [
                  for (final skill in skills) Chip(label: Text(skill)),
                ],
              ),
            ],
            if (profile['incomeGoalPerMonth'] case final num amount)
              ProfileDetailRow(
                icon: Icons.flag_outlined,
                label: 'เป้ารายได้',
                value: baht(amount),
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonalOverview extends StatefulWidget {
  const _PersonalOverview({required this.app, this.onAccounts});
  final AppState app;
  final VoidCallback? onAccounts;

  @override
  State<_PersonalOverview> createState() => _PersonalOverviewState();
}

class _PersonalOverviewState extends State<_PersonalOverview> {
  late Future<PersonalProfile> data;

  @override
  void initState() {
    super.initState();
    widget.app.accounts.refresh();
    data = PersonalProfile.load(widget.app.api);
  }

  void _reload() {
    final request = PersonalProfile.load(widget.app.api);
    setState(() {
      data = request;
    });
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AccountsSnapshot>(
    valueListenable: widget.app.accounts,
    builder: (context, accounts, _) => FutureBuilder<PersonalProfile>(
      future: data,
      builder: (context, state) {
        final profile = state.data;
        final identity = accounts.thaid.identity;
        final name = identity?.displayName ?? profile?.displayName;
        final district = identity?.district ?? profile?.district;
        final skills = (profile?.fields['skills'] as List? ?? const [])
            .whereType<String>()
            .toList();
        final hours = profileText(profile?.fields['hoursPerWeek']);
        final income = profile?.fields['incomeGoalPerMonth'];
        final empty =
            name == null &&
            district == null &&
            skills.isEmpty &&
            hours == null &&
            income == null &&
            profile?.ageBand == null;
        final ready =
            state.connectionState == ConnectionState.done && profile != null;
        final edit = FilledButton.icon(
          onPressed: !ready
              ? null
              : () async {
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (context) => ProfileScreen(
                        app: widget.app,
                        onAccounts: widget.onAccounts == null
                            ? null
                            : () {
                                Navigator.of(this.context).pop();
                                widget.onAccounts!();
                              },
                      ),
                    ),
                  );
                  if (mounted) _reload();
                },
          icon: const Icon(Icons.edit_outlined),
          label: Text(empty ? 'กรอกโปรไฟล์' : 'แก้ไขโปรไฟล์'),
        );
        return Scaffold(
          bottomNavigationBar: ready && !empty
              ? SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(width: double.infinity, child: edit),
                )
              : null,
          body: Column(
            children: [
              BrandHeader(
                child: Column(
                  children: [
                    const Row(
                      children: [
                        BackButton(color: Colors.white),
                        Expanded(
                          child: Text(
                            'โปรไฟล์',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Colors.white,
                        foregroundColor: brandDark,
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(
                        name ?? 'โปรไฟล์ของฉัน',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (identity != null)
                            (identity.mock ? 'ThaID · ข้อมูลจำลอง' : 'ThaID'),
                          ?(identity?.ageText ?? profile?.ageBand),
                          ?district,
                          if (empty && ready) 'ยังไม่ได้กรอกข้อมูล',
                        ].join(' · '),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (state.connectionState != ConnectionState.done)
                      const Center(child: CircularProgressIndicator())
                    else if (!ready)
                      Card(
                        child: ListTile(
                          title: const Text('โหลดโปรไฟล์ไม่ได้'),
                          trailing: TextButton(
                            onPressed: _reload,
                            child: const Text('ลองใหม่'),
                          ),
                        ),
                      )
                    else if (empty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'บอกเราเกี่ยวกับคุณ',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'ระบุทักษะ เวลาว่าง และเป้ารายได้ เพื่อหาโอกาสที่ตรงกับคุณ',
                              ),
                              const SizedBox(height: 10),
                              edit,
                            ],
                          ),
                        ),
                      )
                    else ...[
                      if (identity != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: ThaidIdentityFields(identity: identity),
                          ),
                        ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'ทักษะ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (skills.isEmpty)
                                const Text('ยังไม่ได้ระบุทักษะ')
                              else
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    for (final skill in skills)
                                      Chip(label: Text(skill)),
                                  ],
                                ),
                              const Divider(),
                              Text(
                                'เวลาว่างต่อสัปดาห์ · ${hours ?? 'ยังไม่ได้ระบุ'}',
                              ),
                              Text(
                                'เป้ารายได้ต่อเดือน · ${income is num ? baht(income) : 'ยังไม่ได้ระบุ'}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      ProfileFactDetails(
                        profile: profile.fields,
                        facts: profile.facts,
                        hideMock: accounts.userMode,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
