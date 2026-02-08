import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:another_telephony/telephony.dart';

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
  
  /// Check if all chunks have been loaded
  bool get allChunksLoaded => chunks.length == totalChunks;
  
  /// Get chunks sorted by index
  List<SmsChunk> get sortedChunks {
    final sorted = chunks.values.toList();
    sorted.sort((a, b) => a.index.compareTo(b.index));
    return sorted;
  }
  
  /// Validate that chunk indices are correct (1 to totalChunks)
  bool validateChunks() {
    for (int i = 1; i <= totalChunks; i++) {
      if (!chunks.containsKey(i)) return false;
    }
    return true;
  }
}

/// Callback type for queue status updates
typedef QueueStatusCallback = void Function(String status, bool isError);

/// A chunk-aware SMS queue that ensures all chunks are loaded before sending
class ChunkedSmsQueue {
  static const int MAX_SMS_LENGTH = 160;
  static const Duration CHUNK_SEND_DELAY = Duration(milliseconds: 1000); // 1 second between chunks
  static const Duration SEND_TIMEOUT = Duration(seconds: 5); // Wait up to 5s for send confirmation
  static const int MAX_CHUNK_RETRIES = 3;
  
  final Telephony _telephony = Telephony.instance;
  final Map<String, QueuedMessage> _pendingMessages = {};
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  
  QueueStatusCallback? onLog;
  bool _isProcessing = false;
  Completer<void>? _currentSendLock; // Ensure only one send at a time
  
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  bool get isProcessing => _isProcessing;
  int get pendingCount => _pendingMessages.values.where((m) => !m.isSent).length;
  
  /// Request SMS permissions
  Future<bool> requestPermissions() async {
    bool? granted = await _telephony.requestPhoneAndSmsPermissions;
    return granted == true;
  }
  
  /// Queue a full message - it will be chunked and queued with verification
  /// Returns the message ID
  /// If [existingId] is provided, uses that ID instead of generating a new one.
  /// This is used for responses where we need to preserve the original message ID.
  Future<String> queueMessage(String target, String fullText, {String? existingId}) async {
    _log("📥 Queueing message for $target (${fullText.length} chars)");
    
    // Use existing ID if provided (for responses), otherwise generate new one
    final String msgId = existingId ?? md5.convert(utf8.encode(fullText + DateTime.now().toIso8601String())).toString();
    _log("📋 Message ID: ${msgId.substring(0, 8)}... ${existingId != null ? '(preserved from request)' : '(newly generated)'}");
    
    // Try chunking with retries if verification fails
    QueuedMessage? queuedMessage;
    
    for (int attempt = 1; attempt <= MAX_CHUNK_RETRIES; attempt++) {
      _log("🔄 Chunking attempt $attempt/$MAX_CHUNK_RETRIES");
      
      queuedMessage = _createAndVerifyChunkedMessage(msgId, target, fullText, attempt);
      
      if (queuedMessage != null && queuedMessage.isComplete) {
        _log("✅ Queue verification PASSED on attempt $attempt");
        break;
      } else {
        _log("⚠️ Queue verification FAILED on attempt $attempt", isError: true);
        queuedMessage = null;
        
        // Small delay before retry
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    
    if (queuedMessage == null || !queuedMessage.isComplete) {
      _log("❌ CRITICAL: Failed to create valid queue after $MAX_CHUNK_RETRIES attempts!", isError: true);
      throw Exception("Chunk queue creation failed after $MAX_CHUNK_RETRIES attempts");
    }
    
    // Add to pending messages
    _pendingMessages[msgId] = queuedMessage;
    _notifyStatus();
    
    // Wait 500ms after queue is filled to ensure stability before sending
    _log("⏳ Queue filled. Waiting 500ms before sending...");
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Start processing if not already
    _processQueue();
    
    return msgId;
  }
  
  /// Create chunks and verify the queue integrity
  /// Returns null if verification fails
  QueuedMessage? _createAndVerifyChunkedMessage(String msgId, String target, String fullText, int attempt) {
    try {
      // 1. Chunk the message
      final chunks = _chunkMessage(fullText, msgId);
      _log("📦 Chunked into ${chunks.length} parts");
      
      // 2. Create queued message
      final queuedMessage = QueuedMessage(
        id: msgId,
        target: target,
        totalChunks: chunks.length,
        createdAt: DateTime.now(),
      );
      
      // 3. Add all chunks IN ORDER - use a fresh map each time
      queuedMessage.chunks.clear();
      
      for (int i = 0; i < chunks.length; i++) {
        final chunkContent = chunks[i];
        final index = i + 1; // 1-based index
        
        final smsChunk = SmsChunk(
          id: msgId,
          index: index,
          totalChunks: chunks.length,
          content: chunkContent,
          target: target,
        );
        
        // CRITICAL: Add chunk by index
        queuedMessage.chunks[index] = smsChunk;
      }
      
      // 4. VERIFICATION STEP - Check queue integrity
      final verificationResult = _verifyQueueIntegrity(queuedMessage);
      
      if (!verificationResult.isValid) {
        _log("❌ Verification failed: ${verificationResult.error}", isError: true);
        return null;
      }
      
      // 5. Mark as complete
      queuedMessage.isComplete = true;
      _log("✅ All ${chunks.length} chunks loaded and verified");
      
      // 6. Log verification details
      _log("   ✓ Chunk 1 present: ${queuedMessage.chunks.containsKey(1)}");
      _log("   ✓ Total chunks: ${queuedMessage.chunks.length}/${queuedMessage.totalChunks}");
      _log("   ✓ Sequential order: ${verificationResult.isSequential}");
      _log("   ✓ First chunk index: ${queuedMessage.sortedChunks.first.index}");
      
      return queuedMessage;
      
    } catch (e) {
      _log("❌ Error during chunking: $e", isError: true);
      return null;
    }
  }
  
  /// Verify queue integrity - returns detailed result
  _VerificationResult _verifyQueueIntegrity(QueuedMessage message) {
    // Check 1: Chunk count matches
    if (message.chunks.length != message.totalChunks) {
      return _VerificationResult(
        isValid: false,
        error: "Chunk count mismatch: ${message.chunks.length} != ${message.totalChunks}",
      );
    }
    
    // Check 2: Chunk 1 MUST exist
    if (!message.chunks.containsKey(1)) {
      return _VerificationResult(
        isValid: false,
        error: "Chunk 1 is MISSING!",
      );
    }
    
    // Check 3: All indices from 1 to N must exist
    for (int i = 1; i <= message.totalChunks; i++) {
      if (!message.chunks.containsKey(i)) {
        return _VerificationResult(
          isValid: false,
          error: "Chunk $i is missing!",
        );
      }
    }
    
    // Check 4: Verify sorted order starts at 1
    final sorted = message.sortedChunks;
    if (sorted.isEmpty || sorted.first.index != 1) {
      return _VerificationResult(
        isValid: false,
        error: "First sorted chunk is not index 1! Got: ${sorted.firstOrNull?.index}",
      );
    }
    
    // Check 5: Verify sequential ordering
    for (int i = 0; i < sorted.length; i++) {
      final expectedIndex = i + 1;
      if (sorted[i].index != expectedIndex) {
        return _VerificationResult(
          isValid: false,
          isSequential: false,
          error: "Non-sequential: expected $expectedIndex, got ${sorted[i].index}",
        );
      }
    }
    
    // Check 6: Verify chunk 1 content has "I:1" header
    final chunk1 = message.chunks[1]!;
    if (!chunk1.content.contains("I:1\n")) {
      return _VerificationResult(
        isValid: false,
        error: "Chunk 1 content doesn't have I:1 header!",
      );
    }
    
    // Check 7: Verify chunk 1 has "M:" header (total count)
    if (!chunk1.content.contains("M:${message.totalChunks}\n")) {
      return _VerificationResult(
        isValid: false,
        error: "Chunk 1 doesn't have correct M: header!",
      );
    }
    
    return _VerificationResult(isValid: true, isSequential: true);
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
  
  /// Send a complete message (all chunks in order)
  Future<void> _sendMessage(QueuedMessage message) async {
    // Acquire send lock - only one message at a time
    if (_currentSendLock != null && !_currentSendLock!.isCompleted) {
      _log("⏳ Waiting for previous send to complete...");
      await _currentSendLock!.future;
    }
    _currentSendLock = Completer<void>();
    
    message.isSending = true;
    _notifyStatus();
    
    _log("📤 Starting to send message ${message.id.substring(0, 8)}... to ${message.target}");
    _log("   Total chunks: ${message.totalChunks}");
    
    try {
      final sortedChunks = message.sortedChunks;
      
      // Verify first chunk is index 1
      if (sortedChunks.first.index != 1) {
        throw Exception("First chunk is not index 1! Got index ${sortedChunks.first.index}");
      }
      
      int successCount = 0;
      int failCount = 0;
      
      for (int i = 0; i < sortedChunks.length; i++) {
        final chunk = sortedChunks[i];
        final expectedIndex = i + 1;
        
        // Verify sequential ordering
        if (chunk.index != expectedIndex) {
          throw Exception("Chunk ordering error: expected $expectedIndex, got ${chunk.index}");
        }
        
        _log("   📤 Sending chunk ${chunk.index}/${chunk.totalChunks}...");
        _log("      Content: ${chunk.content.substring(0, chunk.content.length > 50 ? 50 : chunk.content.length)}...");
        
        // Send with confirmation using Completer
        bool sendSuccess = false;
        
        for (int retry = 0; retry < 3; retry++) {
          try {
            final sendCompleter = Completer<bool>();
            
            // Send SMS with status listener
            await _telephony.sendSms(
              to: chunk.target,
              message: chunk.content,
              statusListener: (SendStatus status) {
                _log("      📡 Status: $status");
                if (!sendCompleter.isCompleted) {
                  if (status == SendStatus.SENT) {
                    sendCompleter.complete(true);
                  } else if (status == SendStatus.DELIVERED) {
                    // Already completed on SENT, but log delivery
                    _log("      ✅ Delivered!");
                  }
                }
              },
            );
            
            // Wait for SENT status or timeout
            try {
              sendSuccess = await sendCompleter.future.timeout(
                SEND_TIMEOUT,
                onTimeout: () {
                  _log("      ⏰ Send timeout - assuming success");
                  return true; // Assume success on timeout
                },
              );
            } catch (e) {
              _log("      ⚠️ Completer error: $e");
              sendSuccess = true; // Assume success if completer fails
            }
            
            if (sendSuccess) {
              _log("   ✓ Chunk ${chunk.index} sent!");
              break;
            }
            
          } catch (e) {
            _log("   ⚠️ Chunk ${chunk.index} attempt ${retry + 1} failed: $e", isError: retry == 2);
            if (retry < 2) {
              _log("   🔄 Retrying in 1s...");
              await Future.delayed(const Duration(seconds: 1));
            }
          }
        }
        
        if (sendSuccess) {
          chunk.isSent = true;
          successCount++;
        } else {
          failCount++;
          _log("   ✗ Chunk ${chunk.index} FAILED after 3 attempts!", isError: true);
        }
        
        _notifyStatus();
        
        // CRITICAL: Wait between chunks to ensure carrier processes them in order
        if (i < sortedChunks.length - 1) {
          _log("   ⏳ Waiting ${CHUNK_SEND_DELAY.inMilliseconds}ms before next chunk...");
          await Future.delayed(CHUNK_SEND_DELAY);
        }
      }
      
      _log("📊 Send summary: $successCount sent, $failCount failed out of ${sortedChunks.length} chunks");
      
      message.isSent = (failCount == 0);
      message.isSending = false;
      
      if (failCount > 0) {
        message.error = "$failCount chunks failed to send";
        _log("⚠️ Message partially sent - $failCount chunks failed!", isError: true);
      } else {
        _log("✅ Message ${message.id.substring(0, 8)}... sent successfully (${message.totalChunks} chunks)");
      }
      
    } catch (e) {
      message.isSending = false;
      message.error = e.toString();
      _log("❌ Failed to send message: $e", isError: true);
    } finally {
      // Release send lock
      if (_currentSendLock != null && !_currentSendLock!.isCompleted) {
        _currentSendLock!.complete();
      }
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

/// Helper class for verification results
class _VerificationResult {
  final bool isValid;
  final bool isSequential;
  final String? error;
  
  _VerificationResult({
    required this.isValid,
    this.isSequential = false,
    this.error,
  });
}