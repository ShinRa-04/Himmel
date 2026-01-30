import 'package:flutter/material.dart';
import '../widgets/drawer.dart';
import '../widgets/empty_state.dart';
import '../widgets/input_area.dart';
import '../widgets/message_bubble.dart';
import '../theme/colors.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = []; // {text, isUser}
  final ScrollController _scrollController = ScrollController();

  void _handleSend(String text) {
    setState(() {
      _messages.add({'text': text, 'isUser': true});
    });
    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // Simulate AI Response (Echo for now)
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _messages.add({'text': "I received: $text", 'isUser': false});
        });
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
    });
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
        title: Text(
          "ChatGPT",
          style: TextStyle(
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600
          ),
        ),
        actions: [
            IconButton(
                icon: const Icon(Icons.edit_note), // "New Chat" icon
                onPressed: () {
                    setState(() {
                        _messages.clear();
                    });
                },
            )
        ],
      ),
      drawer: const CustomDrawer(),
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
                        message: msg['text'],
                        isUser: msg['isUser'],
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
