import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/chunked_sms_queue.dart';
import 'services/sms_queue_monitor.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ServerApp());
}

class ServerApp extends StatelessWidget {
  const ServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Himmel Server',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ServerHomePage(),
    );
  }
}

class ServerHomePage extends StatefulWidget {
  const ServerHomePage({super.key});

  @override
  State<ServerHomePage> createState() => _ServerHomePageState();
}

class _ServerHomePageState extends State<ServerHomePage> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.example.server_app/intent');
  
  late final ChunkedSmsQueue _smsQueue;
  late final SmsQueueMonitor _smsMonitor;
  final List<LogEntry> _logs = [];
  
  String _status = "🟡 Initializing...";
  bool _isProcessing = false;
  bool _permissionsGranted = false;
  bool _isDefaultSmsApp = false;
  bool _isMonitoring = false;
  Map<String, dynamic> _queueStats = {};
  
  // Stats for incoming SMS
  int _chunksReceived = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize SMS sending queue
    _smsQueue = ChunkedSmsQueue();
    _smsQueue.onLog = (message, isError) => _addLog(message, isError: isError);
    
    // Initialize SMS monitoring (for incoming messages)
    // Chunks are picked up by the PC via ADB, not forwarded via HTTP
    _smsMonitor = SmsQueueMonitor();
    _smsMonitor.onLog = (message, isError) => _addLog(message, isError: isError);
    _smsMonitor.onSmsReceived = _handleIncomingSms;
    
    _initialize();
  }

  Future<void> _initialize() async {
    _addLog("🚀 Server App Starting...");
    _addLog("📡 Mode: ADB Bridge (PC monitors chunks via ADB)");
    
    // Setup intent listener first - this handles intents pushed from Android
    _setupIntentListener();
    
    // Request permissions on startup
    _addLog("📱 Requesting SMS permissions...");
    _permissionsGranted = await _smsQueue.requestPermissions();
    
    if (_permissionsGranted) {
      _addLog("✅ SMS permissions granted");
    } else {
      _addLog("❌ SMS permissions denied!", isError: true);
      setState(() => _status = "🔴 No SMS Permission");
    }
    
    _addLog("📦 Chunked SMS queue initialized");
    
    // Check if launched with intent BEFORE checking default status
    // This ensures the payload is captured first
    await _checkForIntent();
    
    // Check if we're the default SMS app (after payload is safe)
    await _checkDefaultSmsStatus();
    
    // Listen to queue changes
    _smsQueue.statusStream.listen((stats) {
      if (mounted) {
        setState(() {
          _queueStats = stats;
          _isProcessing = stats['isProcessing'] ?? false;
          
          // Update status based on queue
          final sending = stats['sending'] ?? 0;
          final pending = stats['pending'] ?? 0;
          final failed = stats['failed'] ?? 0;
          
          if (sending > 0) {
            final sentChunks = stats['sentChunks'] ?? 0;
            final totalChunks = stats['totalChunks'] ?? 0;
            _status = "📤 Sending... ($sentChunks/$totalChunks chunks)";
          } else if (pending > 0) {
            _status = "⏳ $pending pending";
          } else if (failed > 0) {
            _status = "⚠️ $failed failed";
          } else if (!_isDefaultSmsApp) {
            _status = "⚠️ Not Default SMS App";
          } else if (_permissionsGranted) {
            _status = "🟢 Server Ready";
          }
        });
      }
    });
  }
  
  Future<void> _checkDefaultSmsStatus() async {
    try {
      final bool isDefault = await platform.invokeMethod('isDefaultSmsApp');
      setState(() => _isDefaultSmsApp = isDefault);
      
      if (isDefault) {
        _addLog("✅ App is the default SMS app");
        setState(() => _status = "🟢 Server Ready");
      } else {
        _addLog("⚠️ App is NOT the default SMS app - reliability limited!", isError: true);
        setState(() => _status = "⚠️ Not Default SMS App");
      }
    } on PlatformException catch (e) {
      _addLog("⚠️ Could not check default SMS status: ${e.message}", isError: true);
    }
  }
  
  Future<void> _requestDefaultSmsApp() async {
    try {
      _addLog("📱 Requesting to become default SMS app...");
      final bool result = await platform.invokeMethod('requestDefaultSmsApp');
      
      setState(() => _isDefaultSmsApp = result);
      
      if (result) {
        _addLog("✅ Now the default SMS app!");
        setState(() => _status = "🟢 Server Ready");
      } else {
        _addLog("❌ Request denied or cancelled", isError: true);
      }
    } on PlatformException catch (e) {
      _addLog("⚠️ Error requesting default SMS: ${e.message}", isError: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _smsQueue.dispose();
    _smsMonitor.stop();
    super.dispose();
  }
  
  // ============ SMS Monitoring ============
  
  void _toggleMonitoring() {
    setState(() {
      if (_isMonitoring) {
        _smsMonitor.stop();
        _isMonitoring = false;
        _addLog("🛑 SMS Monitoring stopped");
      } else {
        _smsMonitor.start();
        _isMonitoring = true;
        _addLog("👂 SMS Monitoring started");
        _addLog("📡 Chunks will be picked up by PC via ADB bridge");
      }
    });
  }
  
  /// Handle incoming SMS chunk from the monitor.
  /// The chunk file is left in place for the PC's ADB bridge to pick up.
  void _handleIncomingSms(IncomingSms sms) {
    setState(() => _chunksReceived++);
    _addLog("📩 Chunk received from ${sms.sender}");
    _addLog("   Content: ${sms.body.substring(0, sms.body.length > 50 ? 50 : sms.body.length)}...");
    _addLog("   📂 Saved to queue for ADB bridge");
    // Note: The file is NOT deleted here - the ADB bridge on PC will read and delete it
  }
  
  /// Handle complete response from the backend (received via ADB intent).
  /// This triggers sending the response back to the original sender.
  /// [messageId] is the original message ID that must be preserved in the response.
  void _handleBackendResponse(String sender, String responseText, {String? messageId}) {
    _addLog("🤖 Got AI response for $sender (${responseText.length} chars)");
    _addLog("   Message ID: ${messageId ?? 'not provided'}");
    _addLog("   Preview: ${responseText.substring(0, responseText.length > 50 ? 50 : responseText.length)}...");
    
    // Queue the response to be sent back to the sender, preserving the original message ID
    _processIncomingPayload(sender, responseText, messageId: messageId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only check default status silently, don't check for intent here
      // Intent is already handled by handleIntent method channel callback
      _checkDefaultSmsStatusSilent();
    }
  }
  
  Future<void> _checkDefaultSmsStatusSilent() async {
    try {
      final bool isDefault = await platform.invokeMethod('isDefaultSmsApp');
      if (mounted) {
        setState(() => _isDefaultSmsApp = isDefault);
      }
    } catch (e) {
      // Ignore errors on silent check
    }
  }

  void _setupIntentListener() {
    platform.setMethodCallHandler((call) async {
      _addLog("📨 Method call received: ${call.method}");
      
      if (call.method == 'handleIntent') {
        final Map<dynamic, dynamic> args = call.arguments;
        final String? target = args['target'];
        final String? message = args['message'];
        final String? messageId = args['message_id'];  // Original message ID to preserve
        
        _addLog("📨 Intent data - target: $target, msgLen: ${message?.length ?? 0}, msgId: ${messageId ?? 'none'}");
        
        if (target != null && message != null) {
          await _processIncomingPayload(target, message, messageId: messageId);
        }
      }
    });
    _addLog("👂 Intent listener setup complete");
  }

  Future<void> _checkForIntent() async {
    try {
      _addLog("🔍 Checking for pending intent...");
      final Map<dynamic, dynamic>? intentData = await platform.invokeMethod('getIntent');
      
      if (intentData != null) {
        final String? target = intentData['target'];
        final String? message = intentData['message'];
        final String? messageId = intentData['message_id'];  // Original message ID
        
        _addLog("📬 Got intent data - target: $target, msgLen: ${message?.length ?? 0}, msgId: ${messageId ?? 'none'}");
        
        if (target != null && message != null && target.isNotEmpty && message.isNotEmpty) {
          await _processIncomingPayload(target, message, messageId: messageId);
        } else {
          _addLog("ℹ️ No valid payload in intent");
        }
      } else {
        _addLog("ℹ️ No pending intent found");
      }
    } on PlatformException catch (e) {
      _addLog("⚠️ Platform Error: ${e.message}", isError: true);
    }
  }

  Future<void> _processIncomingPayload(String target, String message, {String? messageId}) async {
    if (!_permissionsGranted) {
      _addLog("❌ Cannot send - no SMS permission!", isError: true);
      setState(() => _status = "🔴 No SMS Permission");
      return;
    }

    _addLog("📩 Processing message for: $target");
    _addLog("📝 Message length: ${message.length} chars");
    if (messageId != null) {
      _addLog("🔑 Using original message ID: ${messageId.substring(0, 8)}...");
    }
    _addLog("📝 Message preview: ${message.substring(0, message.length > 50 ? 50 : message.length)}...");

    try {
      // Queue the message - it will be chunked and sent in order
      // Pass the existingId to preserve the original message ID for responses
      final msgId = await _smsQueue.queueMessage(target, message, existingId: messageId);
      _addLog("✅ Message queued with ID: ${msgId.substring(0, 8)}...");
    } catch (e) {
      _addLog("❌ Error queueing message: $e", isError: true);
      setState(() => _status = "❌ Error occurred");
    }
  }

  void _addLog(String message, {bool isError = false}) {
    print("LOG: $message"); // Also print to console for debugging
    setState(() {
      _logs.insert(0, LogEntry(
        message: message,
        timestamp: DateTime.now(),
        isError: isError,
      ));
      if (_logs.length > 100) {
        _logs.removeLast();
      }
    });
  }
  
  Future<void> _testSend() async {
    _addLog("🧪 Test send triggered");
    await _processIncomingPayload("1234567890", "This is a test message from Himmel Server App.");
  }
  
  /// Test basic SMS sending to verify the mechanism works
  Future<void> _testBasicSms() async {
    _addLog("🧪 ========== BASIC SMS TEST ==========");
    _addLog("🧪 Testing if SMS sending actually works...");
    
    // Show dialog to get phone number
    final controller = TextEditingController(text: "9149194016");
    final phoneNumber = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Test SMS"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: "Enter phone number to test"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text("Test")),
        ],
      ),
    );
    
    if (phoneNumber == null || phoneNumber.isEmpty) {
      _addLog("🧪 Test cancelled");
      return;
    }
    
    final testMessage = "Himmel Test ${DateTime.now().millisecondsSinceEpoch % 10000}";
    _addLog("🧪 Sending test to: $phoneNumber");
    _addLog("🧪 Test message: $testMessage");
    
    final success = await _smsQueue.testSendSms(phoneNumber, testMessage);
    
    if (success) {
      _addLog("🧪 ✅ BASIC SMS TEST PASSED - SMS is working!");
    } else {
      _addLog("🧪 ❌ BASIC SMS TEST FAILED - SMS sending is broken!", isError: true);
      _addLog("🧪 Check: Is this app the default SMS app?", isError: true);
      _addLog("🧪 Check: Are SMS permissions granted?", isError: true);
    }
    _addLog("🧪 ========================================");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Himmel Server'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _logs.clear()),
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  _isProcessing ? Icons.sync : (_isDefaultSmsApp ? Icons.cloud_done : Icons.warning_amber),
                  size: 48,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 12),
                Text(
                  _status,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                // ADB Bridge info
                Text(
                  'Mode: ADB Bridge • Chunks received: $_chunksReceived',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                  ),
                ),
                if (_isProcessing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                // Show button to become default SMS app if not already
                if (!_isDefaultSmsApp && _permissionsGranted) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _requestDefaultSmsApp,
                    icon: const Icon(Icons.sms),
                    label: const Text('Set as Default SMS App'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Required for reliable message delivery',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // SMS Monitoring Control Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isMonitoring 
                  ? Colors.green.withOpacity(0.2)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: _isMonitoring 
                  ? Border.all(color: Colors.green, width: 2)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  _isMonitoring ? Icons.sensors : Icons.sensors_off,
                  color: _isMonitoring ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isMonitoring ? 'Monitoring Active' : 'Monitoring Stopped',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: _isMonitoring ? Colors.green : null,
                        ),
                      ),
                      Text(
                        _isMonitoring 
                            ? 'Watching for incoming protocol SMS'
                            : 'Tap to start monitoring incoming SMS',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _isDefaultSmsApp ? _toggleMonitoring : null,
                  icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
                  label: Text(_isMonitoring ? 'Stop' : 'Start'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _isMonitoring ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          
          // Queue Stats Card
          if (_queueStats.isNotEmpty) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatChip(context, '⏳', 'Pending', _queueStats['pending'] ?? 0),
                      _buildStatChip(context, '📤', 'Sending', _queueStats['sending'] ?? 0),
                      _buildStatChip(context, '✅', 'Sent', _queueStats['sent'] ?? 0),
                      _buildStatChip(context, '❌', 'Failed', _queueStats['failed'] ?? 0),
                    ],
                  ),
                  if ((_queueStats['totalChunks'] ?? 0) > 0) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_queueStats['sentChunks'] ?? 0) / (_queueStats['totalChunks'] ?? 1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chunks: ${_queueStats['sentChunks'] ?? 0}/${_queueStats['totalChunks'] ?? 0}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Queue Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_queueStats['sent'] ?? 0) > 0
                          ? () {
                              _smsQueue.clearSent();
                              _addLog("🗑️ Cleared sent messages");
                            }
                          : null,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Clear Sent'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _smsQueue.clearAll();
                        _addLog("🗑️ Cleared all messages");
                      },
                      icon: const Icon(Icons.delete_sweep, size: 18),
                      label: const Text('Clear All'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Test SMS Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testBasicSms,
                  icon: const Icon(Icons.science, size: 18),
                  label: const Text('🧪 Test Basic SMS Send'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          
          // Logs Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Activity Log',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '${_logs.length} entries',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          
          // Logs List
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'No activity yet.\nWaiting for ADB commands...',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            log.isError ? Icons.error_outline : Icons.check_circle_outline,
                            color: log.isError ? Colors.red : Colors.green,
                            size: 20,
                          ),
                          title: Text(
                            log.message,
                            style: TextStyle(
                              fontSize: 13,
                              color: log.isError ? Colors.red[300] : null,
                            ),
                          ),
                          subtitle: Text(
                            _formatTime(log.timestamp),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _checkForIntent,
        icon: const Icon(Icons.refresh),
        label: const Text('Check Intent'),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
  
  Widget _buildStatChip(BuildContext context, String emoji, String label, int count) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 2),
        Text(
          count.toString(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class LogEntry {
  final String message;
  final DateTime timestamp;
  final bool isError;

  LogEntry({
    required this.message,
    required this.timestamp,
    this.isError = false,
  });
}
