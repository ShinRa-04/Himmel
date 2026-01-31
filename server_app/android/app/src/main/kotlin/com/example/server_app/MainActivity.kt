package com.example.server_app

import android.content.Intent
import android.os.Bundle
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
                else -> result.notImplemented()
            }
        }
        
        // Process initial intent
        Log.d(TAG, "Processing initial intent")
        handleIntent(intent)
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
                Log.d(TAG, "Invoking handleIntent on Flutter side")
                methodChannel?.invokeMethod("handleIntent", mapOf(
                    "target" to target,
                    "message" to message
                ))
            } else {
                Log.d(TAG, "Invalid payload: target=$target, msgLen=${message?.length ?: 0}")
            }
        }
    }
}
