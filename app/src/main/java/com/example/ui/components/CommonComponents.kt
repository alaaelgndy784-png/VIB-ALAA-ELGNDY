package com.example.ui.components

import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import coil.request.ImageRequest
import com.example.R
import com.example.model.Product
import com.example.model.getCategoryDefaultDrawable
import com.example.ui.theme.BlackSurfaceCard
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.WhitePrimary
import java.util.Locale

fun resolveSafeProductDrawable(context: Context, product: Product): Int {
  val resId = product.drawableRes
  if (resId != null && resId != 0) {
    try {
      val typeName = context.resources.getResourceTypeName(resId)
      if (typeName == "drawable" || typeName == "mipmap") {
        return resId
      }
    } catch (_: Throwable) {
      // Resource ID invalid or remapped
    }
  }
  return getCategoryDefaultDrawable(product.category)
}

@Composable
fun ProductImageDisplay(
  product: Product,
  modifier: Modifier = Modifier,
  contentScale: ContentScale = ContentScale.Crop
) {
  val context = LocalContext.current
  val safeDrawableRes = remember(product.drawableRes, product.category, context) {
    resolveSafeProductDrawable(context, product)
  }

  Box(
    modifier = modifier.background(BlackSurfaceCard),
    contentAlignment = Alignment.Center
  ) {
    if (!product.imageUrl.isNullOrBlank()) {
      SubcomposeAsyncImage(
        model = ImageRequest.Builder(context)
          .data(product.imageUrl)
          .crossfade(true)
          .build(),
        contentDescription = product.name,
        modifier = Modifier.fillMaxSize(),
        contentScale = contentScale,
        loading = {
          Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
              modifier = Modifier.size(24.dp),
              color = GoldPrimary,
              strokeWidth = 2.dp
            )
          }
        },
        error = {
          Image(
            painter = painterResource(id = safeDrawableRes),
            contentDescription = product.name,
            modifier = Modifier.fillMaxSize(),
            contentScale = contentScale
          )
        }
      )
    } else {
      Image(
        painter = painterResource(id = safeDrawableRes),
        contentDescription = product.name,
        modifier = Modifier.fillMaxSize(),
        contentScale = contentScale
      )
    }
  }
}

@Composable
fun PriceDisplay(
  price: Double,
  modifier: Modifier = Modifier,
  fontSize: Int = 16,
  isLarge: Boolean = false
) {
  val formatted = "%,.0f".format(Locale.US, price)
  Row(
    verticalAlignment = Alignment.CenterVertically,
    modifier = modifier
  ) {
    Text(
      text = formatted,
      color = GoldPrimary,
      fontWeight = FontWeight.Bold,
      fontSize = fontSize.sp,
      letterSpacing = 0.5.sp
    )
    Text(
      text = " ج.م",
      color = GoldLight,
      fontWeight = FontWeight.Medium,
      fontSize = if (isLarge) 13.sp else 11.sp,
      modifier = Modifier.padding(start = 2.dp)
    )
  }
}

@Composable
fun GoldBadge(
  text: String,
  modifier: Modifier = Modifier
) {
  Surface(
    modifier = modifier,
    shape = RoundedCornerShape(6.dp),
    color = GoldPrimary.copy(alpha = 0.15f),
    border = androidx.compose.foundation.BorderStroke(0.8.dp, GoldPrimary.copy(alpha = 0.4f))
  ) {
    Text(
      text = text,
      color = GoldLight,
      fontSize = 11.sp,
      fontWeight = FontWeight.Medium,
      modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
    )
  }
}

@Composable
fun CategoryFilterPill(
  title: String,
  isSelected: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier
) {
  val bgColor = if (isSelected) GoldPrimary else Color.Transparent
  val textColor = if (isSelected) Color.Black else WhitePrimary
  val borderColor = if (isSelected) GoldPrimary else GoldPrimary.copy(alpha = 0.35f)

  Box(
    modifier = modifier
      .clip(RoundedCornerShape(20.dp))
      .background(bgColor)
      .border(1.dp, borderColor, RoundedCornerShape(20.dp))
      .clickable(onClick = onClick)
      .padding(horizontal = 16.dp, vertical = 8.dp),
    contentAlignment = Alignment.Center
  ) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      if (isSelected) {
        Icon(
          imageVector = Icons.Default.Check,
          contentDescription = null,
          tint = Color.Black,
          modifier = Modifier.size(14.dp).padding(end = 4.dp)
        )
      }
      Text(
        text = title,
        color = textColor,
        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
        fontSize = 13.sp
      )
    }
  }
}
