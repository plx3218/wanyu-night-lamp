import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  AiService({this.serverUrl = 'http://121.40.96.105:8000'});

  final String serverUrl;
  final List<Map<String, String>> _history = [];
  String? _profileContext;
  bool _profileInjected = false;

  /// 登录/建档后注入用户档案上下文；首轮对话自动带入，clearHistory 后重新注入
  void setProfileContext(String? context) {
    _profileContext = context;
    _profileInjected = false;
  }

  Stream<String> chat(String userMessage) async* {
    if (_profileContext != null && !_profileInjected && _history.isEmpty) {
      _history.add({'role': 'user', 'content': _profileContext!});
      _history.add({'role': 'assistant', 'content': '好，我已经记住你的睡眠习惯了。今晚想怎么安排？'});
      _profileInjected = true;
    }
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

  void clearHistory() {
    _history.clear();
    _profileInjected = false;
  }
}
