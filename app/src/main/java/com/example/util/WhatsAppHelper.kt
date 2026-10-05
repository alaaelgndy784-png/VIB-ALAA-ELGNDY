package com.example.util

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import com.example.model.Customer
import com.example.model.Order
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object WhatsAppHelper {

  fun formatOrderMessage(order: Order, customer: Customer): String {
    val dateFormat = SimpleDateFormat("yyyy/MM/dd - hh:mm a", Locale.forLanguageTag("ar"))
    val currentDate = dateFormat.format(Date(order.createdAt))

    val sb = StringBuilder()
    sb.append("✨ *طلب جديد من تطبيق VIB ALAA ELGNDY* ✨\n")
    sb.append("للأدوات الصحية والسباكة الفاخرة\n")
    sb.append("━━━━━━━━━━━━━━━━━━━━\n")
    sb.append("👤 *بيانات العميل:*\n")
    sb.append("• الاسم: ${customer.name}\n")
    sb.append("• رقم الهاتف: ${customer.phone}\n")
    if (customer.address.isNotBlank()) {
      sb.append("• العنوان: ${customer.address}\n")
    }
    if (customer.notes.isNotBlank()) {
      sb.append("• ملاحظات: ${customer.notes}\n")
    }
    sb.append("━━━━━━━━━━━━━━━━━━━━\n")
    sb.append("🛒 *تفاصيل الأصناف المطلوبة:*\n")

    order.items.forEachIndexed { index, item ->
      val unitPriceStr = "%,.0f".format(Locale.US, item.product.price)
      val subtotalStr = "%,.0f".format(Locale.US, item.subtotal)
      sb.append("${index + 1}. *${item.product.name}*\n")
      sb.append("   القسم: ${item.product.category}\n")
      sb.append("   الكمية: ${item.quantity} × $unitPriceStr ج.م = *$subtotalStr ج.م*\n\n")
    }

    val totalStr = "%,.0f".format(Locale.US, order.totalAmount)
    sb.append("━━━━━━━━━━━━━━━━━━━━\n")
    sb.append("💰 *الإجمالي النهائي: $totalStr ج.م*\n")
    sb.append("📅 تاريخ الطلب: $currentDate\n")
    sb.append("━━━━━━━━━━━━━━━━━━━━\n")
    sb.append("شكراً لاختياركم VIB ALAA ELGNDY للأدوات الصحية 🌟")

    return sb.toString()
  }

  fun invoiceShareIntent(context: Context, pdf: java.io.File, order: Order, targetWhatsAppNumber: String, packageName: String): Intent {
    var number = targetWhatsAppNumber.replace(Regex("[^0-9]"), "")
    if (number.startsWith("0")) number = "2$number"
    else if (!number.startsWith("20") && number.length == 10) number = "20$number"
    require(number.length in 10..15) { "رقم واتساب VIB غير صحيح" }
    val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.updates", pdf)
    return Intent(Intent.ACTION_SEND).apply {
      type = "application/pdf"
      setPackage(packageName)
      putExtra(Intent.EXTRA_STREAM, uri)
      putExtra(Intent.EXTRA_TEXT, "فاتورة طلب ${order.id} - ${order.customer.name}")
      putExtra("jid", "$number@s.whatsapp.net")
      clipData = android.content.ClipData.newUri(context.contentResolver, "فاتورة طلب VIB", uri)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
  }

  fun sendInvoiceViaWhatsApp(context: Context, pdf: java.io.File, order: Order, targetWhatsAppNumber: String): Boolean {
    for (packageName in listOf("com.whatsapp", "com.whatsapp.w4b")) {
      try {
        context.startActivity(invoiceShareIntent(context, pdf, order, targetWhatsAppNumber, packageName))
        return true
      } catch (_: android.content.ActivityNotFoundException) { /* Try WhatsApp Business. */ }
    }
    Toast.makeText(context, "واتساب غير مثبت. ثبّته ثم أعد إرسال فاتورة الطلب.", Toast.LENGTH_LONG).show()
    return false
  }
}
