import 'dart:async';
import 'package:flutter/services.dart';

/// Result of an SMS send operation with delivery confirmation.
class SmsSendResult {
  final bool success;
  final bool delivered;
  final int sentParts;
  final int deliveredParts;
  final String? error;
  
  SmsSendResult({
    required this.success,
    this.delivered = false,
    this.sentParts = 0,
    this.deliveredParts = 0,
    this.error,
  });
  
  factory SmsSendResult.fromMap(Map<String, dynamic> map) {
    return SmsSendResult(
      success: map['success'] ?? false,
      delivered: map['delivered'] ?? false,
      sentParts: map['sentParts'] ?? 0,
      deliveredParts: map['deliveredParts'] ?? 0,
      error: map['error'],
    );
  }
  
  @override
  String toString() => 'SmsSendResult(success: $success, delivered: $delivered, '
      'sent: $sentParts, deliveredParts: $deliveredParts, error: $error)';
}

/// Native SMS sender using Android's SmsManager via platform channel.
/// This is more reliable than the another_telephony package.
/// 
/// Features:
/// - Delivery confirmation via delivery intents
/// - Proper multipart message handling
/// - Automatic write to sent folder (when default SMS app)
class NativeSmsSender {
  static const MethodChannel _channel = MethodChannel('com.himmel.sms/sender');
  
  /// Send an SMS message directly using Android's SmsManager with delivery confirmation.
  /// Returns a SmsSendResult with both sent and delivery status.
  /// 
  /// The 'success' field indicates the message was handed to the carrier.
  /// The 'delivered' field indicates the message reached the recipient (most reliable).
  static Future<SmsSendResult> sendSmsWithDelivery({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('sendSms', {
        'phoneNumber': phoneNumber,
        'message': message,
      });
      
      return SmsSendResult(
        success: result?['success'] ?? false,
        delivered: result?['delivered'] ?? false,
        sentParts: result?['sentParts'] ?? 0,
        deliveredParts: result?['deliveredParts'] ?? 0,
        error: result?['error']?.toString(),
      );
    } on PlatformException catch (e) {
      return SmsSendResult(
        success: false,
        error: 'Platform error: ${e.message}',
      );
    } catch (e) {
      return SmsSendResult(
        success: false,
        error: 'Unknown error: $e',
      );
    }
  }
  
  /// Send an SMS message directly using Android's SmsManager.
  /// Returns a map with 'success' (bool) and 'error' (String?) keys.
  /// @deprecated Use sendSmsWithDelivery for better reliability.
  static Future<Map<String, dynamic>> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('sendSms', {
        'phoneNumber': phoneNumber,
        'message': message,
      });
      
      return {
        'success': result?['success'] ?? false,
        'error': result?['error'],
        'sentParts': result?['sentParts'] ?? 0,
        'delivered': result?['delivered'] ?? false,
        'deliveredParts': result?['deliveredParts'] ?? 0,
      };
    } on PlatformException catch (e) {
      return {
        'success': false,
        'error': 'Platform error: ${e.message}',
        'sentParts': 0,
        'delivered': false,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Unknown error: $e',
        'sentParts': 0,
        'delivered': false,
      };
    }
  }
  
  /// Check if we have SMS send permission.
  static Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
  
  /// Request SMS permission.
  static Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
  
  /// Get the last sent SMS to a specific number.
  /// Returns the message body or null if not found.
  static Future<String?> getLastSentMessage(String phoneNumber) async {
    try {
      final result = await _channel.invokeMethod<String?>('getLastSentMessage', {
        'phoneNumber': phoneNumber,
      });
      return result;
    } catch (e) {
      return null;
    }
  }
}
