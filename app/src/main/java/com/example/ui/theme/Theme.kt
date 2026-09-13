package com.example.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LuxuryGoldDarkColorScheme =
  darkColorScheme(
    primary = GoldPrimary,
    onPrimary = Color.Black,
    primaryContainer = GoldContainer,
    onPrimaryContainer = OnGoldContainer,
    secondary = GoldLight,
    onSecondary = Color.Black,
    secondaryContainer = BlackSurfaceElevated,
    onSecondaryContainer = WhitePrimary,
    tertiary = WhitePrimary,
    onTertiary = Color.Black,
    background = BlackBackground,
    onBackground = WhitePrimary,
    surface = BlackSurface,
    onSurface = WhitePrimary,
    surfaceVariant = BlackSurfaceCard,
    onSurfaceVariant = WhiteSecondary,
    outline = GoldBorder,
    outlineVariant = GoldBorderBright,
    error = DangerRed,
    onError = Color.White
  )

@Composable
fun MyApplicationTheme(
  content: @Composable () -> Unit,
) {
  MaterialTheme(
    colorScheme = LuxuryGoldDarkColorScheme,
    typography = Typography,
    content = content
  )
}
