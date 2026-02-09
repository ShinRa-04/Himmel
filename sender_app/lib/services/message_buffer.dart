import 'dart:async';

/// Represents a message being reassembled from multiple SMS chunks.
class PartialMessage {
  final String msgId;
  final String sender;
  final int timestamp;
  int? maxChunks; // null if unknown (chunk 1 missing)
  final Map<int, String> chunks; // index -> payload (1-based)
  DateTime lastChunkTime;

  PartialMessage({
    required this.msgId,
    required this.sender,
    required this.timestamp,
    this.maxChunks,
  }) : chunks = {},
       lastChunkTime = DateTime.now();

  void addChunk(int index, int? total, String payload) {
    if (total != null && (maxChunks == null || total > maxChunks!)) {
      maxChunks = total;
    }
    chunks[index] = payload;
    lastChunkTime = DateTime.now();
  }

  /// Number of chunks received so far
  int get receivedCount => chunks.length;
  
  /// Highest chunk index we've seen
  int get highestIndex => chunks.keys.isEmpty ? 0 : chunks.keys.reduce((a, b) => a > b ? a : b);

  /// Check if complete (all chunks received)
  bool get isComplete => maxChunks != null && chunks.length == maxChunks;

  /// Merge available chunks, skipping missing ones
  String merge() {
    // Determine the range of chunks to merge
    final maxIdx = maxChunks ?? highestIndex;
    final buffer = StringBuffer();
    
    for (int i = 1; i <= maxIdx; i++) {
      if (chunks.containsKey(i)) {
        buffer.write(chunks[i]);
      } else {
        // Missing chunk - add placeholder or skip
        print('⚠️ Missing chunk $i, skipping');
      }
    }
    return buffer.toString();
  }
}

/// Callback type for when a complete message is assembled.
/// Now includes the message ID for matching with sent messages.
typedef OnMessageComplete = void Function(String messageId, String sender, String fullText, int timestamp);

/// Callback for chunk progress updates.
/// Provides: messageId, sender, receivedCount, expectedTotal (null if unknown)
typedef OnChunkProgress = void Function(String messageId, String sender, int received, int? total);

/// Manages incoming SMS chunks and reassembles them into complete messages.
class MessageBuffer {
  static const Duration CHUNK_TIMEOUT = Duration(milliseconds: 2000);
  
  final Map<String, PartialMessage> _buffer = {};
  final Map<String, Timer> _timeoutTimers = {};
  final OnMessageComplete onMessageComplete;
  OnChunkProgress? onChunkProgress;

  MessageBuffer({required this.onMessageComplete});

  /// Process an incoming SMS and check if it's part of our protocol.
  /// Returns the message ID if processed, null if not a protocol message.
  String? processIncomingSms(String sender, String content, int timestamp) {
    try {
      // Protocol: ID:<id>\n[M:<total>\n]I:<index>\nT:<payload>

      // 1. Extract ID
      final idMatch = RegExp(r'ID:([a-fA-F0-9]+)').firstMatch(content);
      if (idMatch == null) {
        // Not a protocol message
        return null;
      }
      final msgId = idMatch.group(1)!;

      // 2. Extract Index
      final idxMatch = RegExp(r'I:(\d+)').firstMatch(content);
      final index = idxMatch != null ? int.parse(idxMatch.group(1)!) : 1;

      // 3. Extract Total (Optional, usually in chunk 1)
      final totalMatch = RegExp(r'M:(\d+)').firstMatch(content);
      final total = totalMatch != null ? int.parse(totalMatch.group(1)!) : null;

      // 4. Extract Payload (Everything after T:)
      final payloadMatch = RegExp(r'T:(.*)', dotAll: true).firstMatch(content);
      final payload = payloadMatch != null ? payloadMatch.group(1)! : '';

      // 5. Buffer Logic
      if (!_buffer.containsKey(msgId)) {
        _buffer[msgId] = PartialMessage(
          msgId: msgId,
          sender: sender,
          timestamp: timestamp,
        );
      }

      _buffer[msgId]!.addChunk(index, total, payload);

      final receivedCount = _buffer[msgId]!.receivedCount;
      final expectedTotal = _buffer[msgId]!.maxChunks;
      print('🧩 Received Chunk $index (${receivedCount}/${expectedTotal ?? "?"}) for ID ${msgId.substring(0, 8)}...');

      // Notify progress callback
      onChunkProgress?.call(msgId, sender, receivedCount, expectedTotal);

      // Reset/start timeout timer
      _resetTimeout(msgId);

      // 6. Check Completion
      if (_buffer[msgId]!.isComplete) {
        _finalizeMessage(msgId);
      }

      return msgId;  // Return the message ID for tracking
    } catch (e) {
      print('Error parsing chunk: $e');
      return null;
    }
  }

  /// Reset/start the timeout timer for a message
  void _resetTimeout(String msgId) {
    _timeoutTimers[msgId]?.cancel();
    _timeoutTimers[msgId] = Timer(CHUNK_TIMEOUT, () {
      _handleTimeout(msgId);
    });
  }

  /// Handle timeout - finalize message with whatever chunks we have
  void _handleTimeout(String msgId) {
    if (!_buffer.containsKey(msgId)) return;
    
    final msg = _buffer[msgId]!;
    print('⏰ Timeout for message ${msgId.substring(0, 8)}... - finalizing with ${msg.receivedCount} chunks');
    _finalizeMessage(msgId);
  }

  /// Finalize and deliver a message
  void _finalizeMessage(String msgId) {
    if (!_buffer.containsKey(msgId)) return;
    
    final msg = _buffer[msgId]!;
    final fullText = msg.merge();
    
    print('✅ Message ${msgId.substring(0, 8)} finalized! Received: ${msg.receivedCount}/${msg.maxChunks ?? "?"}, Length: ${fullText.length}');
    
    // Cancel timeout timer
    _timeoutTimers[msgId]?.cancel();
    _timeoutTimers.remove(msgId);
    
    // Clean up buffer
    _buffer.remove(msgId);
    
    // Notify callback with message ID
    onMessageComplete(msgId, msg.sender, fullText, msg.timestamp);
  }

  /// Check if there are any messages currently being assembled.
  bool get hasPendingMessages => _buffer.isNotEmpty;

  /// Get the number of pending message IDs.
  int get pendingCount => _buffer.length;
  
  /// Check if a specific message ID is being assembled.
  bool hasPendingMessageId(String messageId) => _buffer.containsKey(messageId);
  
  /// Get progress info for a specific message
  (int received, int? total)? getProgress(String messageId) {
    final msg = _buffer[messageId];
    if (msg == null) return null;
    return (msg.receivedCount, msg.maxChunks);
  }

  /// Clear all pending messages.
  void clear() {
    for (final timer in _timeoutTimers.values) {
      timer.cancel();
    }
    _timeoutTimers.clear();
    _buffer.clear();
  }
}
