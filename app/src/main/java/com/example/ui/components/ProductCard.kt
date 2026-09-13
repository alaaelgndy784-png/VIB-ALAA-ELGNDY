package com.example.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.PriceChange
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.model.Product
import com.example.ui.theme.BlackSurfaceCard
import com.example.ui.theme.BlackSurfaceElevated
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

@Composable
fun ProductCard(
  product: Product,
  cartQuantity: Int,
  isAdmin: Boolean = false,
  onProductClick: () -> Unit,
  onAddToCart: () -> Unit,
  onIncreaseQuantity: () -> Unit,
  onDecreaseQuantity: () -> Unit,
  onEditProduct: (Product) -> Unit = {},
  onQuickPrice: (Product) -> Unit = {},
  onQuickImage: (Product) -> Unit = {},
  onQuickStock: (Product) -> Unit = {},
  onDeleteProduct: (Product) -> Unit = {},
  modifier: Modifier = Modifier
) {
  Card(
    modifier = modifier
      .fillMaxWidth()
      .testTag("product_card_${product.id}")
      .clickable(onClick = onProductClick),
    shape = RoundedCornerShape(14.dp),
    colors = CardDefaults.cardColors(containerColor = BlackSurfaceCard),
    border = BorderStroke(if (isAdmin) 1.2.dp else 0.8.dp, if (isAdmin) GoldPrimary else GoldBorder),
    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
  ) {
    Column {
      // Image container with category badge
      Box(
        modifier = Modifier
          .fillMaxWidth()
          .height(160.dp)
          .clip(RoundedCornerShape(topStart = 14.dp, topEnd = 14.dp))
      ) {
        ProductImageDisplay(
          product = product,
          modifier = Modifier.fillMaxSize()
        )

        // Category Tag at top-right
        GoldBadge(
          text = product.category,
          modifier = Modifier
            .align(Alignment.TopEnd)
            .padding(8.dp)
        )

        // Admin badge on top-left if Admin mode active
        if (isAdmin) {
          Surface(
            shape = RoundedCornerShape(6.dp),
            color = Color.Black.copy(alpha = 0.85f),
            border = BorderStroke(1.dp, GoldPrimary),
            modifier = Modifier
              .align(Alignment.TopStart)
              .padding(8.dp)
          ) {
            Row(
              verticalAlignment = Alignment.CenterVertically,
              modifier = Modifier.padding(horizontal = 6.dp, vertical = 3.dp)
            ) {
              Icon(
                imageVector = Icons.Default.Security,
                contentDescription = null,
                tint = GoldPrimary,
                modifier = Modifier.size(12.dp)
              )
              Spacer(modifier = Modifier.width(3.dp))
              Text(
                text = "تحكم المدير",
                color = GoldPrimary,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold
              )
            }
          }
        }
      }

      // Details
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .padding(12.dp)
      ) {
        Text(
          text = product.name,
          color = WhitePrimary,
          fontSize = 14.sp,
          fontWeight = FontWeight.Bold,
          maxLines = 2,
          overflow = TextOverflow.Ellipsis,
          lineHeight = 20.sp
        )

        Spacer(modifier = Modifier.height(4.dp))

        Text(
          text = product.description,
          color = WhiteMuted,
          fontSize = 12.sp,
          maxLines = 2,
          overflow = TextOverflow.Ellipsis,
          lineHeight = 16.sp
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Price and Cart Action
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          PriceDisplay(
            price = product.price,
            fontSize = 16,
            isLarge = true
          )

          if (cartQuantity > 0) {
            // Already in cart - show plus minus counter
            Surface(
              shape = RoundedCornerShape(20.dp),
              color = Color.Black,
              border = BorderStroke(1.dp, GoldPrimary),
              modifier = Modifier.height(36.dp)
            ) {
              Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(horizontal = 4.dp)
              ) {
                IconButton(
                  onClick = onDecreaseQuantity,
                  modifier = Modifier.size(28.dp).testTag("cart_minus_${product.id}")
                ) {
                  Icon(
                    imageVector = Icons.Default.Remove,
                    contentDescription = "تقليل الكمية",
                    tint = GoldPrimary,
                    modifier = Modifier.size(16.dp)
                  )
                }

                Text(
                  text = "$cartQuantity",
                  color = WhitePrimary,
                  fontWeight = FontWeight.Bold,
                  fontSize = 13.sp,
                  modifier = Modifier.padding(horizontal = 6.dp)
                )

                IconButton(
                  onClick = onIncreaseQuantity,
                  modifier = Modifier.size(28.dp).testTag("cart_plus_${product.id}")
                ) {
                  Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = "زيادة الكمية",
                    tint = GoldPrimary,
                    modifier = Modifier.size(16.dp)
                  )
                }
              }
            }
          } else {
            // Not in cart - Add to cart button
            Surface(
              shape = RoundedCornerShape(20.dp),
              color = GoldPrimary,
              modifier = Modifier
                .height(36.dp)
                .clickable(onClick = onAddToCart)
                .testTag("add_to_cart_${product.id}")
            ) {
              Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(horizontal = 12.dp)
              ) {
                Icon(
                  imageVector = Icons.Default.ShoppingCart,
                  contentDescription = "إضافة للسلة",
                  tint = Color.Black,
                  modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.size(4.dp))
                Text(
                  text = "أضف للسلة",
                  color = Color.Black,
                  fontSize = 12.sp,
                  fontWeight = FontWeight.Bold
                )
              }
            }
          }
        }

        // Dedicated Admin Actions Panel when in Admin Mode
        if (isAdmin) {
          Spacer(modifier = Modifier.height(10.dp))
          HorizontalDivider(color = GoldBorder.copy(alpha = 0.6f), thickness = 0.8.dp)
          Spacer(modifier = Modifier.height(8.dp))

          Text(
            text = "أدوات تحكم المدير:",
            color = GoldLight,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold
          )

          Spacer(modifier = Modifier.height(6.dp))

          // Row 1: Full Edit + Delete
          Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
          ) {
            // Full Edit Button
            Surface(
              shape = RoundedCornerShape(8.dp),
              color = GoldPrimary,
              modifier = Modifier
                .weight(1f)
                .height(32.dp)
                .clickable { onEditProduct(product) }
                .testTag("admin_edit_prod_${product.id}")
            ) {
              Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxSize()
              ) {
                Icon(Icons.Default.Edit, contentDescription = null, tint = Color.Black, modifier = Modifier.size(13.dp))
                Spacer(modifier = Modifier.width(4.dp))
                Text("تعديل شامل", color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Bold)
              }
            }

            // Delete Button (with confirmation)
            Surface(
              shape = RoundedCornerShape(8.dp),
              color = Color(0xFFE53935).copy(alpha = 0.15f),
              border = BorderStroke(1.dp, Color(0xFFE53935)),
              modifier = Modifier
                .weight(0.9f)
                .height(32.dp)
                .clickable { onDeleteProduct(product) }
                .testTag("admin_delete_prod_${product.id}")
            ) {
              Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxSize()
              ) {
                Icon(Icons.Default.Delete, contentDescription = null, tint = Color(0xFFE53935), modifier = Modifier.size(13.dp))
                Spacer(modifier = Modifier.width(3.dp))
                Text("حذف", color = Color(0xFFE53935), fontSize = 11.sp, fontWeight = FontWeight.Bold)
              }
            }
          }

          Spacer(modifier = Modifier.height(6.dp))

          // Row 2: Quick price, Quick image, Quick stock
          Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
          ) {
            // Quick Price
            Surface(
              shape = RoundedCornerShape(6.dp),
              color = BlackSurfaceElevated,
              border = BorderStroke(0.8.dp, GoldBorder),
              modifier = Modifier
                .weight(1f)
                .height(28.dp)
                .clickable { onQuickPrice(product) }
                .testTag("admin_price_prod_${product.id}")
            ) {
              Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxSize()
              ) {
                Icon(Icons.Default.PriceChange, contentDescription = null, tint = GoldLight, modifier = Modifier.size(12.dp))
                Spacer(modifier = Modifier.width(2.dp))
                Text("السعر", color = WhitePrimary, fontSize = 10.sp)
              }
            }

            // Quick Image
            Surface(
              shape = RoundedCornerShape(6.dp),
              color = BlackSurfaceElevated,
              border = BorderStroke(0.8.dp, GoldBorder),
              modifier = Modifier
                .weight(1f)
                .height(28.dp)
                .clickable { onQuickImage(product) }
                .testTag("admin_image_prod_${product.id}")
            ) {
              Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxSize()
              ) {
                Icon(Icons.Default.AddPhotoAlternate, contentDescription = null, tint = GoldLight, modifier = Modifier.size(12.dp))
                Spacer(modifier = Modifier.width(2.dp))
                Text("الصورة", color = WhitePrimary, fontSize = 10.sp)
              }
            }

            // Quick Stock
            Surface(
              shape = RoundedCornerShape(6.dp),
              color = BlackSurfaceElevated,
              border = BorderStroke(0.8.dp, GoldBorder),
              modifier = Modifier
                .weight(1f)
                .height(28.dp)
                .clickable { onQuickStock(product) }
                .testTag("admin_stock_prod_${product.id}")
            ) {
              Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxSize()
              ) {
                Icon(Icons.Default.Inventory2, contentDescription = null, tint = if (product.inStock) GoldLight else Color.Red, modifier = Modifier.size(12.dp))
                Spacer(modifier = Modifier.width(2.dp))
                Text(if (product.inStock) "المخزون" else "نفذ", color = if (product.inStock) WhitePrimary else Color.Red, fontSize = 10.sp)
              }
            }
          }
        }
      }
    }
  }
}
