import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Direct SMS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SendSmsPage(),
    );
  }
}

class SendSmsPage extends StatefulWidget {
  const SendSmsPage({super.key});

  @override
  State<SendSmsPage> createState() => _SendSmsPageState();
}

class _SendSmsPageState extends State<SendSmsPage> {
  final Telephony _telephony = Telephony.instance;
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool _sending = false;

  @override
  void dispose() {
    _numberController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendSms() async {
    final number = _numberController.text.trim();
    final message = _messageController.text.trim();

    if (number.isEmpty || message.isEmpty) {
      _showSnack('Enter both a number and a message.');
      return;
    }

    setState(() => _sending = true);
    try {
      // 1. Ask for the SEND_SMS permission at runtime.
      final status = await Permission.sms.request();
      if (!status.isGranted) {
        _showSnack(
          status.isPermanentlyDenied
              ? 'SMS permission denied. Enable it in Settings.'
              : 'SMS permission is required to send.',
        );
        return;
      }

      // 2. Send directly through the default SMS SIM (set SIM 1 as default
      //    in Android > SIM manager > Messages). No compose screen opens.
      await _telephony.sendSms(to: number, message: message);

      _showSnack('SMS sent to $number on the default SIM.');
    } catch (e) {
      _showSnack('Failed to send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Direct SMS'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _numberController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Recipient number',
                hintText: 'e.g. 09xxxxxxxxx',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.message),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _sending ? null : _sendSms,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Sending…' : 'Send SMS directly'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Sends silently from your default SMS SIM. '
              'No messaging app, no extra confirmation.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
