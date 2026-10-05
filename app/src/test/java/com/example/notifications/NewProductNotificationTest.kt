package com.example.notifications

import org.junit.Assert.*
import org.junit.Test

class NewProductNotificationTest {
  @Test fun oldAndAlreadySeenProductsDoNotRing() {
    val announcement = NewProductAnnouncement("p", "منتج", 200)
    assertFalse(CatalogNotifications.shouldNotify(announcement, 300, 0))
    assertFalse(CatalogNotifications.shouldNotify(announcement, 100, 200))
    assertTrue(CatalogNotifications.shouldNotify(announcement, 100, 150))
  }
  @Test fun invalidAnnouncementsAreIgnored() {
    assertNull(NewProductAnnouncement.fromMap(emptyMap()))
    assertNull(NewProductAnnouncement.fromMap(mapOf("id" to "p", "name" to "منتج", "createdAt" to 0)))
    assertEquals("منتج", NewProductAnnouncement.fromMap(mapOf("id" to "p", "name" to "منتج", "createdAt" to 200))!!.name)
  }
}
