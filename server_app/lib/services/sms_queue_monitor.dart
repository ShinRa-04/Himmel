import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Represents an incoming SMS message from the native queue.
class IncomingSms {
  final String sender;
  final String body;
  final int timestamp;
  final String filename;

  IncomingSms({
    required this.sender,
    required this.body,
    required this.timestamp,
    required this.filename,
  });

  factory IncomingSms.fromJson(Map<String, dynamic> json, String filename) {
    return IncomingSms(
      sender: json['sender'] as String,
      body: json['body'] as String,
      timestamp: json['timestamp'] as int,
      filename: filename,
    );
  }

  @override
  String toString() => 'SMS from $sender at $timestamp: ${body.substring(0, body.length > 30 ? 30 : body.length)}...';
}

/// Callback when a protocol SMS is received.
typedef OnSmsReceived = void Function(IncomingSms sms);

/// Service that monitors the SMS queue directory for incoming protocol messages.
/// The native SmsReceiver writes JSON files to this directory.
class SmsQueueMonitor {
  static const Duration _pollInterval = Duration(milliseconds: 500);
  
  Timer? _pollTimer;
  bool _isRunning = false;
  
  // Track files we've already notified about (to avoid duplicate notifications)
  // The actual file deletion is done by the PC's ADB bridge
  final Set<String> _seenFiles = {};
  
  OnSmsReceived? onSmsReceived;
  void Function(String message, bool isError)? onLog;
  
  /// Start monitoring the SMS queue directory.
  void start() {
    if (_isRunning) return;
    
    _isRunning = true;
    _seenFiles.clear();
    _log('👂 SMS Queue Monitor started');
    
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkQueue());
  }
  
  /// Stop monitoring.
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isRunning = false;
    _seenFiles.clear();
    _log('🛑 SMS Queue Monitor stopped');
  }
  
  /// Check the queue directory for new SMS files.
  Future<void> _checkQueue() async {
    try {
      final queueDir = await _getQueueDirectory();
      if (queueDir == null || !await queueDir.exists()) {
        return;
      }
      
      final files = await queueDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .cast<File>()
          .toList();
      
      // Sort by filename (which contains timestamp)
      files.sort((a, b) => a.path.compareTo(b.path));
      
      // Clean up _seenFiles for files that no longer exist (deleted by ADB bridge)
      final currentFilenames = files.map((f) => f.path.split(Platform.pathSeparator).last).toSet();
      _seenFiles.removeWhere((f) => !currentFilenames.contains(f));
      
      for (final file in files) {
        final filename = file.path.split(Platform.pathSeparator).last;
        
        // Skip if we've already processed this file
        if (_seenFiles.contains(filename)) {
          continue;
        }
        
        try {
          final content = await file.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          
          final sms = IncomingSms.fromJson(json, filename);
          _log('📩 Read SMS from queue: ${sms.sender}');
          
          // Mark as seen
          _seenFiles.add(filename);
          
          // Notify listener (file is NOT deleted - ADB bridge will do that)
          onSmsReceived?.call(sms);
          
        } catch (e) {
          _log('❌ Error processing SMS file: $e', isError: true);
          // Mark as seen to avoid retrying corrupt files
          _seenFiles.add(filename);
        }
      }
    } catch (e) {
      // Silently ignore errors during polling (directory might not exist yet)
    }
  }
  
  /// Get the queue directory path.
  Future<Directory?> _getQueueDirectory() async {
    try {
      // Get the app's internal files directory
      // On Android: /data/data/com.example.server_app/files/sms_queue
      final appDir = Directory('/data/data/com.example.server_app/files/sms_queue');
      return appDir;
    } catch (e) {
      _log('❌ Error getting queue directory: $e', isError: true);
      return null;
    }
  }
  
  void _log(String message, {bool isError = false}) {
    onLog?.call(message, isError);
  }
}
