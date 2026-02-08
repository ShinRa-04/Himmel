import 'package:another_telephony/telephony.dart';
import 'message_buffer.dart';

/// Callback for when a complete message is received.
/// Now includes the message ID for matching with sent messages.
typedef OnCompleteMessageReceived = void Function(String messageId, String sender, String message);

/// Callback for when a chunk is received (for UI feedback).
/// Now includes the message ID being assembled.
typedef OnChunkReceived = void Function(String messageId, String sender, int current, int total);

/// Service that listens for incoming SMS messages and reassembles chunked messages.
class SmsListenerService {
  final Telephony _telephony = Telephony.instance;
  late final MessageBuffer _messageBuffer;
  
  OnCompleteMessageReceived? onCompleteMessage;
  OnChunkReceived? onChunkReceived;
  
  /// The phone number we're expecting messages from (the server phone).
  String? _expectedSender;
  
  bool _isListening = false;

  SmsListenerService() {
    _messageBuffer = MessageBuffer(
      onMessageComplete: _handleMessageComplete,
    );
  }

  /// Called when a complete message is assembled.
  void _handleMessageComplete(String messageId, String sender, String fullText, int timestamp) {
    print('📬 Complete message from $sender with ID ${messageId.substring(0, 8)}: ${fullText.length} chars');
    onCompleteMessage?.call(messageId, sender, fullText);
  }

  /// Start listening for incoming SMS from a specific sender.
  Future<void> startListening({String? expectedSender}) async {
    if (_isListening) {
      print('⚠️ SMS Listener already active');
      return;
    }
    
    _expectedSender = expectedSender;
    
    // Request permissions
    bool? permissionsGranted = await _telephony.requestPhoneAndSmsPermissions;
    
    if (permissionsGranted != true) {
      print('❌ SMS permissions not granted');
      return;
    }
    print('✅ SMS permissions granted');

    // Listen to incoming SMS
    _telephony.listenIncomingSms(
      onNewMessage: _onSmsReceived,
      onBackgroundMessage: _onBackgroundSmsReceived,
      listenInBackground: true,
    );
    
    _isListening = true;
    print('👂 SMS Listener started${_expectedSender != null ? " for $_expectedSender" : ""}');
    print('   Waiting for protocol messages (ID:, I:, T:)...');
  }

  /// Stop listening for SMS.
  void stopListening() {
    _isListening = false;
    _messageBuffer.clear();
    print('🛑 SMS Listener stopped');
  }

  /// Update the expected sender phone number.
  void setExpectedSender(String? sender) {
    _expectedSender = sender;
  }

  /// Handle incoming SMS message.
  void _onSmsReceived(SmsMessage message) {
    final sender = message.address ?? 'Unknown';
    final body = message.body ?? '';
    final timestamp = message.date ?? DateTime.now().millisecondsSinceEpoch;

    print('');
    print('========================================');
    print('📩 INCOMING SMS DETECTED!');
    print('   From: $sender');
    print('   Length: ${body.length} chars');
    print('   Content: ${body.length > 80 ? "${body.substring(0, 80)}..." : body}');
    print('   Expected sender: $_expectedSender');
    print('========================================');

    // Filter by expected sender if set
    if (_expectedSender != null && !_isSameSender(sender, _expectedSender!)) {
      print('⏭️ Ignoring SMS - sender mismatch');
      print('   Got: $sender');
      print('   Expected: $_expectedSender');
      return;
    }

    // Check if it looks like a protocol message
    final hasId = body.contains('ID:');
    final hasIndex = body.contains('I:');
    final hasPayload = body.contains('T:');
    print('📋 Protocol check: ID=$hasId, I=$hasIndex, T=$hasPayload');

    // Try to process as a protocol message
    final messageId = _messageBuffer.processIncomingSms(sender, body, timestamp);
    
    if (messageId != null) {
      print('✅ Processed as protocol message with ID: ${messageId.substring(0, 8)}...');
      // Notify about chunk received for UI feedback
      _notifyChunkReceived(messageId, sender, body);
    } else {
      print('⏭️ Not a protocol message, ignoring');
    }
  }

  /// Check if two phone numbers are the same (handles formatting differences).
  bool _isSameSender(String sender1, String sender2) {
    // Remove all non-digit characters for comparison
    final clean1 = sender1.replaceAll(RegExp(r'\D'), '');
    final clean2 = sender2.replaceAll(RegExp(r'\D'), '');
    
    // Check if one ends with the other (handles country codes)
    return clean1.endsWith(clean2) || clean2.endsWith(clean1) || clean1 == clean2;
  }

  /// Extract chunk info for UI notification.
  void _notifyChunkReceived(String messageId, String sender, String content) {
    if (onChunkReceived == null) return;
    
    final idMatch = RegExp(r'ID:([a-fA-F0-9]+)').firstMatch(content);
    final idxMatch = RegExp(r'I:(\d+)').firstMatch(content);
    final totalMatch = RegExp(r'M:(\d+)').firstMatch(content);
    
    final index = idxMatch != null ? int.parse(idxMatch.group(1)!) : 1;
    final total = totalMatch != null ? int.parse(totalMatch.group(1)!) : 1;
    
    onChunkReceived!(messageId, sender, index, total);
  }

  /// Check if there are messages being assembled.
  bool get hasPendingMessages => _messageBuffer.hasPendingMessages;
}

/// Background message handler (must be a top-level function).
@pragma('vm:entry-point')
void _onBackgroundSmsReceived(SmsMessage message) {
  // Background handling - for now just log
  print('📩 [BG] SMS from ${message.address}: ${message.body?.substring(0, 30)}...');
}
