package com.example.update

import com.example.BuildConfig
import org.junit.Assert.*
import org.junit.Test

class CatalogUpdateTest {
  private fun valid() = mapOf<String, Any?>("versionCode" to 3, "versionName" to "1.2", "apkUrl" to "https://github.com/alaaelgndy784-png/VIB-ALAA-ELGNDY/releases/download/catalog-1.2-123/VIB-CUSTOMER.apk", "sha256" to "a".repeat(64), "packageName" to BuildConfig.APPLICATION_ID)
  @Test fun currentAndOlderVersionsDoNotPrompt() {
    val update = CatalogUpdate.fromMap(valid())!!
    assertTrue(update.isNewerThan(2)); assertFalse(update.isNewerThan(3)); assertFalse(update.isNewerThan(4))
  }
  @Test fun untrustedOrMutableDownloadsAndWrongPackageAreRejected() {
    for (url in listOf("http://github.com/VIB-CUSTOMER.apk", "https://evil.example/VIB-CUSTOMER.apk", "https://github.com/alaaelgndy784-png/VIB-ALAA-ELGNDY/releases/download/customer-latest/VIB-CUSTOMER.apk", "https://github.com/alaaelgndy784-png/VIB-ALAA-ELGNDY/releases/download/catalog-1/VIB-ADMIN.apk")) assertNull(CatalogUpdate.fromMap(valid() + ("apkUrl" to url)))
    assertNull(CatalogUpdate.fromMap(valid() + ("packageName" to "other.app")))
    assertNull(CatalogUpdate.fromMap(valid() + ("sha256" to "invalid")))
  }
  @Test fun publishedMetadataRoundTrips() {
    val update = CatalogUpdate.fromMap(valid())!!
    assertEquals(update, CatalogUpdate.fromMap(update.toMap()))
  }
}
