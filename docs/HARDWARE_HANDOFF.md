# 灯具联调交接

## 你的修改范围

请优先只修改：

```text
lib/services/wifi_lamp_service.dart
lib/models/lamp_models.dart（只有数据字段变化时才修改）
lib/main.dart（将 MockLampService 切换到 WifiLampService）
```

UI 和用户流程不需要随协议变化而修改。

## 软件期望的灯具能力

```text
连接与健康检查
开灯和关灯
设置亮度 0-100
设置颜色 HEX
环境呼吸
提醒抬亮
延长确认
渐暗收尾
接收实体轻触
接收实体长按
读取当前状态
```

## 当前 HTTP 草案

发送命令：

```http
POST http://<lamp-ip>:<port>/api/v1/command
Content-Type: application/json

{
  "command": "WIND_DOWN",
  "request_id": "unique-id"
}
```

建议回包：

```json
{
  "accepted": true,
  "current_state": "WIND_DOWN",
  "request_id": "unique-id"
}
```

健康检查：

```http
GET http://<lamp-ip>:<port>/api/v1/health
```

状态查询：

```http
GET http://<lamp-ip>:<port>/api/v1/state
```

## 接手后请确认

- 灯的发现方式：固定 IP、热点网关地址或局域网发现
- 真实端口
- 三个 endpoint 是否沿用
- 所有命令名称和参数
- 轻触与长按如何上报
- 状态轮询频率
- 超时和重连策略
- `request_id` 是否原样返回

如果固件已采用其他格式，以现有固件为准，只需在 `WifiLampService` 内做转换。
