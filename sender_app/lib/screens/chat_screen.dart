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
  
  String _targetNumber = "7042426701"; // Default - the server phone number
  
  // State for typing indicator
  bool _isWaitingForResponse = false;
  int _receivingChunk = 0;
  int _receivingTotal = 0;
  
  // Track the expected message ID for matching responses
  String? _expectedMessageId;

  @override
  void initState() {
    super.initState();
    _initSmsListener();
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
      _receivingTotal = 0;
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
  void _handleChunkReceived(String messageId, String sender, int current, int total) {
    if (!mounted) return;
    
    // Only show chunk progress if it matches the expected message ID
    if (_expectedMessageId != null && messageId != _expectedMessageId) {
      debugPrint('Ignoring chunk for ID $messageId - waiting for $_expectedMessageId');
      return;
    }
    
    setState(() {
      _receivingChunk = current;
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
          title: const Text("Set Server Phone Number"),
          content: TextField(
            controller: numberController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: "Enter server phone number"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _targetNumber = numberController.text;
                  // Update the SMS listener to listen from the new number
                  _smsListenerService.setExpectedSender(_targetNumber);
                });
                Navigator.pop(context);
              },
              child: const Text("Save"),
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
        title: Column(
          children: [
            Text(
              "Direct SMS",
              style: TextStyle(
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600
              ),
            ),
            Text(
              _targetNumber,
              style: TextStyle(
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
        actions: [
            IconButton(
                icon: const Icon(Icons.edit_note), // "New Chat" icon to clear
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
                        if (_receivingChunk > 0 && _receivingTotal > 0) {
                          return ReceivingIndicator(
                            currentChunk: _receivingChunk,
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

