package com.example

import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.runtime.*
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.example.model.Product
import com.example.ui.components.*
import com.example.ui.theme.MyApplicationTheme
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h800dp-mdpi", sdk = [36])
class ProductGalleryUiTest {
  @get:Rule val compose = createComposeRule()
  private val photos = listOf("android.resource://com.aistudio.sanitaryware.vibalaaelgndy/${R.drawable.faucet_gold}", "android.resource://com.aistudio.sanitaryware.vibalaaelgndy/${R.drawable.brass_fitting}")
  @Test fun swipeShowsNextPhotoAndCompactActionsWork() {
    var clicked = false
    val product = Product(id = "demo", name = "خلاط حوض • صور متعددة", price = 175.0, description = "صور المنتج من أكثر من زاوية", drawableRes = R.drawable.faucet_gold, imageUrl = photos[0], imageUrls = photos.drop(1))
    compose.setContent { MyApplicationTheme { CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
      Column(Modifier.width(360.dp).padding(12.dp)) {
        LuxuryTopAppBar(0, null, true, {}, {}, {})
        ProductCard(product, 0, true, {}, {}, {}, {}, onQuickImage = { clicked = true })
      }
    } } }
    compose.onNodeWithTag("gallery_count_demo").assertTextContains("1 / 2", substring = true)
    compose.onNodeWithTag("gallery_demo").performTouchInput { swipeRight() }
    compose.onNodeWithTag("gallery_count_demo").assertTextContains("2 / 2", substring = true)
    compose.onNodeWithTag("admin_image_prod_demo").performClick()
    assertEquals(true, clicked)
    compose.onRoot().captureRoboImage(filePath = "build/gallery-preview.png")
  }
  @Test fun removingAndChoosingCoverUpdatesDraft() {
    var selected = photos
    compose.setContent { MyApplicationTheme {
      var images by remember { mutableStateOf(photos) }
      ProductImagesEditor(images, { images = it; selected = it })
    } }
    compose.onNodeWithTag("cover_image_1").performClick()
    assertEquals(photos.reversed(), selected)
    compose.onNodeWithTag("remove_image_0").performClick()
    assertEquals(listOf(photos[0]), selected)
  }
  @Test fun customerCardHasNoAdminTools() {
    compose.setContent { MyApplicationTheme { ProductCard(Product(id = "customer"), 0, false, {}, {}, {}, {}) } }
    compose.onNodeWithTag("admin_image_prod_customer").assertDoesNotExist()
    compose.onNodeWithTag("add_to_cart_customer").assertExists()
  }
}
