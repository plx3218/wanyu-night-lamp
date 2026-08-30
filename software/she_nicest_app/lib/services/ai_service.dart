import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  AiService({this.serverUrl = 'http://121.40.96.105:8000'});

  final String serverUrl;
  final List<Map<String, String>> _history = [];

  Stream<String> chat(String userMessage) async* {
    _history.add({'role': 'user', 'content': userMessage});

    final request = http.Request('POST', Uri.parse('$serverUrl/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'messages': _history});

    final client = http.Client();
    final response = await client.send(request);

    final buffer = StringBuffer();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      for (final line in chunk.split('\n')) {
        if (line.startsWith('data: ') && !line.contains('[DONE]')) {
          try {
            final data = jsonDecode(line.substring(6)) as Map<String, dynamic>;
            final content = data['content'] as String? ?? '';
            if (content.isNotEmpty) {
              buffer.write(content);
              yield content;
            }
          } catch (_) {}
        }
      }
    }

    _history.add({'role': 'assistant', 'content': buffer.toString()});
  }

  void clearHistory() => _history.clear();
}
