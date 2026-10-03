const crypto = require('node:crypto');
async function appendInvoice(db, FieldValue, ErrorType, uid, input) {
  const fail = (code, message) => { throw new ErrorType(code, message); };
  const id = x => typeof x === 'string' && x.length > 0 && x.length <= 128 && !x.includes('/');
  const cents = x => {
    if (typeof x !== 'number' || !Number.isFinite(x) || Math.abs(x) > 1e10) fail('invalid-argument', 'قيمة مالية غير صحيحة');
    return Math.round(x * 100);
  };
  if (!input || !['sales', 'purchases'].includes(input.type) || !id(input.invoiceId) ||
      !/^[A-Za-z0-9]{20}$/.test(input.requestId || '') ||
      !Number.isSafeInteger(input.revision) || input.revision < 0 ||
      !Array.isArray(input.items) || input.items.length < 1 || input.items.length > 50 ||
      cents(input.paid) < 0) fail('invalid-argument', 'راجع بيانات الإضافة');
  const seen = new Set();
  for (const item of input.items) {
    if (!id(item?.productId) || seen.has(item.productId) || !Number.isSafeInteger(item.quantity) ||
        item.quantity <= 0 || item.quantity > 1000000 || cents(item.unitPrice) < 0)
      fail('invalid-argument', 'راجع البنود والكميات');
    seen.add(item.productId);
  }
  const fingerprint = crypto.createHash('sha256').update(JSON.stringify(input)).digest('hex');
  const invoiceRef = db.collection(input.type).doc(input.invoiceId);
  const editRef = db.collection('invoiceEdits').doc(input.requestId);
  return db.runTransaction(async tx => {
    const profile = (await tx.get(db.collection('users').doc(uid))).data();
    if (!profile || profile.active !== true || profile.role !== 'owner')
      fail('permission-denied', 'تعديل الفاتورة متاح للمدير فقط');
    const invoiceSnap = await tx.get(invoiceRef), old = invoiceSnap.data();
    if (!old) fail('not-found', 'الفاتورة غير موجودة');
    if (profile.role === 'employee' && (input.type === 'sales' && old.branchId !== profile.branchId))
      fail('permission-denied', 'الفاتورة ليست في فرعك');
    const prior = (await tx.get(editRef)).data();
    if (prior) {
      if (prior.actorId !== uid || prior.fingerprint !== fingerprint) fail('already-exists', 'طلب التعديل محفوظ ببيانات أخرى');
      return {invoiceId: invoiceRef.id, revision: prior.revision};
    }
    if (input.type === 'sales' && old.onlinePaymentEver === true) fail('failed-precondition', 'الفاتورة لها سداد بالكارت؛ أنشئ فاتورة جديدة');
    if (old.status !== 'completed') fail('failed-precondition', 'لا يمكن إضافة بنود لفاتورة مرتجعة');
    if (typeof old.total !== 'number' || typeof old.paid !== 'number' || typeof old.due !== 'number' ||
        cents(old.total) - cents(old.paid) !== cents(old.due))
      fail('failed-precondition', 'هذه فاتورة قديمة تحتاج مراجعة أرصدتها قبل إضافة بنود');
    if ((old.revision ?? 0) !== input.revision) fail('aborted', 'الفاتورة اتعدلت؛ افتحها من جديد');
    const purchase = input.type === 'purchases';
    const stockBranch = purchase ? 'main' : (old.stockBranchId ?? old.branchId);
    if (!id(stockBranch)) fail('failed-precondition', 'المخزون المرتبط بالفاتورة غير صحيح');
    const products = [], stocks = [];
    for (const item of input.items) {
      products.push(await tx.get(db.collection('products').doc(item.productId)));
      stocks.push(await tx.get(db.collection('stock').doc(stockBranch + '_' + item.productId)));
    }
    const accountId = purchase ? old.supplierId : old.customerId;
    if (accountId && !id(accountId)) fail('failed-precondition', 'حساب الفاتورة غير صحيح');
    const accountRef = accountId ? db.collection(purchase ? 'suppliers' : 'customers').doc(accountId) : null;
    const account = accountRef ? (await tx.get(accountRef)).data() : null;
    const cashRef = db.collection('settings').doc('cash'), cash = (await tx.get(cashRef)).data();
    const items = Array.isArray(old.items) && old.items.length
      ? old.items.map(x => ({...x}))
      : [{productId: old.productId, productName: old.productName, quantity: old.quantity,
          [purchase ? 'unitCost' : 'unitPrice']: purchase ? old.unitCost : old.unitPrice, lineTotal: old.total}];
    let addedTotal = 0;
    const added = input.items.map((row, i) => {
      const product = products[i].data();
      if (!product || product.active !== true) fail('failed-precondition', 'الصنف غير متاح');
      const price = cents(row.unitPrice);
      if (!purchase && profile.role === 'employee' && price !== cents(product.price))
        fail('permission-denied', 'الموظف لا يغير سعر البيع');
      if (!purchase && product.purchasePrice != null && price < cents(product.purchasePrice))
        fail('permission-denied', 'سعر البيع أقل من التكلفة');
      const available = stocks[i].data()?.quantity ?? 0;
      if (!Number.isSafeInteger(available) || (!purchase && available < row.quantity))
        fail('failed-precondition', 'الكمية غير متاحة للصنف ' + product.name);
      addedTotal += price * row.quantity;
      const key = purchase ? 'unitCost' : 'unitPrice';
      const existing = items.find(x => x.productId === row.productId);
      if (existing && cents(existing[key]) !== price)
        fail('failed-precondition', 'الصنف موجود بسعر مختلف؛ يلزم مراجعة المدير');
      const addition = {productId: row.productId, productName: product.name, quantity: row.quantity,
        [key]: price / 100, lineTotal: price * row.quantity / 100,
        ...(!purchase && product.purchasePrice != null ? {purchasePriceAtSale: product.purchasePrice} : {})};
      if (existing) {
        if (!purchase && existing.purchasePriceAtSale != null && addition.purchasePriceAtSale != null) {
          existing.purchasePriceAtSale =
            (existing.purchasePriceAtSale * existing.quantity + addition.purchasePriceAtSale * row.quantity) /
            (existing.quantity + row.quantity);
        }
        existing.quantity += row.quantity;
        existing.lineTotal = cents(existing.lineTotal) / 100 + addition.lineTotal;
      } else items.push({...addition});
      return addition;
    });
    if (items.length > 50 || !Number.isSafeInteger(addedTotal) || addedTotal > 1e12)
      fail('invalid-argument', 'عدد البنود أو الإجمالي أكبر من المسموح');
    const payment = cents(input.paid);
    if (payment > addedTotal) fail('invalid-argument', 'المدفوع أكبر من قيمة البنود المضافة');
    const addedDue = addedTotal - payment;
    if ((purchase || addedDue > 0) && !account) fail('failed-precondition', 'الفاتورة غير مرتبطة بحساب نشط');
    if (account?.active === false) fail('failed-precondition', 'الحساب غير نشط');
    const now = FieldValue.serverTimestamp(), revision = input.revision + 1;
    for (const [i, item] of added.entries()) {
      const after = (stocks[i].data()?.quantity ?? 0) + (purchase ? item.quantity : -item.quantity);
      tx.set(stocks[i].ref, {branchId: stockBranch, productId: item.productId, quantity: after,
        ...(!purchase ? {lastSaleId: invoiceRef.id} : {})}, {merge: true});
      tx.set(db.collection('stockMovements').doc(input.requestId + '_item_' + i), {
        productId: item.productId, productName: item.productName, branchId: stockBranch,
        kind: purchase ? 'purchase' : 'sale', quantity: purchase ? item.quantity : -item.quantity,
        balanceAfter: after, referenceId: invoiceRef.id, editId: editRef.id, actorId: uid, createdAt: now,
      });
      if (purchase) tx.update(products[i].ref, {purchasePrice: item.unitCost, updatedAt: now});
    }
    if (addedDue > 0) {
      const before = cents(account.balance ?? 0);
      tx.update(accountRef, {balance: (before + addedDue) / 100, updatedAt: now});
      tx.set(db.collection('accountMovements').doc(input.requestId + '_account'), {
        accountType: purchase ? 'suppliers' : 'customers', accountId, accountName: account.name,
        kind: purchase ? 'purchase' : 'sale', amount: addedDue / 100, balanceBefore: before / 100,
        balanceAfter: (before + addedDue) / 100, referenceId: invoiceRef.id, editId: editRef.id, actorId: uid, createdAt: now,
      });
    }
    if (payment > 0) {
      const before = cents(cash?.balance ?? 0), delta = purchase ? -payment : payment;
      tx.set(cashRef, {balance: (before + delta) / 100, updatedAt: now}, {merge: true});
      tx.set(db.collection('accountMovements').doc(input.requestId + '_cash'), {
        accountType: 'cash', accountId: accountId ?? '', accountName: account?.name ?? '',
        kind: purchase ? 'purchase' : 'sale', amount: payment / 100, delta: delta / 100,
        balanceBefore: before / 100, balanceAfter: (before + delta) / 100,
        referenceId: invoiceRef.id, editId: editRef.id, actorId: uid, createdAt: now,
      });
    }
    const total = cents(old.total) + addedTotal, paid = cents(old.paid ?? 0) + payment;
    tx.update(invoiceRef, {items, itemCount: items.length, total: total / 100, paid: paid / 100,
      due: (total - paid) / 100, paymentStatus: total > paid ? 'credit' : 'cash',
      revision, updatedAt: now, lastEditedBy: uid,
      ...(!purchase ? {customerBalanceAfter: account ? (cents(account.balance ?? 0) + addedDue) / 100 : 0} : {}),
      ...(items.length === 1 ? {productId: items[0].productId, productName: items[0].productName,
        quantity: items[0].quantity, [purchase ? 'unitCost' : 'unitPrice']: items[0][purchase ? 'unitCost' : 'unitPrice']} : {})});
    tx.set(editRef, {invoiceId: invoiceRef.id, invoiceType: input.type, addedItems: added,
      totalAdded: addedTotal / 100, paidAdded: payment / 100, revision, fingerprint, actorId: uid, createdAt: now});
    return {invoiceId: invoiceRef.id, revision};
  });
}
module.exports = {appendInvoice};

