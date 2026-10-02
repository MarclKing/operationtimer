package de.marcel.optimes

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.*
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.unit.DpSize

@Composable
private fun TachoContent() {
    val sizePx = 220
    val bitmap = renderTachoBitmap(sizePx, progress = 0.36)

    Box(
        modifier = GlanceModifier.fillMaxSize().background(bgBase).then(deepLinkClick("fahrtenbuch/neue-fahrt/scan-km-start")),
        contentAlignment = Alignment.Center
    ) {
        Image(
            provider = ImageProvider(bitmap),
            contentDescription = null,
            modifier = GlanceModifier.size(140.dp)
        )
        Column(
            modifier = GlanceModifier.padding(top = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text("🚗", style = TextStyle(fontSize = 24.sp))
            Spacer(modifier = GlanceModifier.height(12.dp))
            Text("Fahrt starten", style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = ColorProvider(textPrimary)))
            Text("KM scannen", style = TextStyle(fontSize = 9.sp, color = ColorProvider(primary)))
        }
    }
}

class FahrtenbuchWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { TachoContent() }
    }
}

class FahrtenbuchWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = FahrtenbuchWidget()
}