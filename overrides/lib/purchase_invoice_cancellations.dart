part of 'main.dart';

// Deleting a posted purchase is an accounting cancellation, not a Firestore
// delete. The original document and its number are retained for the audit.
bool purchaseInvoiceCanBeCancelled(Map<String, dynamic> invoice) {
  if (invoice['status'] != 'completed') return false;
  final partialTotal = invoice['partialReturnTotal'];
  if (partialTotal is num && partialTotal > 0) return false;
  final partial = invoice['partialReturnQuantities'];
  return partial is! Map || partial.isEmpty;
}

Future<bool> confirmPurchaseInvoiceCancellation(
    BuildContext context, String invoiceId) async {
  try {
    final invoiceSnapshot = await db.collection('purchases').doc(invoiceId)
        .get(const GetOptions(source: Source.server));
    if (!invoiceSnapshot.exists || invoiceSnapshot.metadata.isFromCache ||
        invoiceSnapshot.metadata.hasPendingWrites) {
      throw StateError('لا يمكن تأكيد الفاتورة من السيرفر. وصّل الإنترنت وحاول تاني.');
    }
    final invoice = invoiceSnapshot.data();
    if (invoice == null || !visibleAfterReset(invoice) ||
        !invoiceAllowedForReturn(invoice) ||
        !purchaseInvoiceCanBeCancelled(invoice)) {
      throw StateError('الفاتورة قديمة أو ملغاة أو مرتجعة بالفعل، أو بها مرتجع جزئي. لا يمكن مسحها من هنا.');
    }

    final actor = FirebaseAuth.instance.currentUser?.uid;
    if (actor == null) throw StateError('سجّل الدخول بحساب المدير');
    final profile = await db.collection('users').doc(actor)
        .get(const GetOptions(source: Source.server));
    if (profile.metadata.isFromCache ||
        profile.data()?['active'] != true || profile.data()?['role'] != 'owner') {
      throw StateError('الإلغاء متاح للمدير فقط بعد تأكيد صلاحياته من السيرفر');
    }

    // Don't cancel a purchase after partial returns have been issued. This
    // preflight explains the error; the return transaction checks again.
    final returns = await db.collection('purchaseReturns')
        .where('sourceInvoiceId', isEqualTo: invoiceId)
        .get(const GetOptions(source: Source.server));
    if (returns.metadata.isFromCache ||
        returns.docs.any((row) => row.data()['returnType'] == 'partial')) {
      throw StateError('الفاتورة ليها مرتجع أصناف أو بيانات المرتجع غير مؤكدة؛ لا يمكن إلغاؤها بالكامل.');
    }

    final amounts = returnSettlement(invoice, sales: false);
    final partyId = '${invoice['supplierId'] ?? ''}'.trim();
    if (partyId.isEmpty) throw StateError('مورد الفاتورة غير مسجل؛ راجع حساب الفاتورة قبل الإلغاء.');
    if (!context.mounted) return false;
    final reason = TextEditingController();
    final yes = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('مسح فاتورة مشتريات معمولة بالخطأ'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('رقم الفاتورة: ${invoiceDisplayNumber('purchases',invoiceId,invoice)}'),
          Text('المورد: ${invoice['supplierName'] ?? ''}'),
          Text('إجمالي الفاتورة: ${invoice['total'] ?? 0} ج.م'),
          const SizedBox(height: 8),
          const Text('هيتم خصم كميات الفاتورة من المخزون الرئيسي، وتعديل رصيد المورد وعكس المدفوع المسجل في الصندوق.'),
          Text('خصم المديونية: ${amounts.debt.toStringAsFixed(2)} ج.م'),
          Text('استرداد للصندوق: ${amounts.cash.toStringAsFixed(2)} ج.م'),
          const Text('لو كميات الأصناف اتباعت أو اتصرفت، العملية هترفض بدل ما تعمل مخزون بالسالب.',
            style: TextStyle(color: Colors.orangeAccent)),
          const Text('سندات الصرف المستقلة للمورد هتفضل محفوظة؛ راجعها لو كانت مرتبطة بالفاتورة.',
            style: TextStyle(color: Colors.orangeAccent)),
          const Text('الفاتورة هتختفي من القائمة العادية، لكن رقمها وسجل الإلغاء هيفضلوا محفوظين للمراجعة.'),
          TextField(controller: reason, maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'سبب الإلغاء (إلزامي)',
              hintText: 'فاتورة مكررة بالخطأ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('تراجع')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (reason.text.trim().length < 5) {
                ScaffoldMessenger.of(dialog).showSnackBar(
                  const SnackBar(content: Text('اكتب سبب الإلغاء، 5 حروف على الأقل')));
                return;
              }
              Navigator.pop(dialog, true);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('تأكيد مسح الفاتورة'),
          ),
        ],
      ),
    ) ?? false;
    final cancellationReason = reason.text.trim();
    reason.dispose();
    if (!yes || !context.mounted) return false;
    await returnInvoice('purchases', invoiceId,
      expectedSignature: invoiceReturnSignature(invoice),
      cancellationReason: cancellationReason);
    if (context.mounted) {
      await showInvoiceSaveProblem(context,
        'تم إلغاء فاتورة المشتريات من القائمة العادية وعكس المخزون والحساب والصندوق مع الاحتفاظ بسجل الإلغاء.',
        title: 'تم إلغاء الفاتورة', button: 'تمام', success: true);
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      await showInvoiceSaveProblem(context,
        'لم تُلغَ الفاتورة ولم تُغيّر الحسابات: $error',
        title: 'تعذر إلغاء الفاتورة', button: 'رجوع');
    }
    return false;
  }
}
