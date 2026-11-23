'use strict';

function safeName(value, fallback) {
  const name = typeof value === 'string' ? value.trim() : '';
  return (name || fallback).slice(0, 100);
}

function visitNotification(visitId, visit) {
  if (!visit || visit.consented !== true) return null;
  if (typeof visit.employeeId !== 'string' || !visit.employeeId ||
      typeof visit.customerId !== 'string' || !visit.customerId) return null;
  const staff = safeName(visit.employeeName, 'موظف');
  const customer = safeName(visit.customerName, 'عميل');
  return {
    notification: {
      title: 'زيارة تاجر جديدة',
      body: staff + ' سجل زيارة عند ' + customer,
    },
    data: {
      type: 'employee_visit',
      visitId: String(visitId),
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'vib_manager_visit_push_v1',
        sound: 'default',
      },
    },
  };
}

module.exports = {visitNotification};
