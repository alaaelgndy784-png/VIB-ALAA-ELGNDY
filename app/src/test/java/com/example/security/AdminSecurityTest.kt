package com.example.security

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AdminSecurityTest {

  @Test
  fun testSha256Hashing_isNotPlaintext() {
    val rawPassword = "secretPassword123"
    val hash = AdminSecurityManager.hashPassword(rawPassword)
    assertNotEquals(rawPassword, hash)
    assertTrue(hash.length == 64) // SHA-256 produces 64 hex characters
  }

  @Test
  fun testDefaultAdminPins_verifySuccessfully() {
    val context = ApplicationProvider.getApplicationContext<Context>()
    assertTrue(AdminSecurityManager.verifyAdminPassword(context, "1234"))
    assertTrue(AdminSecurityManager.verifyAdminPassword(context, "2026"))
    assertTrue(AdminSecurityManager.verifyAdminPassword(context, "0000"))
    assertFalse(AdminSecurityManager.verifyAdminPassword(context, "wrong_pin_9999"))
  }

  @Test
  fun testCustomPassword_hashesAndVerifies() {
    val context = ApplicationProvider.getApplicationContext<Context>()
    val customPin = "8899"
    AdminSecurityManager.setCustomPassword(context, customPin)

    assertTrue(AdminSecurityManager.verifyAdminPassword(context, "8899"))
    assertFalse(AdminSecurityManager.verifyAdminPassword(context, "1111"))
  }
}
