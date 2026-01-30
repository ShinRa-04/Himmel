import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../models/message.dart';

class MessageBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final MessageStatus status; // Add status

  const MessageBubble({
    super.key, 
    required this.message, 
    required this.isUser,
    this.status = MessageStatus.pending, // Default
  });

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end, // Align to bottom for ticks
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.accentTeal,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            )
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser 
                        ? (isDark ? AppColors.darkUserBubble : AppColors.lightUserBubble)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SelectableText(
                    message,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                    ),
                  ),
                ),
                if (isUser) ...[
                   const SizedBox(height: 4),
                   _buildStatusIcon(context),
                ]
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8.0),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    IconData icon;
    Color color = Colors.grey;
    
    switch (status) {
      case MessageStatus.pending:
        icon = Icons.schedule;
        break;
      case MessageStatus.sent:
        icon = Icons.check;
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
    }

    return Icon(icon, size: 12, color: color);
  }
}
