package com.example.data

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.util.Base64
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ProductGalleryStorageTest {
  @Test fun selectedPhotosBecomeSharedDataAndStayWithinDocumentBudget() = runBlocking {
    val context = ApplicationProvider.getApplicationContext<Context>()
    val repository = FirebaseRepository(context)
    val bitmap = Bitmap.createBitmap(1800, 1200, Bitmap.Config.ARGB_8888)
    bitmap.eraseColor(android.graphics.Color.BLUE)
    val image = File.createTempFile("gallery_test", ".png", context.cacheDir)
    try {
      image.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
      val result = repository.prepareProductGallery(listOf(Uri.fromFile(image).toString(), "https://example.com/second.jpg"))!!
      assertTrue(result[0].startsWith("data:image/jpeg;base64,"))
      assertEquals("https://example.com/second.jpg", result[1])
      val decoded = Base64.decode(result[0].substringAfter(','), Base64.DEFAULT)
      assertTrue(decoded.size <= 180_000)
      assertTrue(result.sumOf { it.toByteArray().size } < 850_000)
    } finally { image.delete(); bitmap.recycle() }
  }
  @Test fun invalidPhotoAndExcessCountRejectTheWholeDraft() = runBlocking {
    val repository = FirebaseRepository(ApplicationProvider.getApplicationContext<Context>())
    assertNull(repository.prepareProductGallery(listOf("https://example.com/ok.jpg", "invalid")))
    assertNull(repository.prepareProductGallery((1..9).map { "https://example.com/$it.jpg" }))
    assertEquals(emptyList<String>(), repository.prepareProductGallery(emptyList()))
  }
}
