const assert = require('node:assert/strict');
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
const FieldValue = {serverTimestamp: () => 'SERVER_TIME'};
function database() {
  let data = new Map([
    ['users/staff', {role: 'employee', active: true, branchId: 'staffBranch'}],
    ['products/a', {name: 'صنف أ', active: true, price: 10.1, purchasePrice: 7}],
    ['products/b', {name: 'صنف ب', active: true, price: 20, purchasePrice: 12}],
    ['stock/main_a', {branchId: 'main', productId: 'a', quantity: 10}],
    ['stock/main_b', {branchId: 'main', productId: 'b', quantity: 10}],
    ['customers/c', {name: 'عميل', phone: '010', balance: 100, active: true}],
    ['settings/cash', {balance: 50}],
  ]);
  const db = {
    collection(name) { return {doc(id) { return {path: name + '/' + id, id}; }}; },
    read(path) { return data.get(path); },
    put(path, value) { data.set(path, value); },
    size() { return data.size; },
    async runTransaction(callback) {
      const pending = [];
      const tx = {
        async get(ref) {
          assert.equal(pending.length, 0, 'All reads must precede all writes');
          return {ref, exists: data.has(ref.path), data: () => data.get(ref.path)};
        },
        set(ref, value, opts) { pending.push([ref, value, opts?.merge]); },
        update(ref, value) { assert.ok(data.has(ref.path)); pending.push([ref, value, true]); },
      };
      const result = await callback(tx);
      const next = new Map(data);
      for (const [ref, value, merge] of pending)
        next.set(ref.path, merge ? {...next.get(ref.path), ...value} : value);
      data = next;
      return result;
    },
  };
  return db;
}

module.exports = {database, HttpsError, FieldValue};
