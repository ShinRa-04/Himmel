import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pending_message.dart';
import 'sms_service.dart';

/// A persistent message queue that survives app restarts and handles retries.
class MessageQueueService {
  static const String _storageKey = 'pending_messages_queue';
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 5);
  
  final SmsService _smsService;
  final List<PendingMessage> _queue = [];
  final _queueController = StreamController<List<PendingMessage>>.broadcast();
  
  bool _isProcessing = false;
  Timer? _retryTimer;
  
  Stream<List<PendingMessage>> get queueStream => _queueController.stream;
  List<PendingMessage> get queue => List.unmodifiable(_queue);
  bool get isProcessing => _isProcessing;
  
  MessageQueueService(this._smsService);
  
  /// Initialize the service and load persisted messages
  Future<void> initialize() async {
    await _loadFromStorage();
    _notifyListeners();
    
    // Start processing any pending messages
    _startProcessing();
    
    // Setup periodic retry for failed messages
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _retryFailedMessages();
    });
  }
  
  /// Dispose resources
  void dispose() {
    _retryTimer?.cancel();
    _queueController.close();
  }
  
  /// Add a new message to the queue
  Future<PendingMessage> enqueue(String target, String message) async {
    final pendingMessage = PendingMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      target: target,
      message: message,
      createdAt: DateTime.now(),
      status: MessageStatus.pending,
    );
    
    _queue.add(pendingMessage);
    await _saveToStorage();
    _notifyListeners();
    
    print("📥 Message queued: ${pendingMessage.id} for $target");
    
    // Start processing if not already
    _startProcessing();
    
    return pendingMessage;
  }
  
  /// Start processing the queue
  void _startProcessing() {
    if (_isProcessing) return;
    _processQueue();
  }
  
  /// Process messages in the queue
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    _notifyListeners();
    
    while (true) {
      // Find next pending message
      final pending = _queue.where(
        (m) => m.status == MessageStatus.pending && m.retryCount < maxRetries
      ).toList();
      
      if (pending.isEmpty) break;
      
      for (final message in pending) {
        await _sendMessage(message);
        await Future.delayed(const Duration(milliseconds: 500)); // Rate limiting
      }
    }
    
    _isProcessing = false;
    _notifyListeners();
  }
  
  /// Send a single message
  Future<void> _sendMessage(PendingMessage message) async {
    message.status = MessageStatus.sending;
    _notifyListeners();
    
    print("📤 Sending message ${message.id} to ${message.target}...");
    
    try {
      final success = await _smsService.sendSms(message.target, message.message);
      
      if (success) {
        message.status = MessageStatus.sent;
        message.errorMessage = null;
        print("✅ Message ${message.id} sent successfully!");
      } else {
        message.status = MessageStatus.failed;
        message.retryCount++;
        message.errorMessage = "SMS sending returned false";
        print("❌ Message ${message.id} failed (attempt ${message.retryCount}/$maxRetries)");
      }
    } catch (e) {
      message.status = MessageStatus.failed;
      message.retryCount++;
      message.errorMessage = e.toString();
      print("❌ Message ${message.id} error: $e (attempt ${message.retryCount}/$maxRetries)");
    }
    
    await _saveToStorage();
    _notifyListeners();
  }
  
  /// Retry failed messages that haven't exceeded max retries
  Future<void> _retryFailedMessages() async {
    final failedMessages = _queue.where(
      (m) => m.status == MessageStatus.failed && m.retryCount < maxRetries
    ).toList();
    
    if (failedMessages.isEmpty) return;
    
    print("🔄 Retrying ${failedMessages.length} failed messages...");
    
    for (final message in failedMessages) {
      message.status = MessageStatus.pending;
    }
    
    _notifyListeners();
    _startProcessing();
  }
  
  /// Force retry a specific message
  Future<void> retryMessage(String id) async {
    final message = _queue.firstWhere(
      (m) => m.id == id,
      orElse: () => throw Exception("Message not found"),
    );
    
    message.status = MessageStatus.pending;
    message.retryCount = 0; // Reset retry count for manual retry
    
    await _saveToStorage();
    _notifyListeners();
    _startProcessing();
  }
  
  /// Remove a message from the queue
  Future<void> removeMessage(String id) async {
    _queue.removeWhere((m) => m.id == id);
    await _saveToStorage();
    _notifyListeners();
  }
  
  /// Clear all sent messages from the queue
  Future<void> clearSent() async {
    _queue.removeWhere((m) => m.status == MessageStatus.sent);
    await _saveToStorage();
    _notifyListeners();
  }
  
  /// Clear all messages from the queue
  Future<void> clearAll() async {
    _queue.clear();
    await _saveToStorage();
    _notifyListeners();
  }
  
  /// Load messages from persistent storage
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final messages = PendingMessage.decodeList(jsonStr);
        _queue.clear();
        _queue.addAll(messages);
        
        // Reset any "sending" status to "pending" (app may have crashed mid-send)
        for (final msg in _queue) {
          if (msg.status == MessageStatus.sending) {
            msg.status = MessageStatus.pending;
          }
        }
        
        print("📂 Loaded ${_queue.length} messages from storage");
      }
    } catch (e) {
      print("⚠️ Error loading from storage: $e");
    }
  }
  
  /// Save messages to persistent storage
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = PendingMessage.encodeList(_queue);
      await prefs.setString(_storageKey, jsonStr);
    } catch (e) {
      print("⚠️ Error saving to storage: $e");
    }
  }
  
  /// Notify listeners of queue changes
  void _notifyListeners() {
    _queueController.add(List.unmodifiable(_queue));
  }
  
  /// Get queue statistics
  Map<String, int> getStats() {
    return {
      'total': _queue.length,
      'pending': _queue.where((m) => m.status == MessageStatus.pending).length,
      'sending': _queue.where((m) => m.status == MessageStatus.sending).length,
      'sent': _queue.where((m) => m.status == MessageStatus.sent).length,
      'failed': _queue.where((m) => m.status == MessageStatus.failed).length,
    };
  }
}
