package com.moneyanywhere.money_anywhere

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val speechRequest = 102
    private var speechResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "money_anywhere/local_settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "settingsDirectory" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "money_anywhere/speech",
        ).setMethodCallHandler { call, result ->
            if (call.method == "recognize") {
                recognizeSpeech(result)
            } else {
                result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun recognizeSpeech(result: MethodChannel.Result) {
        if (speechResult != null) {
            result.error("busy", null, null)
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "th-TH")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        speechResult = result
        try {
            startActivityForResult(intent, speechRequest)
        } catch (_: ActivityNotFoundException) {
            speechResult = null
            result.error("unavailable", null, null)
        } catch (_: SecurityException) {
            speechResult = null
            result.error("permission", null, null)
        }
    }

    @Deprecated("Uses the activity result returned by Android's speech service")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != speechRequest) return
        val result = speechResult
        speechResult = null
        when (resultCode) {
            Activity.RESULT_OK -> result?.success(
                data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull(),
            )
            Activity.RESULT_CANCELED -> result?.success(null)
            else -> result?.error("recognition", null, null)
        }
    }
}
