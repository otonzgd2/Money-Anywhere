import 'package:material_ui/material_ui.dart';

import 'common.dart';
import 'job_application.dart';
import 'plan_info.dart';
import 'route_screen.dart';
import 'thang_rot_theme.dart';

class PlanContactScreen extends StatefulWidget {
  const PlanContactScreen({
    super.key,
    required this.app,
    required this.info,
    required this.reload,
    this.sheet = false,
  });
  final AppState app;
  final PlanInfo info;
  final Future<PlanInfo> Function() reload;
  final bool sheet;

  @override
  State<PlanContactScreen> createState() => _PlanContactScreenState();
}

class _PlanContactScreenState extends State<PlanContactScreen> {
  late PlanInfo info = widget.info;
  bool busy = false;

  Future<void> _retry() async {
    setState(() => busy = true);
    final result = await widget.reload();
    if (mounted) {
      setState(() {
        info = result;
        busy = false;
      });
    }
  }

  void _open(Uri uri) => openExternal(
    context,
    widget.app,
    url: uri.toString(),
    title: info.title,
    askAfterReturn: false,
  );

  @override
  Widget build(BuildContext context) {
    final contacts = info.contacts.toList();
    final area = planArea(info);
    final status = planSourceMessage(info.state);
    final closes = planDate(info.closingTime);
    final guide = info.contactGuide;
    final moneyId = info.moneyId;
    return Scaffold(
      backgroundColor: widget.sheet ? Colors.white : pageBackground,
      appBar: AppBar(
        backgroundColor: widget.sheet ? Colors.white : pageBackground,
        title: const Text('ข้อมูลติดต่อ'),
        automaticallyImplyLeading: !widget.sheet,
        actions: [if (widget.sheet) const CloseButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PlanHeading(info: info, demo: widget.app.demo),
            if (status != null)
              PlanSection('สถานะรายการ', [
                Text(status),
                if (info.state == PlanSourceState.failed)
                  OutlinedButton(
                    onPressed: busy ? null : _retry,
                    child: Text(busy ? 'กำลังโหลด' : 'ลองใหม่'),
                  ),
              ]),
            PlanSection('ช่องทางติดต่อ', [
              if (info.closed)
                Text('ปิดรับรอบนี้แล้ว${closes == null ? '' : ' · $closes'}'),
              if (contacts.isEmpty)
                const Text('ยังไม่มีช่องทางติดต่อที่ตรวจสอบได้'),
              for (final contact in contacts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (contact.purposeLabel case final purpose?)
                          Text(purpose),
                        Semantics(
                          header: true,
                          child: Text(
                            contact.label,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (contact.instructions case final instructions?)
                          Text(instructions),
                        if (contact.hours case final hours?) Text(hours),
                        if (contact.checkedAt case final checked?)
                          Text('ตรวจล่าสุด $checked'),
                        if ((!info.mock || moneyId != null) &&
                            (!info.closed || !contact.takesApplications))
                          if (contact.destination case final destination?)
                            OutlinedButton.icon(
                              onPressed: () => _open(destination),
                              icon: const Icon(Icons.open_in_new),
                              label: Text(contact.action),
                            ),
                        if ((!info.mock || moneyId != null) &&
                            contact.source != null &&
                            contact.source != contact.destination)
                          TextButton(
                            onPressed: () => _open(contact.source!),
                            child: const Text('ดูข้อมูลอ้างอิง'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (guide != null)
                OutlinedButton.icon(
                  onPressed: () =>
                      _open(Uri.parse('${widget.app.api.baseUrl}$guide')),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('อ่านคู่มือติดต่อหน่วยงาน'),
                ),
              if (moneyId != null &&
                  !info.closed &&
                  info.state == PlanSourceState.available)
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RouteScreen(app: widget.app, moneyId: moneyId),
                    ),
                  ),
                  child: const Text('ดูวิธียื่นและติดตามผล'),
                ),
              if (widget.app.allowsDemo && info.sampleApplication)
                OutlinedButton.icon(
                  onPressed: () => _open(
                    Uri.parse(
                      jobApplicationDemoUrl(widget.app.api.baseUrl, info.title),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('ดูรายละเอียดงานตัวอย่าง'),
                ),
            ]),
            if (info.documents.isNotEmpty)
              PlanSection('เอกสารก่อนติดต่อ', [
                for (final document in info.documents) Text('• $document'),
              ]),
            if (area.isNotEmpty) PlanSection('พื้นที่ติดต่อ', area),
          ],
        ),
      ),
    );
  }
}
