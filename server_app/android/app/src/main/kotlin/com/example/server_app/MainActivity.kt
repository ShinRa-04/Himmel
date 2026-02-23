package com.example.server_app

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.app.role.RoleManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Base64
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    private val TAG = "HimmelServer"
    private val CHANNEL = "com.example.server_app/intent"
    private val SMS_CHANNEL = "com.himmel.sms/sender"
    private var pendingTarget: String? = null
    private var pendingMessage: String? = null
    private var pendingMessageId: String? = null  // Original message ID to preserve
    private var methodChannel: MethodChannel? = null
    private var smsMethodChannel: MethodChannel? = null
    private var pendingDefaultSmsResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    
    companion object {
        private const val REQUEST_DEFAULT_SMS = 1001
        private const val REQUEST_SMS_PERMISSION = 1002
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine called")
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d(TAG, "MethodChannel call: ${call.method}")
            when (call.method) {
                "getIntent" -> {
                    Log.d(TAG, "getIntent called - pending: target=$pendingTarget, msgLen=${pendingMessage?.length ?: 0}, msgId=$pendingMessageId")
                    if (pendingTarget != null && pendingMessage != null) {
                        val data = mutableMapOf(
                            "target" to pendingTarget,
                            "message" to pendingMessage
                        )
                        // Include message_id if present
                        if (pendingMessageId != null) {
                            data["message_id"] = pendingMessageId
                        }
                        // Clear after reading
                        val savedTarget = pendingTarget
                        val savedMsgLen = pendingMessage?.length
                        val savedMsgId = pendingMessageId
                        pendingTarget = null
                        pendingMessage = null
                        pendingMessageId = null
                        Log.d(TAG, "Returning intent data: target=$savedTarget, msgLen=$savedMsgLen, msgId=$savedMsgId")
                        result.success(data)
                    } else {
                        Log.d(TAG, "No pending intent data")
                        result.success(null)
                    }
                }
                "isDefaultSmsApp" -> {
                    val isDefault = isDefaultSmsApp()
                    Log.d(TAG, "isDefaultSmsApp: $isDefault")
                    result.success(isDefault)
                }
                "requestDefaultSmsApp" -> {
                    Log.d(TAG, "requestDefaultSmsApp called")
                    pendingDefaultSmsResult = result
                    requestDefaultSmsApp()
                }
                else -> result.notImplemented()
            }
        }
        
        // Setup SMS sender channel
        smsMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
        smsMethodChannel?.setMethodCallHandler { call, result ->
            Log.d(TAG, "SMS MethodChannel call: ${call.method}")
            when (call.method) {
                "sendSms" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")
                    if (phoneNumber != null && message != null) {
                        sendSmsNative(phoneNumber, message, result)
                    } else {
                        result.success(mapOf("success" to false, "error" to "Missing phoneNumber or message"))
                    }
                }
                "sendSmsSimple" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")
                    if (phoneNumber != null && message != null) {
                        sendSmsSimple(phoneNumber, message, result)
                    } else {
                        result.success(mapOf("success" to false, "error" to "Missing phoneNumber or message"))
                    }
                }
                "hasPermission" -> {
                    result.success(hasSmsPermission())
                }
                "requestPermission" -> {
                    if (hasSmsPermission()) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        requestSmsPermission()
                    }
                }
                "getLastSentMessage" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    if (phoneNumber != null) {
                        result.success(getLastSentMessage(phoneNumber))
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Process initial intent
        Log.d(TAG, "Processing initial intent")
        handleIntent(intent)
    }

    private fun isDefaultSmsApp(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ uses RoleManager
            val roleManager = getSystemService(RoleManager::class.java)
            val isDefault = roleManager.isRoleHeld(RoleManager.ROLE_SMS)
            Log.d(TAG, "RoleManager check: isRoleHeld(ROLE_SMS) = $isDefault")
            isDefault
        } else {
            // Android 9 and below uses Telephony
            val defaultSmsPackage = Telephony.Sms.getDefaultSmsPackage(this)
            val isDefault = defaultSmsPackage == packageName
            Log.d(TAG, "Telephony check: defaultPackage=$defaultSmsPackage, ourPackage=$packageName, isDefault=$isDefault")
            isDefault
        }
    }

    private fun requestDefaultSmsApp() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ uses RoleManager
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager.isRoleAvailable(RoleManager.ROLE_SMS)) {
                if (!roleManager.isRoleHeld(RoleManager.ROLE_SMS)) {
                    val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_SMS)
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, REQUEST_DEFAULT_SMS)
                } else {
                    Log.d(TAG, "Already have SMS role")
                    pendingDefaultSmsResult?.success(true)
                    pendingDefaultSmsResult = null
                }
            } else {
                Log.e(TAG, "SMS role not available")
                pendingDefaultSmsResult?.success(false)
                pendingDefaultSmsResult = null
            }
        } else {
            // Android 4.4 - 9: Use Telephony.Sms.Intents
            val intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
            intent.putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName)
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_DEFAULT_SMS)
        }
    }
    
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_DEFAULT_SMS) {
            val isDefault = isDefaultSmsApp()
            Log.d(TAG, "Default SMS request result: isDefault=$isDefault")
            pendingDefaultSmsResult?.success(isDefault)
            pendingDefaultSmsResult = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "========================================")
        Log.d(TAG, "onNewIntent CALLED!")
        Log.d(TAG, "  Action: ${intent.action}")
        Log.d(TAG, "  Extras: ${intent.extras?.keySet()?.joinToString()}")
        Log.d(TAG, "  Has target: ${intent.hasExtra("target")}")
        Log.d(TAG, "  Has message_b64: ${intent.hasExtra("message_b64")}")
        Log.d(TAG, "  Has message_id: ${intent.hasExtra("message_id")}")
        Log.d(TAG, "========================================")
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        Log.d(TAG, "handleIntent called, intent=$intent")
        intent?.let {
            val target = it.getStringExtra("target")
            val messageId = it.getStringExtra("message_id")  // Original message ID
            Log.d(TAG, "Intent target: $target")
            Log.d(TAG, "Intent message_id: $messageId")
            
            // Try base64 encoded message first (preferred), fallback to plain text
            var message: String? = null
            val messageB64 = it.getStringExtra("message_b64")
            Log.d(TAG, "Intent message_b64 length: ${messageB64?.length ?: 0}")
            
            if (!messageB64.isNullOrEmpty()) {
                try {
                    // Decode base64 message
                    val decodedBytes = Base64.decode(messageB64, Base64.DEFAULT)
                    message = String(decodedBytes, Charsets.UTF_8)
                    Log.d(TAG, "Decoded base64 message, length: ${message.length}")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to decode base64: ${e.message}")
                    // Fallback if decode fails
                    message = it.getStringExtra("message")?.trim('"')
                }
            } else {
                // Fallback to plain message (legacy support)
                message = it.getStringExtra("message")?.trim('"')
                Log.d(TAG, "Using plain message, length: ${message?.length ?: 0}")
            }
            
            if (!target.isNullOrEmpty() && !message.isNullOrEmpty()) {
                Log.d(TAG, "========================================")
                Log.d(TAG, "VALID PAYLOAD RECEIVED!")
                Log.d(TAG, "  Target: $target")
                Log.d(TAG, "  Message length: ${message.length}")
                Log.d(TAG, "  Message ID: $messageId")
                Log.d(TAG, "  Method channel ready: ${methodChannel != null}")
                Log.d(TAG, "========================================")
                
                pendingTarget = target
                pendingMessage = message
                pendingMessageId = messageId  // Preserve original message ID
                
                // If Flutter engine is ready, send immediately via method channel
                // and clear pending data to prevent duplicate processing
                if (methodChannel != null) {
                    Log.d(TAG, ">>> INVOKING FLUTTER handleIntent <<<")
                    // Clear pending BEFORE invoking to prevent getIntent from returning same data
                    pendingTarget = null
                    pendingMessage = null
                    pendingMessageId = null
                    
                    val payload = mutableMapOf(
                        "target" to target,
                        "message" to message
                    )
                    if (messageId != null) {
                        payload["message_id"] = messageId
                    }
                    
                    methodChannel?.invokeMethod("handleIntent", payload)
                    Log.d(TAG, ">>> Flutter method invoked <<<")
                } else {
                    Log.d(TAG, "Method channel not ready, data stored for getIntent poll")
                }
            } else {
                Log.d(TAG, "Invalid payload: target=$target, msgLen=${message?.length ?: 0}")
            }
        }
    }
    
    private fun hasSmsPermission(): Boolean {
        val sendPerm = ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
        val readPerm = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
        return sendPerm && readPerm
    }
    
    private fun requestSmsPermission() {
        ActivityCompat.requestPermissions(
            this, 
            arrayOf(Manifest.permission.SEND_SMS, Manifest.permission.READ_SMS), 
            REQUEST_SMS_PERMISSION
        )
    }
    
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_SMS_PERMISSION) {
            // Check if all requested permissions are granted
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            Log.d(TAG, "SMS permission result: allGranted=$allGranted")
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
        }
    }
    
    private fun sendSmsNative(phoneNumber: String, message: String, result: MethodChannel.Result) {
        Log.d(TAG, "sendSmsNative: to=$phoneNumber, msgLen=${message.length}")
        
        if (!hasSmsPermission()) {
            Log.e(TAG, "No SMS permission!")
            result.success(mapOf("success" to false, "error" to "No SMS permission", "sentParts" to 0, "delivered" to false))
            return
        }
        
        try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            
            // Divide the message if it's too long
            val parts: ArrayList<String> = smsManager.divideMessage(message)
            Log.d(TAG, "Message divided into ${parts.size} parts")
            
            val totalParts = parts.size
            val sentCount = AtomicInteger(0)
            val deliveredCount = AtomicInteger(0)
            val failCount = AtomicInteger(0)
            val sentLatch = CountDownLatch(totalParts)
            val deliveryLatch = CountDownLatch(totalParts)
            val resultReported = AtomicBoolean(false)
            
            // Create sent AND delivery intents for reliability
            val sentIntents = ArrayList<PendingIntent>()
            val deliveryIntents = ArrayList<PendingIntent>()
            val timestamp = System.currentTimeMillis()
            
            for (i in 0 until totalParts) {
                val sentAction = "SMS_SENT_${i}_$timestamp"
                val deliveryAction = "SMS_DELIVERED_${i}_$timestamp"
                
                // Register broadcast receiver for sent confirmation
                val sentReceiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context?, intent: Intent?) {
                        Log.d(TAG, "Sent receiver triggered for part $i, resultCode=$resultCode")
                        try {
                            unregisterReceiver(this)
                        } catch (e: Exception) {
                            Log.w(TAG, "Couldn't unregister sent receiver: ${e.message}")
                        }
                        
                        when (resultCode) {
                            Activity.RESULT_OK -> {
                                Log.d(TAG, "Part $i sent to carrier successfully")
                                sentCount.incrementAndGet()
                            }
                            SmsManager.RESULT_ERROR_GENERIC_FAILURE -> {
                                Log.e(TAG, "Part $i: Generic failure")
                                failCount.incrementAndGet()
                            }
                            SmsManager.RESULT_ERROR_NO_SERVICE -> {
                                Log.e(TAG, "Part $i: No service")
                                failCount.incrementAndGet()
                            }
                            SmsManager.RESULT_ERROR_NULL_PDU -> {
                                Log.e(TAG, "Part $i: Null PDU")
                                failCount.incrementAndGet()
                            }
                            SmsManager.RESULT_ERROR_RADIO_OFF -> {
                                Log.e(TAG, "Part $i: Radio off")
                                failCount.incrementAndGet()
                            }
                            else -> {
                                Log.e(TAG, "Part $i: Unknown error: $resultCode")
                                failCount.incrementAndGet()
                            }
                        }
                        sentLatch.countDown()
                    }
                }
                
                // Register broadcast receiver for DELIVERY confirmation (most reliable indicator)
                val deliveryReceiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context?, intent: Intent?) {
                        Log.d(TAG, "Delivery receiver triggered for part $i, resultCode=$resultCode")
                        try {
                            unregisterReceiver(this)
                        } catch (e: Exception) {
                            Log.w(TAG, "Couldn't unregister delivery receiver: ${e.message}")
                        }
                        
                        when (resultCode) {
                            Activity.RESULT_OK -> {
                                Log.d(TAG, "Part $i DELIVERED to recipient!")
                                deliveredCount.incrementAndGet()
                            }
                            Activity.RESULT_CANCELED -> {
                                Log.w(TAG, "Part $i delivery FAILED")
                            }
                            else -> {
                                Log.w(TAG, "Part $i delivery unknown status: $resultCode")
                            }
                        }
                        deliveryLatch.countDown()
                    }
                }
                
                val sentFilter = IntentFilter(sentAction)
                val deliveryFilter = IntentFilter(deliveryAction)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(sentReceiver, sentFilter, Context.RECEIVER_NOT_EXPORTED)
                    registerReceiver(deliveryReceiver, deliveryFilter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    registerReceiver(sentReceiver, sentFilter)
                    registerReceiver(deliveryReceiver, deliveryFilter)
                }
                
                val sentIntent = PendingIntent.getBroadcast(
                    this, i, Intent(sentAction),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val deliveryIntent = PendingIntent.getBroadcast(
                    this, i + 1000, Intent(deliveryAction),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                sentIntents.add(sentIntent)
                deliveryIntents.add(deliveryIntent)
            }
            
            Log.d(TAG, "Sending multipart message with delivery reports...")
            
            // Send the message WITH delivery intents for reliability
            if (parts.size == 1) {
                smsManager.sendTextMessage(phoneNumber, null, message, sentIntents[0], deliveryIntents[0])
            } else {
                smsManager.sendMultipartTextMessage(phoneNumber, null, parts, sentIntents, deliveryIntents)
            }
            
            Log.d(TAG, "sendTextMessage/sendMultipartTextMessage called, waiting for callbacks...")
            
            // Wait for sent+delivery confirmations in background thread
            Thread {
                try {
                    // First wait for all SENT confirmations (max 15 seconds)
                    val sentCompleted = sentLatch.await(15, TimeUnit.SECONDS)
                    Log.d(TAG, "Sent wait completed: $sentCompleted, sent=${sentCount.get()}/$totalParts, fail=${failCount.get()}")
                    
                    // Check for immediate failures
                    if (failCount.get() > 0 || sentCount.get() < totalParts) {
                        if (resultReported.compareAndSet(false, true)) {
                            val errorMsg = if (!sentCompleted) {
                                "Timeout waiting for SMS to reach carrier"
                            } else {
                                "${failCount.get()} of $totalParts parts failed to send"
                            }
                            Log.d(TAG, "SMS FAILED: $errorMsg")
                            runOnUiThread {
                                result.success(mapOf(
                                    "success" to false,
                                    "error" to errorMsg,
                                    "sentParts" to sentCount.get(),
                                    "delivered" to false
                                ))
                            }
                        }
                        return@Thread
                    }
                    
                    // All parts sent to carrier - now wait for delivery (max 45 seconds)
                    // Delivery reports may take time depending on carrier/network
                    val deliveryCompleted = deliveryLatch.await(45, TimeUnit.SECONDS)
                    Log.d(TAG, "Delivery wait completed: $deliveryCompleted, delivered=${deliveredCount.get()}/$totalParts")
                    
                    if (resultReported.compareAndSet(false, true)) {
                        val allDelivered = deliveredCount.get() == totalParts
                        val success = sentCount.get() == totalParts  // Success if sent, delivery is bonus
                        
                        val statusMsg = when {
                            allDelivered -> null
                            deliveredCount.get() > 0 -> "Partial delivery: ${deliveredCount.get()}/$totalParts confirmed"
                            !deliveryCompleted -> "Sent but delivery reports timed out"
                            else -> "Sent but no delivery confirmation"
                        }
                        
                        Log.d(TAG, "SMS complete: success=$success, delivered=$allDelivered")
                        
                        runOnUiThread {
                            result.success(mapOf(
                                "success" to success,
                                "error" to statusMsg,
                                "sentParts" to sentCount.get(),
                                "deliveredParts" to deliveredCount.get(),
                                "delivered" to allDelivered
                            ))
                        }
                        
                        // Write to sent folder if we're the default SMS app
                        if (success && isDefaultSmsApp()) {
                            writeSmsToSentFolder(phoneNumber, message)
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error waiting for SMS send: ${e.message}")
                    if (resultReported.compareAndSet(false, true)) {
                        runOnUiThread {
                            result.success(mapOf(
                                "success" to false,
                                "error" to "Exception: ${e.message}",
                                "sentParts" to 0,
                                "delivered" to false
                            ))
                        }
                    }
                }
            }.start()
            
        } catch (e: Exception) {
            Log.e(TAG, "sendSmsNative exception: ${e.message}", e)
            result.success(mapOf("success" to false, "error" to "Exception: ${e.message}", "sentParts" to 0, "delivered" to false))
        }
    }
    
    /**
     * Write sent SMS to the SMS content provider (sent folder).
     * This ensures the message appears in the SMS app's sent messages.
     * Only works when we're the default SMS app.
     */
    private fun writeSmsToSentFolder(phoneNumber: String, message: String) {
        try {
            if (!isDefaultSmsApp()) {
                Log.d(TAG, "Not default SMS app, skipping sent folder write")
                return
            }
            
            val values = android.content.ContentValues().apply {
                put(Telephony.Sms.ADDRESS, phoneNumber)
                put(Telephony.Sms.BODY, message)
                put(Telephony.Sms.DATE, System.currentTimeMillis())
                put(Telephony.Sms.READ, 1)
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_SENT)
            }
            
            val uri = contentResolver.insert(Telephony.Sms.Sent.CONTENT_URI, values)
            Log.d(TAG, "Wrote sent SMS to content provider: $uri")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write to sent folder: ${e.message}")
        }
    }
    
    private fun getLastSentMessage(phoneNumber: String): String? {
        try {
            // Normalize phone number - get last 10 digits
            val normalizedTarget = phoneNumber.replace(Regex("[^0-9]"), "").takeLast(10)
            
            val cursor: Cursor? = contentResolver.query(
                Uri.parse("content://sms/sent"),
                arrayOf("address", "body", "date"),
                null,
                null,
                "date DESC LIMIT 20"  // Get last 20 sent messages
            )
            
            cursor?.use {
                while (it.moveToNext()) {
                    val address = it.getString(0) ?: continue
                    val body = it.getString(1) ?: continue
                    
                    // Normalize the address for comparison
                    val normalizedAddr = address.replace(Regex("[^0-9]"), "").takeLast(10)
                    
                    if (normalizedAddr == normalizedTarget) {
                        Log.d(TAG, "Found last sent to $phoneNumber: ${body.take(30)}...")
                        return body
                    }
                }
            }
            
            Log.d(TAG, "No sent messages found for $phoneNumber")
            return null
            
        } catch (e: Exception) {
            Log.e(TAG, "Error getting last sent message: ${e.message}")
            return null
        }
    }
    
    /**
     * SIMPLE SMS sender - just sends the SMS and returns immediately.
     * No delivery confirmation, no waiting - just fire and write to DB.
     */
    private fun sendSmsSimple(phoneNumber: String, message: String, result: MethodChannel.Result) {
        Log.d(TAG, "sendSmsSimple: to=$phoneNumber, msgLen=${message.length}")
        
        if (!hasSmsPermission()) {
            Log.e(TAG, "No SMS permission!")
            result.success(mapOf("success" to false, "error" to "No SMS permission"))
            return
        }
        
        try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            
            // Divide the message if it's too long
            val parts: ArrayList<String> = smsManager.divideMessage(message)
            Log.d(TAG, "Message divided into ${parts.size} parts")
            
            // Send WITHOUT waiting for delivery confirmation
            if (parts.size == 1) {
                smsManager.sendTextMessage(phoneNumber, null, message, null, null)
            } else {
                smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
            }
            
            Log.d(TAG, "SMS sent (no delivery wait)")
            
            // Write to sent folder if we're the default SMS app
            if (isDefaultSmsApp()) {
                writeSmsToSentFolder(phoneNumber, message)
            }
            
            result.success(mapOf("success" to true, "error" to null))
            
        } catch (e: Exception) {
            Log.e(TAG, "sendSmsSimple exception: ${e.message}", e)
            result.success(mapOf("success" to false, "error" to "Exception: ${e.message}"))
        }
    }
}
