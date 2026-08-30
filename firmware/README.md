# 晚风灯 ESP32-S3 固件

烧进 ESP32-S3 的固件：WS2812B 灯珠控制、平滑呼吸渐变、HTTP 服务、v0/v1 双协议状态机。

## 烧录前必改

打开 `src/main.cpp`，把 WiFi 改成你自己的手机热点：

```cpp
const char* WIFI_SSID = "你的热点名";
const char* WIFI_PASS = "你的热点密码";
```

> 仓库里是占位符，已脱敏，不会泄露任何真实凭据。

## 物料与接线

见 [`../docs/BOM.md`](../docs/BOM.md)。一句话：`GPIO7 → 330Ω → WS2812B DIN`；`3V3→VCC`；`GND→GND`。灯珠数默认 8（改 `NUMPIXELS` 宏）。

## 烧录

```bash
cd firmware
pio run             # 编译
pio run -t upload   # 烧录（USB 连 ESP32-S3）
pio device monitor  # 串口看分配到的 IP
```

串口会打印 `Web URL: http://<IP>`，浏览器打开即可见自带控制网页。

## 能力

- 7 档平滑亮度（0/5/30/40/50/70/100%），越低越暖
- v1 接口（`/b` `/s` `/api/v1/command` `/api/v1/state`）供 App 直接控制，绕过演示计时
- v0 兼容：自带网页控制台 + 20s 演示流程 + ntfy 系统通知
- 命令幂等（`request_id` 5 秒去重）

协议细节见 [`../docs/PROTOCOL.md`](../docs/PROTOCOL.md)。
