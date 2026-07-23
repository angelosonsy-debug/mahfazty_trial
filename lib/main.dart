import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'parsers/notification_parser.dart';
import 'parsers/parsed_transaction.dart';
import 'parsers/sms_parser.dart';

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
      home: const FinancialInboxPage(),
    );
  }
}

enum EventSource { sms, notification }

/// حدث واحد موحّد - سواء جه من SMS (فودافون كاش/البنك الأهلي) أو من إشعار عام
class FinancialEvent {
  final EventSource source;
  final String rawSender; // رقم المرسل أو اسم الـ package
  final String rawTitle;
  final String rawBody;
  final DateTime time;

  // موجود بس لو المصدر SMS واتعرف عليه Template
  final ParsedTransaction? transaction;

  // موجود بس لو المصدر إشعار عام (النسخة القديمة)
  final NotificationParsedResult? notificationResult;

  FinancialEvent({
    required this.source,
    required this.rawSender,
    required this.rawTitle,
    required this.rawBody,
    required this.time,
    this.transaction,
    this.notificationResult,
  });

  bool get isFinancial {
    if (source == EventSource.sms) return transaction != null;
    return notificationResult?.isFinancial ?? false;
  }

  int get confidence {
    if (source == EventSource.sms) return transaction?.confidence ?? 0;
    return notificationResult?.confidence ?? 0;
  }
}

class FinancialInboxPage extends StatefulWidget {
  const FinancialInboxPage({super.key});

  @override
  State<FinancialInboxPage> createState() => _FinancialInboxPageState();
}

class _FinancialInboxPageState extends State<FinancialInboxPage>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _notificationsChannel =
      MethodChannel('mahfazty/notifications');
  static const MethodChannel _smsChannel = MethodChannel('mahfazty/sms');

  final List<FinancialEvent> _events = [];
  bool _notificationAccessGranted = false;
  bool _smsPermissionGranted = false;
  bool _financialOnly = true;

  @override
  void initState() {
    super.initState();
    _notificationsChannel.setMethodCallHandler(_handleNotification);
    _smsChannel.setMethodCallHandler(_handleSms);
    _checkPermissions();
  }

  Future<void> _handleNotification(MethodCall call) async {
    if (call.method != 'onNotification') return;
    final map = call.arguments as Map<dynamic, dynamic>;
    final title = map['title']?.toString() ?? '';
    final text = map['text']?.toString() ?? '';
    final result = NotificationParser.analyze(title, text);

    setState(() {
      _events.insert(
        0,
        FinancialEvent(
          source: EventSource.notification,
          rawSender: map['packageName']?.toString() ?? 'unknown',
          rawTitle: title,
          rawBody: text,
          time: DateTime.fromMillisecondsSinceEpoch(
            (map['time'] is int) ? map['time'] as int : DateTime.now().millisecondsSinceEpoch,
          ),
          notificationResult: result,
        ),
      );
    });
  }

  Future<void> _handleSms(MethodCall call) async {
    if (call.method != 'onSms') return;
    final map = call.arguments as Map<dynamic, dynamic>;
    final sender = map['sender']?.toString() ?? '';
    final body = map['body']?.toString() ?? '';
    final parsed = SmsParser.parse(sender, body);

    setState(() {
      _events.insert(
        0,
        FinancialEvent(
          source: EventSource.sms,
          rawSender: sender,
          rawTitle: parsed.transaction?.sourceLabel ?? sender,
          rawBody: parsed.normalizedBody,
          time: DateTime.fromMillisecondsSinceEpoch(
            (map['time'] is int) ? map['time'] as int : DateTime.now().millisecondsSinceEpoch,
          ),
          transaction: parsed.transaction,
        ),
      );
    });
  }

  Future<void> _checkPermissions() async {
    try {
      final granted =
          await _notificationsChannel.invokeMethod<bool>('isNotificationAccessGranted');
      setState(() => _notificationAccessGranted = granted ?? false);
    } on PlatformException {
      setState(() => _notificationAccessGranted = false);
    }
    try {
      final granted = await _smsChannel.invokeMethod<bool>('isSmsPermissionGranted');
      setState(() => _smsPermissionGranted = granted ?? false);
    } on PlatformException {
      setState(() => _smsPermissionGranted = false);
    }
  }

  Future<void> _openNotificationAccessSettings() async {
    try {
      await _notificationsChannel.invokeMethod('openNotificationAccessSettings');
    } on PlatformException {
      // ignore
    }
    Future.delayed(const Duration(seconds: 1), _checkPermissions);
  }

  Future<void> _requestSmsPermission() async {
    try {
      await _smsChannel.invokeMethod('requestSmsPermission');
    } on PlatformException {
      // ignore
    }
    Future.delayed(const Duration(seconds: 1), _checkPermissions);
  }

  List<FinancialEvent> get _visibleEvents =>
      _financialOnly ? _events.where((e) => e.isFinancial).toList() : _events;

  @override
  Widget build(BuildContext context) {
    final visible = _visibleEvents;
    return Scaffold(
      appBar: AppBar(
        title: const Text('صندوق الإشعارات المالية (تجريبي)'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'تحديث حالة الأذونات',
            onPressed: _checkPermissions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_notificationAccessGranted) _buildPermissionBanner(
            context,
            'محتاج نفعّل إذن Notification Access عشان نلقط أي إشعار (زي InstaPay مستقبلًا).',
            'فعّل الآن',
            _openNotificationAccessSettings,
          ),
          if (!_smsPermissionGranted) _buildPermissionBanner(
            context,
            'محتاج نفعّل إذن قراءة الرسائل عشان نلقط رسائل فودافون كاش والبنك الأهلي.',
            'اسمح الآن',
            _requestSmsPermission,
          ),
          _buildFilterBar(context),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'مفيش أحداث لسه.\nجرب تعمل عملية فودافون كاش حقيقية، أو تستنى تحويل على الكارت.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _EventCard(event: visible[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('عرض المالي فقط', style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Switch(
            value: _financialOnly,
            onChanged: (v) => setState(() => _financialOnly = v),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner(
    BuildContext context,
    String message,
    String actionLabel,
    VoidCallback onTap,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            const SizedBox(width: 8),
            FilledButton(onPressed: onTap, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final FinancialEvent event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    if (event.source == EventSource.sms) {
      return _buildSmsCard(context);
    }
    return _buildNotificationCard(context);
  }

  Widget _buildSmsCard(BuildContext context) {
    final tx = event.transaction;
    final Color color = tx == null
        ? Colors.grey
        : tx.confidence >= 99
            ? Colors.green
            : tx.confidence >= 85
                ? Colors.lightGreen
                : Colors.amber;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(Icons.account_balance_wallet, color: color),
        ),
        title: Text(tx?.sourceLabel ?? event.rawSender),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tx != null) ...[
              Text(tx.type.labelAr, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (tx.amount != null) Text('المبلغ: ${tx.amount!.toStringAsFixed(2)} جنيه'),
              if (tx.balance != null) Text('الرصيد بعد العملية: ${tx.balance!.toStringAsFixed(2)} جنيه'),
              if (tx.counterpartyName != null) Text('مع: ${tx.counterpartyName}'),
              if (tx.merchant != null) Text('عند: ${tx.merchant}'),
              if (tx.reference != null) Text('رقم العملية: ${tx.reference}'),
            ] else
              const Text('مرسل غير معروف - تم تجاهله'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tx?.confidenceLabelAr ?? '',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Text(
          DateFormat('HH:mm:ss').format(event.time),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _buildNotificationCard(BuildContext context) {
    final result = event.notificationResult;
    final Color color;
    final String badgeText;

    if (result != null && result.amount != null && result.confidence >= 90) {
      color = Colors.green;
      badgeText = '💰 ${result.amount!.toStringAsFixed(2)} جنيه';
    } else if (result != null && result.amount != null) {
      color = Colors.amber;
      badgeText = '💰 ${result.amount!.toStringAsFixed(2)} جنيه؟';
    } else if (result != null && result.isFinancial) {
      color = Colors.orange;
      badgeText = 'مالي محتمل - بدون مبلغ واضح';
    } else {
      color = Colors.grey;
      badgeText = 'غير مالي';
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(Icons.notifications, color: color),
        ),
        title: Text(event.rawTitle.isEmpty ? event.rawSender : event.rawTitle),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.rawBody),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badgeText,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Text(
          DateFormat('HH:mm:ss').format(event.time),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
