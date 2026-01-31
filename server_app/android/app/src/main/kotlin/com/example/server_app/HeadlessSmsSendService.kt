package com.example.server_app

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

/**
 * Required Service for becoming default SMS app.
 * Handles RESPOND_VIA_MESSAGE intent for quick-reply from notifications.
 * 
 * We don't need quick-reply functionality for Himmel's use case,
 * but this service must exist for the app to be eligible as default SMS app.
 */
class HeadlessSmsSendService : Service() {
    private val TAG = "HimmelHeadlessSms"

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "HeadlessSmsSendService started")
        // Quick reply not implemented - just stop service
        stopSelf()
        return START_NOT_STICKY
    }
}
