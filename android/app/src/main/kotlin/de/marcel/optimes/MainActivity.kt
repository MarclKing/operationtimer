package de.marcel.optimes

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.glance.appwidget.updateAll
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

const val WIDGET_PREFS_NAME = "de.marcel.optimes.widget_data"

class MainActivity : FlutterActivity() {
    private val navChannelName = "de.marcel.optimes/navigation"
    private val widgetChannelName = "de.marcel.optimes/widget"
    private var navMethodChannel: MethodChannel? = null
    private var pendingWidgetNavigation: Map<String, String>? = null
    private val uiScope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        navMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, navChannelName)
        pendingWidgetNavigation?.let { dispatchWidgetNavigation(it, 0) }

        val widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannelName)
        val prefs: SharedPreferences = applicationContext.getSharedPreferences(WIDGET_PREFS_NAME, Context.MODE_PRIVATE)

        widgetChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateSchedule" -> {
                    val json = call.argument<String>("json")
                    if (json != null) {
                        prefs.edit().putString("schedule_entries", json).apply()
                    }
                    refreshWidgets()
                    result.success(null)
                }
                "updateCalendarEvents" -> {
                    val json = call.argument<String>("json")
                    val readOnly = call.argument<Boolean>("readOnly")
                    val editor = prefs.edit()
                    if (json != null) editor.putString("calendar_widget_events", json)
                    if (readOnly != null) editor.putBoolean("read_only_mode", readOnly)
                    editor.apply()
                    refreshWidgets()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

        private fun refreshWidgets() {
        uiScope.launch {
            DienstplanWidget().updateAll(applicationContext)
            FahrtenbuchWidget().updateAll(applicationContext)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent, delayMs = 600L)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent, delayMs = 100L)
    }

    private fun handleIntent(intent: Intent, delayMs: Long) {
        val uri = intent.data ?: return
        if (uri.scheme != "optimes") return

        val fullUrl = uri.toString()
        val path = when {
            uri.host == "kalender" -> "kalender"
            fullUrl.contains("fahrtenbuch/neue-fahrt/scan-km-start") -> "fahrtenbuch_neue_fahrt_scan"
            fullUrl.contains("/note/") -> "dienstplan_note"
            uri.host == "dienstplan" -> "dienstplan"
            else -> return
        }

        val data = mapOf("url" to fullUrl, "path" to path)
        pendingWidgetNavigation = data
        Handler(Looper.getMainLooper()).postDelayed({
            dispatchWidgetNavigation(data, 0)
        }, delayMs)
    }

    private fun dispatchWidgetNavigation(data: Map<String, String>, attempt: Int) {
        val channel = navMethodChannel
        if (channel == null) {
            retryWidgetNavigation(data, attempt)
            return
        }

        channel.invokeMethod("openFromWidget", data, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (pendingWidgetNavigation == data) pendingWidgetNavigation = null
            }

            override fun error(code: String, message: String?, details: Any?) {
                retryWidgetNavigation(data, attempt)
            }

            override fun notImplemented() {
                retryWidgetNavigation(data, attempt)
            }
        })
    }

    private fun retryWidgetNavigation(data: Map<String, String>, attempt: Int) {
        if (attempt >= 20 || pendingWidgetNavigation != data) return
        Handler(Looper.getMainLooper()).postDelayed({
            dispatchWidgetNavigation(data, attempt + 1)
        }, 200L)
    }
}