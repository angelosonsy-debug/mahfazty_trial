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

/// -------------------------------------------------------------------------
/// Financial Parser (المرحلة الثانية من الـ Pipeline)
/// بيحول النص الخام للإشعار لـ: هل ده إشعار مالي؟ + كام المبلغ المحتمل؟
/// -------------------------------------------------------------------------

class FinancialParser {
  // كلمات بتدل إن الإشعار مالي حتى لو الرقم مش واضح أو مفيش رقم أصلًا
  static final List<String> _keywords = [
    'فودافون كاش', 'vodafone cash', 'انستاباي', 'instapay', 'فوري', 'fawry',
    'محفظة', 'رصيدك', 'رصيد', 'تحويل', 'حوالة', 'حولت', 'حولتلك',
    'دفعت', 'خصم', 'خصمية', 'ايداع', 'إيداع', 'سحب', 'استلمت',
    'wallet', 'transfer', 'payment', 'balance', 'orange cash',
    'etisalat cash', 'we pay', 'بنك', 'bank', 'فيزا', 'visa',
    'ماستركارد', 'mastercard', 'قسط', 'أقساط', 'فاتورة',
  ];

  // كلمات لو لقيناها نستبعد الإشعار حتى لو فيه رقم (شحن بطارية، تحديثات...)
  static final List<String> _excludeKeywords = [
    'الشحن', 'battery', 'شاحن', 'تحديث', 'update available',
    'تنزيل', 'downloading', 'تقويم', 'calendar',
  ];

  // بيحول الأرقام العربية/الهندية والفارسية لأرقام لاتينية عادية
  // عشان الـ Regex يقدر يمسكها (موبايلات كتير في مصر بتعرض الأرقام بالشكل ده)
  static String normalizeDigits(String input) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      final aIndex = arabicIndic.indexOf(char);
      if (aIndex != -1) {
        buffer.write(aIndex.toString());
        continue;
      }
      final eIndex = easternArabic.indexOf(char);
      if (eIndex != -1) {
        buffer.write(eIndex.toString());
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  // رقم (ممكن فيه فواصل آلاف ونقطة عشرية) وقبله أو بعده كلمة عملة
  static final RegExp _amountRegex = RegExp(
    r'(\d{1,3}(?:[,\.]\d{3})*(?:\.\d{1,2})?)\s*(?:جنيه|جنيها|ج\.م|egp|le)\b'
    r'|(?:egp|le)\s*(\d{1,3}(?:[,\.]\d{3})*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static ParsedResult analyze(String title, String text) {
    final rawCombined = '$title $text';
    final normalized = normalizeDigits(rawCombined).toLowerCase();

    final isExcluded = _excludeKeywords.any((k) => normalized.contains(k.toLowerCase()));
    if (isExcluded) {
      return const ParsedResult(isFinancial: false, amount: null, confidence: 0);
    }

    final match = _amountRegex.firstMatch(normalized);
    double? amount;
    if (match != null) {
      final raw = (match.group(1) ?? match.group(2))?.replaceAll(',', '');
      if (raw != null) amount = double.tryParse(raw);
    }

    final hasKeyword = _keywords.any((k) => normalized.contains(k.toLowerCase()));

    if (amount != null && hasKeyword) {
      return ParsedResult(isFinancial: true, amount: amount, confidence: 95);
    }
    if (amount != null) {
      // فيه مبلغ واضح بس من غير كلمة مالية معروفة - نعرضه بثقة متوسطة
      return ParsedResult(isFinancial: true, amount: amount, confidence: 60);
    }
    if (hasKeyword) {
      // كلمة مالية بس من غير مبلغ واضح (يبقى محتاج مراجعة يدوية)
      return const ParsedResult(isFinancial: true, amount: null, confidence: 40);
    }
    return const ParsedResult(isFinancial: false, amount: null, confidence: 0);
  }
}

class ParsedResult {
  final bool isFinancial;
  final double? amount;
  final int confidence; // 0-100

  const ParsedResult({
    required this.isFinancial,
    required this.amount,
    required this.confidence,
  });
}

/// -------------------------------------------------------------------------

class CapturedNotification {
  final String packageName;
  final String title;
  final String text;
  final DateTime time;
  final ParsedResult parsed;

  CapturedNotification({
    required this.packageName,
    required this.title,
    required this.text,
    required this.time,
    required this.parsed,
  });

  factory CapturedNotification.fromMap(Map<dynamic, dynamic> map) {
    final title = map['title']?.toString() ?? '';
    final text = map['text']?.toString() ?? '';
    return CapturedNotification(
      packageName: map['packageName']?.toString() ?? 'unknown',
      title: title,
      text: text,
      time: DateTime.fromMillisecondsSinceEpoch(
        (map['time'] is int) ? map['time'] as int : DateTime.now().millisecondsSinceEpoch,
      ),
      parsed: FinancialParser.analyze(title, text),
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
  bool _financialOnly = true;

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
    Future.delayed(const Duration(seconds: 1), _checkAccess);
  }

  List<CapturedNotification> get _visibleNotifications => _financialOnly
      ? _notifications.where((n) => n.parsed.isFinancial).toList()
      : _notifications;

  @override
  Widget build(BuildContext context) {
    final visible = _visibleNotifications;
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
          _buildFilterBar(context),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        !_accessGranted
                            ? 'محتاج تفعّل الإذن الأول من فوق عشان الإشعارات تبدأ تظهر هنا.'
                            : _financialOnly
                                ? 'مفيش إشعارات مالية لسه.\nجرب حوّل لنفسك على فودافون كاش أو انستاباي.'
                                : 'مفيش إشعارات لسه خالص.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _NotificationCard(n: visible[index]),
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
          Text(
            'عرض المالي فقط',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Spacer(),
          Switch(
            value: _financialOnly,
            onChanged: (v) => setState(() => _financialOnly = v),
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

class _NotificationCard extends StatelessWidget {
  final CapturedNotification n;
  const _NotificationCard({required this.n});

  @override
  Widget build(BuildContext context) {
    final parsed = n.parsed;
    final Color badgeColor;
    final String badgeText;

    if (parsed.amount != null && parsed.confidence >= 90) {
      badgeColor = Colors.green;
      badgeText = '💰 ${parsed.amount!.toStringAsFixed(2)} جنيه';
    } else if (parsed.amount != null) {
      badgeColor = Colors.amber;
      badgeText = '💰 ${parsed.amount!.toStringAsFixed(2)} جنيه؟';
    } else if (parsed.isFinancial) {
      badgeColor = Colors.orange;
      badgeText = 'مالي محتمل - بدون مبلغ واضح';
    } else {
      badgeColor = Colors.grey;
      badgeText = 'غير مالي';
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: badgeColor.withOpacity(0.2),
          child: Icon(Icons.notifications, color: badgeColor),
        ),
        title: Text(n.title.isEmpty ? n.packageName : n.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.text),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badgeText,
                style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Text(
          DateFormat('HH:mm:ss').format(n.time),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
