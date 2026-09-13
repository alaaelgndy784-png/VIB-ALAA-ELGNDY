package com.example.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AdminPanelSettings
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
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
import com.example.ui.theme.BlackBackground
import com.example.ui.theme.BlackSurfaceElevated
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

@Composable
fun AdminModeBanner(
  onAddNewProduct: () -> Unit,
  onOpenAdminPanel: () -> Unit,
  onLogoutAdmin: () -> Unit,
  modifier: Modifier = Modifier
) {
  Surface(
    modifier = modifier
      .fillMaxWidth()
      .padding(horizontal = 16.dp, vertical = 6.dp)
      .clip(RoundedCornerShape(14.dp)),
    shape = RoundedCornerShape(14.dp),
    color = BlackSurfaceElevated,
    border = BorderStroke(1.2.dp, GoldPrimary)
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(14.dp)
    ) {
      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
      ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Box(
            modifier = Modifier
              .size(34.dp)
              .clip(CircleShape)
              .background(GoldPrimary.copy(alpha = 0.2f))
              .border(1.dp, GoldPrimary, CircleShape),
            contentAlignment = Alignment.Center
          ) {
            Icon(
              imageVector = Icons.Default.Security,
              contentDescription = null,
              tint = GoldPrimary,
              modifier = Modifier.size(20.dp)
            )
          }

          Spacer(modifier = Modifier.width(10.dp))

          Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
              Text(
                text = "وضع المدير مفعل",
                color = GoldPrimary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
              )
              Spacer(modifier = Modifier.width(6.dp))
              Surface(
                shape = RoundedCornerShape(4.dp),
                color = GoldPrimary
              ) {
                Text(
                  text = "ADMIN",
                  color = Color.Black,
                  fontSize = 9.sp,
                  fontWeight = FontWeight.ExtraBold,
                  modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp)
                )
              }
            }
            Text(
              text = "يمكنك تعديل أي منتج أو حذفه أو إضافة منتجات جديدة",
              color = WhiteMuted,
              fontSize = 11.sp
            )
          }
        }

        OutlinedButton(
          onClick = onLogoutAdmin,
          modifier = Modifier.testTag("exit_admin_button"),
          shape = RoundedCornerShape(8.dp),
          border = BorderStroke(0.8.dp, GoldBorder),
          colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.Transparent)
        ) {
          Icon(
            imageVector = Icons.Default.Logout,
            contentDescription = null,
            tint = WhiteMuted,
            modifier = Modifier.size(14.dp)
          )
          Spacer(modifier = Modifier.width(4.dp))
          Text("خروج", color = WhiteMuted, fontSize = 11.sp)
        }
      }

      Spacer(modifier = Modifier.height(10.dp))

      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
      ) {
        // Clear Add New Product Button
        Button(
          onClick = onAddNewProduct,
          modifier = Modifier
            .weight(1.3f)
            .height(40.dp)
            .testTag("admin_add_product_banner_button"),
          shape = RoundedCornerShape(10.dp),
          colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
        ) {
          Icon(
            imageVector = Icons.Default.Add,
            contentDescription = null,
            tint = Color.Black,
            modifier = Modifier.size(18.dp)
          )
          Spacer(modifier = Modifier.width(6.dp))
          Text(
            text = "إضافة منتج جديد",
            color = Color.Black,
            fontWeight = FontWeight.Bold,
            fontSize = 12.sp
          )
        }

        // Cloud Settings / Admin Panel Button
        OutlinedButton(
          onClick = onOpenAdminPanel,
          modifier = Modifier
            .weight(1f)
            .height(40.dp)
            .testTag("admin_panel_settings_button"),
          shape = RoundedCornerShape(10.dp),
          border = BorderStroke(1.dp, GoldBorder)
        ) {
          Icon(
            imageVector = Icons.Default.AdminPanelSettings,
            contentDescription = null,
            tint = GoldLight,
            modifier = Modifier.size(16.dp)
          )
          Spacer(modifier = Modifier.width(4.dp))
          Text(
            text = "لوحة التحكم",
            color = WhitePrimary,
            fontSize = 12.sp
          )
        }
      }
    }
  }
}
