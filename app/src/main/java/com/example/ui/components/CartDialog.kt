package com.example.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.example.model.CartItem
import com.example.ui.theme.BlackBackground
import com.example.ui.theme.BlackSurfaceCard
import com.example.ui.theme.BlackSurfaceElevated
import com.example.ui.theme.DangerRed
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.WhatsAppGreen
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

@Composable
fun CartDialog(
  cartItems: List<CartItem>,
  totalAmount: Double,
  onDismiss: () -> Unit,
  onUpdateQuantity: (String, Int) -> Unit,
  onRemoveItem: (String) -> Unit,
  onClearCart: () -> Unit,
  onProceedToCheckout: () -> Unit,
  modifier: Modifier = Modifier
) {
  Dialog(
    onDismissRequest = onDismiss,
    properties = DialogProperties(usePlatformDefaultWidth = false)
  ) {
    Surface(
      modifier = modifier
        .fillMaxWidth(0.95f)
        .fillMaxHeight(0.85f),
      shape = RoundedCornerShape(20.dp),
      color = BlackBackground,
      border = BorderStroke(1.2.dp, GoldBorder)
    ) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .padding(16.dp)
      ) {
        // Header
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
              imageVector = Icons.Default.ShoppingCart,
              contentDescription = null,
              tint = GoldPrimary,
              modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
              text = "سلة المشتريات",
              color = WhitePrimary,
              fontSize = 18.sp,
              fontWeight = FontWeight.Bold
            )
            if (cartItems.isNotEmpty()) {
              Spacer(modifier = Modifier.width(6.dp))
              Text(
                text = "(${cartItems.sumOf { it.quantity }} صنف)",
                color = GoldLight,
                fontSize = 13.sp
              )
            }
          }

          Row {
            if (cartItems.isNotEmpty()) {
              IconButton(
                onClick = onClearCart,
                modifier = Modifier.testTag("clear_cart_button")
              ) {
                Icon(
                  imageVector = Icons.Default.DeleteOutline,
                  contentDescription = "تفريغ السلة",
                  tint = DangerRed.copy(alpha = 0.8f)
                )
              }
            }
            IconButton(
              onClick = onDismiss,
              modifier = Modifier.testTag("close_cart_button")
            ) {
              Icon(
                imageVector = Icons.Default.Close,
                contentDescription = "إغلاق",
                tint = WhiteMuted
              )
            }
          }
        }

        HorizontalDivider(
          color = GoldBorder,
          thickness = 0.8.dp,
          modifier = Modifier.padding(vertical = 12.dp)
        )

        // Content
        if (cartItems.isEmpty()) {
          Column(
            modifier = Modifier
              .weight(1f)
              .fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
          ) {
            Icon(
              imageVector = Icons.Default.ShoppingCart,
              contentDescription = null,
              tint = GoldBorder,
              modifier = Modifier.size(72.dp)
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
              text = "سلة المشتريات فارغة",
              color = WhitePrimary,
              fontSize = 17.sp,
              fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
              text = "تصفح معروضات VIB الفاخرة وأضف مستلزمات السباكة والأدوات الصحية إلى سلتك",
              color = WhiteMuted,
              fontSize = 13.sp,
              textAlign = TextAlign.Center,
              modifier = Modifier.padding(horizontal = 24.dp)
            )
          }
        } else {
          LazyColumn(
            modifier = Modifier
              .weight(1f)
              .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp)
          ) {
            items(cartItems, key = { it.product.id }) { item ->
              CartItemRow(
                item = item,
                onIncrease = { onUpdateQuantity(item.product.id, 1) },
                onDecrease = { onUpdateQuantity(item.product.id, -1) },
                onRemove = { onRemoveItem(item.product.id) }
              )
            }
          }

          HorizontalDivider(
            color = GoldBorder,
            thickness = 0.8.dp,
            modifier = Modifier.padding(vertical = 12.dp)
          )

          // Invoice Summary
          Surface(
            color = BlackSurfaceElevated,
            shape = RoundedCornerShape(12.dp),
            border = BorderStroke(0.8.dp, GoldBorder),
            modifier = Modifier.fillMaxWidth()
          ) {
            Column(modifier = Modifier.padding(12.dp)) {
              Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
              ) {
                Text(
                  text = "المجموع الكلي للطلبية:",
                  color = WhitePrimary,
                  fontSize = 14.sp,
                  fontWeight = FontWeight.Bold
                )
                PriceDisplay(
                  price = totalAmount,
                  fontSize = 18,
                  isLarge = true
                )
              }
            }
          }

          Spacer(modifier = Modifier.height(14.dp))

          // WhatsApp Checkout Button
          Button(
            onClick = onProceedToCheckout,
            modifier = Modifier
              .fillMaxWidth()
              .height(50.dp)
              .testTag("checkout_whatsapp_button"),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(containerColor = WhatsAppGreen)
          ) {
            Icon(
              imageVector = Icons.AutoMirrored.Filled.Send,
              contentDescription = null,
              tint = Color.White,
              modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
              text = "إرسال الطلب عبر واتساب",
              color = Color.White,
              fontSize = 15.sp,
              fontWeight = FontWeight.Bold
            )
          }
        }
      }
    }
  }
}

@Composable
fun CartItemRow(
  item: CartItem,
  onIncrease: () -> Unit,
  onDecrease: () -> Unit,
  onRemove: () -> Unit,
  modifier: Modifier = Modifier
) {
  Card(
    modifier = modifier.fillMaxWidth(),
    shape = RoundedCornerShape(12.dp),
    colors = CardDefaults.cardColors(containerColor = BlackSurfaceCard),
    border = BorderStroke(0.6.dp, GoldBorder)
  ) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(10.dp),
      verticalAlignment = Alignment.CenterVertically
    ) {
      // Thumbnail
      Box(
        modifier = Modifier
          .size(60.dp)
          .clip(RoundedCornerShape(8.dp))
      ) {
        ProductImageDisplay(
          product = item.product,
          modifier = Modifier.fillMaxSize()
        )
      }

      Spacer(modifier = Modifier.width(10.dp))

      // Info
      Column(modifier = Modifier.weight(1f)) {
        Text(
          text = item.product.name,
          color = WhitePrimary,
          fontSize = 13.sp,
          fontWeight = FontWeight.Bold,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis
        )
        Text(
          text = item.product.category,
          color = GoldLight,
          fontSize = 11.sp
        )
        Spacer(modifier = Modifier.height(4.dp))
        PriceDisplay(
          price = item.product.price,
          fontSize = 13
        )
      }

      // Quantity controls
      Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
          .clip(RoundedCornerShape(20.dp))
          .background(Color.Black)
          .border(0.8.dp, GoldPrimary, RoundedCornerShape(20.dp))
          .padding(horizontal = 4.dp, vertical = 2.dp)
      ) {
        IconButton(
          onClick = onDecrease,
          modifier = Modifier.size(24.dp)
        ) {
          Icon(
            imageVector = Icons.Default.Remove,
            contentDescription = "تقليل",
            tint = GoldPrimary,
            modifier = Modifier.size(14.dp)
          )
        }

        Text(
          text = "${item.quantity}",
          color = WhitePrimary,
          fontWeight = FontWeight.Bold,
          fontSize = 13.sp,
          modifier = Modifier.padding(horizontal = 6.dp)
        )

        IconButton(
          onClick = onIncrease,
          modifier = Modifier.size(24.dp)
        ) {
          Icon(
            imageVector = Icons.Default.Add,
            contentDescription = "زيادة",
            tint = GoldPrimary,
            modifier = Modifier.size(14.dp)
          )
        }
      }

      Spacer(modifier = Modifier.width(6.dp))

      IconButton(
        onClick = onRemove,
        modifier = Modifier.size(30.dp)
      ) {
        Icon(
          imageVector = Icons.Default.DeleteOutline,
          contentDescription = "حذف الصنف",
          tint = DangerRed.copy(alpha = 0.8f),
          modifier = Modifier.size(18.dp)
        )
      }
    }
  }
}
