import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../services/sms_service.dart';
import '../viewmodels/send_sms_viewmodel.dart';

/// View for the send-SMS screen.
///
/// Pure UI: it builds the form, observes [SendSmsViewModel] via
/// [ListenableBuilder], and forwards the button tap. It owns the view-model's
/// lifecycle but contains no business logic of its own.
class SendSmsView extends StatefulWidget {
  const SendSmsView({super.key, required this.smsService});

  final SmsService smsService;

  @override
  State<SendSmsView> createState() => _SendSmsViewState();
}

class _SendSmsViewState extends State<SendSmsView> {
  late final SendSmsViewModel _viewModel = SendSmsViewModel(widget.smsService);

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _onSendPressed() async {
    FocusScope.of(context).unfocus();
    await _viewModel.sendSms();
    if (!mounted) return;
    final feedback = _viewModel.feedback;
    if (feedback != null) _showSnack(feedback);
  }

  void _showSnack(String message) {
    final lower = message.toLowerCase();
    final color = lower.startsWith('sms sent')
        ? Colors.green.shade700
        : lower.startsWith('enter')
        ? Colors.orange.shade800
        : Colors.red.shade700;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Send SMS'), centerTitle: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _InfoBanner(),
                      const SizedBox(height: 24),
                      const _FieldLabel('Recipient number'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _viewModel.numberController,
                        keyboardType: TextInputType.phone,
                        decoration: _fieldDecoration(
                          context,
                          hint: '09xxxxxxxxx',
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('Message'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _viewModel.messageController,
                        minLines: 4,
                        maxLines: 8,
                        decoration: _fieldDecoration(
                          context,
                          hint: 'Type your message…',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ListenableBuilder(
                          listenable: _viewModel.messageController,
                          builder: (context, _) {
                            final len = _viewModel.messageController.text.length;
                            final parts = len == 0
                                ? 0
                                : (len <= 160 ? 1 : (len / 153).ceil());
                            return Text(
                              '$len chars · $parts SMS',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) {
                  final sending = _viewModel.sending;
                  return FilledButton.icon(
                    onPressed: sending ? null : _onSendPressed,
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(CupertinoIcons.paperplane_fill),
                    label: Text(sending ? 'Sending…' : 'Send SMS'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context, {required String hint}) {
  final scheme = Theme.of(context).colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: scheme.primary, width: 2),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.paperplane_fill, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Sent silently from your default SIM — no messaging app, '
              'no extra tap.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
