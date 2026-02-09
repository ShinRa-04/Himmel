import 'package:flutter/material.dart';
import '../widgets/drawer.dart';
import '../widgets/empty_state.dart';
import '../widgets/input_area.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../theme/colors.dart';
import '../models/message.dart';
import '../services/sms_service.dart';
import '../services/sms_listener_service.dart';
import '../services/settings_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final SmsService _smsService = SmsService();
  final SmsListenerService _smsListenerService = SmsListenerService();
  
  String _targetNumber = ""; // Will be loaded from settings
  
  // State for typing indicator
  bool _isWaitingForResponse = false;
  int _receivingChunk = 0;
  int? _receivingTotal; // null if total is unknown (chunk 1 missing)
  
  // Track the expected message ID for matching responses
  String? _expectedMessageId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Load saved settings (server phone number).
  Future<void> _loadSettings() async {
    final savedNumber = await SettingsService.getServerPhoneNumber();
    if (mounted) {
      setState(() {
        _targetNumber = savedNumber;
      });
      _initSmsListener();
    }
  }

  @override
  void dispose() {
    _smsListenerService.stopListening();
    _scrollController.dispose();
    super.dispose();
  }

  /// Initialize the SMS listener to receive incoming messages.
  Future<void> _initSmsListener() async {
    // Set up callbacks
    _smsListenerService.onCompleteMessage = _handleIncomingMessage;
    _smsListenerService.onChunkReceived = _handleChunkReceived;
    
    // Start listening for messages from the server phone
    await _smsListenerService.startListening(expectedSender: _targetNumber);
  }

  /// Called when a complete message is received and assembled.
  void _handleIncomingMessage(String messageId, String sender, String message) {
    if (!mounted) return;
    
    // Only accept response if it matches the expected message ID
    if (_expectedMessageId != null && messageId != _expectedMessageId) {
      debugPrint('Ignoring response with ID $messageId - waiting for $_expectedMessageId');
      return;
    }
    
    setState(() {
      _isWaitingForResponse = false;
      _receivingChunk = 0;
      _receivingTotal = null;
      _expectedMessageId = null; // Clear expected ID
      
      // Add the AI response message
      _messages.add(Message(
        text: message,
        isUser: false,
        status: MessageStatus.sent,
      ));
    });
    
    _scrollToBottom();
  }

  /// Called when a chunk is received (for progress feedback).
  void _handleChunkReceived(String messageId, String sender, int received, int? total) {
    if (!mounted) return;
    
    // Only show chunk progress if it matches the expected message ID
    if (_expectedMessageId != null && messageId != _expectedMessageId) {
      debugPrint('Ignoring chunk for ID $messageId - waiting for $_expectedMessageId');
      return;
    }
    
    setState(() {
      _receivingChunk = received;
      _receivingTotal = total;
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend(String text) async {
    // 1. Add Pending Message
    final newMessage = Message(text: text, isUser: true, status: MessageStatus.pending);
    setState(() {
      _messages.add(newMessage);
      _isWaitingForResponse = true; // Show typing indicator
    });
    _scrollToBottom();

    // 2. Send SMS via Service
    final result = await _smsService.sendSms(_targetNumber, text);

    // 3. Update Status and track message ID
    if (mounted) {
      setState(() {
        newMessage.status = result.success ? MessageStatus.sent : MessageStatus.failed;
        if (result.success && result.messageId != null) {
          // Store the expected message ID for matching responses
          _expectedMessageId = result.messageId;
          debugPrint('Waiting for response with ID: $_expectedMessageId');
        } else if (!result.success) {
          // If send failed, stop waiting for response
          _isWaitingForResponse = false;
          _expectedMessageId = null;
        }
      });
    }
    
    _scrollToBottom();
  }

  void _showEditNumberDialog() {
    final TextEditingController numberController = TextEditingController(text: _targetNumber);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(Icons.phone, size: 32),
          title: const Text("Target Phone Number"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Enter the phone number to send messages to:",
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: numberController,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "e.g., 9876543210",
                  prefixIcon: const Icon(Icons.dialpad),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                onSubmitted: (_) async {
                  final newNumber = numberController.text.trim();
                  if (newNumber.isNotEmpty) {
                    await SettingsService.setServerPhoneNumber(newNumber);
                    setState(() {
                      _targetNumber = newNumber;
                      _smsListenerService.setExpectedSender(_targetNumber);
                    });
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            FilledButton.icon(
              onPressed: () async {
                final newNumber = numberController.text.trim();
                if (newNumber.isNotEmpty) {
                  await SettingsService.setServerPhoneNumber(newNumber);
                  setState(() {
                    _targetNumber = newNumber;
                    _smsListenerService.setExpectedSender(_targetNumber);
                  });
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.save),
              label: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
     bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        centerTitle: true,
        title: GestureDetector(
          onTap: _showEditNumberDialog,
          child: Column(
            children: [
              Text(
                "Direct SMS",
                style: TextStyle(
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.phone,
                    size: 10,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _targetNumber.isEmpty ? "Tap to set number" : _targetNumber,
                    style: TextStyle(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit,
                    size: 10,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
            IconButton(
                icon: const Icon(Icons.phone_outlined),
                tooltip: 'Edit Target Number',
                onPressed: _showEditNumberDialog,
            ),
            IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Clear Chat',
                onPressed: () {
                    setState(() {
                        _messages.clear();
                    });
                },
            )
        ],
      ),
      drawer: CustomDrawer(onEditNumber: _showEditNumberDialog), // Pass callback
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && !_isWaitingForResponse
                ? const EmptyStateWidget()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 20),
                    // +1 for typing indicator if waiting
                    itemCount: _messages.length + (_isWaitingForResponse ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Show typing indicator as the last item
                      if (_isWaitingForResponse && index == _messages.length) {
                        // Show receiving progress if chunks are coming
                        if (_receivingChunk > 0) {
                          return ReceivingIndicator(
                            receivedChunks: _receivingChunk,
                            totalChunks: _receivingTotal,
                          );
                        }
                        // Show typing dots while waiting
                        return const TypingIndicator();
                      }
                      
                      final msg = _messages[index];
                      return MessageBubble(
                        message: msg.text,
                        isUser: msg.isUser,
                        status: msg.status, // Pass status
                      );
                    },
                  ),
          ),
          ChatInputArea(onSend: _handleSend),
        ],
      ),
    );
  }
}

