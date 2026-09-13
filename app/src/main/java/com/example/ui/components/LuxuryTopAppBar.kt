package com.example.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AdminPanelSettings
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.R
import com.example.model.Customer
import com.example.ui.theme.BlackBackground
import com.example.ui.theme.BlackSurfaceElevated
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

@Composable
fun LuxuryTopAppBar(
  cartCount: Int,
  currentCustomer: Customer?,
  isAdminLoggedIn: Boolean,
  onCartClick: () -> Unit,
  onProfileClick: () -> Unit,
  onAdminClick: () -> Unit,
  modifier: Modifier = Modifier
) {
  Surface(
    modifier = modifier
      .fillMaxWidth()
      .background(BlackBackground),
    color = BlackBackground,
    border = BorderStroke(0.dp, Color.Transparent)
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .statusBarsPadding()
        .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
      ) {
        // Logo and Brand Name
        Row(
          verticalAlignment = Alignment.CenterVertically,
          modifier = Modifier.weight(1f)
        ) {
          Image(
            painter = painterResource(id = R.drawable.vib_logo),
            contentDescription = "شعار VIB ALAA ELGNDY",
            modifier = Modifier
              .size(42.dp)
              .clip(CircleShape)
              .border(1.2.dp, GoldPrimary, CircleShape)
          )

          Spacer(modifier = Modifier.width(10.dp))

          Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
              Text(
                text = "VIB ALAA ELGNDY",
                color = GoldPrimary,
                fontWeight = FontWeight.ExtraBold,
                fontSize = 16.sp,
                letterSpacing = 0.5.sp
              )
              if (isAdminLoggedIn) {
                Spacer(modifier = Modifier.width(6.dp))
                Surface(
                  shape = RoundedCornerShape(4.dp),
                  color = GoldPrimary,
                  modifier = Modifier.padding(horizontal = 4.dp)
                ) {
                  Text(
                    text = "مدير",
                    color = Color.Black,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp)
                  )
                }
              }
            }
            Text(
              text = "للأدوات الصحية والسباكة الحديثة",
              color = WhiteMuted,
              fontSize = 11.sp,
              fontWeight = FontWeight.Normal
            )
          }
        }

        // Action Buttons: Admin, Profile/Login, Cart
        Row(
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
          // Admin Panel Button
          IconButton(
            onClick = onAdminClick,
            modifier = Modifier
              .size(38.dp)
              .clip(CircleShape)
              .background(if (isAdminLoggedIn) GoldPrimary.copy(alpha = 0.2f) else BlackSurfaceElevated)
              .border(0.8.dp, if (isAdminLoggedIn) GoldPrimary else GoldBorder, CircleShape)
              .testTag("admin_button")
          ) {
            Icon(
              imageVector = Icons.Default.AdminPanelSettings,
              contentDescription = "لوحة التحكم",
              tint = if (isAdminLoggedIn) GoldPrimary else WhitePrimary,
              modifier = Modifier.size(20.dp)
            )
          }

          // Customer Profile Button
          IconButton(
            onClick = onProfileClick,
            modifier = Modifier
              .size(38.dp)
              .clip(CircleShape)
              .background(BlackSurfaceElevated)
              .border(0.8.dp, GoldBorder, CircleShape)
              .testTag("profile_button")
          ) {
            Icon(
              imageVector = Icons.Default.Person,
              contentDescription = "الملف الشخصي",
              tint = if (currentCustomer != null) GoldLight else WhitePrimary,
              modifier = Modifier.size(20.dp)
            )
          }

          // Shopping Cart Button with Badge
          IconButton(
            onClick = onCartClick,
            modifier = Modifier
              .size(38.dp)
              .clip(CircleShape)
              .background(GoldPrimary)
              .testTag("cart_button")
          ) {
            BadgedBox(
              badge = {
                if (cartCount > 0) {
                  Badge(
                    containerColor = Color.Black,
                    contentColor = GoldPrimary
                  ) {
                    Text(
                      text = "$cartCount",
                      fontSize = 10.sp,
                      fontWeight = FontWeight.Bold
                    )
                  }
                }
              }
            ) {
              Icon(
                imageVector = Icons.Default.ShoppingCart,
                contentDescription = "سلة المشتريات",
                tint = Color.Black,
                modifier = Modifier.size(20.dp)
              )
            }
          }
        }
      }

      Spacer(modifier = Modifier.height(8.dp))

      // Subtle gold hairline divider
      Box(
        modifier = Modifier
          .fillMaxWidth()
          .height(0.8.dp)
          .background(GoldBorder)
      )
    }
  }
}
