import 'package:another_telephony/telephony.dart';
import 'chunking_service.dart';

/// Result of sending an SMS
class SmsSendResult {
  final bool success;
  final String? messageId;  // The ID used for this message (for matching responses)
  final String? error;
  
  SmsSendResult({required this.success, this.messageId, this.error});
}

class SmsService {
  final Telephony _telephony = Telephony.instance;
  final ChunkingService _chunker = ChunkingService();

  /// Send an SMS and return the result including the message ID.
  Future<SmsSendResult> sendSms(String to, String message) async {
    bool? permissionsGranted = await _telephony.requestPhoneAndSmsPermissions;

    if (permissionsGranted == true) {
      try {
        // Get chunks and the message ID
        final result = _chunker.chunkMessage(message);
        final chunks = result.chunks;
        final messageId = result.messageId;
        
        print('📤 Sending message with ID: ${messageId.substring(0, 8)}...');
        print('   Total chunks: ${chunks.length}');
        
        for (int i = 0; i < chunks.length; i++) {
          print('   Sending chunk ${i + 1}/${chunks.length}...');
          await _telephony.sendSms(
            to: to,
            message: chunks[i],
          );
          // Small delay to ensure order in buffer
          if (i < chunks.length - 1) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
        
        print('✅ All chunks sent for message ${messageId.substring(0, 8)}');
        return SmsSendResult(success: true, messageId: messageId);
      } catch (e) {
        print("❌ Error sending SMS: $e");
        return SmsSendResult(success: false, error: e.toString());
      }
    } else {
      print("❌ SMS Permissions not granted");
      return SmsSendResult(success: false, error: "Permissions not granted");
    }
  }
}

