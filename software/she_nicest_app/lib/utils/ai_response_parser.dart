import 'dart:convert';

/// 从混合文本（自然语言 + JSON + 分隔符）中提取「最后一个合法的平衡 {} JSON 对象」
/// 与服务端 extract_json 行为一致：服务器补发修正 JSON 时，取最后一个
Map<String, dynamic>? extractLastJson(String text) {
  final src = text;
  final candidates = <Map<String, dynamic>>[];
  int searchFrom = 0;
  while (true) {
    final start = src.indexOf('{', searchFrom);
    if (start == -1) break;
    int depth = 0;
    int end = -1;
    bool inStr = false;
    bool escape = false;
    for (int i = start; i < src.length; i++) {
      final ch = src[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (ch == '\\') {
        escape = true;
        continue;
      }
      if (ch == '"') {
        inStr = !inStr;
        continue;
      }
      if (!inStr) {
        if (ch == '{') depth++;
        else if (ch == '}') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
    }
    if (end != -1) {
      try {
        final obj = jsonDecode(src.substring(start, end + 1));
        if (obj is Map<String, dynamic>) candidates.add(obj);
      } catch (_) {}
      searchFrom = end + 1;
    } else {
      break;
    }
  }
  if (candidates.isEmpty) return null;
  return candidates.last;
}

/// extractLastJson 失败（JSON 不完整/非标准格式）时的 regex 兜底提取
Map<String, dynamic>? extractFieldsFromText(String text) {
  final statusMatch = RegExp(r'"status"\s*:\s*"(\w+)"').firstMatch(text);
  final status = statusMatch?.group(1);
  final replyMatch = RegExp(r'"reply"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(text);
  final reply = replyMatch?.group(1);
  if (status == null && reply == null) return null;
  final questionMatch = RegExp(r'"question"\s*:\s*(?:"((?:[^"\\]|\\.)*)"|null)').firstMatch(text);
  final question = questionMatch?.group(1);
  String? planRaw;
  final planIdx = text.indexOf('"plan"');
  if (planIdx != -1) {
    final colonIdx = text.indexOf(':', planIdx + 6);
    if (colonIdx != -1) {
      final after = text.substring(colonIdx + 1).trimLeft();
      if (after.startsWith('{')) {
        int depth = 0;
        int end = -1;
        bool inStr = false;
        bool escape = false;
        for (int i = 0; i < after.length; i++) {
          final ch = after[i];
          if (escape) {
            escape = false;
            continue;
          }
          if (ch == '\\') {
            escape = true;
            continue;
          }
          if (ch == '"') {
            inStr = !inStr;
            continue;
          }
          if (!inStr) {
            if (ch == '{') depth++;
            else if (ch == '}') {
              depth--;
              if (depth == 0) {
                end = i;
                break;
              }
            }
          }
        }
        if (end != -1) {
          planRaw = after.substring(0, end + 1);
        } else if (depth > 0) {
          planRaw = after.substring(0);
        }
      }
    }
  }
  Map<String, dynamic>? plan;
  if (planRaw != null) {
    try {
      final p = jsonDecode(planRaw);
      if (p is Map<String, dynamic>) plan = p;
    } catch (_) {}
  }
  return {
    'reply': reply,
    'status': status,
    'question': question,
    'plan': plan,
  };
}

/// 从 AI 响应里解析出可直接喂 TonightPlan.fromServerJson 的 payload（含 status/plan），
/// 双通道（extractLastJson → extractFieldsFromText），聊天页与静默生成都用它
Map<String, dynamic>? extractPlanPayload(String fullText) {
  final parsed = extractLastJson(fullText);
  if (parsed != null && parsed['status'] != null) return parsed;
  final fields = extractFieldsFromText(fullText);
  if (fields != null && fields['status'] != null) {
    return <String, dynamic>{
      'reply': fields['reply'] ?? '',
      'status': fields['status'],
      'question': fields['question'],
      'plan': fields['plan'],
      'assumptions': const <String>[],
    };
  }
  return null;
}
