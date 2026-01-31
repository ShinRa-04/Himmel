import 'package:flutter/material.dart';
import '../widgets/drawer.dart';
import '../widgets/empty_state.dart';
import '../widgets/input_area.dart';
import '../widgets/message_bubble.dart';
import '../theme/colors.dart';
import '../models/message.dart';
import '../services/sms_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final SmsService _smsService = SmsService();
  String _targetNumber = "7042505681"; // Default

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
    });
    _scrollToBottom();

    // 2. Send SMS via Service
    bool success = await _smsService.sendSms(_targetNumber, text);

    // 3. Update Status
    if (mounted) {
      setState(() {
        newMessage.status = success ? MessageStatus.sent : MessageStatus.failed;
      });
    }

    // 4. (Optional) Simulate Reply later or just listen to incoming (out of scope for now)
  }

  void _showEditNumberDialog() {
    final TextEditingController numberController = TextEditingController(text: _targetNumber);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Set Target Number"),
          content: TextField(
            controller: numberController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: "Enter phone number"),
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
            child: _messages.isEmpty
                ? const EmptyStateWidget()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
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

