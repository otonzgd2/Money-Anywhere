import 'package:material_ui/material_ui.dart';

import 'common.dart';
import 'connected_accounts.dart';
import 'opportunity_assessment.dart';
import 'profile_screen.dart';

class ConnectedAccountRow extends StatelessWidget {
  const ConnectedAccountRow({
    super.key,
    required this.source,
    required this.account,
    required this.onRetry,
    this.availability,
    this.onConnect,
    this.onDisconnect,
  });

  final DemoSource source;
  final ConnectedAccount account;
  final Object? availability;
  final VoidCallback onRetry;
  final VoidCallback? onConnect, onDisconnect;

  String get _summary => switch (source) {
    DemoSource.thaid => 'ชื่อ อายุ และเขตตามทะเบียนบ้าน',
    DemoSource.thangRat => 'สถานะบัตรประจำตัวคนพิการ',
    DemoSource.socialSecurity => 'ประวัติส่งเงินสมทบ',
    DemoSource.dMyTax => 'ข้อมูลภาษีหัก ณ ที่จ่าย',
  };

  Widget _details() {
    final date = checkedDate(account.checkedAt);
    final detail = account.detail;
    final identity = account.identity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (account.mock)
            const Align(alignment: Alignment.centerLeft, child: DemoPill()),
          if (identity != null)
            ThaidIdentityFields(identity: identity)
          else if (detail != null && source == DemoSource.dMyTax) ...[
            // The existing API returns the amount and tax year in one value.
            if (detail.contains(' · ปีภาษี '))
              AccountDetailField('ปีภาษี', detail.split(' · ปีภาษี ').last),
            AccountDetailField(
              'ภาษีหัก ณ ที่จ่าย',
              detail.split(' · ปีภาษี ').first,
            ),
          ] else if (detail != null)
            AccountDetailField(_summary, detail),
          if (date != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('ตรวจล่าสุด $date'),
            ),
          if (onDisconnect case final disconnect?)
            OutlinedButton(
              onPressed: disconnect,
              child: const Text('ยกเลิกการเชื่อม ThaID'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = account.status;
    final connected = status == AccountStatus.connected;
    final label = switch (status) {
      AccountStatus.loading => 'กำลังตรวจสถานะ…',
      AccountStatus.disconnected => 'ยังไม่เชื่อม',
      AccountStatus.skipped => 'ยังไม่เชื่อม · ข้ามตอนเริ่มต้น',
      AccountStatus.failed => 'โหลดไม่ได้',
      AccountStatus.connected => 'เชื่อมแล้ว · $_summary',
    };
    final title = Text(
      source.label,
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        if (status == AccountStatus.disconnected)
          if (availability == 'approval_required')
            const Text('รอกรมการปกครองอนุมัติการเชื่อมต่อ')
          else if (availability == 'access_required')
            const Text('รอสิทธิ์เข้าถึงข้อมูลจากหน่วยงานเจ้าของบริการ'),
      ],
    );
    final logo = Image.asset(
      'assets/thang-rot/${source.image}',
      width: 34,
      height: 34,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.white,
      elevation: 0,
      shape: shape.copyWith(
        side: BorderSide(
          color: connected ? const Color(0xFFBBCFF2) : const Color(0xFFE6EBF2),
        ),
      ),
      child: connected
          ? ExpansionTile(
              shape: shape,
              collapsedShape: shape,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: logo,
              title: title,
              subtitle: subtitle,
              children: [_details()],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: logo,
                  title: title,
                  subtitle: subtitle,
                ),
                if (status == AccountStatus.failed || onConnect != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: status == AccountStatus.failed
                            ? onRetry
                            : onConnect,
                        child: Text(
                          status == AccountStatus.failed
                              ? 'ลองใหม่'
                              : 'เชื่อม ThaID',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
