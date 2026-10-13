package gov.ifso.location_requests

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Android BroadcastReceiver for capturing raw incoming telecom SMS responses.
 *
 * Listens for android.provider.Telephony.SMS_RECEIVED.
 * Extracts originating carrier shortcode/address and raw SMS body without modification,
 * preserving chain of custody before forwarding to Flutter.
 */
class SmsResponseReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent == null || intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) {
            return
        }

        val sender = messages[0].displayOriginatingAddress ?: ""
        val timestamp = messages[0].timestampMillis

        val bodyBuilder = StringBuilder()
        for (message in messages) {
            val body = message.displayMessageBody
            if (!body.isNullOrEmpty()) {
                bodyBuilder.append(body)
            }
        }

        val rawBody = bodyBuilder.toString()
        if (rawBody.isNotBlank()) {
            MainActivity.forwardSmsToFlutter(sender, rawBody, timestamp)
        }
    }
}
