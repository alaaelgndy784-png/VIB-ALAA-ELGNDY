package com.example.model

import org.junit.Assert.*
import org.junit.Test

class ProductGalleryTest {
  @Test fun legacyCoverStillDisplays() {
    val product = Product.fromMap("old", mapOf("imageUrl" to "https://example.com/old.jpg"))
    assertEquals(listOf("https://example.com/old.jpg"), product.galleryImages())
  }
  @Test fun roundTripPreservesOrderWithoutDuplicatingCover() {
    val product = Product(id = "new", imageUrl = "https://example.com/cover.jpg", imageUrls = listOf("https://example.com/two.jpg", "https://example.com/three.jpg"))
    val map = product.toMap()
    assertEquals(product.galleryImages(), Product.fromMap("new", map).galleryImages())
    assertEquals(product.galleryImages().drop(1), map["imageUrls"])
  }
  @Test fun malformedAndDuplicateEntriesDoNotBreakGallery() {
    val product = Product.fromMap("old", mapOf("imageUrl" to " a ", "imageUrls" to listOf("a", "", 3, "b")))
    assertEquals(listOf("a", "b"), product.galleryImages())
  }
  @Test fun deletedCoverFallsBackToNextPhoto() {
    val product = Product(imageUrls = listOf("next"))
    assertEquals("next", product.toMap()["imageUrl"])
    assertEquals(emptyList<String>(), product.toMap()["imageUrls"])
  }
}
