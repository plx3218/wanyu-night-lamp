# 晚风灯 · 晚屿（Wanyu）

一盏会呼吸的 AI 床头灯：ESP32-S3 + WS2812B 固件 + 配套 App（晚屿）。AI 根据你今晚的聊天和入睡计划，驱动灯光在 8 种状态间平滑流转——计划就绪、温柔守护、到点提醒、延时陪伴、晚安渐灭……灯就是看得见的陪伴。

## 它是什么

晚屿是一盏"会说话"的床头灯：你跟 App 聊几句今晚的状态和明早安排，AI 生成一份最多 3 步的温和收尾计划；到了时间点，灯按计划平滑变暗变暖，App 推送轻量提醒，而不是粗暴地催你睡觉。硬件是一颗 ESP32-S3 驱动的 WS2812B 灯带，跑在手机热点上，被 App 通过局域网 HTTP 直接控制。

## 仓库结构

```
firmware/                 ESP32-S3 固件（PlatformIO / Arduino）
  src/main.cpp            WS2812B 控制 + HTTP 服务 + 状态机
  platformio.ini
software/she_nicest_app/  配套 App（Flutter，Android 优先）
server/                   AI 对话与个性化通知服务（FastAPI）
docs/
  PROTOCOL.md             通信协议（/b /s /api/v1/command）
  BOM.md                  物料清单 + 接线
  HARDWARE_HANDOFF.md     早期软硬交接记录
```

## 快速复现

1. 按 [`docs/BOM.md`](docs/BOM.md) 组装硬件（ESP32-S3 + WS2812B 8 灯珠，GPIO7）
2. 改 `firmware/src/main.cpp` 里的 WiFi 为你的手机热点，烧录到 ESP32-S3
3. 在 `software/she_nicest_app` 里填入灯的局域网 IP（App 内"我的晚风灯"页可改）
4. 跑 `server/`（可选，提供 AI 对话/个性化通知；缺服务器时 App 会降级为本地流程）
5. App 聊几句生成今晚计划 → 灯开始按计划呼吸

## 设计要点

- 8 种灯光状态映射（计划就绪 / 守护呼吸 / 提醒抬亮 / 延时陪伴 / 晚安渐灭…），与 App `NightSessionState` 命名一一对应
- 命令幂等（`request_id` 5 秒去重），新旧固件双协议兼容（v1 分级亮度 + v0 网页演示）
- 灯离线不阻断 App 流程：所有灯光命令静默失败，时间线照常推进
- 平滑渐变（70→50%≈1.1s，50→5%≈2.4s），越暗越暖

## 技术栈

- **固件**：ESP32-S3 / Arduino + Adafruit NeoPixel / PlatformIO
- **App**：Flutter（Android 14+ 前台服务保活，离线降级）
- **服务端**：FastAPI + DeepSeek（睡前计划生成 + 个性化通知文案）

## 安全提示

- 固件 WiFi 已脱敏为占位符，烧录前自行填入
- AI 服务器的 DeepSeek key 从环境变量 `DEEPSEEK_API_KEY` 读取，不在代码中硬编码
- App 与灯之间为局域网明文 HTTP，仅限演示；生产应改 TLS

> 仓库 Topic：`shenicest-fission`
