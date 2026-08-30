/**
 * ESP32-S3 护眼灯 - ntfy 系统通知版
 * 
 * 硬件接线:
 *   GPIO7  ──── 330Ω电阻 ──── DIN  (WS2812B 灯带)
 *   3V3    ─────────────────── 5V/VCC
 *   GND    ─────────────────── GND
 * 
 * 网络: 连接手机热点 Xiaomi 15 上网
 * 通知: 通过 ntfy.sh 发送系统级通知到手机
 * 
 * 功能 (亮度全部平滑过渡):
 *   1. 开始 → 平滑变到 70% 暖橙光
 *   2. 20秒 → 平滑渐变到 50% 暖光
 *   3. 30秒 → 平滑渐变到 30% 极暖光 + ntfy 系统通知
 *   4. 选"是" → 保持 30% 极暖光 10 秒 → 渐变到 5% 夜灯
 *   5. 选"否" → 平滑渐变到 5% 夜灯
 * 
 * 手机端:
 *   1. ntfy App 订阅话题: eyecare_light_x7k2
 *   2. 浏览器访问 ESP32 的 IP 地址打开控制页
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <Adafruit_NeoPixel.h>

// ==================== 配置 ====================
#define LED_PIN       7
#define NUMPIXELS     8

// 手机热点 — 烧录前改成你自己的 WiFi（手机热点）。
// ⚠️ 不要把真实密码提交到公开仓库。
const char* WIFI_SSID = "YOUR_WIFI_SSID";
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";

// ntfy 推送配置
const char* NTFY_TOPIC = "eyecare_light_x7k2";
const char* NTFY_URL   = "http://ntfy.sh/eyecare_light_x7k2";

// ==================== 全局对象 ====================
Adafruit_NeoPixel strip(NUMPIXELS, LED_PIN, NEO_GRB + NEO_KHZ800);
WebServer server(80);

// ==================== 颜色配置 ====================
#define BASE_R 255
#define BASE_G 140
#define BASE_B 40

float curR = 0, curG = 0, curB = 0;
float targetR = 0, targetG = 0, targetB = 0;
bool fading = false;
unsigned long lastFadeTime = 0;
const int fadeStepMs = 25;
// 2026-08-29 调慢渐变速度（3.0 → 1.2）：70%→50% 约 1.1s，50%→5% 约 2.4s，
// 切换更"自然平顺"（用户要求），不再是一闪而过。
const float fadeStep = 1.2;

void applyColorRaw(int r, int g, int b) {
  uint32_t color = strip.Color(r, g, b);
  for (int i = 0; i < NUMPIXELS; i++) {
    strip.setPixelColor(i, color);
  }
  strip.show();
}

void setFadeTarget(int pct, int r, int g, int b) {
  float f = pct / 100.0;
  targetR = r * f;
  targetG = g * f;
  targetB = b * f;
  fading = true;
}

bool fadeAdvance() {
  if (!fading) return true;
  unsigned long now = millis();
  if (now - lastFadeTime < fadeStepMs) return false;
  lastFadeTime = now;

  float dr = (targetR > curR) ? fadeStep : -fadeStep;
  float dg = (targetG > curG) ? fadeStep : -fadeStep;
  float db = (targetB > curB) ? fadeStep : -fadeStep;

  curR += dr; curG += dg; curB += db;

  bool done = true;
  if ((dr > 0 && curR >= targetR) || (dr < 0 && curR <= targetR)) curR = targetR; else done = false;
  if ((dg > 0 && curG >= targetG) || (dg < 0 && curG <= targetG)) curG = targetG; else done = false;
  if ((db > 0 && curB >= targetB) || (db < 0 && curB <= targetB)) curB = targetB; else done = false;

  applyColorRaw((int)curR, (int)curG, (int)curB);
  if (done) fading = false;
  return done;
}

// ==================== ntfy 推送 ====================
void sendNtfyNotification(const char* title, const char* body) {
  HTTPClient http;
  http.begin(NTFY_URL);
  http.addHeader("Title", title);
  http.addHeader("Priority", "urgent");
  http.addHeader("Tags", "alarm_clock,warning");
  int code = http.POST(body);
  if (code > 0) {
    Serial.printf("[NTFY] Sent (HTTP %d): %s\n", code, body);
  } else {
    Serial.printf("[NTFY] Failed: %s\n", http.errorToString(code).c_str());
  }
  http.end();
}

// ==================== 状态机 ====================
// v0（旧）: IDLE -> TIMING(20s) -> REACHED_20 -> WAITING_CHOICE -> DELAYING -> NIGHT
// v1（App 直接控制，推荐）：SheNicest 发送 /b 和 /s，App 自己负责时间调度。
//     状态：IDLE / PLANNED / OBSERVING / NUDGED / EXTENDING / REPLACING / MUTED / FINISHED
//     与 Flutter NightSessionState 命名一一对应，App 读取 /status 的 current_state 直接显示
enum State {
  // v0 旧状态（保留兼容）
  IDLE, TIMING, REACHED_20, WAITING_CHOICE, DELAYING, NIGHT_LIGHT,
  // v1 新状态
  ST_PLANNED, ST_OBSERVING, ST_NUDGED, ST_EXTENDING, ST_REPLACING, ST_MUTED, ST_FINISHED
};
State state = IDLE;

unsigned long startTime = 0;
unsigned long stateTime = 0;
int delayCountdown = 0;
bool ntfySent = false;  // 30秒通知是否已发送

/// 当前目标亮度百分比（0-100）：/b?l= 直接写、/s?n= 按模式写、/cmd?c= 也同步修改
/// 这样 Flutter 端无论发哪类命令，灯带都能平滑过渡到对应亮度，不再被 v0 20秒硬循环卡住。
int currentBrightnessPct = 0;
/// 当前色温（R/G/B 基线，保持暖光），APP 端可不改，默认 BASE_R/G/B
int baseR = BASE_R, baseG = BASE_G, baseB = BASE_B;

const char* stateDesc(State s) {
  switch (s) {
    // v0 旧（保持 Flutter 老兼容）
    case IDLE:           return "idle";
    case TIMING:         return "timing";
    case REACHED_20:     return "reached20";
    case WAITING_CHOICE: return "waiting";
    case DELAYING:       return "delaying";
    case NIGHT_LIGHT:    return "night";
    // v1 新：与 Flutter NightSessionState 命名严格一致
    case ST_PLANNED:   return "planned";
    case ST_OBSERVING: return "observing";
    case ST_NUDGED:    return "nudged";
    case ST_EXTENDING: return "extending";
    case ST_REPLACING: return "replacing";
    case ST_MUTED:     return "muted";
    case ST_FINISHED:  return "finished";
    default:             return "unknown";
  }
}

// ==================== App 风格网页 ====================
const char HTML_PAGE[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="theme-color" content="#1a1a2e">
  <title>护眼灯</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
    body {
      font-family: -apple-system, 'Segoe UI', Arial, sans-serif;
      background: #1a1a2e; color: #eee; min-height: 100vh;
      display: flex; flex-direction: column; align-items: center; justify-content: center;
      user-select: none; -webkit-user-select: none;
    }
    .header { text-align:center; margin-bottom:8px; }
    .header h1 { font-size:1.6em; font-weight:700; }
    .conn { font-size:0.8em; margin-top:4px; display:flex; align-items:center; gap:4px; }
    .dot { width:8px; height:8px; border-radius:50%; }
    .dot-on { background:#2ecc71; } .dot-off { background:#e74c3c; }
    .timer {
      font-size:4.5em; font-weight:800; color:#f39c12;
      text-shadow:0 0 30px rgba(243,156,18,0.3);
      margin:12px 0; font-variant-numeric:tabular-nums;
    }
    .stage {
      font-size:1.15em; padding:10px 28px; border-radius:12px;
      background:#2c3e50; margin-bottom:24px; min-width:200px; text-align:center;
    }
    .btns { display:flex; gap:12px; }
    .btn {
      font-size:1.1em; font-weight:600; padding:14px 36px;
      border:none; border-radius:14px; cursor:pointer; color:#fff;
      transition:transform .1s, opacity .2s; min-width:120px;
    }
    .btn:active { transform:scale(0.93); }
    .btn-start { background:linear-gradient(135deg,#e67e22,#d35400); }
    .btn-reset { background:#555; }
    .btn:disabled { opacity:0.4; }
    .info { margin-top:28px; font-size:0.75em; color:#666; }
    .modal-bg {
      display:none; position:fixed; inset:0; background:rgba(0,0,0,0.75);
      align-items:center; justify-content:center; z-index:999;
    }
    .modal-bg.show { display:flex; }
    .modal {
      background:#2c3e50; border-radius:24px; padding:32px 40px;
      text-align:center; max-width:85%; box-shadow:0 8px 40px rgba(0,0,0,0.5);
    }
    .modal h2 { color:#f39c12; font-size:1.4em; margin-bottom:12px; }
    .modal p { color:#ccc; font-size:1.05em; margin-bottom:24px; }
    .modal-btns { display:flex; gap:16px; justify-content:center; }
    .modal-btn {
      font-size:1.15em; font-weight:600; padding:12px 32px;
      border:none; border-radius:14px; cursor:pointer; color:#fff;
    }
    .modal-btn:active { transform:scale(0.93); }
    .mb-yes { background:#27ae60; } .mb-no { background:#c0392b; }
  </style>
</head>
<body>
  <div class="header">
    <h1>💡 护眼灯</h1>
    <div class="conn">
      <span class="dot dot-off" id="dot"></span>
      <span id="connText">未连接</span>
    </div>
  </div>
  <div class="timer" id="timer">0s</div>
  <div class="stage" id="stage">点击开始计时</div>
  <div class="btns">
    <button class="btn btn-start" id="btnStart" onclick="sendCmd('start')">开始计时</button>
    <button class="btn btn-reset" id="btnReset" onclick="sendCmd('reset')">重置</button>
  </div>
  <div class="info">ESP32-S3 · ntfy 系统通知 · 平滑变光</div>
  <div class="modal-bg" id="modal">
    <div class="modal">
      <h2>⏰ 休息提醒</h2>
      <p>您已使用 30 秒，是否延时 10 秒？</p>
      <div class="modal-btns">
        <button class="modal-btn mb-no" onclick="sendCmd('no'); closeModal();">否</button>
        <button class="modal-btn mb-yes" onclick="sendCmd('yes'); closeModal();">是</button>
      </div>
    </div>
  </div>
  <script>
    var localStart = 0, started = false, dialogShown = false;
    function poll() {
      fetch('/status')
        .then(r => r.json())
        .then(d => {
          document.getElementById('dot').className = 'dot dot-on';
          document.getElementById('connText').textContent = '已连接';
          document.getElementById('connText').style.color = '#2ecc71';
          var elapsed = started ? Math.floor((Date.now()-localStart)/1000) : d.t;
          document.getElementById('timer').textContent = elapsed + 's';
          var sm = {
            'idle':'待机中','timing':'70% 暖橙光','reached20':'50% 暖光',
            'waiting':'30% 极暖光','delaying':'延时中 '+(d.d>0?'('+d.d+'s)':''),
            'night':'5% 夜灯模式'
          };
          document.getElementById('stage').textContent = sm[d.s] || d.s;
          if (d.s === 'waiting' && !dialogShown) {
            dialogShown = true;
            document.getElementById('modal').classList.add('show');
          }
          if (d.s !== 'waiting') dialogShown = false;
          document.getElementById('btnStart').disabled = (d.s !== 'idle' && d.s !== 'night');
        })
        .catch(err => {
          document.getElementById('dot').className = 'dot dot-off';
          document.getElementById('connText').textContent = '未连接';
          document.getElementById('connText').style.color = '#e74c3c';
        });
    }
    function sendCmd(cmd) {
      fetch('/cmd?c=' + cmd)
        .then(r => r.text())
        .then(() => {
          if (cmd === 'start') { localStart = Date.now(); started = true; }
          if (cmd === 'reset') { started = false; }
          poll();
        })
        .catch(err => alert('通信失败: ' + err));
    }
    function closeModal() { document.getElementById('modal').classList.remove('show'); }
    setInterval(poll, 1000);
    poll();
  </script>
</body>
</html>
)rawliteral";

// ==================== HTTP 回调 ====================
void handleRoot() {
  server.send(200, "text/html", HTML_PAGE);
}

void handleStatus() {
  unsigned long elapsed = 0;
  int delayLeft = 0;
  if (state != IDLE) {
    elapsed = (millis() - startTime) / 1000;
  }
  if (state == DELAYING) {
    delayLeft = delayCountdown - (int)((millis() - stateTime) / 1000);
    if (delayLeft < 0) delayLeft = 0;
  }
  String json = "{\"t\":" + String(elapsed) + ",\"s\":\"" + stateDesc(state) + "\",\"d\":" + String(delayLeft) + "}";
  server.send(200, "application/json", json);
}

void handleCmd() {
  if (server.hasArg("c")) {
    String c = server.arg("c");
    if (c == "start") {
      curR = 0; curG = 0; curB = 0;
      currentBrightnessPct = 70;
      setFadeTarget(70, baseR, baseG, baseB);
      state = TIMING;
      startTime = millis();
      stateTime = millis();
      ntfySent = false;
      Serial.println("[CMD] Start, fade to 70% warm");
    } else if (c == "yes") {
      // v0 兼容：必须是 WAITING_CHOICE 才执行 10s 延迟
      if (state == WAITING_CHOICE) {
        state = DELAYING;
        stateTime = millis();
        delayCountdown = 10;
        currentBrightnessPct = 30;
        setFadeTarget(30, 255, 100, 20);
        Serial.println("[CMD] YES - hold 30% for 10s");
      } else {
        // v1 兼容：APP 端 EXTEND 直接延长 30% 保持，不再进入 DELAYING
        state = ST_EXTENDING;
        stateTime = millis();
        currentBrightnessPct = 30;
        setFadeTarget(30, 255, 120, 30);
        Serial.println("[CMD] YES (v1 extend) - hold 30% warm, no auto countdown");
      }
    } else if (c == "no") {
      // v0 兼容：必须是 WAITING_CHOICE 或 v1 任一状态 → 直接 night
      state = NIGHT_LIGHT;
      stateTime = millis();
      currentBrightnessPct = 5;
      setFadeTarget(5, 255, 80, 10);
      Serial.println("[CMD] NO - fade to 5% night light");
    } else if (c == "reset") {
      state = IDLE;
      fading = false;
      curR = 0; curG = 0; curB = 0;
      currentBrightnessPct = 0;
      applyColorRaw(0, 0, 0);
      ntfySent = false;
      Serial.println("[CMD] Reset");
    }
    server.send(200, "text/plain", "OK");
  } else {
    server.send(400, "text/plain", "Missing");
  }
}

// =================== v1 新增接口：/b?l=亮度 和 /s?n=模式 ===================

/// GET /b?l=<0-100>  立即平滑把亮度改为 l%，保持当前色温不变，不改变状态机当前状态。
/// 这是 Flutter 端"分级亮度"的核心接口：100%/70%/50%/30%/5% 都通过它直接驱动，完全绕过 v0 20秒等待。
void handleBrightness() {
  if (!server.hasArg("l")) {
    server.send(400, "application/json", "{\"ok\":false,\"error\":\"missing l\"}");
    return;
  }
  String ls = server.arg("l");
  int l = ls.toInt();
  l = constrain(l, 0, 100);
  currentBrightnessPct = l;
  if (l == 0) {
    // 完全灭：保留当前 state 不回 IDLE（App 侧状态机继续流）
    setFadeTarget(0, baseR, baseG, baseB);
  } else {
    // 根据亮度微调色温：越低越暖（R 不变，G/B 降）
    int r = baseR;
    int g = map(l, 0, 100, 60, baseG);
    int b = map(l, 0, 100, 10,  baseB);
    setFadeTarget(l, r, g, b);
  }
  Serial.printf("[API /b] brightness %d%%\n", l);
  String ack = "{\"ok\":true,\"current_state\":\"" + String(stateDesc(state))
             + "\",\"brightness\":" + String(currentBrightnessPct) + "}";
  server.send(200, "application/json", ack);
}

/// GET /s?n=<0..12> 或 n=planned/observing/nudged/extending/replacing/muted/finished/idle
///   0=planned,1=observing,2=nudged,3=extending,4=replacing,5=muted,6=finished,7=idle
/// 同时会把亮度按模式预置（但你也可以先/s再/b覆盖）。
/// App 状态机切换时先发 /s 立即切预置色，再发 /b 精确。
void handleSetState() {
  // 1. 解析参数
  int modeCode = -1;
  if (server.hasArg("n")) {
    String ns = server.arg("n");
    ns.trim();
    if (ns == "0" || ns == "planned")   modeCode = 0;
    else if (ns == "1" || ns == "observing") modeCode = 1;
    else if (ns == "2" || ns == "nudged")    modeCode = 2;
    else if (ns == "3" || ns == "extending") modeCode = 3;
    else if (ns == "4" || ns == "replacing") modeCode = 4;
    else if (ns == "5" || ns == "muted")     modeCode = 5;
    else if (ns == "6" || ns == "finished")  modeCode = 6;
    else if (ns == "7" || ns == "idle")      modeCode = 7;
  }
  if (modeCode < 0 || modeCode > 7) {
    server.send(400, "application/json", "{\"ok\":false,\"error\":\"bad n\"}");
    return;
  }
  // 2. 设 state + 预置亮度（按 FR-11 语义）
  switch (modeCode) {
    case 0:
      state = ST_PLANNED;  currentBrightnessPct = 70;
      setFadeTarget(70, 255, 170, 80); break;
    case 1:
      state = ST_OBSERVING; currentBrightnessPct = 50;
      setFadeTarget(50, 255, 140, 50); break;
    case 2:
      state = ST_NUDGED;    currentBrightnessPct = 30;
      setFadeTarget(30, 255, 100, 20);
      // NUDGED 也顺手发一次 ntfy（Flutter 本地通知仍为主，这里仅冗余）
      if (!ntfySent) {
        ntfySent = true;
        sendNtfyNotification("💤 该收尾了", "今晚已陪你一会儿，慢慢准备睡觉吧。");
      }
      break;
    case 3:
      state = ST_EXTENDING; currentBrightnessPct = 40;
      setFadeTarget(40, 255, 130, 40); break;
    case 4:
      state = ST_REPLACING; currentBrightnessPct = 60;
      setFadeTarget(60, 255, 180, 90); break;
    case 5:
      state = ST_MUTED;     // 亮度不变（保持当前亮度，仅状态）
      break;
    case 6:
      state = ST_FINISHED;  currentBrightnessPct = 5;
      setFadeTarget(5, 255, 80, 10); break;
    case 7:
      state = IDLE;         currentBrightnessPct = 0;
      fading = false; curR = 0; curG = 0; curB = 0;
      applyColorRaw(0, 0, 0); break;
  }
  stateTime = millis();
  Serial.printf("[API /s] -> %s (brightness %d%%)\n", stateDesc(state), currentBrightnessPct);
  // 3. 返回 Flutter NightSessionState 同名字段
  String ack = "{"
      "\"ok\":true,"
      "\"accepted\":true,"
      "\"current_state\":\"" + String(stateDesc(state)) + "\","
      "\"brightness\":" + String(currentBrightnessPct) + ","
      "\"connected\":true"
      "}";
  server.send(200, "application/json", ack);
}

// =================== v1 新增：兼容 Flutter POST /api/v1/command ===================
/// 与 Flutter LampCommandId 一一对应，内部直接调用 /b 和 /s 的等价逻辑。
/// 返回 JSON: {ok, accepted, request_id, current_state, brightness, connected}
void handleApiV1Command() {
  String body = server.arg("plain");
  // 默认参数值
  String cmdName = "";
  String reqId = "";
  int brightness = -1;
  int durSec = -1;

  // 简易 JSON 解析（ArduinoJson 不一定装了，手写关键字段提取即可）
  if (body.length() > 0) {
    // 提取 "command":"xxx"
    int idx1 = body.indexOf("\"command\"");
    if (idx1 >= 0) {
      int c1 = body.indexOf('"', idx1 + 10);
      int c2 = body.indexOf('"', c1 + 1);
      if (c1 >= 0 && c2 >= 0) cmdName = body.substring(c1 + 1, c2);
    }
    // 提取 "request_id":"xxx"
    int idx2 = body.indexOf("\"request_id\"");
    if (idx2 >= 0) {
      int r1 = body.indexOf('"', idx2 + 14);
      int r2 = body.indexOf('"', r1 + 1);
      if (r1 >= 0 && r2 >= 0) reqId = body.substring(r1 + 1, r2);
    }
    // 提取 "brightness":N
    int idx3 = body.indexOf("\"brightness\"");
    if (idx3 >= 0) {
      int c1 = body.indexOf(':', idx3);
      if (c1 >= 0) {
        int c2 = c1 + 1;
        while (c2 < (int)body.length() && (body[c2] == ' ' || body[c2] == '\t')) c2++;
        int c3 = c2;
        while (c3 < (int)body.length() && isDigit(body[c3])) c3++;
        if (c3 > c2) brightness = body.substring(c2, c3).toInt();
      }
    }
    // 提取 "duration_sec":N
    int idx4 = body.indexOf("\"duration_sec\"");
    if (idx4 >= 0) {
      int d1 = body.indexOf(':', idx4);
      if (d1 >= 0) {
        int d2 = d1 + 1;
        while (d2 < (int)body.length() && (body[d2] == ' ' || body[d2] == '\t')) d2++;
        int d3 = d2;
        while (d3 < (int)body.length() && isDigit(body[d3])) d3++;
        if (d3 > d2) durSec = body.substring(d2, d3).toInt();
      }
    }
  }

  Serial.printf("[API /api/v1/command] cmd=%s req=%s b=%d ds=%d\n",
                cmdName.c_str(), reqId.c_str(), brightness, durSec);

  // 根据 command 映射到状态+亮度（与 Flutter LampCommandId 命名一致）
  int targetB = -1;
  const char* targetMode = NULL;

  if (cmdName == "lightLevel3" || cmdName == "restoreLight") {
    targetB = brightness < 0 ? 100 : brightness;  targetMode = "planned";
  } else if (cmdName == "lightLevel2" || cmdName == "enterReplace") {
    targetB = brightness < 0 ? 70 : brightness;   targetMode = "planned";
  } else if (cmdName == "windDown") {
    targetB = brightness < 0 ? 50 : brightness;   targetMode = "observing";
  } else if (cmdName == "lightLevel1" || cmdName == "nudge") {
    targetB = brightness < 0 ? 30 : brightness;   targetMode = "nudged";
  } else if (cmdName == "extend") {
    targetB = brightness < 0 ? 40 : brightness;   targetMode = "extending";
  } else if (cmdName == "finish") {
    targetB = brightness < 0 ? 5 : brightness;    targetMode = "finished";
  } else if (cmdName == "mute") {
    targetMode = "muted";                         // 亮度不变
  } else if (cmdName == "unmute") {
    targetB = brightness < 0 ? 60 : brightness;   targetMode = "observing";
  }

  if (targetMode != NULL) {
    // 直接复用 /s 的核心逻辑：写状态 + 写亮度
    int modeCode = -1;
    String m = String(targetMode);
    if      (m == "planned")   modeCode = 0;
    else if (m == "observing") modeCode = 1;
    else if (m == "nudged")    modeCode = 2;
    else if (m == "extending") modeCode = 3;
    else if (m == "replacing") modeCode = 4;
    else if (m == "muted")     modeCode = 5;
    else if (m == "finished")  modeCode = 6;
    else if (m == "idle")      modeCode = 7;

    if (modeCode >= 0) {
      switch (modeCode) {
        case 0:
          state = ST_PLANNED;  currentBrightnessPct = targetB < 0 ? 70 : targetB;
          setFadeTarget(currentBrightnessPct, 255, 170, 80); break;
        case 1:
          state = ST_OBSERVING; currentBrightnessPct = targetB < 0 ? 50 : targetB;
          setFadeTarget(currentBrightnessPct, 255, 140, 50); break;
        case 2:
          state = ST_NUDGED;    currentBrightnessPct = targetB < 0 ? 30 : targetB;
          setFadeTarget(currentBrightnessPct, 255, 100, 20);
          if (!ntfySent) { ntfySent = true;
            sendNtfyNotification("💤 该收尾了", "今晚已陪你一会儿，慢慢准备睡觉吧。"); }
          break;
        case 3:
          state = ST_EXTENDING; currentBrightnessPct = targetB < 0 ? 40 : targetB;
          setFadeTarget(currentBrightnessPct, 255, 130, 40); break;
        case 4:
          state = ST_REPLACING; currentBrightnessPct = targetB < 0 ? 60 : targetB;
          setFadeTarget(currentBrightnessPct, 255, 180, 90); break;
        case 5:
          state = ST_MUTED;     break;   // 亮度不变
        case 6:
          state = ST_FINISHED;  currentBrightnessPct = targetB < 0 ? 5 : targetB;
          setFadeTarget(currentBrightnessPct, 255, 80, 10); break;
        case 7:
          state = IDLE;         currentBrightnessPct = 0;
          fading = false; curR = 0; curG = 0; curB = 0;
          applyColorRaw(0, 0, 0); break;
      }
      stateTime = millis();
    }
  } else if (targetB >= 0) {
    // 只改亮度不改状态（未来扩展用）
    currentBrightnessPct = targetB;
    int r = baseR;
    int g = map(targetB, 0, 100, 60, baseG);
    int b = map(targetB, 0, 100, 10,  baseB);
    setFadeTarget(targetB, r, g, b);
  }

  // 响应：严格匹配 Flutter Esp32LampService 期望字段
  String ack = "{"
      "\"ok\":true,"
      "\"accepted\":true,"
      "\"request_id\":\"" + reqId + "\","
      "\"current_state\":\"" + String(stateDesc(state)) + "\","
      "\"brightness\":" + String(currentBrightnessPct) + ","
      "\"connected\":true"
      "}";
  server.send(200, "application/json", ack);
}

/// Flutter getStateV1 也会尝试 /api/v1/state → 返回统一格式
void handleApiV1State() {
  String ack = "{"
      "\"ok\":true,"
      "\"current_state\":\"" + String(stateDesc(state)) + "\","
      "\"brightness\":" + String(currentBrightnessPct) + ","
      "\"connected\":true,"
      "\"raw_v0\":\"" + String(stateDesc(state)) + "\","
      "\"elapsed_seconds\":" + String(state == IDLE ? 0 : (millis() - stateTime) / 1000) +
  "}";
  server.send(200, "application/json", ack);
}

// ==================== 初始化 ====================
void setup() {
  Serial.begin(115200);
  delay(300);

  strip.begin();
  strip.clear();
  strip.show();

  Serial.println("=================================");
  Serial.println("  ESP32-S3 Eye Care Light (ntfy)");
  Serial.println("=================================");

  // 连接手机热点
  WiFi.mode(WIFI_STA);
  WiFi.setTxPower(WIFI_POWER_19_5dBm);
  Serial.print("Connecting to WiFi: ");
  Serial.println(WIFI_SSID);

  WiFi.begin(WIFI_SSID, WIFI_PASS);
  int retry = 0;
  while (WiFi.status() != WL_CONNECTED && retry < 30) {
    delay(500);
    Serial.print(".");
    retry++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.println("WiFi connected!");
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
    Serial.print("Web URL:   http://");
    Serial.println(WiFi.localIP());
    Serial.print("ntfy topic: ");
    Serial.println(NTFY_TOPIC);
  } else {
    Serial.println();
    Serial.println("[ERROR] WiFi connection failed!");
    Serial.println("Please check SSID and password.");
  }
  Serial.println("=================================");

  server.on("/", HTTP_GET, handleRoot);
  server.on("/status", HTTP_GET, handleStatus);
  server.on("/cmd", HTTP_GET, handleCmd);
  // ===== v1 新增：App 直接控制亮度和模式（绕开 v0 20s 等待）=====
  server.on("/b", HTTP_GET, handleBrightness);   // /b?l=0..100  立即设亮度
  server.on("/s", HTTP_GET, handleSetState);     // /s?n=planned|observing|nudged|...  立即切模式
  // ===== 额外支持 POST /api/v1/command（App sendCommandV1 原路径）=====
  server.on("/api/v1/command", HTTP_POST, handleApiV1Command);
  server.on("/api/v1/state", HTTP_GET, handleApiV1State);
  server.begin();

  Serial.println("Web Server ready!");
}

// ==================== 主循环 ====================
void loop() {
  server.handleClient();
  fadeAdvance();

  unsigned long now = millis();

  switch (state) {
    case TIMING:
      if ((now - startTime) / 1000 >= 20) {
        state = REACHED_20;
        stateTime = now;
        setFadeTarget(50, BASE_R, BASE_G, BASE_B);
        Serial.println("[TIMER] 20s -> fade to 50% warm");
      }
      break;

    case REACHED_20:
      if ((now - startTime) / 1000 >= 30) {
        state = WAITING_CHOICE;
        stateTime = now;
        setFadeTarget(30, 255, 100, 20);
        // 发送 ntfy 系统通知!
        if (!ntfySent) {
          ntfySent = true;
          sendNtfyNotification("⏰ 休息提醒", "您已使用 30 秒，该休息一下了！打开护眼灯页面选择是否延时。");
        }
        Serial.println("[TIMER] 30s -> fade to 30%, ntfy sent, waiting...");
      }
      break;

    case DELAYING:
      if ((now - stateTime) / 1000 >= 10) {
        state = NIGHT_LIGHT;
        stateTime = now;
        setFadeTarget(5, 255, 80, 10);
        Serial.println("[TIMER] Delay done -> fade to 5% night");
      }
      break;

    case NIGHT_LIGHT:
    case IDLE:
    case WAITING_CHOICE:
      break;
  }
}
