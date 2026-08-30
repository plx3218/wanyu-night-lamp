# 晚风灯通信协议

ESP32-S3 固件在 **80 端口**提供 HTTP 服务（明文，局域网内使用）。支持两套接口：

- **v1（推荐，配套 App 使用）**：分级亮度 + 状态机，App 直接驱动
- **v0（兼容，自带网页控制台 + 20s 演示流程）**：独立可玩

## 硬件前提
- ESP32-S3-DevKitC-1，STA 模式连手机热点
- WS2812B 灯带 8 颗灯珠，DIN 接 GPIO7（经 330Ω 电阻）
- HTTP 端口 80

## v1 接口（App 使用）

### GET /b?l=<0-100>
立即把亮度平滑渐变到 `l%`，保持当前色温走向（越低越暖），**不改变状态机当前状态**。
App 的 7 档亮度（0/5/20/40/50/70/100）都通过它驱动，完全绕过 v0 的 20s 等待。

响应：
```json
{"ok":true,"current_state":"observing","brightness":50}
```

### GET /s?n=<mode>
立即切换状态并预置对应亮度/色温。`n` 取值（数字或名称均可）：

| n | 状态 | 预置亮度 |
|---|---|---|
| 0 / planned | 计划就绪 | 70% |
| 1 / observing | 温柔守护 | 50% |
| 2 / nudged | 到点提醒 | 30% |
| 3 / extending | 延时陪伴 | 40% |
| 4 / replacing | 替代活动 | 60% |
| 5 / muted | 静默（不打扰） | 不变 |
| 6 / finished | 晚安收尾 | 5% |
| 7 / idle | 待机 | 0% |

响应：
```json
{"ok":true,"accepted":true,"current_state":"nudged","brightness":30,"connected":true}
```

### POST /api/v1/command
请求体（JSON）：
```json
{"command":"windDown","request_id":"abc123","brightness":50,"duration_sec":600}
```
`command` 与 App 的 `LampCommandId` 一一对应：

| command | 目标状态 | 亮度 |
|---|---|---|
| lightLevel3 / restoreLight | planned | 70/100 |
| lightLevel2 / enterReplace | planned | 70 |
| windDown | observing | 50 |
| lightLevel1 / nudge | nudged | 30 |
| extend | extending | 40 |
| finish | finished | 5 |
| mute | muted | 不变 |
| unmute | observing | 60 |

响应：
```json
{"ok":true,"accepted":true,"request_id":"abc123","current_state":"observing","brightness":50,"connected":true}
```
**幂等**：`request_id` 原样返回；App 端 5 秒内对相同 id 不重复下发，避免重复按压/重发造成灯光闪烁。

### GET /api/v1/state
```json
{"ok":true,"current_state":"observing","brightness":50,"connected":true,"raw_v0":"observing","elapsed_seconds":120}
```

## v0 兼容接口（自带网页控制台）
- `GET /` → App 风格控制网页（开始计时/重置/延时弹窗）
- `GET /status` → `{"t":<已用秒>,"s":"<状态>","d":<延时剩余秒>}`
- `GET /cmd?c=start|yes|no|reset` → v0 20s 演示流程控制

v0 演示流程：start→70%暖橙 → 20s→50%暖 → 30s→30%极暖+ntfy通知 → 选"是"保持30%延时10s → 5%夜灯。

## 状态枚举
- v1：`idle / planned / observing / nudged / extending / replacing / muted / finished`（与 Flutter `NightSessionState` 命名严格一致）
- v0（旧，保留兼容）：`idle / timing / reached20 / waiting / delaying / night`

## 亮度与色温
亮度档：100 / 70 / 50 / 40 / 30 / 5（%）。色温随亮度降低而更暖（G/B 比例下降），营造"渐暗渐暖"的入睡氛围。所有过渡均为平滑渐变（约 25ms 一档步进，70→50% 约 1.1s，50→5% 约 2.4s），不是一闪而过。

## 实体按钮
当前固件版本未接入实体按钮，控制通过 App 或网页 HTTP 完成。`HARDWARE_HANDOFF.md` 中提到的"实体轻触/长按"为预留能力，后续可在空闲 GPIO 上接按钮扩展（固件 `loop()` 已留扩展点）。
