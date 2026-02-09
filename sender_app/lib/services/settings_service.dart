import 'package:shared_preferences/shared_preferences.dart';

/// Service for persisting app settings like the server phone number.
class SettingsService {
  static const String _keyServerNumber = 'server_phone_number';
  static const String _defaultNumber = '7042426701';
  
  /// Retrieves the saved server phone number, or returns the default.
  static Future<String> getServerPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerNumber) ?? _defaultNumber;
  }
  
  /// Saves the server phone number to persistent storage.
  static Future<bool> setServerPhoneNumber(String number) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(_keyServerNumber, number);
  }
}
