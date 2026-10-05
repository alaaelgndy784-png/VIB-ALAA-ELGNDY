package com.example.util

import android.app.Application
import android.content.Intent
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.test.core.app.ApplicationProvider
import com.example.model.CartItem
import com.example.model.Customer
import com.example.model.Order
import com.example.model.Product
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class OrderInvoicePdfTest {
  private fun order(count: Int = 3): Order {
    val items = (1..count).map { index -> CartItem(Product(id = "p$index", name = if (index == 1) "شيك بلف سخان إيطالي من شركة الحياة" else "شطاف كروم مع الخرطوم والتوصيلات رقم $index", price = if (index == 1) 175.0 else 4.77), if (index == 1) 2 else 10) }
    return Order("ORD-20261005-DEMO", Customer(name = "محمد أحمد - معرض النور", phone = "01012345678", address = "مدينة نصر - القاهرة", notes = "التوصيل بعد الظهر"), items, items.sumOf { it.subtotal }, 1791216000000L)
  }
  @Test fun sampleInvoiceRendersAndMoneyKeepsFractions() {
    val context = ApplicationProvider.getApplicationContext<Application>()
    val pdf = OrderInvoicePdf.create(context, order())
    assertTrue(pdf.readBytes().take(5).toByteArray().toString(Charsets.US_ASCII).startsWith("%PDF"))
    assertEquals("4.77", OrderInvoicePdf.money(4.77))
    val destination = File("build/order-invoice-preview.pdf").apply { parentFile.mkdirs() }
    pdf.copyTo(destination, overwrite = true)
    ParcelFileDescriptor.open(pdf, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
      PdfRenderer(descriptor).use { renderer -> assertEquals(1, renderer.pageCount) }
    }
  }
  @Test fun longOrderPaginatesInsteadOfDroppingProducts() {
    val context = ApplicationProvider.getApplicationContext<Application>()
    val pdf = OrderInvoicePdf.create(context, order(80))
    pdf.copyTo(File("build/order-invoice-multipage.pdf").apply { parentFile.mkdirs() }, overwrite = true)
    ParcelFileDescriptor.open(pdf, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
      PdfRenderer(descriptor).use { renderer -> assertTrue(renderer.pageCount >= 4) }
    }
  }
  @Test fun whatsappSharesThePdfWithReadPermissionAndConfiguredRecipient() {
    val context = ApplicationProvider.getApplicationContext<Application>()
    val order = order()
    val pdf = OrderInvoicePdf.create(context, order)
    val intent = WhatsAppHelper.invoiceShareIntent(context, pdf, order, "01012345678", "com.whatsapp")
    assertEquals(Intent.ACTION_SEND, intent.action)
    assertEquals("application/pdf", intent.type)
    assertEquals("com.whatsapp", intent.`package`)
    assertEquals("201012345678@s.whatsapp.net", intent.getStringExtra("jid"))
    assertNotNull(intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM))
    assertTrue(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
    assertNotNull(intent.clipData)
  }
}
