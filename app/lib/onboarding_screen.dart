import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'opportunity_assessment.dart';
import 'thang_rot_theme.dart';

enum ConnectionStage { idle, connecting, connected, failed }

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({
    super.key,
    required this.app,
    required this.index,
    required this.choices,
    required this.stage,
    required this.acknowledged,
    required this.onBack,
    required this.onConnect,
    required this.onSkip,
    required this.onSkipAll,
    required this.onAcknowledge,
    required this.onStart,
    this.error,
  });

  final AppState app;
  final int index;
  final String choices;
  final ConnectionStage stage;
  final bool acknowledged;
  final VoidCallback onBack, onConnect, onSkip, onSkipAll, onStart;
  final ValueChanged<bool> onAcknowledge;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final sources = DemoSource.values;
    final summary = index == sources.length;
    final source = summary ? null : sources[index];
    final locked =
        stage == ConnectionStage.connecting ||
        stage == ConnectionStage.connected;
    final titleStyle = Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w800);
    final count = choices.split('').where((answer) => answer == 'y').length;
    return PopScope(
      canPop: !locked && index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !locked && index > 0) onBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final gap = ((viewport.maxHeight - 570) / 3).clamp(4.0, 36.0);
                return SingleChildScrollView(
                  key: ValueKey(index),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (index > 0)
                            IconButton(
                              onPressed: locked ? null : onBack,
                              tooltip: 'ย้อนกลับ',
                              icon: const Icon(Icons.arrow_back),
                            )
                          else
                            const SizedBox(width: 48),
                          Expanded(
                            child: Semantics(
                              label: summary
                                  ? 'พร้อมเริ่มใช้งาน'
                                  : 'บริการที่ ${index + 1} จาก ${sources.length}',
                              child: Row(
                                children: [
                                  for (var n = 0; n < sources.length; n++)
                                    Expanded(
                                      child: Container(
                                        height: 4,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: n <= index
                                              ? brandBlue
                                              : cardBorder,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (!summary)
                            TextButton(
                              onPressed: locked ? null : onSkipAll,
                              child: const Text('ข้ามทั้งหมด'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (source != null) ...[
                        Text('เชื่อมต่อ ${source.label}', style: titleStyle),
                        const SizedBox(height: 8),
                        Text(
                          'ทางรอดจะใช้${source.description}เพื่อประเมินสิทธิ์และรายได้ของคุณ',
                        ),
                        SizedBox(height: gap),
                        Center(
                          child: _SourceLogo(source: source, stage: stage),
                        ),
                        SizedBox(height: gap),
                        _DemoPreviewCard(
                          key: ValueKey(source),
                          api: app.api,
                          source: source,
                        ),
                        if (error case final detail?)
                          Semantics(
                            liveRegion: true,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                detail,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: locked ? null : onConnect,
                          style: FilledButton.styleFrom(
                            backgroundColor: brandBlue,
                          ),
                          child: Text(
                            stage == ConnectionStage.failed
                                ? 'ลองเชื่อมใหม่'
                                : 'เชื่อมต่อข้อมูลจำลอง',
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: locked ? null : onSkip,
                          style: TextButton.styleFrom(
                            backgroundColor: blueTint,
                          ),
                          child: const Text('ไว้ภายหลัง'),
                        ),
                      ] else ...[
                        Text('พร้อมเริ่มใช้งาน', style: titleStyle),
                        const SizedBox(height: 8),
                        Text(
                          'เชื่อมแล้ว $count จาก ${sources.length} บริการ ทางรอดจะประเมินสิทธิ์และรายได้จากข้อมูลที่มี',
                        ),
                        SizedBox(height: gap),
                        const Center(
                          child: BrandLogo(size: 104, wordmark: true),
                        ),
                        SizedBox(height: gap),
                        Card(
                          child: Column(
                            children: [
                              for (final service in sources)
                                ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  leading: Image.asset(
                                    'assets/thang-rot/${service.image}',
                                    width: 34,
                                    height: 34,
                                  ),
                                  title: Text(service.label),
                                  trailing: Semantics(
                                    label: service.answer(choices) == 'y'
                                        ? 'เชื่อมข้อมูลจำลองแล้ว'
                                        : 'ไว้ภายหลัง',
                                    child: Icon(
                                      service.answer(choices) == 'y'
                                          ? Icons.check_circle_outline
                                          : Icons.horizontal_rule,
                                      size: 20,
                                      color: service.answer(choices) == 'y'
                                          ? const Color(0xFF13704D)
                                          : mutedInk,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: acknowledged,
                          onChanged: (value) => onAcknowledge(value == true),
                          title: const Text(
                            'ฉันรับทราบเงื่อนไขการใช้งานและประกาศความเป็นส่วนตัว',
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => showNotice(context, app),
                            child: const Text('อ่านเงื่อนไขการใช้งานและประกาศ'),
                          ),
                        ),
                        FilledButton(
                          onPressed: acknowledged ? onStart : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: brandBlue,
                          ),
                          child: const Text('เริ่มใช้งาน'),
                        ),
                        if (error case final detail?)
                          Text(
                            detail,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoPreviewCard extends StatefulWidget {
  const _DemoPreviewCard({super.key, required this.api, required this.source});

  final Api api;
  final DemoSource source;

  @override
  State<_DemoPreviewCard> createState() => _DemoPreviewCardState();
}

class _DemoPreviewCardState extends State<_DemoPreviewCard> {
  late Future<Map<String, String>> preview = widget.source.loadPreview(
    widget.api,
  );

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: FutureBuilder<Map<String, String>>(
        future: preview,
        builder: (context, snapshot) {
          final values = snapshot.data ?? const <String, String>{};
          final loading = snapshot.connectionState != ConnectionState.done;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DemoPill(),
              const SizedBox(height: 5),
              const Text(
                'ใช้ข้อมูลจำลองเพื่อประเมินสิทธิ์และรายได้',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (loading)
                const LinearProgressIndicator(
                  semanticsLabel: 'กำลังโหลดค่าตัวอย่าง',
                ),
              const Divider(),
              for (final field in widget.source.previewFields.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          field.value,
                          style: const TextStyle(color: mutedInk),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          values[field.key] ??
                              (loading ? '—' : 'ยังไม่มีข้อมูล'),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              if (values['summary'] case final summary?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(summary),
                ),
              if (snapshot.hasError)
                TextButton(
                  onPressed: () => setState(() {
                    preview = widget.source.loadPreview(widget.api);
                  }),
                  child: const Text('ลองโหลดค่าตัวอย่างอีกครั้ง'),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _SourceLogo extends StatelessWidget {
  const _SourceLogo({required this.source, required this.stage});
  final DemoSource source;
  final ConnectionStage stage;

  @override
  Widget build(BuildContext context) {
    final linked = stage == ConnectionStage.connected;
    final connecting = stage == ConnectionStage.connecting;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 124,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  padding: EdgeInsets.all(source == DemoSource.thaid ? 0 : 16),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/thang-rot/${source.image}',
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
                if (connecting || linked)
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: linked ? 1 : null,
                      strokeWidth: 4,
                    ),
                  ),
                if (linked)
                  const Positioned(
                    bottom: 1,
                    right: 1,
                    child: CircleAvatar(
                      radius: 15,
                      child: Icon(Icons.check, size: 19),
                    ),
                  ),
              ],
            ),
          ),
          if (connecting || linked)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  linked
                      ? 'เชื่อม ${source.label} แล้ว'
                      : 'กำลังเชื่อมต่อ ${source.label}…',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
