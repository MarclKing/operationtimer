package de.marcel.optimes

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.*
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import org.json.JSONArray
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle as JTextStyle
import java.util.Locale

private fun loadShifts(context: Context): Map<String, String> {
    val prefs = context.getSharedPreferences(WIDGET_PREFS_NAME, Context.MODE_PRIVATE)
    val json = prefs.getString("schedule_entries", "[]") ?: "[]"
    val arr = JSONArray(json)
    val result = mutableMapOf<String, String>()
    for (i in 0 until arr.length()) {
        val obj = arr.getJSONObject(i)
        val d = obj.optString("date", "")
        val s = obj.optString("shift", "")
        if (d.isNotEmpty()) result[d] = s
    }
    return result
}

// ── Tag-Kachel — mit Ring-Hervorhebung für den 1. eines Monats ────────────
@Composable
private fun RowScope.DayTile(
    date: LocalDate,
    shift: String,
    isToday: Boolean,
    isPast: Boolean,
    isFirstOfMonth: Boolean
) {
    val isEmpty = shift.isEmpty()
    val color = shiftColor(shift)
    val bg = if (isToday) color else if (isEmpty) tileIdle else color.copy(alpha = 0.12f)
    val fade = if (isPast && isEmpty) 0.25f else 1.0f
    val ring = isFirstOfMonth && !isToday

    val dayName = date.dayOfWeek.getDisplayName(JTextStyle.SHORT, Locale.GERMAN).take(2).uppercase()
    val dayNum = date.dayOfMonth.toString()

    Box(
        modifier = GlanceModifier
            .defaultWeight()
            .fillMaxHeight()
            .padding(horizontal = 1.5.dp)
            .background(if (ring) primary.copy(alpha = 0.55f) else Color.Transparent)
            .cornerRadius(8.dp)
    ) {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(if (ring) 1.5.dp else 0.dp)
                .background(bg)
                .cornerRadius(7.dp)
                .padding(2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(dayName, style = TextStyle(fontSize = 6.5.sp,
                color = ColorProvider(if (isToday) androidx.compose.ui.graphics.Color.White.copy(alpha = 0.75f) else textMuted.copy(alpha = fade))))
            Text(dayNum, style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold,
                color = ColorProvider(if (isToday) androidx.compose.ui.graphics.Color.White else textPrimary.copy(alpha = fade))))
            Text(if (isEmpty) "–" else shift, style = TextStyle(fontSize = 8.sp, fontWeight = FontWeight.Bold,
                color = ColorProvider(if (isToday) androidx.compose.ui.graphics.Color.White else if (isEmpty) textHint else color.copy(alpha = fade))))
        }
    }
}

// ── Medium: aktuelle Woche ──────────────────────────────────────────────
@Composable
private fun MediumContent(shifts: Map<String, String>) {
    val today = LocalDate.now()
    val monday = today.minusDays((today.dayOfWeek.value - 1).toLong())
    val fmt = DateTimeFormatter.ISO_LOCAL_DATE

    Column(
        modifier = GlanceModifier.fillMaxSize().background(bgBase).padding(12.dp)
            .then(deepLinkClick("dienstplan"))
    ) {
        Text("DIENSTPLAN · DIESE WOCHE", style = TextStyle(fontSize = 9.sp, fontWeight = FontWeight.Bold, color = ColorProvider(primary)))
        Spacer(modifier = GlanceModifier.height(8.dp))
        Row(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
            for (i in 0 until 7) {
                val date = monday.plusDays(i.toLong())
                DayTile(
                    date = date,
                    shift = shifts[date.format(fmt)] ?: "",
                    isToday = date == today,
                    isPast = date.isBefore(today),
                    isFirstOfMonth = date.dayOfMonth == 1
                )
            }
        }
    }
}

// ── Large: aktuelle Woche OBEN, dann kommende Wochen — springt erst nach
//    vollständigem Wochenablauf (Montags-Anker wird jeden Tag neu berechnet,
//    bleibt aber bis zum nächsten Montag dieselbe Woche) ────────────────────
@Composable
private fun LargeContent(shifts: Map<String, String>) {
    val today = LocalDate.now()
    val fmt = DateTimeFormatter.ISO_LOCAL_DATE
    val currentMonday = today.minusDays((today.dayOfWeek.value - 1).toLong())
    val weekCount = 4

    val firstDay = currentMonday
    val lastDay = currentMonday.plusWeeks((weekCount - 1).toLong()).plusDays(6)
    val monthFmt = java.time.format.DateTimeFormatter.ofPattern("d. MMM", Locale.GERMAN)
    val rangeLabel = if (firstDay.month == lastDay.month)
        "${firstDay.dayOfMonth}.–${lastDay.format(monthFmt)}"
    else
        "${firstDay.format(monthFmt)} – ${lastDay.format(monthFmt)}"

    Column(
        modifier = GlanceModifier.fillMaxSize().background(bgBase).padding(10.dp)
            .then(deepLinkClick("dienstplan"))
    ) {
        Text("DIENSTPLAN · $rangeLabel", style = TextStyle(fontSize = 9.sp, fontWeight = FontWeight.Bold, color = ColorProvider(primary)))
        Spacer(modifier = GlanceModifier.height(6.dp))
        Column(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
            for (w in 0 until weekCount) {
                Row(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                    for (d in 0 until 7) {
                        val date = currentMonday.plusWeeks(w.toLong()).plusDays(d.toLong())
                        DayTile(
                            date = date,
                            shift = shifts[date.format(fmt)] ?: "",
                            isToday = date == today,
                            isPast = date.isBefore(today),
                            isFirstOfMonth = date.dayOfMonth == 1
                        )
                    }
                }
            }
        }
    }
}

class DienstplanWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val shifts = loadShifts(context)
        provideContent {
            val size = androidx.glance.LocalSize.current
            if (size.height < 150.dp) MediumContent(shifts) else LargeContent(shifts)
        }
    }
}

class DienstplanWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DienstplanWidget()
}