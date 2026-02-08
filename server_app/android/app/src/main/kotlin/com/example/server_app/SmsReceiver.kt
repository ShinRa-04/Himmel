package com.example.server_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import android.content.ContentValues
import java.io.File

/**
 * BroadcastReceiver for incoming SMS messages (SMS_DELIVER intent).
 * As the default SMS app, this receives all incoming SMS.
 * 
 * For Himmel protocol messages (containing ID:, I:, T:), we:
 * 1. Write to a shared file for Flutter to pick up
 * 2. Also save to SMS database for persistence
 */
class SmsReceiver : BroadcastReceiver() {
    private val TAG = "HimmelSmsReceiver"

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d(TAG, "SMS received via SMS_DELIVER")
        
        if (context == null || intent?.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) {
            return
        }
        
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        
        messages?.forEach { smsMessage ->
            val sender = smsMessage.displayOriginatingAddress ?: return@forEach
            val body = smsMessage.messageBody ?: return@forEach
            val timestamp = smsMessage.timestampMillis
            
            Log.d(TAG, "SMS from $sender: ${body.take(50)}...")
            
            // Check if this is a Himmel protocol message
            if (isProtocolMessage(body)) {
                Log.d(TAG, "✅ Protocol message detected!")
                
                // Write to shared file for Flutter to read
                writeIncomingSms(context, sender, body, timestamp)
                
                // Send broadcast to notify Flutter
                val notifyIntent = Intent("com.example.server_app.SMS_RECEIVED")
                notifyIntent.setPackage(context.packageName)
                notifyIntent.putExtra("sender", sender)
                notifyIntent.putExtra("body", body)
                notifyIntent.putExtra("timestamp", timestamp)
                context.sendBroadcast(notifyIntent)
            } else {
                Log.d(TAG, "⏭️ Non-protocol message, ignoring")
            }
            
            // Save to SMS database (required as default SMS app)
            saveToSmsDatabase(context, sender, body, timestamp)
        }
    }
    
    /**
     * Check if the message follows Himmel protocol format.
     * Protocol: ID:<hash>\n[M:<total>\n]I:<index>\nT:<payload>
     */
    private fun isProtocolMessage(body: String): Boolean {
        return body.contains("ID:") && body.contains("I:") && body.contains("T:")
    }
    
    /**
     * Write incoming SMS to a JSON file for Flutter to pick up.
     * Uses a queue file that Flutter polls.
     */
    private fun writeIncomingSms(context: Context, sender: String, body: String, timestamp: Long) {
        try {
            val queueDir = File(context.filesDir, "sms_queue")
            if (!queueDir.exists()) {
                queueDir.mkdirs()
            }
            
            // Use timestamp as unique filename
            val filename = "sms_${timestamp}_${System.nanoTime()}.json"
            val file = File(queueDir, filename)
            
            // Escape JSON strings properly
            val escapedBody = body
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t")
            
            val escapedSender = sender
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
            
            val json = """{"sender":"$escapedSender","body":"$escapedBody","timestamp":$timestamp}"""
            
            file.writeText(json)
            Log.d(TAG, "📝 Written SMS to queue: $filename")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to write SMS to queue: ${e.message}")
        }
    }
    
    /**
     * Save SMS to the system SMS database.
     * Required for the app to function properly as default SMS app.
     */
    private fun saveToSmsDatabase(context: Context, sender: String, body: String, timestamp: Long) {
        try {
            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, sender)
                put(Telephony.Sms.BODY, body)
                put(Telephony.Sms.DATE, timestamp)
                put(Telephony.Sms.DATE_SENT, timestamp)
                put(Telephony.Sms.READ, 1) // Mark as read
                put(Telephony.Sms.SEEN, 1)
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_INBOX)
            }
            
            context.contentResolver.insert(Telephony.Sms.CONTENT_URI, values)
            Log.d(TAG, "💾 Saved SMS to database")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to save SMS to database: ${e.message}")
        }
    }
}

