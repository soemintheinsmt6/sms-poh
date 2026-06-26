import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../models/sms_request.dart';
import '../models/socket_status.dart';
import '../services/relay_service_controller.dart';
import '../services/sms_service.dart';
import '../viewmodels/start_viewmodel.dart';
import 'send_sms_view.dart';

/// Start screen: shows the background service's connection status and the
/// latest verification it received/sent, with manual start/stop controls.
class StartView extends StatefulWidget {
  const StartView({
    super.key,
    required this.service,
    required this.smsService,
    this.autoStart = true,
  });

  final RelayServiceController service;
  final SmsService smsService;

  /// Request permissions and start the service as soon as the screen mounts.
  /// Disabled in tests.
  final bool autoStart;

  @override
  State<StartView> createState() => _StartViewState();
}

class _StartViewState extends State<StartView> {
  late final StartViewModel _viewModel = StartViewModel(widget.service);
  StreamSubscription<String>? _smsResultSub;

  @override
  void initState() {
    super.initState();
    _smsResultSub = widget.service.smsResultStream.listen(_showSnack);
    if (widget.autoStart) _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _viewModel.ensurePermissions();
    await _viewModel.start();
  }

  @override
  void dispose() {
    _smsResultSub?.cancel();
    _viewModel.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted || message.isEmpty) return;
    final ok = message.toLowerCase().startsWith('sent');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
          content: Text(message),
        ),
      );
  }

  void _openSmsSender() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SendSmsView(smsService: widget.smsService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Listener'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusHero(status: _viewModel.status),
                  const SizedBox(height: 20),
                  _PrimaryAction(
                    status: _viewModel.status,
                    onStart: _viewModel.start,
                    onStop: _viewModel.stop,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Latest verification',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  _VerificationCard(
                    message: _viewModel.lastMessage,
                    receivedAt: _viewModel.lastReceivedAt,
                    sendOk: _viewModel.lastSendOk,
                    sentAt: _viewModel.lastResultAt,
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _openSmsSender,
                    icon: const Icon(CupertinoIcons.chat_bubble_text),
                    label: const Text('Open SMS sender'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

typedef _StatusVisual = ({
  Color color,
  String label,
  String description,
  IconData icon,
});

_StatusVisual _visualFor(SocketStatus status) {
  return switch (status) {
    SocketStatus.connected => (
      color: const Color(0xFF2E7D32),
      label: 'Connected',
      description: 'Listening for verification codes',
      icon: CupertinoIcons.check_mark_circled_solid,
    ),
    SocketStatus.connecting => (
      color: const Color(0xFFE9871A),
      label: 'Connecting…',
      description: 'Establishing connection',
      icon: CupertinoIcons.arrow_2_circlepath,
    ),
    SocketStatus.disconnected => (
      color: const Color(0xFF607D8B),
      label: 'Disconnected',
      description: 'Not listening — tap Start',
      icon: CupertinoIcons.wifi_slash,
    ),
    SocketStatus.error => (
      color: const Color(0xFFC62828),
      label: 'Connection error',
      description: 'Reconnecting automatically…',
      icon: CupertinoIcons.exclamationmark_circle_fill,
    ),
  };
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.status});

  final SocketStatus status;

  @override
  Widget build(BuildContext context) {
    final v = _visualFor(status);
    final connecting = status == SocketStatus.connecting;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: v.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: v.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: v.color, shape: BoxShape.circle),
            child: connecting
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Icon(v.icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.label,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: v.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  v.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.status,
    required this.onStart,
    required this.onStop,
  });

  final SocketStatus status;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(vertical: 16);
    switch (status) {
      case SocketStatus.connecting:
        return FilledButton.icon(
          onPressed: null,
          icon: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('Connecting…'),
          style: FilledButton.styleFrom(padding: padding),
        );
      case SocketStatus.connected:
        final scheme = Theme.of(context).colorScheme;
        return FilledButton.icon(
          onPressed: onStop,
          icon: const Icon(CupertinoIcons.stop_fill),
          label: const Text('Stop listening'),
          style: FilledButton.styleFrom(
            padding: padding,
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
          ),
        );
      case SocketStatus.disconnected:
      case SocketStatus.error:
        return FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(CupertinoIcons.play_arrow_solid),
          label: const Text('Start listening'),
          style: FilledButton.styleFrom(padding: padding),
        );
    }
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.message,
    required this.receivedAt,
    required this.sendOk,
    required this.sentAt,
  });

  final SmsRequest? message;
  final DateTime? receivedAt;
  final bool? sendOk;
  final DateTime? sentAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final color = scheme.surfaceContainerHighest.withValues(alpha: 0.4);
    final message = this.message;

    if (message == null) {
      return Card(
        elevation: 0,
        color: color,
        shape: shape,
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(CupertinoIcons.tray, color: Colors.grey),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No codes yet'),
                    SizedBox(height: 2),
                    Text(
                      'Incoming verification requests will appear here.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: color,
      shape: shape,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.number, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  message.code,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  CupertinoIcons.phone_fill,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  message.phoneNumber,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SendStatusChip(sendOk: sendOk, at: sentAt ?? receivedAt),
          ],
        ),
      ),
    );
  }
}

class _SendStatusChip extends StatelessWidget {
  const _SendStatusChip({required this.sendOk, required this.at});

  final bool? sendOk;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (sendOk) {
      true => (Colors.green.shade700, CupertinoIcons.check_mark_circled_solid, 'SMS sent'),
      false => (Colors.red.shade700, CupertinoIcons.exclamationmark_circle_fill, 'Send failed'),
      null => (Colors.orange.shade700, CupertinoIcons.hourglass, 'Sending…'),
    };
    final when = at;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            when == null ? label : '$label · ${_fmtTime(when)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
