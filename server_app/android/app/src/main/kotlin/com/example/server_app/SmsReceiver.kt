package com.example.server_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * Required BroadcastReceiver for becoming default SMS app.
 * Receives incoming SMS messages via SMS_DELIVER intent.
 * 
 * We don't need to process incoming SMS for Himmel's use case,
 * but this receiver must exist for the app to be eligible as default SMS app.
 */
class SmsReceiver : BroadcastReceiver() {
    private val TAG = "HimmelSmsReceiver"

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d(TAG, "SMS received via SMS_DELIVER")
        
        if (intent?.action == Telephony.Sms.Intents.SMS_DELIVER_ACTION) {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            
            messages?.forEach { smsMessage ->
                val sender = smsMessage.displayOriginatingAddress
                val body = smsMessage.messageBody
                Log.d(TAG, "SMS from $sender: ${body?.take(50)}...")
                
                // Note: As the default SMS app, we're responsible for writing 
                // incoming messages to the SMS database if we want them stored.
                // For Himmel server, we're only interested in SENDING, not receiving,
                // so we just acknowledge receipt without storing.
            }
        }
    }
}
