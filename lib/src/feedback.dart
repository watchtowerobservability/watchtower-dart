/// The `POST /v1/rum/feedback` body (ERR-014), like the browser SDK's `feedbackBody`: the message
/// trimmed and cut to 4096 characters, name and email to 256, and `event_id` only when it is 32 hex
/// characters once the dashes of a UUID are gone. Null without a message.
Map<String, String>? feedbackBody(String message, {String? name, String? email, String? eventId}) {
  String cut(String? s, int max) {
    final t = (s ?? '').trim();
    return t.length > max ? t.substring(0, max) : t;
  }

  final m = cut(message, 4096);
  if (m.isEmpty) return null;
  final id = (eventId ?? '').replaceAll('-', '').toLowerCase();
  final n = cut(name, 256), e = cut(email, 256);
  return {
    'message': m,
    if (RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) 'event_id': id,
    if (n.isNotEmpty) 'name': n,
    if (e.isNotEmpty) 'email': e,
  };
}
