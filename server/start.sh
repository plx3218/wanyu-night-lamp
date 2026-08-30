#!/bin/bash
# SheNicest AI Server 部署脚本
# 在云服务器上执行：bash start.sh

set -e

echo "=== SheNicest AI Server 部署 ==="

# 检查 Python
if ! command -v python3 &> /dev/null; then
    echo "安装 Python..."
    sudo apt update && sudo apt install -y python3 python3-pip
fi

echo "Python: $(python3 --version)"

# 创建虚拟环境
python3 -m venv venv
source venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 检查 API Key
if [ -z "$DEEPSEEK_API_KEY" ]; then
    echo ""
    echo "⚠️  请先设置 DeepSeek API Key："
    echo "   export DEEPSEEK_API_KEY=你的key"
    echo ""
    echo "然后重新运行：bash start.sh"
    exit 1
fi

# 启动服务
echo "启动 AI 服务，端口 8000..."
uvicorn server:app --host 0.0.0.0 --port 8000 --reload
