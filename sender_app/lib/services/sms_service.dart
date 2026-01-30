import 'package:another_telephony/telephony.dart';
import 'chunking_service.dart';

class SmsService {
  final Telephony _telephony = Telephony.instance;
  final ChunkingService _chunker = ChunkingService();

  Future<bool> sendSms(String to, String message) async {
    bool? permissionsGranted = await _telephony.requestPhoneAndSmsPermissions;

    if (permissionsGranted == true) {
      try {
        List<String> chunks = _chunker.chunkMessage(message);
        
        for (String chunk in chunks) {
          await _telephony.sendSms(
            to: to,
            message: chunk,
          );
          // Small delay to ensure order in buffer
          await Future.delayed(const Duration(milliseconds: 300));
        }
        return true;
      } catch (e) {
        print("Error sending SMS: $e");
        return false;
      }
    } else {
      print("SMS Permissions not granted");
      return false;
    }
  }
}

