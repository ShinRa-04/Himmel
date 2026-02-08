import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// A typing indicator widget that shows animated dots (like "AI is typing...").
class TypingIndicator extends StatefulWidget {
  final bool showText;
  final String text;
  
  const TypingIndicator({
    super.key,
    this.showText = true,
    this.text = 'AI is thinking',
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _controllers = List.generate(
      3,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: controller,
          curve: Curves.easeInOut,
        ),
      );
    }).toList();

    // Start animations with staggered delay
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // AI Avatar
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: AppColors.accentTeal,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
          ),
          // Typing bubble
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.grey[800]?.withOpacity(0.5) 
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showText) ...[
                  Text(
                    widget.text,
                    style: TextStyle(
                      color: isDark 
                          ? AppColors.darkTextSecondary 
                          : AppColors.lightTextSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Animated dots
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    return AnimatedBuilder(
                      animation: _animations[index],
                      builder: (context, child) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          child: Transform.translate(
                            offset: Offset(0, -4 * _animations[index].value),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.accentTeal.withOpacity(
                                  0.5 + 0.5 * _animations[index].value,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A simpler receiving indicator that shows chunk progress.
class ReceivingIndicator extends StatelessWidget {
  final int currentChunk;
  final int totalChunks;

  const ReceivingIndicator({
    super.key,
    required this.currentChunk,
    required this.totalChunks,
  });

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = totalChunks > 0 ? currentChunk / totalChunks : 0.0;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: AppColors.accentTeal,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.grey[800]?.withOpacity(0.5) 
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    color: AppColors.accentTeal,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Receiving $currentChunk/$totalChunks',
                  style: TextStyle(
                    color: isDark 
                        ? AppColors.darkTextSecondary 
                        : AppColors.lightTextSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
