import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'sms_queue_monitor.dart';

/// Configuration for the PC backend connection.
class BackendConfig {
  final String host;
  final int port;
  
  BackendConfig({
    this.host = '192.168.1.100', // Default - should be configured
    this.port = 8000,
  });
  
  String get baseUrl => 'http://$host:$port';
  String get chunkEndpoint => '$baseUrl/api/chunk';
  String get resultEndpoint => '$baseUrl/api/result';
}

/// Response from the backend after submitting a chunk.
class ChunkResponse {
  final bool success;
  final String? messageId;
  final bool isComplete;
  final String? error;
  
  ChunkResponse({
    required this.success,
    this.messageId,
    this.isComplete = false,
    this.error,
  });
}

/// Response from polling for a result.
class ResultResponse {
  final String status; // "Processing", "Completed", "Error"
  final String? content;
  final String? sender;
  final String? error;
  
  ResultResponse({
    required this.status,
    this.content,
    this.sender,
    this.error,
  });
  
  bool get isCompleted => status == 'Completed';
  bool get isProcessing => status == 'Processing';
  bool get isError => status == 'Error';
}

/// Callback when a complete response is received from the backend.
typedef OnResponseReady = void Function(String sender, String responseText);

/// Service that forwards SMS chunks to the PC backend and polls for responses.
class BackendForwarder {
  BackendConfig config;
  
  // Track messages we're waiting for responses on
  final Map<String, _PendingResponse> _pendingResponses = {};
  Timer? _pollTimer;
  
  OnResponseReady? onResponseReady;
  void Function(String message, bool isError)? onLog;
  
  BackendForwarder({BackendConfig? config}) 
      : config = config ?? BackendConfig();
  
  /// Update the backend configuration.
  void updateConfig(String host, int port) {
    config = BackendConfig(host: host, port: port);
    _log('🔧 Backend config updated: ${config.baseUrl}');
  }
  
  /// Forward a raw SMS chunk to the backend.
  /// The backend will handle reassembly.
  Future<ChunkResponse> forwardChunk(IncomingSms sms) async {
    try {
      _log('📤 Forwarding chunk to backend...');
      
      final response = await http.post(
        Uri.parse(config.chunkEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender': sms.sender,
          'content': sms.body,
          'timestamp': sms.timestamp,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messageId = data['message_id'] as String?;
        final isComplete = data['is_complete'] as bool? ?? false;
        
        _log('✅ Chunk forwarded. ID: ${messageId?.substring(0, 8)}..., Complete: $isComplete');
        
        // If this message is now complete, start polling for result
        if (isComplete && messageId != null) {
          _startPollingForResult(messageId, sms.sender);
        }
        
        return ChunkResponse(
          success: true,
          messageId: messageId,
          isComplete: isComplete,
        );
      } else {
        _log('❌ Backend error: ${response.statusCode} - ${response.body}', isError: true);
        return ChunkResponse(
          success: false,
          error: 'HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      _log('❌ Failed to forward chunk: $e', isError: true);
      return ChunkResponse(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Start polling for a result from the backend.
  void _startPollingForResult(String messageId, String sender) {
    _log('⏳ Waiting for response for message ${messageId.substring(0, 8)}...');
    
    _pendingResponses[messageId] = _PendingResponse(
      messageId: messageId,
      sender: sender,
      startedAt: DateTime.now(),
    );
    
    // Start the poll timer if not already running
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollPendingResults(),
    );
  }
  
  /// Poll all pending results.
  Future<void> _pollPendingResults() async {
    if (_pendingResponses.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    
    final toRemove = <String>[];
    
    for (final entry in _pendingResponses.entries) {
      final messageId = entry.key;
      final pending = entry.value;
      
      // Check for timeout (5 minutes)
      if (DateTime.now().difference(pending.startedAt).inMinutes > 5) {
        _log('⏰ Timeout waiting for response: ${messageId.substring(0, 8)}', isError: true);
        toRemove.add(messageId);
        continue;
      }
      
      try {
        final result = await _pollResult(messageId);
        
        if (result.isCompleted && result.content != null) {
          _log('📬 Response ready for ${messageId.substring(0, 8)}!');
          onResponseReady?.call(pending.sender, result.content!);
          toRemove.add(messageId);
        } else if (result.isError) {
          _log('❌ Backend error for ${messageId.substring(0, 8)}: ${result.error}', isError: true);
          toRemove.add(messageId);
        }
        // If still processing, continue polling
      } catch (e) {
        _log('⚠️ Poll error: $e', isError: true);
      }
    }
    
    // Clean up completed/failed requests
    for (final id in toRemove) {
      _pendingResponses.remove(id);
    }
  }
  
  /// Poll for a single result.
  Future<ResultResponse> _pollResult(String messageId) async {
    try {
      final response = await http.get(
        Uri.parse('${config.resultEndpoint}/$messageId'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ResultResponse(
          status: data['status'] as String? ?? 'Unknown',
          content: data['content'] as String?,
          sender: data['sender'] as String?,
        );
      } else if (response.statusCode == 404) {
        return ResultResponse(status: 'Processing');
      } else {
        return ResultResponse(
          status: 'Error',
          error: 'HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return ResultResponse(
        status: 'Error',
        error: e.toString(),
      );
    }
  }
  
  /// Stop all polling.
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pendingResponses.clear();
  }
  
  void _log(String message, {bool isError = false}) {
    onLog?.call(message, isError);
  }
}

class _PendingResponse {
  final String messageId;
  final String sender;
  final DateTime startedAt;
  
  _PendingResponse({
    required this.messageId,
    required this.sender,
    required this.startedAt,
  });
}
