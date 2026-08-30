# 物料清单与接线（BOM）

## BOM 物料清单

| 序号 | 物料 | 规格 | 数量 | 说明 |
|---|---|---|---|---|
| 1 | 主控板 | ESP32-S3-DevKitC-1 | 1 | WiFi + HTTP 服务 |
| 2 | 灯带 | WS2812B（8 颗 5050 RGB 灯珠） | 1 | 可寻址，单线控制 |
| 3 | 限流电阻 | 330Ω | 1 | 串接 DIN，保护信号线 |
| 4 | 杜邦线 | 母-母 | 若干 | 信号/电源/地，至少 3 根 |
| 5 | 外壳 / 灯罩 | 鹅卵石磨砂灯罩 | 1 | 散光，营造氛围 |
| 6 | 供电 | USB 5V（开发板 Type-C） | 1 | 开发板自带 |

## 接线说明

```
ESP32-S3              WS2812B 灯带
GPIO7  ─── 330Ω ────  DIN
3V3    ─────────────  VCC / 5V
GND    ─────────────  GND
```

> 固件默认 `LED_PIN=7`、`NUMPIXELS=8`。如灯珠数量不同，改 `firmware/src/main.cpp` 的 `NUMPIXELS` 宏即可。

## 接线示意

（待补：手画拍照或 Fritzing 截图，放 `docs/images/wiring.jpg`）

## 实物照片

（待补：建议 2–3 张——内部接线 1 张 + 成品点亮效果 2 张，放 `docs/images/`）

## 烧录步骤

1. 安装 [PlatformIO](https://platformio.org/)（VSCode 插件或 CLI）
2. `cd firmware`
3. 先改 `src/main.cpp` 里的 `WIFI_SSID` / `WIFI_PASS` 为你的手机热点
4. `pio run` 编译
5. `pio run -t upload` 烧录（USB 连 ESP32-S3）
6. `pio device monitor -p <COM口> -b 115200` 看串口，会打印分配到的局域网 IP（`Web URL: http://<IP>`）
7. 浏览器打开该 IP，可见自带控制网页
