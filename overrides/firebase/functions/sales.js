const crypto = require('node:crypto');

// The transaction is shared with tests; the callable supplies the real Admin SDK.
async function saveStaffSale(db, FieldValue, ErrorType, uid, input) {
  const fail = (code, message) => { throw new ErrorType(code, message); };
  const id = (value) => typeof value === 'string' && value.length > 0 && value.length <= 128 && !value.includes('/');
  const money = (value) => {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1e10)
      fail('invalid-argument', 'قيمة مالية غير صحيحة');
    return Math.round(value * 100);
  };
  if (!input || !/^[A-Za-z0-9]{20}$/.test(input.requestId || '') ||
      typeof input.credit !== 'boolean' || typeof input.customerId !== 'string' ||
      (input.customerId !== '' && !id(input.customerId)) ||
      !Array.isArray(input.items) || input.items.length < 1 || input.items.length > 50)
    fail('invalid-argument', 'راجع بيانات الفاتورة');
  const seen = new Set();
  for (const item of input.items) {
    if (!item || !id(item.productId) || seen.has(item.productId) ||
        !Number.isSafeInteger(item.quantity) || item.quantity < 1 || item.quantity > 1000000)
      fail('invalid-argument', 'راجع الأصناف والكميات ولا تكرر الصنف');
    money(item.unitPrice);
    if (item.basePrice !== undefined) money(item.basePrice);
    const discount = item.discountPercent === undefined ? 0 : item.discountPercent;
    if (typeof discount !== 'number' || !Number.isFinite(discount) || discount < 0 || discount > 100)
      fail('invalid-argument', 'نسبة الخصم غير صحيحة');
    seen.add(item.productId);
  }
  const requestedPaid = money(input.paid);
  const fingerprint = crypto.createHash('sha256').update(JSON.stringify({
    customerId: input.customerId, credit: input.credit, paid: requestedPaid,
    items: input.items.map(x => [x.productId, x.quantity, money(x.unitPrice), money(x.basePrice ?? x.unitPrice), x.discountPercent ?? 0]),
  })).digest('hex');
  const saleRef = db.collection('sales').doc(input.requestId);
  return db.runTransaction(async (tx) => {
    const profileSnap = await tx.get(db.collection('users').doc(uid));
    const profile = profileSnap.data();
    if (!profile || profile.active !== true || profile.role !== 'employee' || !id(profile.branchId))
      fail('permission-denied', 'حساب الموظف غير مفعّل أو غير مربوط بفرع');
    const existing = await tx.get(saleRef);
    if (existing.exists) {
      const saved = existing.data();
      if (saved.employeeId !== uid || saved.requestFingerprint !== fingerprint)
        fail('already-exists', 'تم حفظ فاتورة بهذا الرقم؛ افتحها من المبيعات');
      return {saleId: saleRef.id, total: saved.total, paid: saved.paid, due: saved.due};
    }
    // Complete every read before scheduling writes, including all 50 possible items.
    const products = [], stocks = [];
    for (const item of input.items) {
      products.push(await tx.get(db.collection('products').doc(item.productId)));
      stocks.push(await tx.get(db.collection('stock').doc('main_' + item.productId)));
    }
    const customerRef = input.customerId ? db.collection('customers').doc(input.customerId) : null;
    const customerSnap = customerRef ? await tx.get(customerRef) : null;
    const cashRef = db.collection('settings').doc('cash');
    const cashSnap = await tx.get(cashRef);
    const customer = customerSnap?.data();
    if (customerRef && (!customer || customer.active === false))
      fail('failed-precondition', 'العميل غير موجود أو غير نشط');
    let totalCents = 0;
    const items = input.items.map((line, i) => {
      const product = products[i].data();
      if (!product || product.active !== true) fail('failed-precondition', 'الصنف غير متاح');
      const productPrice = money(product.price);
      const basePrice = money(line.basePrice ?? line.unitPrice);
      const price = money(line.unitPrice);
      const discount = line.discountPercent ?? 0;
      const discountedPrice = Math.round(basePrice * (100 - discount) / 100);
      if (profile.canEditSalePrice !== true && (basePrice !== productPrice || price !== discountedPrice))
        fail('permission-denied', 'تعديل سعر الصنف يحتاج صلاحية المدير');
      if (product.purchasePrice != null && price < money(product.purchasePrice))
        fail('permission-denied', 'البيع أقل من التكلفة يحتاج صلاحية المدير');
      const available = stocks[i].data()?.quantity ?? 0;
      if (!Number.isSafeInteger(available) || available < line.quantity)
        fail('failed-precondition', 'الكمية غير متاحة للصنف ' + product.name);
      totalCents += price * line.quantity;
      return {productId: line.productId, productName: product.name,
        quantity: line.quantity, unitPrice: price / 100, basePrice: basePrice / 100,
        discountPercent: discount, lineTotal: price * line.quantity / 100,
        purchasePriceAtSale: product.purchasePrice ?? 0};
    });
    if (!Number.isSafeInteger(totalCents) || totalCents > 1e12) fail('invalid-argument', 'إجمالي الفاتورة غير صحيح');
    const paidCents = input.credit ? requestedPaid : totalCents;
    if (paidCents > totalCents) fail('invalid-argument', 'المدفوع أكبر من الإجمالي');
    const dueCents = totalCents - paidCents;
    if (dueCents > 0 && !customer) fail('invalid-argument', 'اختر العميل للفاتورة الآجل');
    // Opening balances can be credits, so signed balances remain signed.
    const balance = (value) => {
      if (typeof value !== 'number' || !Number.isFinite(value) || Math.abs(value) > 1e12)
        fail('failed-precondition', 'رصيد الحساب غير صحيح');
      return Math.round(value * 100);
    };
    const beforeCustomer = customer ? balance(customer.balance ?? 0) : 0;
    const afterCustomer = beforeCustomer + dueCents;
    const beforeCash = balance(cashSnap.data()?.balance ?? 0);
    const now = FieldValue.serverTimestamp();
    for (const [i, item] of items.entries()) {
      const after = stocks[i].data().quantity - item.quantity;
      tx.set(stocks[i].ref, {branchId: 'main', productId: item.productId, quantity: after,
        lastSaleId: saleRef.id}, {merge: true});
      tx.set(db.collection('stockMovements').doc(saleRef.id + '_item_' + i), {
        productId: item.productId, productName: item.productName, branchId: 'main',
        employeeBranchId: profile.branchId, kind: 'sale', quantity: -item.quantity,
        balanceAfter: after, referenceId: saleRef.id, actorId: uid, createdAt: now,
      });
    }
    const customerName = customer?.name ?? '', customerPhone = customer?.phone ?? '';
    if (dueCents > 0) {
      tx.update(customerRef, {balance: afterCustomer / 100, updatedAt: now});
      tx.set(db.collection('accountMovements').doc(saleRef.id + '_customer'), {
        accountType: 'customers', accountId: input.customerId, accountName: customerName,
        kind: 'sale', amount: dueCents / 100, balanceBefore: beforeCustomer / 100,
        balanceAfter: afterCustomer / 100, referenceId: saleRef.id, actorId: uid, createdAt: now,
      });
    }
    if (paidCents > 0) {
      tx.set(cashRef, {balance: (beforeCash + paidCents) / 100, updatedAt: now}, {merge: true});
      tx.set(db.collection('accountMovements').doc(saleRef.id + '_cash'), {
        accountType: 'cash', accountId: input.customerId, accountName: customerName,
        kind: 'sale', amount: paidCents / 100, delta: paidCents / 100,
        balanceBefore: beforeCash / 100, balanceAfter: (beforeCash + paidCents) / 100,
        referenceId: saleRef.id, reason: 'تحصيل فاتورة مبيعات', actorId: uid, createdAt: now,
      });
    }
    const sale = {branchId: profile.branchId, stockBranchId: 'main', employeeId: uid,
      customerId: input.customerId, customerName, customerPhone,
      customerPreviousBalance: beforeCustomer / 100, customerBalanceAfter: afterCustomer / 100,
      items, itemCount: items.length, stockIndex: Object.fromEntries(items.map((item, i) => [item.productId, i])),
      cashBefore: beforeCash / 100, cashAfter: (beforeCash + paidCents) / 100,
      total: totalCents / 100, paid: paidCents / 100,
      due: dueCents / 100, paymentStatus: dueCents > 0 ? 'credit' : 'cash',
      status: 'completed', createdAt: now, requestFingerprint: fingerprint,
      ...(items.length === 1 ? {productId: items[0].productId, productName: items[0].productName,
        quantity: items[0].quantity, unitPrice: items[0].unitPrice} : {})};
    tx.set(saleRef, sale);
    return {saleId: saleRef.id, total: sale.total, paid: sale.paid, due: sale.due};
  });
}
module.exports = {saveStaffSale};
