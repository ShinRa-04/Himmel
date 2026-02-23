import 'package:flutter/services.dart';

/// Simple SMS sender - just sends the SMS and checks the database.
/// No delivery confirmation, no retries, no complex verification.
class SimpleSMSSender {
  static const MethodChannel _channel = MethodChannel('com.himmel.sms/sender');
  
  /// Send an SMS message directly. Returns true if sent successfully.
  /// Does NOT wait for delivery confirmation - just fires and checks DB.
  static Future<bool> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('sendSmsSimple', {
        'phoneNumber': phoneNumber,
        'message': message,
      });
      
      return result?['success'] == true;
    } on PlatformException catch (e) {
      print('SimpleSMSSender: Platform error: ${e.message}');
      return false;
    } catch (e) {
      print('SimpleSMSSender: Error: $e');
      return false;
    }
  }
  
  /// Check if a message exists in the sent SMS database.
  static Future<bool> verifyInSentDb(String phoneNumber, String message) async {
    try {
      final lastMessage = await _channel.invokeMethod<String?>('getLastSentMessage', {
        'phoneNumber': phoneNumber,
      });
      
      return lastMessage == message;
    } catch (e) {
      print('SimpleSMSSender: Error checking DB: $e');
      return false;
    }
  }
  
  /// Check if we have SMS permission.
  static Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
