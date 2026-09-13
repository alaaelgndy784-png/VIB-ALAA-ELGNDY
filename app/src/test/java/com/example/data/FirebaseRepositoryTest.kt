package com.example.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class FirebaseRepositoryTest {

  @Test
  fun testRepositoryInitialization_loadsDefaultCatalogImmediately() {
    val context = ApplicationProvider.getApplicationContext<Context>()
    val repository = FirebaseRepository(context)

    // Should immediately have catalog without blocking
    val products = repository.products.value
    assertNotNull(products)
    assertTrue("Products should be populated immediately from default catalog", products.isNotEmpty())
    assertFalse("Firebase should not be marked connected with invalid/missing config", repository.isFirebaseConnected.value)
  }

  @Test
  fun testSafeProductDrawableResolution_withInvalidResId_fallsBackWithoutCrash() {
    val context = ApplicationProvider.getApplicationContext<Context>()
    // 0x7f040002 was the crash ID (complex map / attr type)
    val invalidProduct = com.example.model.Product(
      id = "test_invalid",
      name = "Test",
      category = com.example.model.SanitaryCategory.FAUCETS,
      drawableRes = 0x7f040002
    )

    val resolvedRes = com.example.ui.components.resolveSafeProductDrawable(context, invalidProduct)
    // Must fall back to faucet drawable
    org.junit.Assert.assertEquals(com.example.R.drawable.faucet_gold, resolvedRes)
  }
}
