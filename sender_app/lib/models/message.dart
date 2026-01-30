enum MessageStatus {
  pending,
  sent,
  failed,
}

class Message {
  final String text;
  final bool isUser;
  MessageStatus status;
  final DateTime timestamp;

  Message({
    required this.text,
    required this.isUser,
    this.status = MessageStatus.pending,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
