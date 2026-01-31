import 'dart:convert';

enum MessageStatus {
  pending,
  sending,
  sent,
  failed,
}

class PendingMessage {
  final String id;
  final String target;
  final String message;
  final DateTime createdAt;
  MessageStatus status;
  int retryCount;
  String? errorMessage;

  PendingMessage({
    required this.id,
    required this.target,
    required this.message,
    required this.createdAt,
    this.status = MessageStatus.pending,
    this.retryCount = 0,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'target': target,
    'message': message,
    'createdAt': createdAt.toIso8601String(),
    'status': status.index,
    'retryCount': retryCount,
    'errorMessage': errorMessage,
  };

  factory PendingMessage.fromJson(Map<String, dynamic> json) => PendingMessage(
    id: json['id'],
    target: json['target'],
    message: json['message'],
    createdAt: DateTime.parse(json['createdAt']),
    status: MessageStatus.values[json['status'] ?? 0],
    retryCount: json['retryCount'] ?? 0,
    errorMessage: json['errorMessage'],
  );

  static String encodeList(List<PendingMessage> messages) {
    return jsonEncode(messages.map((m) => m.toJson()).toList());
  }

  static List<PendingMessage> decodeList(String jsonStr) {
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((e) => PendingMessage.fromJson(e)).toList();
  }
}
