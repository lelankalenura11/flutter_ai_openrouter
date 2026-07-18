/// Represents a single search match within a message.
class SearchMatch {
  final String messageId;
  final int start;
  final int end;

  const SearchMatch(this.messageId, this.start, this.end);
}
