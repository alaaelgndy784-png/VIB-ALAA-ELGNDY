part of 'main.dart';

// A separate, owner-only registry is intentional: historic account movements
// are immutable under Firestore rules. This assigns stable numeric references
// without editing amounts, supplier balances, cashbox entries or original IDs.
const supplierPaymentLegacyRegistryId = 'supplierPaymentLegacyNumbers';

Map<String, int> readSupplierPaymentLegacyRegistry(Map<String, dynamic>? data) {
  final raw = data?['numbers'];
  if (raw is! Map) return <String, int>{};
  final numbers = <String, int>{};
  for (final entry in raw.entries) {
    final id = entry.key.toString();
    final value = entry.value;
    if (id.isNotEmpty && value is int && value > 0) numbers[id] = value;
  }
  return numbers;
}

Map<String, dynamic> supplierPaymentWithLegacySerial(
    String documentId, Map<String, dynamic> voucher,
    Map<String, int> legacyNumbers) {
  if (supplierPaymentVoucherDisplayNumber(voucher) != 'سابق بدون ترقيم') {
    return voucher;
  }
  final serial = legacyNumbers[documentId];
  if (serial == null || serial <= 0) return voucher;
  return <String, dynamic>{...voucher, 'paymentNumber': serial};
}

int supplierPaymentMaxSerial(
    Iterable<Map<String, dynamic>> payments,
    Map<String, int> oldNumbers,
    int storedLastNumber) {
  var maxSerial = storedLastNumber;
  for (final value in oldNumbers.values) {
    if (value > maxSerial) maxSerial = value;
  }
  for (final voucher in payments) {
    final raw = voucher['paymentNumber'];
    final value = raw is int ? raw : raw is String ? int.tryParse(raw) : null;
    if (value != null && value > maxSerial) maxSerial = value;
  }
  return maxSerial;
}

Future<int> assignOldSupplierPaymentSerials() async {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) throw StateError('سجل الدخول للمدير أولًا');
  final user = await db.collection('users').doc(userId)
      .get(const GetOptions(source: Source.server));
  if (user.data()?['role'] != 'owner' || user.data()?['active'] != true) {
    throw StateError('ترقيم السندات القديمة متاح للمدير الرئيسي فقط');
  }
  final movements = await db.collection('accountMovements')
      .where('accountType', isEqualTo: 'suppliers')
      .get(const GetOptions(source: Source.server));
  if (movements.metadata.isFromCache || movements.metadata.hasPendingWrites) {
    throw StateError('لازم اتصال بالخادم قبل ترقيم السندات القديمة');
  }
  final registryRef = db.collection('settings').doc(supplierPaymentLegacyRegistryId);
  final counterRef = db.collection('settings').doc('supplierPaymentVoucherCounter');
  final savedRegistry = await registryRef.get(const GetOptions(source: Source.server));
  if (savedRegistry.metadata.isFromCache || savedRegistry.metadata.hasPendingWrites) {
    throw StateError('تعذر التأكد من أرقام السندات السابقة');
  }
  final existingSerials = readSupplierPaymentLegacyRegistry(savedRegistry.data());
  final payments = movements.docs.where((doc) => doc.data()['kind'] == 'payment').toList()
    ..sort((a, b) {
      DateTime? dateOf(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
        final stamp = doc.data()['createdAt'];
        return stamp is Timestamp ? stamp.toDate() : stamp is DateTime ? stamp : null;
      }
      final left = dateOf(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = dateOf(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final compared = left.compareTo(right);
      return compared != 0 ? compared : a.id.compareTo(b.id);
    });
  final unnumbered = payments.where((doc) =>
    supplierPaymentVoucherDisplayNumber(doc.data()) == 'سابق بدون ترقيم' &&
    !existingSerials.containsKey(doc.id)).toList();
  if (unnumbered.isEmpty) return 0;
  // The registry stays below Firestore's per-document size limit; these
  // small batches also permit a safe retry if connectivity is interrupted.
  if (existingSerials.length + unnumbered.length > 12000) {
    throw StateError('عدد السندات كبير؛ يلزم نقل سجل الترقيم إلى أجزاء قبل التنفيذ');
  }
  final maxPrior = supplierPaymentMaxSerial(
    payments.map((doc) => doc.data()), existingSerials, 0);
  var created = 0;
  for (var offset = 0; offset < unnumbered.length; offset += 50) {
    final batch = unnumbered.skip(offset).take(50).toList();
    final newlyAssigned = await db.runTransaction<int>((transaction) async {
      // Firestore transactions require all reads before any writes.
      final counterSnapshot = await transaction.get(counterRef);
      final registrySnapshot = await transaction.get(registryRef);
      final originalRecords = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in batch) {
        originalRecords.add(await transaction.get(doc.reference));
      }
      final currentNumbers = readSupplierPaymentLegacyRegistry(registrySnapshot.data());
      final lastStored = counterSnapshot.data()?['lastNumber'];
      if (lastStored != null && (lastStored is! int || lastStored < 0)) {
        throw StateError('عداد سندات الصرف غير صالح؛ لا يمكن ترقيم القديمة');
      }
      var next = supplierPaymentMaxSerial(
        payments.map((doc) => doc.data()), currentNumbers,
        (lastStored as int?) ?? 0);
      if (maxPrior > next) next = maxPrior;
      var assigned = 0;
      for (var i = 0; i < batch.length; i++) {
        final original = originalRecords[i];
        if (!original.exists || original.data()?['kind'] != 'payment' ||
            original.data()?['accountType'] != 'suppliers' ||
            supplierPaymentVoucherDisplayNumber(original.data()!) != 'سابق بدون ترقيم' ||
            currentNumbers.containsKey(batch[i].id)) continue;
        next = nextSupplierPaymentVoucherNumber(next);
        currentNumbers[batch[i].id] = next;
        assigned++;
      }
      if (assigned > 0) {
        final now = FieldValue.serverTimestamp();
        transaction.set(registryRef, {
          'kind':'supplierPaymentLegacyNumbers',
          'numbers':currentNumbers,
          'updatedAt':now,
        },SetOptions(merge:true));
        transaction.set(counterRef, {
          'lastNumber':next,
          'updatedAt':now,
        },SetOptions(merge:true));
      }
      return assigned;
    }, maxAttempts: 5);
    created += newlyAssigned;
  }
  return created;
}

final supplierPaymentLegacyNumberingBusy = ValueNotifier<bool>(false);

Future<void> promptOldSupplierPaymentNumbering(BuildContext context, int count) async {
  if (supplierPaymentLegacyNumberingBusy.value) return;
  final agreed = await showDialog<bool>(context:context,builder:(dialog) => AlertDialog(
    title: const Text('ترقيم سندات الصرف القديمة'),
    content: Text('يوجد $count سند صرف قديم من غير رقم متسلسل. '
      'هيتحفظ رقم جديد لكل سند حسب تاريخ إنشائه، من غير تغيير أصل السند '
      'أو مبالغه أو رصيد المورد أو الصندوق. '
      'الأرقام الجديدة مش هتتكرر مع سندات الصرف الموجودة. '
      'يجب الاتصال بالإنترنت لإتمام العملية.'),
    actions: [
      TextButton(onPressed:()=>Navigator.pop(dialog,false),
        child:const Text('إلغاء')),
      FilledButton(onPressed:()=>Navigator.pop(dialog,true),
        child:const Text('تأكيد ترقيم السندات')),
    ],
  ));
  if (agreed != true || !context.mounted) return;
  supplierPaymentLegacyNumberingBusy.value = true;
  try {
    final changed = await assignOldSupplierPaymentSerials();
    if (context.mounted) await showInvoiceSaveProblem(context,
      changed == 0
        ? 'السندات القديمة مُرقّمة بالفعل.'
        : 'تم تخصيص أرقام متسلسلة لعدد $changed سند صرف قديم. '
          'أرصدة الموردين والصندوق ومبالغ السندات لم تتغير.',
      title:'ترقيم سندات الصرف',button:'تمام',success:true);
  } catch (error) {
    if (context.mounted) await showInvoiceSaveProblem(context,
      'تعذر استكمال ترقيم السندات القديمة: $error. '
      'يمكنك إعادة المحاولة؛ الأرقام المحفوظة لن تتكرر.',
      title:'تعذر الترقيم',button:'رجوع');
  } finally {
    supplierPaymentLegacyNumberingBusy.value = false;
  }
}
