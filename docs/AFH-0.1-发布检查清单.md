# AFH-0.1 发布检查清单

> 当前分支：`feature/AFH-003-p0-core-loop`  
> 目标：只允许经过测试、配置明确、可追溯的构建进入真实用户测试或主线。

## 1. 构建配置

- [x] 客户端不再内置旧生产服务器地址。
- [x] API 与 AI 共用 `WANYU_API_BASE_URL` 构建参数。
- [x] 后端地址为空或格式无效时，客户端给出明确错误；AI 计划仍走本地降级计划。
- [x] HTTP 仅作为显式调试配置使用：`WANYU_ALLOW_INSECURE_HTTP=true`。
- [ ] 真实测试构建必须替换为团队确认过的 HTTPS API 地址。

示例：

```powershell
flutter build apk --debug `
  --dart-define=WANYU_API_BASE_URL=https://<团队确认的域名> `
  --dart-define=WANYU_ALLOW_INSECURE_HTTP=false
```

本地临时 HTTP 调试只能显式执行，并且不得用于发给测试用户：

```powershell
flutter run --debug `
  --dart-define=WANYU_API_BASE_URL=http://<本地或测试机地址>:8000 `
  --dart-define=WANYU_ALLOW_INSECURE_HTTP=true
```

## 2. Android 传输与签名

- [x] 主清单关闭明文流量。
- [x] debug 构建单独允许调试覆盖，release 不继承该覆盖。
- [x] release 不再使用 debug 签名。
- [ ] 配置真实发布签名环境变量后，才能构建发布包；当前状态为**发布阻断**。

发布签名需要由负责人在安全环境配置，不得提交到 Git：

```text
WANYU_RELEASE_STORE_FILE
WANYU_RELEASE_STORE_PASSWORD
WANYU_RELEASE_KEY_ALIAS
WANYU_RELEASE_KEY_PASSWORD
```

配置前执行 `flutter build apk --release` 应明确失败并提示缺少签名配置；这属于预期的安全保护，不是验收通过。

## 3. 密钥、账号和数据

- [x] DeepSeek key、管理员密码从环境变量读取。
- [x] `*.env`、keystore、`key.properties`、证书文件已加入忽略规则。
- [x] 部署脚本不再写入占位密钥、不自动移动目录、不杀进程、不把服务绑定到公网。
- [ ] 发布前由提交人执行一次敏感信息扫描，并确认本地数据库没有被 Git 跟踪。
- [ ] 服务器通过 HTTPS 反向代理对外提供接口；Uvicorn 仅监听 `127.0.0.1`。

建议检查：

```powershell
git grep -n -E "121\.40\.96\.105|DEEPSEEK_API_KEY=|ADMIN_PASSWORD=|sk-[A-Za-z0-9]" -- .
git ls-files | Select-String -Pattern "(^|/)(wanyu\.db|.*\.env|.*\.jks|.*\.keystore)$"
```

## 4. P0 联调门禁

- [x] Flutter 自动化测试：当前 38/38 通过。
- [x] 覆盖率命令可执行并通过。
- [x] debug APK 可构建、可安装、冷启动无致命异常。
- [ ] 小米 15 手工开启“使用情况访问”并完成 AFH-003 R-01～R-10。
- [ ] 至少完成 1 名内部试用者的 3 天基线记录。
- [ ] 再邀请 10 名真实用户进行 7 天干预试用。
- [ ] 仅在证据齐全后，把产品需求池 AFH-003 改为“已完成”。

当前未满足手工权限验收，因此本清单不能作为主线合并批准。

## 5. 分支与合并规则

1. 所有实现提交到个人分支 `feature/AFH-003-p0-core-loop`。
2. 每个大功能先完成自动化测试、APK 构建和真实机验证。
3. 证据记录进入 `docs/AFH-0.1-真实机验收报告.md`，再更新需求池。
4. P0 全部联调通过后，再向 `chenyizhou5885-lang/SheNicest` 提交 PR。
5. 未经 Chenyi 和用户联合验收，不合并到正式仓库 `main`。
