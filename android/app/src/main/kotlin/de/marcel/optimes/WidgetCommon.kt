package de.marcel.optimes

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color as AColor
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.graphics.SweepGradient
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import androidx.glance.LocalContext
import androidx.glance.appwidget.action.actionStartActivity

// ── Shield-Palette ──────────────────────────────────────────────────────
val bgBase      = Color(0xFF0A0B0F)
val primary     = Color(0xFF2D6CFF)
val neutral     = Color(0xFF7A8699)
val danger      = Color(0xFFEF5B5B)
val textPrimary = Color(0xFFFFFFFF)
val textMuted   = Color(0x59FFFFFF)
val textHint    = Color(0x33FFFFFF)
val tileIdle    = Color(0x0AFFFFFF)

fun shiftColor(shift: String): Color = when (shift.uppercase()) {
    "U", "DA", "X" -> neutral
    "VK" -> danger
    else -> primary
}

// ── Deep-Link-Helfer: öffnet MainActivity mit optimes://<path> ─────────────
val destinationPathKey = ActionParameters.Key<String>("destination_path")

class OpenDeepLinkAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters
    ) {
        val path = parameters[destinationPathKey] ?: return
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("optimes://$path")).apply {
            setClass(context, MainActivity::class.java)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}

@Composable
fun deepLinkClick(path: String): GlanceModifier {
    val context = LocalContext.current
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("optimes://$path")).apply {
        setClass(context, MainActivity::class.java)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
    return GlanceModifier.clickable(actionStartActivity(intent))
}

// ── Tacho-Bitmap (1:1-Nachbau des iOS-Canvas) ───────────────────────────────
fun renderTachoBitmap(sizePx: Int, progress: Double): Bitmap {
    val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bmp)
    val cx = sizePx / 2f
    val cy = sizePx / 2f
    val r = min(sizePx, sizePx) * 0.40f

    val startAngle = 150.0
    val sweep = 240.0

    val cPrimary = AColor.parseColor("#2D6CFF")
    val cSecondary = AColor.parseColor("#1746B8")
    val cLight = AColor.parseColor("#9DBBFF")
    val cLighter = AColor.parseColor("#C5DDFF")
    val cMid = AColor.parseColor("#5A8CFF")
    val cDeep = AColor.parseColor("#0E1016")

    val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader = RadialGradient(cx, cy, r * 1.4f,
            intArrayOf(AColor.argb(15, 45, 108, 255), AColor.TRANSPARENT),
            floatArrayOf(0f, 1f), Shader.TileMode.CLAMP)
    }
    canvas.drawRect(0f, 0f, sizePx.toFloat(), sizePx.toFloat(), bgPaint)

    val bezelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    listOf(Triple(r + 10, 0.06f, 1.0f), Triple(r + 6, 0.14f, 1.2f), Triple(r + 2, 0.06f, 0.8f)).forEach { (br, op, lw) ->
        bezelPaint.color = cPrimary
        bezelPaint.alpha = (op * 255).toInt()
        bezelPaint.strokeWidth = lw
        canvas.drawCircle(cx, cy, br, bezelPaint)
    }

    val oval = android.graphics.RectF(cx - r, cy - r, cx + r, cy + r)

    val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = 6f; color = AColor.argb(10, 255, 255, 255)
    }
    canvas.drawArc(oval, startAngle.toFloat(), sweep.toFloat(), false, trackPaint)

    val sweepPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = 6f; strokeCap = Paint.Cap.ROUND
        shader = SweepGradient(cx, cy, intArrayOf(cSecondary, cPrimary, cLight), floatArrayOf(0f, 0.6f, 1f))
    }
    canvas.drawArc(oval, startAngle.toFloat(), (sweep * progress).toFloat(), false, sweepPaint)

    var deg = 150.0
    while (deg <= 390.0) {
        val isMajor = (deg.toInt() % 30 == 0)
        val normRatio = (deg - 150.0) / 240.0
        val isActive = normRatio <= progress
        val innerR = r + (if (isMajor) 1f else 4f)
        val outerR = r + (if (isMajor) 10f else 6f)
        val tickColor = when {
            isActive && isMajor -> cLighter
            isActive -> AColor.argb(128, 45, 108, 255)
            else -> AColor.argb(if (isMajor) 128 else 51, 23, 70, 184)
        }
        val rad = Math.toRadians(deg % 360)
        val ix = cx + innerR * cos(rad).toFloat(); val iy = cy + innerR * sin(rad).toFloat()
        val ox = cx + outerR * cos(rad).toFloat(); val oy = cy + outerR * sin(rad).toFloat()
        val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = tickColor; strokeWidth = if (isMajor) 2.2f else 1.0f; strokeCap = Paint.Cap.ROUND
        }
        canvas.drawLine(ix, iy, ox, oy, tickPaint)
        deg += 10.0
    }

    val dotCount = 21
    val dotStep = sweep / (dotCount - 1)
    val activeDotCount = ((dotCount - 1) * progress).toInt()
    val dotRadius = r - 14
    for (i in 0 until dotCount) {
        val angleDeg = startAngle + i * dotStep
        val distFromEnd = activeDotCount - i
        val (fillColor, dotSize) = when {
            i > activeDotCount -> AColor.argb(242, AColor.red(cDeep), AColor.green(cDeep), AColor.blue(cDeep)) to 1.5f
            distFromEnd == 0 -> cLighter to 3.0f
            distFromEnd == 1 -> cLight to 2.5f
            distFromEnd in 2..3 -> cMid to 2.1f
            else -> cPrimary to 1.9f
        }
        val rad = Math.toRadians(angleDeg)
        val px = cx + dotRadius * cos(rad).toFloat(); val py = cy + dotRadius * sin(rad).toFloat()
        val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = fillColor }
        canvas.drawCircle(px, py, dotSize, dotPaint)
    }

    val needleAngleDeg = startAngle + activeDotCount * dotStep
    val needleRad = Math.toRadians(needleAngleDeg)
    val tipX = cx + (r + 6) * cos(needleRad).toFloat(); val tipY = cy + (r + 6) * sin(needleRad).toFloat()
    val baseX = cx + (dotRadius - 5) * cos(needleRad).toFloat(); val baseY = cy + (dotRadius - 5) * sin(needleRad).toFloat()
    val needleGlow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = cMid; alpha = 115; strokeWidth = 4f; strokeCap = Paint.Cap.ROUND
    }
    canvas.drawLine(tipX, tipY, baseX, baseY, needleGlow)
    val needleMain = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = AColor.WHITE; alpha = 242; strokeWidth = 1.8f; strokeCap = Paint.Cap.ROUND
    }
    canvas.drawLine(tipX, tipY, baseX, baseY, needleMain)

    val hubGlow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader = RadialGradient(cx, cy, 7f, intArrayOf(AColor.argb(153, 157, 187, 255), AColor.TRANSPARENT),
            floatArrayOf(0f, 1f), Shader.TileMode.CLAMP)
    }
    canvas.drawCircle(cx, cy, 7f, hubGlow)
    val hubDot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = AColor.WHITE }
    canvas.drawCircle(cx, cy, 3f, hubDot)

    return bmp
}