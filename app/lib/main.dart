import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SMSVibeApp(),
  ));
}

class SMSVibeApp extends StatefulWidget {
  const SMSVibeApp({super.key});

  @override
  State<SMSVibeApp> createState() => _SMSVibeAppState();
}

class _SMSVibeAppState extends State<SMSVibeApp> {
  // THE VARIABLE YOU CAN EDIT
  final String targetNumber = "8595819054"; 

  final TextEditingController _messageController = TextEditingController();
  final Telephony telephony = Telephony.instance;
  String _status = "Ready to send";

  // LOGIC TO SEND DIRECTLY WITHOUT OPENING SMS APP
  Future<void> _sendDirectSMS() async {
    // Requests permissions for both SMS and Phone state
    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;

    if (permissionsGranted == true) {
      try {
        await telephony.sendSms(
          to: targetNumber,
          message: _messageController.text,
        );
        setState(() {
          _status = "Message Sent to $targetNumber!";
          _messageController.clear();
        });
      } catch (e) {
        setState(() => _status = "Error: $e");
      }
    } else {
      setState(() => _status = "Permission Denied. Check App Info.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Dark theme vibe
      appBar: AppBar(
        title: const Text('Direct SMS Vibe'),
        backgroundColor: Colors.blueGrey[900],
      ),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Recipient: $targetNumber",
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type your message...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _sendDirectSMS,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("SEND SMS NOW", style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 20),
            Text(
              _status,
              style: TextStyle(
                color: _status.contains("Error") ? Colors.red : Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}