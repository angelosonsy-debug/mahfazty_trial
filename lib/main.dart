import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MahfaztyTrialApp());
}

class MahfaztyTrialApp extends StatelessWidget {
  const MahfaztyTrialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mahfazty Trial',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF10B981),
        brightness: Brightness.dark,
      ),
      home: const NotificationInboxPage(),
    );
  }
}

class CapturedNotification {
  final String packageName;
  final String title;
  final String text;
  final DateTime time;

  CapturedNotification({
    required this.packageName,
    required this.title,
    required this.text,
    required this.time,
  });

  factory CapturedNotification.fromMap(Map<dynamic, dynamic> map) {
    return CapturedNotification(
      packageName: map['packageName']?.toString() ?? 'unknown',
      title: map['title']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      time: DateTime.fromMillisecondsSinceEpoch(
        (map['time'] is int) ? map['time'] as int : DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class NotificationInboxPage extends StatefulWidget {
  const NotificationInboxPage({super.key});

  @override
  State<NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<NotificationInboxPage> {
  static const MethodChannel _channel = MethodChannel('mahfazty/notifications');

  final List<CapturedNotification> _notifications = [];
  bool _accessGranted = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNative);
    _checkAccess();
  }

  Future<void> _handleNative(MethodCall call) async {
    if (call.method == 'onNotification') {
      final map = call.arguments as Map<dynamic, dynamic>;
      setState(() {
        _notifications.insert(0, CapturedNotification.fromMap(map));
      });
    }
  }

  Future<void> _checkAccess() async {
    try {
      final granted = await _channel.invokeMethod<bool>('isNotificationAccessGranted');
      setState(() => _accessGranted = granted ?? false);
    } on PlatformException {
      setState(() => _accessGranted = false);
    }
  }

  Future<void> _openAccessSettings() async {
    try {
      await _channel.invokeMethod('openNotificationAccessSettings');
    } on PlatformException {
      // ignore - user can open settings manually
    }
    // give the user time to toggle the setting, then re-check on return
    Future.delayed(const Duration(seconds: 1), _checkAccess);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('صندوق الإشعارات المالية (تجريبي)'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'تحديث حالة الإذن',
            onPressed: _checkAccess,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_accessGranted) _buildAccessBanner(context),
          Expanded(
            child: _notifications.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _accessGranted
                            ? 'مفيش إشعارات لسه.\nجرب تبعتلك رسالة واتساب أو تعمل أي إشعار على الموبايل.'
                            : 'محتاج تفعّل الإذن الأول من فوق عشان الإشعارات تبدأ تظهر هنا.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final n = _notifications[index];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.notifications)),
                          title: Text(n.title.isEmpty ? n.packageName : n.title),
                          subtitle: Text(n.text),
                          trailing: Text(
                            DateFormat('HH:mm:ss').format(n.time),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessBanner(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'لسه معملتش تفعيل لإذن Notification Access — من غيره التطبيق مش هيقدر يقرأ أي إشعار.',
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _openAccessSettings,
              child: const Text('فعّل الآن'),
            ),
          ],
        ),
      ),
    );
  }
}
