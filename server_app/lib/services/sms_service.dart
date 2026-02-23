import 'package:another_telephony/telephony.dart';
import 'chunking_service.dart';

class SmsService {
  final Telephony _telephony = Telephony.instance;
  final ChunkingService _chunker = ChunkingService();

  /// Request permissions - call this once during app init
  Future<bool> requestPermissions() async {
    bool? granted = await _telephony.requestPhoneAndSmsPermissions;
    return granted == true;
  }

  /// Send SMS with chunking - assumes permissions are already granted
  Future<bool> sendSms(String to, String message) async {
    try {
      List<String> chunks = _chunker.chunkMessage(message);
      print("📦 Chunking message into ${chunks.length} parts");
      
      for (int i = 0; i < chunks.length; i++) {
        String chunk = chunks[i];
        print("📤 Sending chunk ${i + 1}/${chunks.length} (${chunk.length} chars)");
        
        await _telephony.sendSms(
          to: to,
          message: chunk,
        );
        
        // Delay between chunks to ensure ordering
        if (i < chunks.length - 1) {
          await Future.delayed(const Duration(milliseconds: 1200));
        }
      }
      
      print("✅ All ${chunks.length} chunks sent successfully");
      return true;
    } catch (e) {
      print("❌ Error sending SMS: $e");
      return false;
    }
  }
}
