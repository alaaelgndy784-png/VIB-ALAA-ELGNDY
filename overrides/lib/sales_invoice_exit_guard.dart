import 'package:flutter/material.dart';

/// Prevents the Android Back button/gesture from silently discarding a sale.
class SalesInvoiceExitGuard extends StatelessWidget {
  const SalesInvoiceExitGuard({
    super.key,
    required this.saving,
    required this.child,
  });

  final bool saving;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) requestSalesInvoiceExit(context, saving: saving);
        },
        child: child,
      );
}

/// Both the system Back gesture and the invoice's Cancel button call this.
Future<void> requestSalesInvoiceExit(
  BuildContext context, {
  required bool saving,
}) async {
  if (saving || !context.mounted) return;
  final leave = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تأكيد الخروج من فاتورة المبيعات'),
      content: const Text(
        'الفاتورة لم تُحفظ بعد. إذا خرجت الآن ستفقد البنود والبيانات التي أدخلتها. هل تريد الخروج بدون حفظ؟',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('استكمال الفاتورة'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('الخروج بدون حفظ'),
        ),
      ],
    ),
  );
  if (leave == true && context.mounted) Navigator.of(context).pop();
}
