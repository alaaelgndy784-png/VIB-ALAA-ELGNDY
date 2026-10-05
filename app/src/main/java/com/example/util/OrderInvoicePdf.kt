package com.example.util

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import androidx.core.content.ContextCompat
import com.example.R
import com.example.model.Order
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs

object OrderInvoicePdf {
  private const val GOLD = 0xFFD4AF37.toInt()
  private const val INK = 0xFF181818.toInt()
  private const val BOTTOM = 764f
  fun money(value: Double): String = String.format(Locale.US, "%,.2f", value)

  fun create(context: Context, order: Order): File {
    require(order.items.isNotEmpty()) { "السلة فارغة" }
    require(order.items.all { it.quantity > 0 && it.product.price.isFinite() && it.product.price >= 0 }) { "بيانات السلة غير صالحة" }
    val total = order.items.sumOf { it.subtotal }
    require(order.totalAmount.isFinite() && abs(total - order.totalAmount) < 0.01) { "إجمالي الطلب غير متطابق" }
    val directory = File(context.cacheDir, "order_invoices").apply { mkdirs() }
    val id = order.id.replace(Regex("[^A-Za-z0-9_-]"), "_").take(80)
    val output = File(directory, "VIB-order-$id.pdf")
    val document = PdfDocument()
    try {
      val writer = Writer(context, document, order)
      writer.newPage()
      writer.paragraph("العميل: ${order.customer.name}", bold = true)
      writer.paragraph("رقم الهاتف: ${order.customer.phone}")
      if (order.customer.address.isNotBlank()) writer.paragraph("العنوان: ${order.customer.address}")
      if (order.customer.notes.isNotBlank()) writer.paragraph("ملاحظات: ${order.customer.notes}")
      writer.y += 10
      writer.tableHeader()
      order.items.forEachIndexed { index, item -> writer.item(index + 1, item.product.name, money(item.product.price), item.quantity.toString(), money(item.subtotal)) }
      writer.totals(total, order.items.size, order.items.sumOf { it.quantity })
      writer.finishPage()
      output.outputStream().use { document.writeTo(it) }
    } finally { document.close() }
    return output
  }

  private class Writer(val context: Context, val document: PdfDocument, val order: Order) {
    private var page: PdfDocument.Page? = null
    private var number = 0
    var y = 0f
    private val canvas: Canvas get() = page!!.canvas
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val columns = listOf(24f to 95, 119f to 55, 174f to 85, 259f to 270, 529f to 42)
    private fun layout(text: String, width: Int, size: Float = 12f, bold: Boolean = false, color: Int = INK, center: Boolean = false, rtl: Boolean = true): StaticLayout {
      val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = size; this.color = color
        typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
      }
      return StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
        .setTextDirection(if (rtl) TextDirectionHeuristics.RTL else TextDirectionHeuristics.LTR)
        .setAlignment(if (center) Layout.Alignment.ALIGN_CENTER else Layout.Alignment.ALIGN_NORMAL)
        .setIncludePad(false).build()
    }
    private fun draw(value: StaticLayout, x: Float, top: Float) { canvas.save(); canvas.translate(x, top); value.draw(canvas); canvas.restore() }
    fun newPage(withTable: Boolean = false) {
      if (page != null) finishPage()
      number++
      page = document.startPage(PdfDocument.PageInfo.Builder(595, 842, number).create())
      canvas.drawColor(Color.WHITE)
      fill.color = INK
      canvas.drawRoundRect(24f, 24f, 571f, 128f, 12f, 12f, fill)
      draw(layout("VIB ALAA ELGNDY", 430, 16f, true, GOLD, rtl = false), 40f, 37f)
      draw(layout("فاتورة طلب بضاعة", 450, 22f, true, Color.WHITE, center = true), 24f, 66f)
      ContextCompat.getDrawable(context, R.drawable.vib_logo)?.let { logo -> logo.setBounds(507, 38, 558, 89); logo.draw(canvas) }
      draw(layout("رقم الطلب: ${order.id}", 265, 9f, color = Color.WHITE), 40f, 108f)
      val date = SimpleDateFormat("yyyy/MM/dd  HH:mm", Locale.US).format(Date(order.createdAt))
      draw(layout(date, 215, 10f, color = GOLD, rtl = false), 339f, 108f)
      y = 144f
      if (withTable) tableHeader()
    }
    fun finishPage() {
      if (page == null) return
      fill.color = GOLD; fill.strokeWidth = 1f
      canvas.drawLine(24f, 790f, 571f, 790f, fill)
      draw(layout("شكرًا لتعاملكم مع VIB للأدوات الصحية والسباكة", 450, 10f, center = true), 85f, 802f)
      draw(layout("صفحة $number", 60, 9f, center = true), 24f, 803f)
      document.finishPage(page!!); page = null
    }
    private fun fitPrefix(text: String, value: StaticLayout, available: Float): Int {
      var line = value.getLineForVertical(available.toInt().coerceAtLeast(1))
      while (line > 0 && value.getLineBottom(line) > available) line--
      return value.getLineEnd(line).coerceAtLeast(1).coerceAtMost(text.length)
    }
    fun paragraph(value: String, bold: Boolean = false) {
      var remaining = value
      while (remaining.isNotEmpty()) {
        if (BOTTOM - y < 28) newPage()
        val full = layout(remaining, 531, bold = bold)
        val end = if (full.height <= BOTTOM - y) remaining.length else fitPrefix(remaining, full, BOTTOM - y)
        val chunk = layout(remaining.substring(0, end), 531, bold = bold)
        draw(chunk, 32f, y); y += chunk.height + 7
        remaining = remaining.substring(end)
        if (remaining.isNotEmpty()) newPage()
      }
    }
    fun tableHeader() {
      if (y + 34 > BOTTOM) newPage()
      fill.color = GOLD; canvas.drawRect(24f, y, 571f, y + 30, fill)
      listOf("الإجمالي", "العدد", "السعر", "المنتج", "م").forEachIndexed { index, label ->
        val (x, width) = columns[index]
        draw(layout(label, width, 12f, true, center = true), x, y + 7)
      }
      y += 30
    }
    fun item(index: Int, name: String, price: String, quantity: String, subtotal: String) {
      var remaining = name.ifBlank { "منتج" }
      var first = true
      while (remaining.isNotEmpty()) {
        if (BOTTOM - y < 34) newPage(withTable = true)
        val full = layout(remaining, 254)
        val end = if (full.height + 12 <= BOTTOM - y) remaining.length else fitPrefix(remaining, full, BOTTOM - y - 12)
        val chunk = layout(remaining.substring(0, end), 254)
        val height = maxOf(34f, chunk.height + 12f)
        fill.color = if (index % 2 == 0) 0xFFF6F3EA.toInt() else Color.WHITE
        canvas.drawRect(24f, y, 571f, y + height, fill)
        fill.color = 0xFFDBCDA7.toInt(); fill.style = Paint.Style.STROKE; fill.strokeWidth = 0.6f
        columns.forEach { (x, width) -> canvas.drawRect(x, y, x + width, y + height, fill) }
        fill.style = Paint.Style.FILL
        draw(chunk, 267f, y + 6)
        val values = listOf(if (first) subtotal else "", if (first) quantity else "", if (first) price else "", "", if (first) index.toString() else "تابع")
        values.forEachIndexed { column, value ->
          if (column != 3 && value.isNotBlank()) {
            val (x, width) = columns[column]
            val text = layout(value, width - 6, 11f, center = true)
            draw(text, x + 3, y + (height - text.height) / 2)
          }
        }
        y += height; first = false; remaining = remaining.substring(end)
        if (remaining.isNotEmpty()) newPage(withTable = true)
      }
    }
    fun totals(total: Double, kinds: Int, quantity: Int) {
      if (y + 105 > BOTTOM) newPage()
      y += 16
      fill.color = INK; canvas.drawRoundRect(24f, y, 571f, y + 58, 8f, 8f, fill)
      draw(layout("الإجمالي: ${money(total)} ج.م", 515, 20f, true, GOLD, center = true), 40f, y + 14)
      y += 70
      draw(layout("عدد الأصناف: $kinds   |   إجمالي الكمية: $quantity", 547, 11f, center = true), 24f, y)
    }
  }
}
