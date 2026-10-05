import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../app_controller.dart';
import '../models/tonight_plan.dart';
import '../theme/app_theme.dart';
import '../utils/ai_response_parser.dart';

class ChatMessage {
  final bool isUser;
  final String text;
  final bool isPlan;
  final Map<String, dynamic>? planData;
  ChatMessage({required this.isUser, required this.text, this.isPlan = false, this.planData});
}

/// 清理流式结尾多余的 \n\n 分隔符和半截 JSON
String cleanDisplayText(String raw) {
  String s = raw.trim();
  // 2026-08-29 核心修复：优先用 regex 提取 reply 值，不管 JSON 格式是否合法。
  // DeepSeek 可能输出非标准 JSON（无外层 {}、字段间无逗号），
  // 此时 _lastJsonBlockRange 会误匹配 plan 子对象里的 {}，导致裸字段泄露给用户。
  final replyComplete = RegExp(r'"reply"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(s);
  if (replyComplete != null) {
    var v = replyComplete.group(1) ?? '';
    v = v.replaceAll('\\n', '\n').replaceAll('\\"', '"').replaceAll('\\\\', '\\');
    if (v.trim().isNotEmpty) return v.trim();
  }
  // 回退：用位置匹配移除最后一个合法 JSON 块
  final block = _lastJsonBlockRange(s);
  if (block != null) {
    String before = s.substring(0, block.$1).trim();
    while (before.endsWith('\n')) before = before.substring(0, before.length - 1).trim();
    if (before.isNotEmpty) {
      // before 里可能有裸 "reply":"..." 字段，尝试提取
      final m2 = RegExp(r'"reply"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(before);
      if (m2 != null) {
        var v = m2.group(1) ?? '';
        v = v.replaceAll('\\n', '\n').replaceAll('\\"', '"').replaceAll('\\\\', '\\');
        if (v.trim().isNotEmpty) return v.trim();
      }
      return before;
    }
    final reply = block.$3['reply'] as String?;
    if (reply != null && reply.trim().isNotEmpty) return reply.trim();
    return '';
  }
  // 最后 fallback：不完整 reply（流式截断，值没闭合）
  final partial = RegExp(r'"reply"\s*:\s*"((?:[^"\\]|\\.)*)').firstMatch(s);
  if (partial != null) {
    var v = partial.group(1) ?? '';
    v = v.replaceAll('\\n', '\n').replaceAll('\\"', '"').replaceAll('\\\\', '\\');
    if (v.trim().isNotEmpty) return v.trim();
  }
  return s;
}

/// 返回 (start, endExclusive, parsedJson) 或 null
(int, int, Map<String, dynamic>)? _lastJsonBlockRange(String text) {
  (int, int, Map<String, dynamic>)? last;
  int searchFrom = 0;
  while (true) {
    final start = text.indexOf('{', searchFrom);
    if (start == -1) break;
    int depth = 0;
    int end = -1;
    bool inStr = false;
    bool escape = false;
    for (int i = start; i < text.length; i++) {
      final ch = text[i];
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
        final obj = jsonDecode(text.substring(start, end + 1));
        if (obj is Map<String, dynamic>) {
          last = (start, end + 1, obj);
        }
      } catch (_) {}
      searchFrom = end + 1;
    } else {
      break;
    }
  }
  return last;
}

/// 流式实时清理：DeepSeek 可能直接输出 JSON 结构，用户在 _AiReplyingWidget 看到
/// 裸字段名（"reply": ..., "status": ...）。此函数在流式累加过程中实时剥离 JSON 语法，
/// 优先提取 reply 字段值作为显示文本。
String cleanStreamingDisplay(String raw) {
  // 2026-08-29 核心修复：优先从整个 raw 提取 reply 值，不管 { 在哪里。
  // 旧逻辑找 { 后只在其后找 reply，但 DeepSeek 非标准 JSON 中
  // "reply" 在 "plan":{ 之前 → reply 被遗漏在 before 里 → 用户看到裸字段。
  final m = RegExp(r'"reply"\s*:\s*"((?:[^"\\]|\\.)*)').firstMatch(raw);
  if (m != null) {
    var v = m.group(1) ?? '';
    v = v
        .replaceAll('\\n', '\n')
        .replaceAll('\\"', '"')
        .replaceAll('\\\\', '\\');
    if (v.trim().isNotEmpty) return v;
  }
  // 没有 reply 字段 → 隐藏裸字段名前缀和 JSON 语法
  final idx = raw.indexOf('{');
  if (idx == -1) {
    return raw.replaceFirst(
        RegExp(r'^\s*"(reply|status|question|plan|assumptions)"\s*:\s*'), '');
  }
  return raw.substring(0, idx);
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.controller, super.key});
  final AppController controller;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = stt.SpeechToText();
  final List<ChatMessage> _messages = [];
  bool _isAiReplying = false;
  bool _isListening = false;
  String _currentAiText = '';

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(
      isUser: false,
      text: '晚上好。今天的你，是累得想立刻休息，还是还舍不得结束今天？',
    ));
  }

  void _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isAiReplying) return;

    setState(() {
      _messages.add(ChatMessage(isUser: true, text: trimmed));
      _isAiReplying = true;
      _currentAiText = '';
    });
    _input.clear();
    _scrollToBottom();

    try {
      final stream = widget.controller.ai.chat(trimmed);
      await for (final chunk in stream) {
        setState(() {
          _currentAiText += chunk;
        });
        _scrollToBottom();
      }
      final fullReply = _currentAiText;

      // ====== 解析修复：extractLastJson + extractFieldsFromText 双通道 ======
      // 2026-08-29 核心修复：DeepSeek 可能输出非标准 JSON（无外层 {}、字段间无逗号），
      // extractLastJson 会误匹配 plan 子对象里的 {}，导致 status/reply 字段丢失。
      // 解决方案：两条通道都跑，选含 status 字段的那个作为有效 payload。
      String displayText;
      bool isPlan = false;
      Map<String, dynamic>? planData;

      final parsed = extractLastJson(fullReply);
      final fields = extractFieldsFromText(fullReply);
      final cleaned = cleanDisplayText(fullReply);

      // 决定使用哪个解析结果：优先用含 status 的那个
      String? status;
      String? reply;
      dynamic plan;
      String? question;
      Map<String, dynamic>? sourcePayload;

      if (parsed != null && parsed['status'] != null) {
        // extractLastJson 成功且是完整 payload
        status = parsed['status'] as String? ?? '';
        reply = parsed['reply'] as String?;
        plan = parsed['plan'];
        question = parsed['question'] as String?;
        sourcePayload = parsed;
      } else if (fields != null && fields['status'] != null) {
        // extractLastJson 失败或非完整 payload → 用 regex 提取
        status = fields['status'] as String?;
        reply = fields['reply'] as String?;
        plan = fields['plan'];
        question = fields['question'] as String?;
        // 构造 payload
        sourcePayload = <String, dynamic>{
          'reply': reply ?? '',
          'status': status ?? '',
          'plan': plan,
          'question': question,
          'assumptions': const <String>[],
        };
      }

      if (status != null) {
        if (status == 'ready') {
          displayText = reply?.trim().isNotEmpty == true
              ? reply!
              : (cleaned.isNotEmpty ? cleaned : '好的，我帮你整理好了今晚的安排。');
          if (plan is Map<String, dynamic>) {
            isPlan = true;
            planData = sourcePayload;
            // ---- AI→今晚安排 联动核心：ready plan 立即挂到 controller 共享状态
            widget.controller.setTonightPlan(TonightPlan.fromServerJson(planData!));
          }
        } else if (status == 'need_more_info') {
          if (cleaned.isNotEmpty) {
            displayText = cleaned;
          } else if (reply?.trim().isNotEmpty == true) {
            displayText = reply!;
          } else if (question?.trim().isNotEmpty == true) {
            displayText = question!;
          } else {
            displayText = fullReply.trim();
          }
        } else {
          displayText = cleaned.isNotEmpty ? cleaned : (reply ?? fullReply.trim());
        }
      } else {
        // 两条通道都没提取到 status → 直接显示清理后的文本
        displayText = cleaned.isNotEmpty ? cleaned : fullReply.trim();
      }

      // 最后安全：极端情况下 reply 仍为空，不要显示空字符串
      if (displayText.trim().isEmpty) {
        displayText = '嗯，我听到了。还有什么想告诉我的吗？';
      }

      setState(() {
        _messages.add(ChatMessage(
          isUser: false,
          text: displayText,
          isPlan: isPlan,
          planData: planData,
        ));
        _isAiReplying = false;
        _currentAiText = '';
      });
    } catch (e) {
      // 2026-08-29：打印具体错误到控制台，方便排查"网络有点卡"的真实原因
      debugPrint('[_sendMessage] 异常: $e');
      // 如果已经收到部分回复（流式中途断开），尝试解析已收到的内容
      if (_currentAiText.trim().isNotEmpty) {
        try {
          // 2026-08-29 核心修复：双通道解析（同主流程）
          final parsed = extractLastJson(_currentAiText);
          final fields = extractFieldsFromText(_currentAiText);
          final cleaned = cleanDisplayText(_currentAiText);
          String displayText;
          bool isPlan = false;
          Map<String, dynamic>? planData;

          String? status;
          String? reply;
          dynamic plan;
          Map<String, dynamic>? sourcePayload;

          if (parsed != null && parsed['status'] != null) {
            status = parsed['status'] as String? ?? '';
            reply = parsed['reply'] as String?;
            plan = parsed['plan'];
            sourcePayload = parsed;
          } else if (fields != null && fields['status'] != null) {
            status = fields['status'] as String?;
            reply = fields['reply'] as String?;
            plan = fields['plan'];
            sourcePayload = <String, dynamic>{
              'reply': reply ?? '',
              'status': status ?? '',
              'plan': plan,
              'question': fields['question'],
              'assumptions': const <String>[],
            };
          }

          if (status == 'ready' && plan is Map<String, dynamic>) {
            displayText = reply?.trim().isNotEmpty == true
                ? reply!
                : (cleaned.isNotEmpty ? cleaned : '好的，我帮你整理好了今晚的安排。');
            isPlan = true;
            planData = sourcePayload;
            widget.controller.setTonightPlan(TonightPlan.fromServerJson(planData!));
          } else if (reply != null && reply.trim().isNotEmpty) {
            displayText = reply;
          } else {
            displayText = cleaned.isNotEmpty ? cleaned : _currentAiText.trim();
          }

          if (displayText.trim().isEmpty) {
            displayText = '嗯，我听到了。还有什么想告诉我的吗？';
          }
          setState(() {
            _messages.add(ChatMessage(
              isUser: false,
              text: displayText,
              isPlan: isPlan,
              planData: planData,
            ));
            _isAiReplying = false;
            _currentAiText = '';
          });
        } catch (_) {
          setState(() {
            _messages.add(ChatMessage(
              isUser: false,
              text: '网络有点卡，你可以再说一次吗？我会陪你慢慢整理的。',
            ));
            _isAiReplying = false;
            _currentAiText = '';
          });
        }
      } else {
        setState(() {
          _messages.add(ChatMessage(
            isUser: false,
            text: '网络有点卡，你可以再说一次吗？我会陪你慢慢整理的。',
          ));
          _isAiReplying = false;
        });
      }
    }
    _scrollToBottom();
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final available = await _speech.initialize();
    if (!available) return;

    setState(() => _isListening = true);
    _speech.listen(
      localeId: 'zh_CN',
      onResult: (result) {
        setState(() {
          _input.text = result.recognizedWords;
          _input.selection = TextSelection.fromPosition(TextPosition(offset: _input.text.length));
        });
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/erhai-blue-hour.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x44102028), Color(0x22102028), Color(0xEE14252B)],
                stops: [0, 0.3, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.dusk.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('模拟演示', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    itemCount: _messages.length + (_isAiReplying ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (index == _messages.length && _isAiReplying) {
                        // 2026-08-29 修复：流式实时清理 JSON 语法，避免用户看到 "reply": ..., "status": ... 等裸字段
                        return _AiReplyingWidget(text: cleanStreamingDisplay(_currentAiText));
                      }
                      final msg = _messages[index];
                      return _MessageWidget(message: msg);
                    },
                  ),
                ),
                if (_messages.length == 1 && !_isAiReplying)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _QuickChip(label: '有点累', onTap: () => _sendMessage('有点累，但还想刷一会儿')),
                        _QuickChip(label: '脑子停不下来', onTap: () => _sendMessage('脑子停不下来')),
                        _QuickChip(label: '明早 7 点半起', onTap: () => _sendMessage('明天 7 点半要起床')),
                      ],
                    ),
                  ),
                // —— 2026-08-29 修复：用 controller.hasTonightPlan（全局共享），而不是 _messages.any（页面关掉就丢了）——
                //    这样用户聊完 → 退出聊天页 → 再回来，「看看今晚的安排」按钮依然存在。
                AnimatedBuilder(
                  animation: widget.controller,
                  builder: (_, __) {
                    final showBtn = widget.controller.hasTonightPlan && !_isAiReplying;
                    if (!showBtn) return const SizedBox.shrink();
                    final plan = widget.controller.tonightPlan!;
                    String hint;
                    try {
                      hint = '明早 ${plan.wakeTime.replaceFirst(RegExp(r'^0'), '')} 起 · ${plan.steps.length} 步';
                    } catch (_) {
                      hint = '已生成睡前安排';
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FilledButton.icon(
                              onPressed: () => Navigator.pushNamed(context, '/plan'),
                              icon: const Icon(Icons.nights_stay_rounded),
                              label: const Text('看看今晚的安排'),
                            ),
                            const SizedBox(height: 4),
                            Text(hint,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textTertiary, height: 1.4)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                _InputDock(
                  controller: _input,
                  isListening: _isListening,
                  onMicTap: _toggleListening,
                  onSend: () => _sendMessage(_input.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageWidget extends StatelessWidget {
  const _MessageWidget({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.lake.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.lake.withValues(alpha: 0.3)),
            ),
            child: Text(message.text, style: const TextStyle(fontSize: 16, height: 1.5)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        message.text,
        style: const TextStyle(fontSize: 18, height: 1.6, color: AppColors.textPrimary),
      ),
    );
  }
}

class _AiReplyingWidget extends StatelessWidget {
  const _AiReplyingWidget({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    // 流式输出文本可见（避免用户以为 AI 没回复 → 然后突然出现被"覆盖"的观感）
    if (text.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: const TextStyle(fontSize: 18, height: 1.6, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                _Dot(),
                SizedBox(width: 4),
                _Dot(delay: 200),
                SizedBox(width: 4),
                _Dot(delay: 400),
              ],
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          _Dot(),
          SizedBox(width: 4),
          _Dot(delay: 200),
          SizedBox(width: 4),
          _Dot(delay: 400),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({this.delay = 0});
  final int delay;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.quiet.withValues(alpha: 0.3 + 0.5 * _ctrl.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      labelStyle: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      side: BorderSide(color: AppColors.lake.withValues(alpha: 0.4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onPressed: onTap,
    );
  }
}

class _InputDock extends StatelessWidget {
  const _InputDock({
    required this.controller,
    required this.isListening,
    required this.onMicTap,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isListening;
  final VoidCallback onMicTap;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF273A40), Color(0xFF182A31)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onMicTap,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isListening ? AppColors.lake.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06),
                ),
                child: Icon(
                  isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: isListening ? AppColors.lake : AppColors.textTertiary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: isListening
                  ? const _WaveformAnimation()
                  : TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '告诉我你现在的感受',
                        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 15),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.moon,
                ),
                child: const Icon(Icons.arrow_upward_rounded, color: AppColors.ink, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformAnimation extends StatefulWidget {
  const _WaveformAnimation();

  @override
  State<_WaveformAnimation> createState() => _WaveformAnimationState();
}

class _WaveformAnimationState extends State<_WaveformAnimation> with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 800), vsync: this)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(28, (i) {
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final phase = i * 0.2;
            final value = (math.sin((_ctrl.value + phase) * math.pi) + 1) / 2;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3.0,
              height: (8.0 + value * 28.0),
              decoration: BoxDecoration(
                color: AppColors.lake.withValues(alpha: 0.4 + value * 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        );
      }),
    );
  }
}
