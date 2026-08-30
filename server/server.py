import os, json, re
from datetime import datetime, timedelta
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
import httpx

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
DEEPSEEK_URL = "https://api.deepseek.com/v1/chat/completions"

SYSTEM_PROMPT = """你是 SheNicest 的睡前时间规划助手。

你的职责不是催促、批评或管教用户，而是根据用户今晚的状态、当前时间和明早安排，帮助用户制定一个温和、可执行、最多 3 步的睡前计划。

【🔴 核心原则：优先直接生成 plan，不要追问】
- **第一轮对话就必须输出 ready 状态的 plan**，不要使用 need_more_info 反复追问用户。
- 用户没说起床时间 → 默认 07:30，写入 assumptions 标记「默认起床时间 07:30」。
- 用户没说疲劳程度 → 默认中等疲劳，写入 assumptions 标记「未提供疲劳度，按中等估计」。
- 用户没说替代活动 → 默认「音乐」，写入 assumptions 标记「默认替代活动：音乐」。
- 用户没说当前时间 → 系统已注入「当前时间：YYYY-MM-DD HH:MM」，按这个时间算。
- 只有在以下情况才允许 need_more_info：
  1. 用户明确表达严重困惑、想自杀、自伤或紧急危险（应温和建议寻求专业帮助）；
  2. 用户明确说"我想再聊聊一会儿"、"先别给我计划"、"我有问题想问你"等要求更多对话的意愿；
  3. 用户表达的内容完全无法理解（无法推断任何意图）。
- 普通的"我有点累"、"脑子停不下来"、"想再刷一会儿"等模糊表述，都应该直接生成 plan。

【🔴 三步时间规划逻辑 — 必须严格遵守】
用户会告诉你一个「起始时间」和「睡觉时间」（或从中可以推断出），你需要按以下规则生成三个步骤：

**第一步：放下手边的事，靠一靠**
- 时间 = 用户说的起始时间（如"22:40起"→ 第一步 time = "22:40"）
- action = "放下手边的事，靠一靠"
- 如果用户没说起始时间，默认 = 当前时间 + 5 分钟

**第二步：听点轻音乐，什么都不想**
- 时间 = 第一步时间 + 10~15 分钟
- action = "听点轻音乐，什么都不想"

**第三步：准备结束今天（用户设定的睡觉时间）**
- 时间 = 用户说的睡觉时间（如"23:00睡"→ 第三步 time = "23:00"）
- action = "准备结束今天"
- 如果用户没说睡觉时间，默认 = 第一步时间 + 20 分钟

举例：用户说"22:40起，连续刷10分钟我就轻轻提醒你，23:00睡"
- 第一步 time="22:40", action="放下手边的事，靠一靠"
- 第二步 time="22:50", action="听点轻音乐，什么都不想"
- 第三步 time="23:00", action="准备结束今天"
- recommended_bedtime = "23:00"（= 第三步时间）
- wind_down_time = "22:40"（= 第一步时间）
- reminder_time = "22:50"（= 第二步时间）

【🔴 时间约束】
- 从 recommended_bedtime 到 wake_time（明早起床）的睡眠时长保持 **7~9 小时**（默认 8 小时）。
- 三个步骤时间必须符合先后顺序，不能倒序。
- 跨越午夜时必须正确处理日期。
- 如果用户说的起始时间已经过了，按当前时间 + 5 分钟算。

规划原则：
- 优先保证用户明早安排和合理睡眠时间。
- 不强迫用户立刻睡觉，允许设置明确的缓冲和收尾时间。
- 计划最多 3 步，每一步必须有具体时间和明确动作。
- 用户不接受建议时，提供更轻量的替代方案。
- 不评价用户是否自律，不制造羞耻、焦虑或睡眠压力。
- 不提供疾病诊断、药物建议或治疗承诺。
- 用户提到严重失眠、持续痛苦、自伤或紧急危险时，停止普通规划，温和建议寻求专业或紧急帮助。
- 不虚构用户没有提供的信息；使用默认值时必须明确标记到 assumptions 数组。

**只输出下面格式的 JSON，不要添加 Markdown，不要在 JSON 前后写任何自然语言文字：**

{
  "reply": "给用户的简短、温和回复（一两句话即可，例如：好的，我帮你整理了一份轻柔的安排，看看合不合适）",
  "status": "ready",
  "question": null,
  "plan": {
    "wake_time": "07:30",
    "recommended_bedtime": "23:00",
    "wind_down_time": "22:40",
    "reminder_time": "22:50",
    "steps": [
      {
        "time": "22:40",
        "action": "放下手边的事，靠一靠"
      },
      {
        "time": "22:50",
        "action": "听点轻音乐，什么都不想"
      },
      {
        "time": "23:00",
        "action": "准备结束今天"
      }
    ],
    "replacement_activity": "音乐",
    "extension_minutes": 10
  },
  "assumptions": ["默认起床时间 07:30", "默认替代活动：音乐"]
}"""

FALLBACK_PLAN = {
    "reply": "我先按简单方案帮你安排。今晚给自己留一点收尾时间就好。",
    "status": "ready",
    "question": None,
    "plan": {
        "wake_time": "07:30",
        "recommended_bedtime": (datetime.now() + timedelta(hours=1)).strftime("%H:%M"),
        "wind_down_time": (datetime.now() + timedelta(minutes=10)).strftime("%H:%M"),
        "reminder_time": (datetime.now() + timedelta(minutes=20)).strftime("%H:%M"),
        "steps": [
            {"time": (datetime.now() + timedelta(minutes=10)).strftime("%H:%M"), "action": "完成手边的事情"},
            {"time": (datetime.now() + timedelta(minutes=20)).strftime("%H:%M"), "action": "放松 10 分钟"},
            {"time": (datetime.now() + timedelta(hours=1)).strftime("%H:%M"), "action": "准备结束今天"}
        ],
        "replacement_activity": "音乐",
        "extension_minutes": 10
    },
    "assumptions": ["默认起床时间 07:30", "默认延长 10 分钟"]
}


def validate_plan(data):
    """四层校验之一：强制 JSON Schema 校验"""
    if not isinstance(data, dict):
        return False
    if "reply" not in data or "status" not in data:
        return False
    status = data.get("status")
    if status not in ("need_more_info", "ready"):
        return False
    if status == "ready":
        plan = data.get("plan")
        if not isinstance(plan, dict):
            return False
        # 时间先后顺序校验
        try:
            wake = datetime.strptime(plan.get("wake_time", ""), "%H:%M")
            bed = datetime.strptime(plan.get("recommended_bedtime", ""), "%H:%M")
            wind = datetime.strptime(plan.get("wind_down_time", ""), "%H:%M")
            remind = datetime.strptime(plan.get("reminder_time", ""), "%H:%M")
            now = datetime.now()
            # 不生成已经过去的提醒时间
            def _in_past(t):
                full = now.replace(hour=t.hour, minute=t.minute, second=0, microsecond=0)
                # 跨午夜处理：如果时间比现在早超过6小时，认为是次日
                diff = (now - full).total_seconds()
                if 0 < diff < 6 * 3600:
                    return True
                return False
            if _in_past(remind):
                return False
        except (ValueError, TypeError):
            return False
        steps = plan.get("steps", [])
        if not isinstance(steps, list) or len(steps) > 3 or len(steps) == 0:
            return False
        for s in steps:
            if not isinstance(s, dict) or "time" not in s or "action" not in s:
                return False
            if not s.get("action", "").strip() or not s.get("time", "").strip():
                return False
        if not isinstance(plan.get("replacement_activity", ""), str):
            return False
        if not isinstance(plan.get("extension_minutes", 0), int):
            return False
    elif status == "need_more_info":
        if not isinstance(data.get("question"), str) or not data.get("question", "").strip():
            return False
        if data.get("plan") is not None:
            return False
    assumptions = data.get("assumptions", [])
    if not isinstance(assumptions, list):
        return False
    return True


def extract_json(text):
    """从模型输出中提取 JSON，支持被自然语言包裹的场景"""
    # 先尝试找最外层的完整 JSON 对象（匹配成对大括号）
    start = text.find('{')
    if start == -1:
        return None
    depth = 0
    end = -1
    in_str = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if escape:
            escape = False
            continue
        if ch == '\\':
            escape = True
            continue
        if ch == '"':
            in_str = not in_str
            continue
        if not in_str:
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    end = i
                    break
    if end == -1:
        # 回退到简单正则
        matches = list(re.finditer(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', text))
        if not matches:
            return None
        candidate = matches[-1].group()
    else:
        candidate = text[start:end+1]
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        return None


def extract_json_fallback(text):
    """2026-08-29 修复：当 extract_json 失败时，用 regex 从非标准 JSON 文本中提取字段。
    DeepSeek 可能输出无外层 {}、字段间无逗号的非标准格式，导致 extract_json 解析失败。"""
    # 提取 status
    status_m = re.search(r'"status"\s*:\s*"(\w+)"', text)
    status = status_m.group(1) if status_m else None
    # 提取 reply（完整值）
    reply_m = re.search(r'"reply"\s*:\s*"((?:[^"\\]|\\.)*)"', text)
    reply = reply_m.group(1) if reply_m else None
    if reply is None:
        # 不完整的 reply（没闭合的 "）
        reply_m2 = re.search(r'"reply"\s*:\s*"((?:[^"\\]|\\.)*)', text)
        reply = reply_m2.group(1) if reply_m2 else None
    # 提取 question
    question_m = re.search(r'"question"\s*:\s*(?:"((?:[^"\\]|\\.)*)"|null)', text)
    question = None
    if question_m and question_m.group(1) is not None:
        question = question_m.group(1)
    # 提取 plan（平衡匹配 {}）
    plan = None
    plan_idx = text.find('"plan"')
    if plan_idx != -1:
        colon_idx = text.find(':', plan_idx + 6)
        if colon_idx != -1:
            after = text[colon_idx + 1:].strip()
            if after.startswith('{'):
                depth = 0
                end = -1
                in_str = False
                escape = False
                for i, ch in enumerate(after):
                    if escape:
                        escape = False
                        continue
                    if ch == '\\':
                        escape = True
                        continue
                    if ch == '"':
                        in_str = not in_str
                        continue
                    if not in_str:
                        if ch == '{':
                            depth += 1
                        elif ch == '}':
                            depth -= 1
                            if depth == 0:
                                end = i
                                break
                if end != -1:
                    plan_text = after[:end + 1]
                elif depth > 0:
                    # plan JSON 不完整，尝试补全 }
                    plan_text = after + '}' * depth
                else:
                    plan_text = None
                if plan_text:
                    try:
                        plan = json.loads(plan_text)
                    except json.JSONDecodeError:
                        # 尝试修复缺失的逗号
                        plan_fixed = _fix_json_commas(plan_text)
                        try:
                            plan = json.loads(plan_fixed)
                        except json.JSONDecodeError:
                            pass
    # 提取 assumptions
    assumptions = []
    assum_m = re.search(r'"assumptions"\s*:\s*\[([^\]]*)\]', text)
    if assum_m:
        assumptions = re.findall(r'"([^"]*)"', assum_m.group(1))
    if status is None and reply is None:
        return None
    return {
        "reply": reply or "",
        "status": status or "",
        "question": question,
        "plan": plan,
        "assumptions": assumptions
    }


def _fix_json_commas(text):
    """修复 JSON 字段间缺失的逗号（DeepSeek 非标准输出）"""
    fixed = text
    # " 后跟 " 补逗号
    fixed = re.sub(r'"\s*\n\s*"', '", "', fixed)
    # null 后跟 " 补逗号
    fixed = re.sub(r'null\s*\n\s*"', 'null, "', fixed, flags=re.IGNORECASE)
    # } 后跟 " 补逗号
    fixed = re.sub(r'}\s*\n\s*"', '}, "', fixed)
    # " 后跟 null 补逗号
    fixed = re.sub(r'"\s*\n\s*null', '", null', fixed, flags=re.IGNORECASE)
    # " 后跟 { 补逗号
    fixed = re.sub(r'"\s*\n\s*\{', '", {', fixed)
    # " 后跟 [ 补逗号
    fixed = re.sub(r'"\s*\n\s*\[', '", [', fixed)
    # ] 后跟 " 补逗号
    fixed = re.sub(r'\]\s*\n\s*"', '], "', fixed)
    return fixed


def wrap_as_need_more_info(natural_text: str) -> dict:
    """将 AI 自然语言回复包装为 need_more_info 结构，保证客户端正常显示"""
    # 去除末尾空白和 markdown 标记
    cleaned = natural_text.strip()
    cleaned = re.sub(r'^```json\s*', '', cleaned)
    cleaned = re.sub(r'\s*```$', '', cleaned).strip()
    # 尝试提取一句话作为问题（取第一个问号或句号之前的内容）
    question = cleaned
    m = re.search(r'([^。！？\n]*[？?])', cleaned)
    if m:
        question = m.group(1).strip()
    else:
        # 取前 80 字
        question = cleaned[:80]
    return {
        "reply": cleaned,
        "status": "need_more_info",
        "question": question,
        "plan": None,
        "assumptions": []
    }


def validate_and_fix_times(data: dict) -> dict:
    """四层校验之二：时间计算校验 + 业务规则兜底（本地修正模型不合理输出但尽量保留 DeepSeek 原文）"""
    if not isinstance(data, dict):
        return FALLBACK_PLAN.copy()
    if data.get("status") != "ready":
        return data
    plan = data.get("plan") or {}
    if not isinstance(plan, dict):
        plan = {}
    now = datetime.now()

    def _parse(t):
        """宽容时间解析：支持 7:30 / 07:30 / 7：30（全角冒号）/ 23点30分 / 11pm 等"""
        if not isinstance(t, str):
            return None
        s = t.strip()
        if not s:
            return None
        # 尝试 strptime 标准格式
        for fmt in ("%H:%M", "%H.%M", "%I:%M %p", "%H:%M:%S"):
            try:
                dt = datetime.strptime(s, fmt)
                return now.replace(hour=dt.hour, minute=dt.minute, second=0, microsecond=0)
            except (ValueError, TypeError):
                continue
        # 正则兜底：提取数字
        m = re.search(r'(\d{1,2})\s*[:：\.]\s*(\d{1,2})', s)
        if m:
            h, mi = int(m.group(1)), int(m.group(2))
            if 0 <= h <= 23 and 0 <= mi <= 59:
                return now.replace(hour=h, minute=mi, second=0, microsecond=0)
        m = re.search(r'(\d{1,2})\s*点\s*(\d{1,2})?', s)
        if m:
            h = int(m.group(1))
            mi = int(m.group(2)) if m.group(2) else 0
            if 0 <= h <= 23 and 0 <= mi <= 59:
                return now.replace(hour=h, minute=mi, second=0, microsecond=0)
        return None

    def _fmt(dt):
        # 2026-08-29 修复：兼容字符串输入（plan 里可能存的是字符串而非 datetime）
        if isinstance(dt, str):
            parsed = _parse(dt)
            if parsed is not None:
                dt = parsed
            else:
                return dt  # 无法解析，返回原始字符串
        if hasattr(dt, 'strftime'):
            return dt.strftime("%H:%M")
        return str(dt)

    def _is_past(dt):
        """时间是否已过去（跨午夜宽容：如果时间比现在早超过6小时，视为次日不判定为过去）"""
        diff = (now - dt).total_seconds()
        return 0 < diff < 6 * 3600

    # 1) wake_time：默认 07:30
    wake_dt = _parse(plan.get("wake_time", ""))
    assumptions_out = list(data.get("assumptions") if isinstance(data.get("assumptions"), list) else [])
    if wake_dt is None:
        wake_dt = now.replace(hour=7, minute=30, second=0, microsecond=0)
        # 如果这个起床时间离现在太近（<2小时）视为明天
        if (wake_dt - now).total_seconds() < 2 * 3600:
            wake_dt += timedelta(days=1)
        assumptions_out.append("默认起床时间 07:30")

    # 2) recommended_bedtime：默认 wake 前 8 小时
    bed_dt = _parse(plan.get("recommended_bedtime", ""))
    if bed_dt is None:
        bed_dt = wake_dt - timedelta(hours=8)
        # 若 bedtime 已经过去（但不足6小时）→ 视为今天过去的 bedtime，不正常
        if _is_past(bed_dt):
            # 改到 wake 的前一天这个时刻
            # 最简单的处理：如果 bedtime 过去时间不长，以当前时间+30分钟为新 bedtime
            bed_dt = now + timedelta(minutes=30)

    # 3) wind_down_time & reminder_time
    wind_dt = _parse(plan.get("wind_down_time", ""))
    if wind_dt is None:
        wind_dt = bed_dt - timedelta(minutes=20)
        if _is_past(wind_dt):
            wind_dt = now + timedelta(minutes=5)
    remind_dt = _parse(plan.get("reminder_time", ""))
    if remind_dt is None:
        remind_dt = bed_dt - timedelta(minutes=10)
        if _is_past(remind_dt):
            remind_dt = now + timedelta(minutes=10)

    # 4) steps 修正：DeepSeek 可能给的是 str 数组 或 action/time 轻微格式不对
    raw_steps = plan.get("steps") if isinstance(plan.get("steps"), list) else []
    steps = []
    for i, s in enumerate(raw_steps):
        action = ""
        t_dt = None
        if isinstance(s, str):
            action = s.strip()
        elif isinstance(s, dict):
            action = str(s.get("action", "")).strip()
            t_dt = _parse(s.get("time", ""))
        if not action:
            continue
        if t_dt is None:
            if len(steps) == 0:
                t_dt = wind_dt
            else:
                t_dt = steps[-1]["_dt"] + timedelta(minutes=10)
        steps.append({"action": action, "time": _fmt(t_dt), "_dt": t_dt})

    # 完全没有 steps → 本地兜底 3 步
    if len(steps) == 0:
        steps = [
            {"action": "完成手边的事", "_dt": wind_dt},
            {"action": "换一种放松方式", "_dt": remind_dt},
            {"action": "准备结束今天", "_dt": bed_dt},
        ]
        assumptions_out.append("未给出具体步骤，已生成本地建议的三步")
    steps = steps[:3]  # 最多 3 步

    # ===== 2026-08-29 新增：本地强制收紧时间跨度（服务器兜底，不让 AI 拉太远）=====
    def _mins_between(a, b):
        """两个 datetime 之间的分钟差（宽容跨午夜：如果差 < 0 且绝对值 > 6h，视为 b 在次日）"""
        d = (b - a).total_seconds() / 60
        if d < 0 and -d > 6 * 60:
            d += 24 * 60
        return d

    # (a) 从 now 到 bedtime 的总跨度：最多 90 分钟（强制）
    span_bed = _mins_between(now, bed_dt)
    if span_bed > 90:
        # 收紧到 now + 75 分钟（留 15 分钟缓冲让用户进入计划）
        new_bed = now + timedelta(minutes=75)
        bed_dt = new_bed
        assumptions_out.append(f"建议收尾时间从原来的 {_fmt(plan.get('recommended_bedtime', ''))} 收紧到 {_fmt(bed_dt)}（总跨度不超过 90 分钟）")

    # (b) wind_down / reminder 强制在 now 之后且不超过 bedtime - 10
    if _is_past(wind_dt) or _mins_between(wind_dt, bed_dt) > 45 or _mins_between(now, wind_dt) > 15:
        wind_dt = now + timedelta(minutes=5)
    if _is_past(remind_dt) or _mins_between(remind_dt, bed_dt) > 20 or _mins_between(wind_dt, remind_dt) < 10:
        remind_dt = bed_dt - timedelta(minutes=10)
        if _mins_between(wind_dt, remind_dt) < 10:
            remind_dt = wind_dt + timedelta(minutes=15)

    # (c) 重算每个 step 的时间（强制间隔 20 分钟、跨度 ≤ 60 分钟）
    #     把 steps 按数量均匀分布到 [wind_dt, bed_dt]
    if steps:
        n = len(steps)
        # 最后一个 step 放在 bedtime 前 5 分钟以内（收尾动作）
        last_dt = bed_dt - timedelta(minutes=5)
        # 中间的 step 均匀分布在 wind_dt ~ last_dt 之间
        if n == 1:
            steps[0]["_dt"] = bed_dt - timedelta(minutes=5)
        elif n == 2:
            steps[0]["_dt"] = wind_dt
            steps[1]["_dt"] = last_dt
        else:
            # 3 步：wind_dt, wind_dt + 25, last_dt
            steps[0]["_dt"] = wind_dt
            steps[1]["_dt"] = wind_dt + timedelta(minutes=25)
            steps[2]["_dt"] = last_dt
        # 强制所有 step 在 now + 0~15 分钟之后开始（让用户能立刻开始第一个动作）
        for s in steps:
            if _mins_between(now, s["_dt"]) > 15:
                s["_dt"] = now + timedelta(minutes=5)
                assumptions_out.append("第一步时间提前到当前 +5 分钟，让你立刻开始")
                break  # 只改第一步，后面按间隔顺延
        # 统一写回 time 字符串
        for s in steps:
            s["time"] = _fmt(s["_dt"])

    # (d) 睡眠时间：bedtime 到 wake 强制 7~9h，默认 8h
    sleep_hrs = _mins_between(bed_dt, wake_dt) / 60
    if sleep_hrs < 6:
        # 睡眠时间不够：把 bedtime 再提前（最保守）
        bed_dt = wake_dt - timedelta(hours=8)
        if _mins_between(now, bed_dt) > 90:
            bed_dt = now + timedelta(minutes=75)
        assumptions_out.append("睡眠时间不足 6 小时，已把建议收尾时间前移保证休息")
    elif sleep_hrs > 9:
        # 睡眠太多：适度收紧（最多收到 8.5h）
        bed_dt = wake_dt - timedelta(hours=8, minutes=30)
        assumptions_out.append("睡眠时间超过 9 小时，已适度收紧")

    # 5) 写回修正后的 plan（**保留 DeepSeek 提供的其他字段 + 修正时间**）
    plan_out = {
        "wake_time": _fmt(wake_dt),
        "recommended_bedtime": _fmt(bed_dt),
        "wind_down_time": _fmt(wind_dt),
        "reminder_time": _fmt(remind_dt),
        "steps": [{"time": s["time"], "action": s["action"]} for s in steps],
        "replacement_activity": plan.get("replacement_activity") if isinstance(plan.get("replacement_activity"), str) and plan.get("replacement_activity") else "音乐",
        "extension_minutes": int(plan.get("extension_minutes")) if isinstance(plan.get("extension_minutes"), int) and plan.get("extension_minutes") > 0 else 10,
    }

    # **优先保留 DeepSeek 的 reply 文案**，绝不使用 FALLBACK_PLAN 的默认 reply
    reply_text = data.get("reply") if isinstance(data.get("reply"), str) and data.get("reply").strip() else "好的，我帮你整理好了今晚的安排，看看合不合适？"

    return {
        "reply": reply_text,
        "status": "ready",
        "question": None,
        "plan": plan_out,
        "assumptions": assumptions_out,
    }


@app.post("/chat")
async def chat(request: Request):
    body = await request.json()
    messages = body.get("messages", [])
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    context_msg = {"role": "system", "content": f"当前时间：{now}"}
    payload = {
        "model": "deepseek-chat",
        "messages": [{"role": "system", "content": SYSTEM_PROMPT}, context_msg] + messages,
        "max_tokens": 800,
        "temperature": 0.7,
        "stream": True,
    }
    headers = {"Authorization": f"Bearer {DEEPSEEK_API_KEY}", "Content-Type": "application/json"}

    async def stream():
        full_text = ""
        transport_error = False
        try:
            if not DEEPSEEK_API_KEY:
                # API Key 未配置 → 直接走本地兜底（标记为异常路径）
                raise RuntimeError("DEEPSEEK_API_KEY not configured")
            async with httpx.AsyncClient(timeout=90.0) as client:
                async with client.stream("POST", DEEPSEEK_URL, json=payload, headers=headers) as resp:
                    async for line in resp.aiter_lines():
                        if line.startswith("data: ") and line != "data: [DONE]":
                            try:
                                data = json.loads(line[6:])
                                delta = data.get("choices", [{}])[0].get("delta", {})
                                c = delta.get("content", "")
                                if c:
                                    full_text += c
                                    yield f"data: {json.dumps({'content': c}, ensure_ascii=False)}\n\n"
                            except json.JSONDecodeError:
                                continue
        except Exception:
            # 仅在传输/鉴权异常时使用 FALLBACK_PLAN (ready 状态)
            transport_error = True
            fallback = json.dumps(FALLBACK_PLAN, ensure_ascii=False)
            yield f"data: {json.dumps({'content': fallback}, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"
            return

        if not full_text.strip():
            # 空内容才用兜底计划
            fb = json.dumps(FALLBACK_PLAN, ensure_ascii=False)
            yield "data: " + json.dumps({"content": fb}, ensure_ascii=False) + "\n\n"
            yield "data: [DONE]\n\n"
            return

        # ====== 四层校验 & 处理流程（聊天与执行分离） ======
        # 2026-08-29 防御性 try-except：处理流程任何异常都不应中断流式连接，
        # 出错时用 FALLBACK_PLAN 兜底 + 保留 DeepSeek 原始 reply，保证客户端能拿到 plan
        try:
            # 第 1 步：尝试从模型输出提取 JSON
            parsed = extract_json(full_text)
            # 2026-08-29 修复：extract_json 失败时用 regex fallback 提取非标准 JSON
            # DeepSeek 可能输出无外层 {}、字段间无逗号的格式
            if parsed is None:
                parsed = extract_json_fallback(full_text)
            final_payload = None
            if parsed is not None and isinstance(parsed, dict):
                status = parsed.get("status")
                if status == "ready":
                    # ===== 核心修复：基于 DeepSeek 的 parsed 做宽容修正 =====
                    # 即使 validate_plan 失败（时间格式/字段轻微异常），也直接喂 validate_and_fix_times，
                    # 它会保留 DeepSeek 的 reply + action 文本，只修正缺省字段
                    final_payload = validate_and_fix_times(parsed)
                    # 修正后若仍不通过（极端异常），则拿 FALLBACK 结构兜底，但仍保留 DeepSeek 的 reply！
                    if not validate_plan(final_payload):
                        fb = validate_and_fix_times(FALLBACK_PLAN.copy())
                        preserved_reply = (
                            parsed.get("reply")
                            if isinstance(parsed.get("reply"), str) and parsed.get("reply").strip()
                            else fb.get("reply", "")
                        )
                        fb["reply"] = preserved_reply
                        fb["assumptions"] = list(fb.get("assumptions") or []) + ["模型输出格式异常，已启用本地修正方案"]
                        final_payload = fb
                elif status == "need_more_info":
                    # DeepSeek 说 need_more_info：补全 question/plan null，保持 reply 原文
                    question = parsed.get("question")
                    cleaned_reply = (
                        parsed.get("reply")
                        if isinstance(parsed.get("reply"), str) and parsed.get("reply").strip()
                        else full_text.strip()
                    )
                    if not isinstance(question, str) or not question.strip():
                        m = re.search(r'([^。！？\n]*[？?])', cleaned_reply)
                        question = m.group(1).strip() if m else cleaned_reply[:80]
                    assumptions = parsed.get("assumptions")
                    final_payload = {
                        "reply": cleaned_reply,
                        "status": "need_more_info",
                        "question": question,
                        "plan": None,
                        "assumptions": assumptions if isinstance(assumptions, list) else []
                    }
                else:
                    # status 未知 → 视为纯自然语言
                    final_payload = wrap_as_need_more_info(full_text)
            else:
                # 提取不到 JSON 结构 → 纯自然语言对话（信息收集阶段）
                final_payload = wrap_as_need_more_info(full_text)

            # 如果最终 payload 是 ready 计划，且流式输出里没有完整合法 JSON → 补发修正后的 JSON
            # 这样客户端可以拿到结构化 plan；但只要 DeepSeek 原文有 JSON，就沿用（已经通过 validate_and_fix_times 修正）
            if final_payload.get("status") == "ready":
                existing_json = extract_json(full_text)
                already_valid = (
                    existing_json is not None
                    and isinstance(existing_json, dict)
                    and existing_json.get("status") == "ready"
                    and validate_plan(validate_and_fix_times(existing_json))
                )
                if not already_valid:
                    corrected_text = json.dumps(final_payload, ensure_ascii=False)
                    # 用 \n\n 作为分隔符，客户端会优先提取**最后一个**合法 JSON 作为 plan 结构
                    yield "data: " + json.dumps({"content": "\n\n"}, ensure_ascii=False) + "\n\n"
                    chunk_size = 64
                    s = corrected_text
                    for i in range(0, len(s), chunk_size):
                        yield "data: " + json.dumps({"content": s[i:i+chunk_size]}, ensure_ascii=False) + "\n\n"
        except Exception as e:
            # 处理流程异常 → 用 FALLBACK_PLAN 兜底，保留 DeepSeek 原始文本作为 reply
            import traceback
            print(f"[stream] 处理异常: {e}\n{traceback.format_exc()}")
            try:
                preserved_reply = full_text.strip()[:200] if full_text.strip() else "好的，我帮你整理好了今晚的安排。"
            except Exception:
                preserved_reply = "好的，我帮你整理好了今晚的安排。"
            safe_payload = validate_and_fix_times(FALLBACK_PLAN.copy())
            safe_payload["reply"] = preserved_reply
            safe_payload["assumptions"] = list(safe_payload.get("assumptions") or []) + ["服务端处理异常，已启用兜底方案"]
            corrected_text = json.dumps(safe_payload, ensure_ascii=False)
            yield "data: " + json.dumps({"content": "\n\n"}, ensure_ascii=False) + "\n\n"
            chunk_size = 64
            s = corrected_text
            for i in range(0, len(s), chunk_size):
                yield "data: " + json.dumps({"content": s[i:i+chunk_size]}, ensure_ascii=False) + "\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.get("/health")
async def health():
    return {"status": "ok", "ai": "deepseek"}


# ==================== 个性化通知生成 ====================

NOTIFY_SYSTEM_PROMPT = """你是 SheNicest 的睡前通知文案生成器。根据用户的入睡计划和聊天记录，生成一条个性化的推送通知。

【输入】你会收到一个 JSON，包含：
- stage: 当前阶段（wind_down=入睡前提醒, agenda=今晚日程, bedtime=到点入睡, extended=延时后）
- plan: 用户的入睡计划（recommended_bedtime, wake_time, steps, remaining_tasks 等）
- chat_summary: 用户聊天中提到的关键信息

【输出】只返回一个 JSON，格式：
{"title": "通知标题", "body": "通知正文", "used_fields": ["用到的字段名"]}

【文案规则】
1. 每条通知至少引用一项用户真实说过的信息
2. 优先使用入睡时间、起床时间和今晚待办
3. 先表达系统记得的内容，再给出一个具体行动建议
4. 一次只推动一个动作，不要同时要求用户完成多件事
5. 使用陈述句和轻量祈使句，不使用问句
6. 不使用"您已使用手机很长时间""健康提醒""准备结束今天"等系统化表达
7. 不训诫、不制造焦虑、不评价用户自控力
8. 通知正文控制在两句话以内
9. 不编造聊天记录中没有出现的事情
10. 缺少个性化信息时逐级降级，只使用已有信息，不允许补写虚假细节

【各阶段重点】
- wind_down: 重点提醒目标入睡时间，结合还没完成的事情提示开始收尾
- agenda: 根据剩余事项，提醒用户接下来做一件最具体的事情
- bedtime: 到达目标入睡时间后，结合计划完成情况提醒用户睡觉
- extended: 结合原定入睡时间、起床时间和累计延时时长生成

【标题规则】
标题优先引用最重要的计划信息，例如：
- "你说今晚 23:30 想睡"
- "睡前还剩一件事"
- "明早 7:30 还要起"
- "已经到今晚的入睡时间了"

【降级规则】
如果信息不足，使用已有信息生成，不要编造。完全没有信息时返回：
{"title": "今晚，慢一点", "body": "时间不早了，慢慢收尾吧。", "used_fields": []}
"""

# 各阶段降级文案
FALLBACK_NOTIFY = {
    "wind_down": {"title": "今晚，慢一点", "body": "时间不早了，可以慢慢收尾了。"},
    "agenda": {"title": "今晚，慢一点", "body": "接下来做一件最重要的事就好。"},
    "bedtime": {"title": "今晚，慢一点", "body": "到时间了，去睡吧。"},
    "extended": {"title": "今晚，慢一点", "body": "已经比计划晚了，今晚就到这里吧。"},
}


@app.post("/api/v1/notify")
async def generate_notify(req: Request):
    """根据入睡计划生成个性化通知文案"""
    try:
        body = await req.json()
        stage = body.get("stage", "wind_down")
        plan = body.get("plan", {})
        chat_summary = body.get("chat_summary", "")

        # 构建 user message
        plan_info = json.dumps(plan, ensure_ascii=False, indent=2)
        user_msg = f"""stage: {stage}
plan: {plan_info}
chat_summary: {chat_summary}

请根据以上信息生成一条个性化通知。只返回 JSON。"""

        # 调用 DeepSeek
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                DEEPSEEK_URL,
                headers={
                    "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": "deepseek-chat",
                    "messages": [
                        {"role": "system", "content": NOTIFY_SYSTEM_PROMPT},
                        {"role": "user", "content": user_msg},
                    ],
                    "max_tokens": 200,
                    "temperature": 0.7,
                },
            )
            resp.raise_for_status()
            data = resp.json()
            content = data["choices"][0]["message"]["content"].strip()

            # 提取 JSON（兼容 markdown code block）
            json_match = re.search(r'\{[^{}]*\}', content, re.DOTALL)
            if json_match:
                result = json.loads(json_match.group())
                return {
                    "title": result.get("title", FALLBACK_NOTIFY.get(stage, FALLBACK_NOTIFY["wind_down"])["title"]),
                    "body": result.get("body", FALLBACK_NOTIFY.get(stage, FALLBACK_NOTIFY["wind_down"])["body"]),
                    "used_fields": result.get("used_fields", []),
                    "source": "deepseek",
                }

        # JSON 解析失败 → 降级
        fb = FALLBACK_NOTIFY.get(stage, FALLBACK_NOTIFY["wind_down"])
        return {"title": fb["title"], "body": fb["body"], "used_fields": [], "source": "fallback_parse"}

    except Exception as e:
        fb = FALLBACK_NOTIFY.get(stage, FALLBACK_NOTIFY["wind_down"])
        return {"title": fb["title"], "body": fb["body"], "used_fields": [], "source": f"fallback_error: {str(e)[:100]}"}
