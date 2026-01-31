import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/sms_service.dart';

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
  
  final SmsService _smsService = SmsService();
  final List<LogEntry> _logs = [];
  
  String _status = "🟡 Initializing...";
  bool _isProcessing = false;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    _addLog("🚀 Server App Starting...");
    
    // Setup intent listener first
    _setupIntentListener();
    
    // Request permissions on startup
    _addLog("📱 Requesting SMS permissions...");
    _permissionsGranted = await _smsService.requestPermissions();
    
    if (_permissionsGranted) {
      _addLog("✅ SMS permissions granted");
      setState(() => _status = "🟢 Server Ready");
    } else {
      _addLog("❌ SMS permissions denied!", isError: true);
      setState(() => _status = "🔴 No SMS Permission");
    }
    
    // Check if launched with intent
    await _checkForIntent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _addLog("📱 App resumed, checking for intents...");
      _checkForIntent();
    }
  }

  void _setupIntentListener() {
    platform.setMethodCallHandler((call) async {
      _addLog("📨 Method call received: ${call.method}");
      
      if (call.method == 'handleIntent') {
        final Map<dynamic, dynamic> args = call.arguments;
        final String? target = args['target'];
        final String? message = args['message'];
        
        _addLog("📨 Intent data - target: $target, msgLen: ${message?.length ?? 0}");
        
        if (target != null && message != null) {
          await _processIncomingPayload(target, message);
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
        
        _addLog("📬 Got intent data - target: $target, msgLen: ${message?.length ?? 0}");
        
        if (target != null && message != null && target.isNotEmpty && message.isNotEmpty) {
          await _processIncomingPayload(target, message);
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

  Future<void> _processIncomingPayload(String target, String message) async {
    if (_isProcessing) {
      _addLog("⏳ Already processing, please wait...", isError: true);
      return;
    }
    
    if (!_permissionsGranted) {
      _addLog("❌ Cannot send - no SMS permission!", isError: true);
      setState(() => _status = "🔴 No SMS Permission");
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = "📤 Sending to $target...";
    });

    _addLog("📩 Processing payload for: $target");
    _addLog("📝 Message length: ${message.length} chars");
    _addLog("📝 Message preview: ${message.substring(0, message.length > 50 ? 50 : message.length)}...");

    try {
      bool success = await _smsService.sendSms(target, message);
      
      if (success) {
        _addLog("✅ SMS sent successfully!");
        setState(() => _status = "✅ Last send: Success");
      } else {
        _addLog("❌ SMS send failed!", isError: true);
        setState(() => _status = "❌ Last send: Failed");
      }
    } catch (e) {
      _addLog("❌ Error: $e", isError: true);
      setState(() => _status = "❌ Error occurred");
    } finally {
      setState(() => _isProcessing = false);
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
                  _isProcessing ? Icons.sync : Icons.cloud_done,
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
                if (_isProcessing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          
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
