import 'package:flutter/material.dart';

/// Blocks the phone Back button/gesture from discarding an unsaved purchase.
class PurchaseInvoiceExitGuard extends StatelessWidget {
  const PurchaseInvoiceExitGuard({
    super.key,
    required this.saving,
    required this.child,
    this.onDiscard,
  });

  final bool saving;
  final Widget child;
  final Future<void> Function()? onDiscard;

  @override
  Widget build(BuildContext context) => PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) requestPurchaseInvoiceExit(context, saving: saving, onDiscard: onDiscard);
        },
        child: child,
      );
}

/// Called by both Android Back and the purchase invoice Cancel button.
Future<void> requestPurchaseInvoiceExit(
  BuildContext context, {
  required bool saving,
  Future<void> Function()? onDiscard,
}) async {
  if (saving || !context.mounted) return;
  final leave = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تأكيد الخروج من فاتورة المشتريات'),
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
  if (leave == true && context.mounted) {
    if (onDiscard != null) await onDiscard();
    if (context.mounted) Navigator.of(context).pop();
  }
}
