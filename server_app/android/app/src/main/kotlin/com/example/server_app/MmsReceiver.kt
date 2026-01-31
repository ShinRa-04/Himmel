package com.example.server_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Required BroadcastReceiver for becoming default SMS app.
 * Receives incoming MMS messages via WAP_PUSH_DELIVER intent.
 * 
 * We don't need to process MMS for Himmel's use case,
 * but this receiver must exist for the app to be eligible as default SMS app.
 */
class MmsReceiver : BroadcastReceiver() {
    private val TAG = "HimmelMmsReceiver"

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d(TAG, "MMS received via WAP_PUSH_DELIVER")
        // MMS handling not required for Himmel - just acknowledge receipt
    }
}
