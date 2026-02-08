
/// Represents a message being reassembled from multiple SMS chunks.
class PartialMessage {
  final String msgId;
  final String sender;
  final int timestamp;
  int maxChunks;
  final Map<int, String> chunks; // index -> payload (1-based)

  PartialMessage({
    required this.msgId,
    required this.sender,
    required this.timestamp,
    this.maxChunks = 1,
  }) : chunks = {};

  void addChunk(int index, int? total, String payload) {
    if (total != null) {
      maxChunks = total;
    }
    chunks[index] = payload;
  }

  bool get isComplete => chunks.length == maxChunks;

  String merge() {
    final sortedIndices = chunks.keys.toList()..sort();
    return sortedIndices.map((i) => chunks[i]).join('');
  }
}

/// Callback type for when a complete message is assembled.
/// Now includes the message ID for matching with sent messages.
typedef OnMessageComplete = void Function(String messageId, String sender, String fullText, int timestamp);

/// Manages incoming SMS chunks and reassembles them into complete messages.
class MessageBuffer {
  final Map<String, PartialMessage> _buffer = {};
  final OnMessageComplete onMessageComplete;

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

      final currentCount = _buffer[msgId]!.chunks.length;
      final totalCount = _buffer[msgId]!.maxChunks;
      print('🧩 Received Chunk $index/$totalCount for ID ${msgId.substring(0, 8)}...');

      // 6. Check Completion
      if (_buffer[msgId]!.isComplete) {
        final fullText = _buffer[msgId]!.merge();
        final msgSender = _buffer[msgId]!.sender;
        final msgTimestamp = _buffer[msgId]!.timestamp;
        
        print('✅ Message ${msgId.substring(0, 8)} Complete! Length: ${fullText.length}');
        
        // Clean up buffer
        _buffer.remove(msgId);
        
        // Notify callback with message ID
        onMessageComplete(msgId, msgSender, fullText, msgTimestamp);
      }

      return msgId;  // Return the message ID for tracking
    } catch (e) {
      print('Error parsing chunk: $e');
      return null;
    }
  }

  /// Check if there are any messages currently being assembled.
  bool get hasPendingMessages => _buffer.isNotEmpty;

  /// Get the number of pending message IDs.
  int get pendingCount => _buffer.length;
  
  /// Check if a specific message ID is being assembled.
  bool hasPendingMessageId(String messageId) => _buffer.containsKey(messageId);

  /// Clear all pending messages.
  void clear() {
    _buffer.clear();
  }
}
