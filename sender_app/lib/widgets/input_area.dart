import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';

class ChatInputArea extends StatefulWidget {
  final Function(String) onSend;

  const ChatInputArea({super.key, required this.onSend});

  @override
  State<ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<ChatInputArea> {
  final TextEditingController _controller = TextEditingController();
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _isTyping = _controller.text.isNotEmpty;
      });
    });
  }

  void _handleSend() {
    if (_controller.text.isNotEmpty) {
      // Add haptic feedback for premium feel
      HapticFeedback.lightImpact();
      
      widget.onSend(_controller.text);
      _controller.clear();
      setState(() => _isTyping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    Color iconColor = isDark ? AppColors.iconColorDark : AppColors.iconColorLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Theme.of(context).scaffoldBackgroundColor, // Match background
      child: SafeArea( // Ensure it doesn't overlap gesture bar
        child: Row(
          children: [
             IconButton(
              icon: Icon(Icons.add, color: iconColor),
              onPressed: () {}, // Attachment logic (placeholder)
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        style: Theme.of(context).textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: "Message",
                          hintStyle: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    IconButton( // Right-inside icon
                      icon: Icon(Icons.graphic_eq, color: iconColor), // Voice Mode Placeholder
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isTyping ? _handleSend : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                   color: _isTyping ? (isDark ? Colors.white : Colors.black) : Colors.transparent, // Solid when typing
                   shape: BoxShape.circle,
                ),
                child: Icon(
                  _isTyping ? Icons.arrow_upward : Icons.headphones,
                  color: _isTyping ? (isDark ? Colors.black : Colors.white) : iconColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
