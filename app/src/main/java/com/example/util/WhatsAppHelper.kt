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

  fun sendOrderViaWhatsApp(
    context: Context,
    order: Order,
    customer: Customer,
    targetWhatsAppNumber: String
  ) {
    try {
      val message = formatOrderMessage(order, customer)
      val encodedMessage = URLEncoder.encode(message, "UTF-8")

      // Clean phone number: remove +, spaces, dashes
      var cleanNumber = targetWhatsAppNumber.replace(Regex("[^0-9]"), "")
      if (cleanNumber.startsWith("0")) {
        // If Egyptian local number e.g. 010... -> add 20
        cleanNumber = "2$cleanNumber"
      } else if (!cleanNumber.startsWith("20") && cleanNumber.length == 10) {
        cleanNumber = "20$cleanNumber"
      }

      val uri = Uri.parse("https://api.whatsapp.com/send?phone=$cleanNumber&text=$encodedMessage")
      val intent = Intent(Intent.ACTION_VIEW, uri).apply {
        setPackage("com.whatsapp")
        flags = Intent.FLAG_ACTIVITY_NEW_TASK
      }

      try {
        context.startActivity(intent)
      } catch (_: Exception) {
        // WhatsApp standard not installed, try WhatsApp Business or generic view intent
        val fallbackIntent = Intent(Intent.ACTION_VIEW, uri).apply {
          flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(fallbackIntent)
      }
    } catch (e: Exception) {
      Toast.makeText(context, "تعذر فتح تطبيق واتساب: ${e.localizedMessage}", Toast.LENGTH_LONG).show()
    }
  }
}
