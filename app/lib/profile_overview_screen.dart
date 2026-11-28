import 'package:material_ui/material_ui.dart';

import 'common.dart';
import 'connected_accounts.dart';
import 'money.dart';
import 'profile_fact_details.dart';
import 'profile_screen.dart';

export 'connected_accounts.dart' show ProfileDemo;

class ProfileOverviewScreen extends StatelessWidget {
  const ProfileOverviewScreen({super.key, required this.app, this.demo});

  final AppState app;
  final ProfileDemo? demo;

  @override
  Widget build(BuildContext context) {
    final sample = demo;
    if (sample == null) return ProfileScreen(app: app);
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
