/// Represents a single search match within a message.
class ChatSearchMatch {
  final String messageId;
  final int start;
  final int end;

  const ChatSearchMatch({
    required this.messageId,
    required this.start,
    required this.end,
  });
}