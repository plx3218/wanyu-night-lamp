#!/bin/bash
set -e
pkill -f "uvicorn server:app" || true
sleep 1
mv /opt/shenicest /opt/wanyu
for f in /opt/wanyu/venv/bin/*; do
  if [ -f "$f" ] && [ ! -L "$f" ]; then
    if grep -q "/opt/shenicest" "$f" 2>/dev/null; then
      sed -i "s|/opt/shenicest|/opt/wanyu|g" "$f"
    fi
  fi
done
sed -i "s|/opt/shenicest|/opt/wanyu|g" /opt/wanyu/venv/pyvenv.cfg 2>/dev/null || true
rm -rf /opt/wanyu/__pycache__
# 首次部署时写入 .env；真实 key 已配置在服务器 /opt/wanyu/.env，不硬编码在脚本里
if [ ! -f /opt/wanyu/.env ]; then
  printf "DEEPSEEK_API_KEY=YOUR_DEEPSEEK_API_KEY\n" > /opt/wanyu/.env
  chmod 600 /opt/wanyu/.env
fi
/opt/wanyu/venv/bin/python3 -c "import py_compile; py_compile.compile('/tmp/server.py', doraise=True); print('COMPILE_OK')"
cp /tmp/server.py /opt/wanyu/server.py
cp /tmp/wanyu-api.service /etc/systemd/system/wanyu-api.service
systemctl daemon-reload
systemctl enable --now wanyu-api
sleep 3
echo "---SERVICE---"
systemctl is-active wanyu-api
echo "---HEALTH---"
curl -s http://localhost:8000/api/health
echo ""
curl -s http://localhost:8000/health
echo ""
echo "---DIR---"
ls /opt/wanyu/
