import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 50), // Spacing for status bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    "Previous 7 Days",
                    style: TextStyle(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildHistoryItem(context, "Flutter UI Design"),
                _buildHistoryItem(context, "State Management Pattern"),
                _buildHistoryItem(context, "API Integration Tips"),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildUserProfile(context),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, String title) {
    return ListTile(
      leading: const Icon(Icons.chat_bubble_outline, size: 18),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        HapticFeedback.lightImpact();
      },
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
    );
  }


  Widget _buildUserProfile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.accentTeal,
            child: const Text("U", style: TextStyle(color: Colors.white, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Text(
            "User Profile",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          const Icon(Icons.more_horiz),
        ],
      ),
    );
  }
}
