package com.example.server_app

import android.app.Activity
import android.app.role.RoleManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Telephony
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val TAG = "HimmelServer"
    private val CHANNEL = "com.example.server_app/intent"
    private var pendingTarget: String? = null
    private var pendingMessage: String? = null
    private var methodChannel: MethodChannel? = null
    private var pendingDefaultSmsResult: MethodChannel.Result? = null
    
    companion object {
        private const val REQUEST_DEFAULT_SMS = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine called")
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d(TAG, "MethodChannel call: ${call.method}")
            when (call.method) {
                "getIntent" -> {
                    Log.d(TAG, "getIntent called - pending: target=$pendingTarget, msgLen=${pendingMessage?.length ?: 0}")
                    if (pendingTarget != null && pendingMessage != null) {
                        val data = mapOf(
                            "target" to pendingTarget,
                            "message" to pendingMessage
                        )
                        // Clear after reading
                        val savedTarget = pendingTarget
                        val savedMsgLen = pendingMessage?.length
                        pendingTarget = null
                        pendingMessage = null
                        Log.d(TAG, "Returning intent data: target=$savedTarget, msgLen=$savedMsgLen")
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
        Log.d(TAG, "onNewIntent called")
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        Log.d(TAG, "handleIntent called, intent=$intent")
        intent?.let {
            val target = it.getStringExtra("target")
            Log.d(TAG, "Intent target: $target")
            
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
                Log.d(TAG, "Valid payload received! Setting pending data.")
                pendingTarget = target
                pendingMessage = message
                
                // If Flutter engine is ready, send immediately via method channel
                // and clear pending data to prevent duplicate processing
                if (methodChannel != null) {
                    Log.d(TAG, "Invoking handleIntent on Flutter side")
                    // Clear pending BEFORE invoking to prevent getIntent from returning same data
                    pendingTarget = null
                    pendingMessage = null
                    methodChannel?.invokeMethod("handleIntent", mapOf(
                        "target" to target,
                        "message" to message
                    ))
                } else {
                    Log.d(TAG, "Method channel not ready, data stored for getIntent")
                }
            } else {
                Log.d(TAG, "Invalid payload: target=$target, msgLen=${message?.length ?: 0}")
            }
        }
    }
}
