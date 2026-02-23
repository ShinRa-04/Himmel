import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:another_telephony/telephony.dart';
import 'simple_sms_sender.dart';

/// Represents a single SMS chunk waiting to be sent
class SmsChunk {
  final String id;        // Message ID (MD5 hash)
  final int index;        // 1-based index
  final int totalChunks;  // Total chunks in this message
  final String content;   // Full SMS content (header + payload)
  final String target;    // Phone number
  bool isSent;
  
  SmsChunk({
    required this.id,
    required this.index,
    required this.totalChunks,
    required this.content,
    required this.target,
    this.isSent = false,
  });
  
  @override
  String toString() => 'Chunk[$index/$totalChunks] id:${id.substring(0, 8)}...';
}

/// Represents a complete message being assembled in the queue
class QueuedMessage {
  final String id;
  final String target;
  final int totalChunks;
  final Map<int, SmsChunk> chunks; // index -> chunk
  final DateTime createdAt;
  bool isComplete;
  bool isSending;
  bool isSent;
  String? error;
  
  QueuedMessage({
    required this.id,
    required this.target,
    required this.totalChunks,
    required this.createdAt,
  }) : chunks = {},
       isComplete = false,
       isSending = false,
       isSent = false;
  
  /// Get chunks sorted by index
  List<SmsChunk> get sortedChunks {
    final sorted = chunks.values.toList();
    sorted.sort((a, b) => a.index.compareTo(b.index));
    return sorted;
  }
}

/// Callback type for queue status updates
typedef QueueStatusCallback = void Function(String status, bool isError);

/// SIMPLIFIED chunk-aware SMS queue
/// - No delivery confirmation waiting
/// - No complex verification loops
/// - Just send SMS and verify in database
class ChunkedSmsQueue {
  static const int MAX_SMS_LENGTH = 160;
  static const Duration CHUNK_SEND_DELAY = Duration(milliseconds: 500); // 500ms between chunks
  
  final Telephony _telephony = Telephony.instance;
  final Map<String, QueuedMessage> _pendingMessages = {};
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  
  QueueStatusCallback? onLog;
  bool _isProcessing = false;
  
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  bool get isProcessing => _isProcessing;
  int get pendingCount => _pendingMessages.values.where((m) => !m.isSent).length;
  
  /// Request SMS permissions
  Future<bool> requestPermissions() async {
    bool? granted = await _telephony.requestPhoneAndSmsPermissions;
    return granted == true;
  }
  
  /// Test sending a simple SMS - just send it, no fancy verification
  Future<bool> testSendSms(String target, String message) async {
    _log("🧪 TEST: Sending SMS to $target");
    _log("🧪 TEST: Message: $message");
    
    // Check permissions first
    final hasPermission = await SimpleSMSSender.hasPermission();
    if (!hasPermission) {
      _log("🧪 TEST: ❌ No SMS permission!", isError: true);
      return false;
    }
    
    // Just send it
    final success = await SimpleSMSSender.sendSms(phoneNumber: target, message: message);
    
    if (success) {
      _log("🧪 TEST: ✅ SMS sent successfully!");
      
      // Give it a moment to appear in DB
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Verify it's in the database
      final inDb = await SimpleSMSSender.verifyInSentDb(target, message);
      _log("🧪 TEST: Database verification: $inDb");
      
      return true;
    } else {
      _log("🧪 TEST: ❌ SMS send failed!", isError: true);
      return false;
    }
  }
  
  /// Queue a full message - it will be chunked and sent
  /// Returns the message ID
  Future<String> queueMessage(String target, String fullText, {String? existingId}) async {
    _log("📥 Queueing message for $target (${fullText.length} chars)");
    
    // Use existing ID if provided, otherwise generate new one
    final String msgId = existingId ?? md5.convert(utf8.encode(fullText + DateTime.now().toIso8601String())).toString();
    _log("📋 Message ID: ${msgId.substring(0, 8)}...");
    
    // Chunk the message
    final chunks = _chunkMessage(fullText, msgId);
    _log("📦 Split into ${chunks.length} chunks");
    
    // Create queued message
    final queuedMessage = QueuedMessage(
      id: msgId,
      target: target,
      totalChunks: chunks.length,
      createdAt: DateTime.now(),
    );
    
    // Add all chunks
    for (int i = 0; i < chunks.length; i++) {
      final index = i + 1;
      queuedMessage.chunks[index] = SmsChunk(
        id: msgId,
        index: index,
        totalChunks: chunks.length,
        content: chunks[i],
        target: target,
      );
    }
    
    queuedMessage.isComplete = true;
    _pendingMessages[msgId] = queuedMessage;
    _notifyStatus();
    
    // Start processing
    _processQueue();
    
    return msgId;
  }
  
  /// Process the queue - send complete messages
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    _notifyStatus();
    
    try {
      while (true) {
        // Find next complete, unsent message
        final readyMessages = _pendingMessages.values
            .where((m) => m.isComplete && !m.isSending && !m.isSent)
            .toList();
        
        if (readyMessages.isEmpty) break;
        
        // Sort by creation time (FIFO)
        readyMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        
        for (final message in readyMessages) {
          await _sendMessage(message);
        }
      }
    } finally {
      _isProcessing = false;
      _notifyStatus();
    }
  }
  
  /// Send a complete message (all chunks in order) - SIMPLE VERSION
  Future<void> _sendMessage(QueuedMessage message) async {
    message.isSending = true;
    _notifyStatus();
    
    _log("📤 Sending ${message.totalChunks} chunks to ${message.target}");
    
    try {
      final sortedChunks = message.sortedChunks;
      int successCount = 0;
      
      for (int i = 0; i < sortedChunks.length; i++) {
        final chunk = sortedChunks[i];
        
        _log("   📤 Chunk ${chunk.index}/${chunk.totalChunks}");
        
        // Simply send the SMS
        final success = await SimpleSMSSender.sendSms(
          phoneNumber: chunk.target,
          message: chunk.content,
        );
        
        if (success) {
          chunk.isSent = true;
          successCount++;
          _log("   ✓ Chunk ${chunk.index} sent!");
          
          // Verify in database
          await Future.delayed(const Duration(milliseconds: 200));
          final inDb = await SimpleSMSSender.verifyInSentDb(chunk.target, chunk.content);
          if (inDb) {
            _log("   ✓ Verified in SMS DB");
          } else {
            _log("   ⚠️ Not found in SMS DB (might still be processing)");
          }
        } else {
          _log("   ✗ Chunk ${chunk.index} FAILED!", isError: true);
        }
        
        _notifyStatus();
        
        // Brief delay between chunks
        if (i < sortedChunks.length - 1) {
          await Future.delayed(CHUNK_SEND_DELAY);
        }
      }
      
      _log("📊 Sent $successCount/${sortedChunks.length} chunks");
      
      message.isSent = (successCount == sortedChunks.length);
      message.isSending = false;
      
      if (message.isSent) {
        _log("✅ Message sent successfully!");
      } else {
        message.error = "${sortedChunks.length - successCount} chunks failed";
        _log("⚠️ Some chunks failed!", isError: true);
      }
      
    } catch (e) {
      message.isSending = false;
      message.error = e.toString();
      _log("❌ Error: $e", isError: true);
    }
    
    _notifyStatus();
  }
  
  /// Chunk a message into SMS-sized parts with protocol headers
  List<String> _chunkMessage(String fullText, String msgId) {
    if (fullText.isEmpty) return [];
    
    // Dry run to get actual chunk count
    List<String> dryRunChunks = _performSplit(fullText, msgId, 99);
    int actualTotal = dryRunChunks.length;
    
    // Real split with correct total
    return _performSplit(fullText, msgId, actualTotal);
  }
  
  List<String> _performSplit(String text, String id, int totalChunks) {
    List<String> chunks = [];
    int cursor = 0;
    int index = 1;
    
    while (cursor < text.length) {
      StringBuffer header = StringBuffer();
      header.write("ID:$id\n");
      if (index == 1) {
        header.write("M:$totalChunks\n");
      }
      header.write("I:$index\n");
      header.write("T:");
      
      String headerStr = header.toString();
      int availableSpace = MAX_SMS_LENGTH - headerStr.length;
      
      if (availableSpace <= 0) {
        throw Exception("Header exceeds SMS limit!");
      }
      
      int remainingChars = text.length - cursor;
      int grab = remainingChars > availableSpace ? availableSpace : remainingChars;
      
      String payload = text.substring(cursor, cursor + grab);
      chunks.add(headerStr + payload);
      
      cursor += grab;
      index++;
    }
    
    return chunks;
  }
  
  void _log(String message, {bool isError = false}) {
    print("ChunkedQueue: $message");
    onLog?.call(message, isError);
  }
  
  void _notifyStatus() {
    final stats = getStats();
    _statusController.add(stats);
  }
  
  /// Get queue statistics
  Map<String, dynamic> getStats() {
    int pending = 0;
    int sending = 0;
    int sent = 0;
    int failed = 0;
    int totalChunks = 0;
    int sentChunks = 0;
    
    for (final msg in _pendingMessages.values) {
      totalChunks += msg.totalChunks;
      sentChunks += msg.chunks.values.where((c) => c.isSent).length;
      
      if (msg.isSent) {
        sent++;
      } else if (msg.error != null) {
        failed++;
      } else if (msg.isSending) {
        sending++;
      } else {
        pending++;
      }
    }
    
    return {
      'pending': pending,
      'sending': sending,
      'sent': sent,
      'failed': failed,
      'totalChunks': totalChunks,
      'sentChunks': sentChunks,
      'isProcessing': _isProcessing,
    };
  }
  
  /// Clear sent messages from memory
  void clearSent() {
    _pendingMessages.removeWhere((_, msg) => msg.isSent);
    _notifyStatus();
  }
  
  /// Clear all messages
  void clearAll() {
    _pendingMessages.clear();
    _notifyStatus();
  }
  
  void dispose() {
    _statusController.close();
  }
}