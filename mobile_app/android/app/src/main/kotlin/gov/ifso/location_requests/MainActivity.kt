package gov.ifso.location_requests

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Main Android Activity providing the telephony platform bridge for the IO application.
 *
 * Enforces corporate MDM hardware SIM boundaries:
 * - Dispatches carrier SMS queries via native SmsManager.
 * - Handles Android SEND_SMS permission checks.
 * - Forwards incoming carrier SMS replies received by [SmsResponseReceiver] to Flutter.
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val CHANNEL_NAME = "gov.ifso.location_requests/telephony"
        private const val PERMISSION_REQUEST_CODE = 4001

        @Volatile
        var activeChannel: MethodChannel? = null

        /**
         * Forwards an intercepted telecom SMS message to the active Flutter session.
         */
        fun forwardSmsToFlutter(sender: String, body: String, timestamp: Long) {
            val payload = mapOf(
                "sender" to sender,
                "body" to body,
                "timestamp" to timestamp
            )
            activeChannel?.invokeMethod("onSmsReceived", payload)
        }
    }

    private var permissionResultCallback: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        activeChannel = channel

        channel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "checkSmsPermission" -> handleCheckPermission(result)
                "requestSmsPermission" -> handleRequestPermission(result)
                "sendSms" -> handleSendSms(call, result)
                "shareText" -> {
                    val text = call.argument<String>("text").orEmpty()
                    if (text.isBlank()) {
                        result.success(false)
                    } else {
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        startActivity(Intent.createChooser(sendIntent, "Share authorized result"))
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (activeChannel != null) {
            activeChannel = null
        }
        super.onDestroy()
    }

    private fun handleCheckPermission(result: MethodChannel.Result) {
        val sendGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED

        val receiveGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECEIVE_SMS
        ) == PackageManager.PERMISSION_GRANTED

        result.success(sendGranted && receiveGranted)
    }

    private fun handleRequestPermission(result: MethodChannel.Result) {
        val permissions = arrayOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_PHONE_STATE
        )

        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isEmpty()) {
            result.success(true)
            return
        }

        permissionResultCallback = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == PERMISSION_REQUEST_CODE) {
            val callback = permissionResultCallback ?: return
            permissionResultCallback = null

            val allGranted = grantResults.isNotEmpty() && grantResults.all {
                it == PackageManager.PERMISSION_GRANTED
            }
            callback.success(allGranted)
        }
    }

    private fun handleSendSms(call: MethodCall, result: MethodChannel.Result) {
        val requestId = call.argument<String>("requestId") ?: ""
        val destinationAddress = call.argument<String>("destinationAddress") ?: ""
        val message = call.argument<String>("message") ?: ""
        val simSlotIndex = call.argument<Int>("simSlotIndex") ?: 0

        if (destinationAddress.isBlank() || message.isBlank()) {
            result.success(
                mapOf(
                    "success" to false,
                    "errorCode" to "INVALID_ARGUMENTS",
                    "errorMessage" to "Destination address and message content cannot be empty."
                )
            )
            return
        }

        val hasSendPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasSendPermission) {
            result.success(
                mapOf(
                    "success" to false,
                    "errorCode" to "PERMISSION_DENIED",
                    "errorMessage" to "android.permission.SEND_SMS has not been granted."
                )
            )
            return
        }

        try {
            val subscriptionManager = getSystemService(SubscriptionManager::class.java)
            val selectedSubscription = subscriptionManager
                ?.activeSubscriptionInfoList
                ?.firstOrNull { it.simSlotIndex == simSlotIndex }

            if (selectedSubscription == null) {
                result.success(
                    mapOf(
                        "success" to false,
                        "errorCode" to "SIM_NOT_AVAILABLE",
                        "errorMessage" to "No active SIM is available in the selected slot."
                    )
                )
                return
            }

            // Never silently fall back to the device default SIM: the selected
            // authorized SIM slot must match the request execution context.
            @Suppress("DEPRECATION")
            val smsManager = SmsManager.getSmsManagerForSubscriptionId(
                selectedSubscription.subscriptionId
            )

            val sentAction = "gov.ifso.location_requests.SMS_SENT_${System.currentTimeMillis()}"
            val sentIntent = Intent(sentAction)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_ONE_SHOT
            }
            val sentPI = PendingIntent.getBroadcast(this, 0, sentIntent, flags)

            val answered = AtomicBoolean(false)

            val sentReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (answered.compareAndSet(false, true)) {
                        try {
                            unregisterReceiver(this)
                        } catch (_: Exception) {
                        }

                        when (resultCode) {
                            Activity.RESULT_OK -> {
                                result.success(
                                    mapOf(
                                        "success" to true,
                                        "deliveryStatus" to "SENT"
                                    )
                                )
                            }
                            SmsManager.RESULT_ERROR_NO_SERVICE -> {
                                result.success(
                                    mapOf(
                                        "success" to false,
                                        "errorCode" to "NO_SERVICE",
                                        "errorMessage" to "No cellular network service available."
                                    )
                                )
                            }
                            SmsManager.RESULT_ERROR_RADIO_OFF -> {
                                result.success(
                                    mapOf(
                                        "success" to false,
                                        "errorCode" to "RADIO_OFF",
                                        "errorMessage" to "Cellular radio is off (Airplane mode active)."
                                    )
                                )
                            }
                            SmsManager.RESULT_ERROR_NULL_PDU -> {
                                result.success(
                                    mapOf(
                                        "success" to false,
                                        "errorCode" to "NULL_PDU",
                                        "errorMessage" to "PDU generation failed (Null PDU)."
                                    )
                                )
                            }
                            else -> {
                                result.success(
                                    mapOf(
                                        "success" to false,
                                        "errorCode" to "GENERIC_FAILURE",
                                        "errorMessage" to "SMS transmission failed with code $resultCode."
                                    )
                                )
                            }
                        }
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(sentReceiver, IntentFilter(sentAction), Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(sentReceiver, IntentFilter(sentAction))
            }

            smsManager.sendTextMessage(destinationAddress, null, message, sentPI, null)
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "success" to false,
                    "errorCode" to "SMS_EXCEPTION",
                    "errorMessage" to (e.message ?: "Unexpected exception during SMS transmission.")
                )
            )
        }
    }
}
