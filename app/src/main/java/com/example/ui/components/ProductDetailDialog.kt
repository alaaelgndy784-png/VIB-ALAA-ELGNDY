package com.example.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.example.model.Product
import com.example.ui.theme.BlackBackground
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.SuccessGreen
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

@Composable
fun ProductDetailDialog(
  product: Product,
  cartQuantity: Int,
  isAdmin: Boolean = false,
  onDismiss: () -> Unit,
  onAddToCart: () -> Unit,
  onEditProduct: (Product) -> Unit = {},
  onDeleteProduct: (Product) -> Unit = {},
  modifier: Modifier = Modifier
) {
  Dialog(
    onDismissRequest = onDismiss,
    properties = DialogProperties(usePlatformDefaultWidth = false)
  ) {
    Surface(
      modifier = modifier
        .fillMaxWidth(0.92f)
        .clip(RoundedCornerShape(20.dp)),
      shape = RoundedCornerShape(20.dp),
      color = BlackBackground,
      border = BorderStroke(1.2.dp, GoldBorder)
    ) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .verticalScroll(rememberScrollState())
          .padding(20.dp)
      ) {
        // Top row with close
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          GoldBadge(text = product.category)

          IconButton(
            onClick = onDismiss,
            modifier = Modifier.testTag("close_detail_button")
          ) {
            Icon(
              imageVector = Icons.Default.Close,
              contentDescription = "إغلاق",
              tint = WhiteMuted
            )
          }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Large Image
        Box(
          modifier = Modifier
            .fillMaxWidth()
            .height(230.dp)
            .clip(RoundedCornerShape(14.dp))
        ) {
          ProductImageDisplay(
            product = product,
            modifier = Modifier.fillMaxWidth().height(230.dp)
          )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Title
        Text(
          text = product.name,
          color = WhitePrimary,
          fontSize = 18.sp,
          fontWeight = FontWeight.Bold,
          lineHeight = 24.sp
        )

        Spacer(modifier = Modifier.height(8.dp))

        // In stock indicator & Price
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          PriceDisplay(
            price = product.price,
            fontSize = 20,
            isLarge = true
          )

          Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
              imageVector = Icons.Default.CheckCircle,
              contentDescription = null,
              tint = SuccessGreen,
              modifier = Modifier.size(16.dp)
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
              text = "متوفر بالمخزن",
              color = SuccessGreen,
              fontSize = 12.sp,
              fontWeight = FontWeight.Medium
            )
          }
        }

        HorizontalDivider(
          color = GoldBorder,
          thickness = 0.8.dp,
          modifier = Modifier.padding(vertical = 14.dp)
        )

        // Description / Specifications
        Text(
          text = "الوصف والمواصفات:",
          color = GoldLight,
          fontSize = 14.sp,
          fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(6.dp))

        Text(
          text = product.description,
          color = WhitePrimary.copy(alpha = 0.9f),
          fontSize = 13.sp,
          lineHeight = 22.sp
        )

        Spacer(modifier = Modifier.height(20.dp))

        // Add to Cart Action
        Button(
          onClick = {
            onAddToCart()
            onDismiss()
          },
          modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .testTag("detail_add_cart_button"),
          shape = RoundedCornerShape(12.dp),
          colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
        ) {
          Icon(
            imageVector = Icons.Default.ShoppingCart,
            contentDescription = null,
            tint = Color.Black,
            modifier = Modifier.size(20.dp)
          )
          Spacer(modifier = Modifier.width(8.dp))
          Text(
            text = if (cartQuantity > 0) "إضافة قطعة أخرى للسلة ($cartQuantity بالسلة)" else "إضافة إلى سلة المشتريات",
            color = Color.Black,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold
          )
        }

        // Admin Only actions in detail dialog
        if (isAdmin) {
          Spacer(modifier = Modifier.height(14.dp))
          HorizontalDivider(color = GoldBorder, thickness = 0.8.dp)
          Spacer(modifier = Modifier.height(12.dp))

          Text(
            text = "تحكم الإدارة في هذا المنتج:",
            color = GoldLight,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold
          )

          Spacer(modifier = Modifier.height(8.dp))

          Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
          ) {
            Button(
              onClick = {
                onDismiss()
                onEditProduct(product)
              },
              modifier = Modifier.weight(1f).height(42.dp),
              shape = RoundedCornerShape(10.dp),
              colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
            ) {
              Icon(Icons.Default.Edit, contentDescription = null, tint = Color.Black, modifier = Modifier.size(16.dp))
              Spacer(modifier = Modifier.width(6.dp))
              Text("تعديل كامل", color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }

            OutlinedButton(
              onClick = {
                onDismiss()
                onDeleteProduct(product)
              },
              modifier = Modifier.weight(1f).height(42.dp),
              shape = RoundedCornerShape(10.dp),
              border = BorderStroke(1.dp, Color(0xFFE53935)),
              colors = ButtonDefaults.outlinedButtonColors(containerColor = Color(0xFFE53935).copy(alpha = 0.15f))
            ) {
              Icon(Icons.Default.Delete, contentDescription = null, tint = Color(0xFFE53935), modifier = Modifier.size(16.dp))
              Spacer(modifier = Modifier.width(6.dp))
              Text("حذف المنتج", color = Color(0xFFE53935), fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
          }
        }
      }
    }
  }
}
