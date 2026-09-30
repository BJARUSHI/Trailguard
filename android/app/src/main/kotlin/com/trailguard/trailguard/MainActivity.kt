package com.trailguard.trailguard

import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.trailguard.trailguard/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sendSms") {
                val phone = call.argument<String>("phone")
                val message = call.argument<String>("message")

                if (phone.isNullOrBlank() || message.isNullOrBlank()) {
                    result.error("BAD_ARGS", "Phone number or message was empty", null)
                    return@setMethodCallHandler
                }

                try {
                    val smsManager = SmsManager.getDefault()
                    val parts = smsManager.divideMessage(message)
                    smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SEND_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
