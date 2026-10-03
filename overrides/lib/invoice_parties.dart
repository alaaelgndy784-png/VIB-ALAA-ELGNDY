part of 'main.dart';

String accountPhone(String value) => _ocrNumber(value.trim())
  .replaceAll(RegExp(r'[\s()\-]'), '');

class AccountEntryDialog extends StatefulWidget {
  final bool supplier, allowOpeningBalance;
  final Future<String> Function(Map<String, dynamic>) onSave;
  const AccountEntryDialog({super.key, required this.supplier,
    required this.onSave, this.allowOpeningBalance = false});
  @override State<AccountEntryDialog> createState() => _AccountEntryDialogState();
}

class _AccountEntryDialogState extends State<AccountEntryDialog> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), phone = TextEditingController();
  final address = TextEditingController(), note = TextEditingController();
  final opening = TextEditingController(text: '0');
  bool saving = false;
  String? error;
  @override void dispose() {
    for (final controller in [name, phone, address, note, opening]) { controller.dispose(); }
    super.dispose();
  }
  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final balance = widget.allowOpeningBalance
      ? double.parse(_ocrNumber(opening.text.trim().replaceAll(',', '.'))) : 0.0;
    final fields = <String, dynamic>{'name': name.text.trim(),
      'phone': accountPhone(phone.text), 'address': address.text.trim(),
      'note': note.text.trim(), 'openingBalance': balance, 'balance': balance, 'active': true};
    setState(() { saving = true; error = null; });
    try {
      final id = await widget.onSave(fields);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() {
        saving = false;
        error = e is FirebaseException
          ? 'تعذر تأكيد حفظ الحساب. راجع الاتصال وصلاحيات المدير ثم حاول من نفس الشاشة. (${e.code})'
          : 'تعذر حفظ الحساب: $e';
      });
    }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: !saving,
    child: AlertDialog(title: Text(widget.supplier ? 'إضافة مورد' : 'إضافة عميل'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Form(key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, enabled: !saving, maxLength: 100,
            decoration: const InputDecoration(labelText: 'الاسم *'),
            validator: (value) => (value ?? '').trim().isEmpty ? 'اكتب الاسم' : null),
          TextFormField(controller: phone, enabled: !saving, maxLength: 25,
            keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رقم الهاتف *'),
            validator: (value) => RegExp(r'^\+?[0-9]{6,15}$').hasMatch(accountPhone(value ?? ''))
              ? null : 'اكتب رقم هاتف صحيح'),
          TextFormField(controller: address, enabled: !saving, maxLength: 200, maxLines: 2,
            decoration: const InputDecoration(labelText: 'العنوان (اختياري)')),
          TextFormField(controller: note, enabled: !saving, maxLength: 500, maxLines: 2,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
          if (widget.allowOpeningBalance) TextFormField(controller: opening, enabled: !saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي'), validator: (value) {
              final amount = double.tryParse(_ocrNumber((value ?? '').trim().replaceAll(',', '.')));
              return amount != null && amount.isFinite ? null : 'اكتب رصيدًا صحيحًا';
            }),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
        ])))),
      actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: saving ? null : save,
          child: saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('حفظ الحساب'))],
    ));
}

// The document ID survives retries; an uncertain response cannot create a second account.
Future<({String id, Map<String, dynamic> data})?> createInvoiceParty(BuildContext context, String collection, bool supplier,
    {bool allowOpeningBalance = false}) async {
  if (collection != (supplier ? 'suppliers' : 'customers')) throw ArgumentError('نوع الحساب غير صحيح');
  final ref = db.collection(collection).doc();
  Map<String, dynamic>? savedFields;
  final id = await showDialog<String>(context: context, barrierDismissible: false,
    builder: (_) => Directionality(textDirection: TextDirection.rtl, child: AccountEntryDialog(
      supplier: supplier, allowOpeningBalance: allowOpeningBalance, onSave: (fields) async {
        await db.runTransaction((tx) async {
          final existing = (await tx.get(ref)).data();
          if (existing != null) {
            if (fields.entries.any((entry) => existing[entry.key] != entry.value)) {
              throw StateError('الحساب محفوظ بالفعل ببيانات مختلفة؛ أغلق الشاشة واختره من القائمة');
            }
            return;
          }
          tx.set(ref, {...fields, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
          final balance = fields['openingBalance'] as double;
          if (balance != 0) tx.set(db.collection('accountMovements').doc('${ref.id}_opening'), {
            'accountType': collection, 'accountId': ref.id, 'accountName': fields['name'],
            'kind': 'opening', 'amount': balance.abs(), 'balanceBefore': 0, 'balanceAfter': balance,
            'createdAt': FieldValue.serverTimestamp(), 'actorId': FirebaseAuth.instance.currentUser!.uid,
          });
        });
        savedFields = Map<String, dynamic>.from(fields);
        return ref.id;
      },
    )));
  return id == null ? null : (id: id, data: savedFields!);
}
