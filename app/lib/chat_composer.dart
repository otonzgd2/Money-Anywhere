import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'common.dart';
import 'thang_rot_theme.dart';

Future<bool> confirmChatConsent(BuildContext context, AppState app) async {
  if (!context.mounted) return false;
  FocusManager.instance.primaryFocus?.unfocus();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('ก่อนส่งข้อความถึง AI'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'เมื่อยอมรับ คุณยืนยันว่าอายุ 20 ปีขึ้นไปหรือผู้ปกครองยินยอม และให้ AI ใช้คำตอบของคุณช่วยวิเคราะห์ คุณถอนความยินยอมได้ในบัญชี',
          ),
          TextButton(
            onPressed: () => showNotice(context, app),
            child: const Text('อ่านประกาศความเป็นส่วนตัว'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () {
            if (ModalRoute.of(context)?.isCurrent == true) {
              Navigator.pop(context, true);
            }
          },
          child: const Text('ยอมรับและส่ง'),
        ),
      ],
    ),
  );
  return context.mounted && accepted == true;
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSend,
    this.busy = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSend;
  final bool busy;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  static const speech = MethodChannel('money_anywhere/speech');
  final focus = FocusNode();
  bool voiceFlow = false;
  bool listening = false;

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    if (voiceFlow || widget.busy) return;
    setState(() => voiceFlow = true);
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('พิมพ์ด้วยเสียง'),
          content: const Text(
            'บริการถอดเสียงของอุปกรณ์อาจประมวลผลเสียงผ่านอินเทอร์เน็ต คุณตรวจและแก้ข้อความได้ก่อนกดส่ง',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ใช้แป้นพิมพ์'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('เริ่มพูด'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (accepted != true) {
        focus.requestFocus();
        return;
      }
      focus.unfocus();
      setState(() => listening = true);
      final text = await speech.invokeMethod<String>('recognize');
      if (!mounted) return;
      if (text != null && text.trim().isNotEmpty) {
        widget.controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      focus.requestFocus();
    } on MissingPluginException {
      _speechUnavailable();
    } on PlatformException {
      _speechUnavailable();
    } finally {
      if (mounted) {
        setState(() {
          voiceFlow = false;
          listening = false;
        });
      }
    }
  }

  void _speechUnavailable() {
    if (!mounted) return;
    toast(context, 'ถอดเสียงบนอุปกรณ์นี้ไม่ได้ พิมพ์ข้อความต่อได้');
    focus.requestFocus();
  }

  void _send(String text) {
    if (widget.busy || voiceFlow || text.trim().isEmpty) return;
    focus.unfocus();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: widget.controller,
          focusNode: focus,
          readOnly: listening,
          textInputAction: TextInputAction.send,
          onSubmitted: _send,
          decoration: InputDecoration(
            hintText: listening ? 'กำลังฟัง…' : widget.hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
      ),
      const SizedBox(width: 6),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final typed = value.text.trim().isNotEmpty;
          return IconButton.filled(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            style: IconButton.styleFrom(backgroundColor: brandButton),
            tooltip: typed ? 'ส่งข้อความ' : 'พิมพ์ด้วยเสียง',
            onPressed: widget.busy || voiceFlow
                ? null
                : typed
                ? () => _send(value.text)
                : _listen,
            icon: Icon(
              typed
                  ? Icons.send
                  : listening
                  ? Icons.mic
                  : Icons.mic_none,
            ),
          );
        },
      ),
    ],
  );
}
