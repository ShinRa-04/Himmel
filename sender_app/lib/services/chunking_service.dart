import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Result of chunking a message
class ChunkResult {
  final List<String> chunks;
  final String messageId;
  
  ChunkResult({required this.chunks, required this.messageId});
}

class ChunkingService {
  static const int MAX_SMS_LENGTH = 160;

  /// Splits a message into chunks based on the defined protocol.
  /// Returns both the chunks and the message ID for tracking.
  /// Header:
  /// ID: <MD5 Hash>
  /// M: <Total Chunks> (Only in Chunk 1)
  /// I: <Index> (1-based)
  /// T: <Text Payload>
  ChunkResult chunkMessage(String fullText) {
    if (fullText.isEmpty) return ChunkResult(chunks: [], messageId: '');

    // 1. Generate ID (MD5 Hash)
    final String msgId = md5.convert(utf8.encode(fullText)).toString();

    // 2. Pre-calculate estimated chunks (Naive first pass)
    // Minimal headers: ID:32chars\nI:1\nT: -> around 40 chars
    // Payload ~120 chars.
    int estimatedChunks = (fullText.length / 110).ceil();
    if (estimatedChunks == 0) estimatedChunks = 1;

    // We will build chunks dynamically. The "M" variable is tricky because
    // calculating exact split points is circular (headers depend on M and I width).
    // However, given SMS limit 160, headers are relatively small.
    // We will assume 160 limit and fill greedily.
    // The Issue: We need to know "M" for the first chunk BEFORE we finish splitting.
    // Strategy: Split recursively or iteratively with a safety margin.
    
    // Better Strategy:
    // Determine Header function
    // Try to fit content.
    
    // We need to simulate the split to find M first?
    // Actually, "M" is only in the FIRST chunk.
    // So subsequent chunks don't care about M.
    // We can just split the rest and count them + 1.
    // BUT the length of the FIRST chunk's payload depends on the value of M (1 digit vs 2 digits).
    
    // Simplification: Assume M will fit in 2 digits (up to 99 chunks).
    // If it's huge, we handle it.
    
    // Let's do a simulation pass.
    List<String> dryRunChunks = _performSplit(fullText, msgId, 99); // Assume 2-digit M for safety
    int actualTotal = dryRunChunks.length;
    
    // Real pass
    final chunks = _performSplit(fullText, msgId, actualTotal);
    return ChunkResult(chunks: chunks, messageId: msgId);
  }

  List<String> _performSplit(String text, String id, int totalChunks) {
    List<String> chunks = [];
    int cursor = 0;
    int index = 1;
    
    while (cursor < text.length) {
      // Build Header Start
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
        throw Exception("Header exceeds SMS limit! Content cannot be sent.");
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
}
