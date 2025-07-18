#!/bin/bash

# 安装目录，用于存放trojan-go的可执行文件和配置文件
INSTALL_DIR="/usr/local/trojan-go"
# 服务名称，用于systemd服务管理
SERVICE_NAME="trojan-go"
# systemd服务文件路径
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
# trojan-go下载链接，指向GitHub releases的最新Linux amd64版本
DOWNLOAD_URL="https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip"
# 临时目录，用于下载和解压trojan-go
TEMP_DIR="/tmp/trojan-go-download"
# SSL证书默认目录
CERT_DIR="/etc/ssl"

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo "错误: 此脚本需要以root权限运行"
    echo "请使用 sudo $0"
    exit 1
fi

# 检测系统类型并设置包管理器
if command -v apt &> /dev/null; then
    PACKAGE_MANAGER="apt"
    UPDATE_CMD="apt update"
    INSTALL_CMD="apt install -y"
elif command -v yum &> /dev/null; then
    PACKAGE_MANAGER="yum"
    UPDATE_CMD="yum makecache"
    INSTALL_CMD="yum install -y"
else
    echo "错误: 不支持的系统，未找到apt或yum包管理器"
    exit 1
fi

# 检查并安装必要的工具
echo "检查并安装必要的工具..."
for cmd in curl unzip; do
    if ! command -v $cmd &> /dev/null; then
        echo "$cmd 未安装，正在安装..."
        $UPDATE_CMD
        $INSTALL_CMD $cmd
        if [ $? -ne 0 ]; then
            echo "错误: 安装 $cmd 失败"
            exit 1
        fi
        echo "$cmd 安装成功"
    else
        echo "$cmd 已安装"
    fi
done

# 检查并安装nginx
if ! command -v nginx &> /dev/null; then
    echo "nginx 未安装，正在安装..."
    $UPDATE_CMD
    $INSTALL_CMD nginx
    if [ $? -ne 0 ]; then
        echo "错误: 安装 nginx 失败"
        exit 1
    fi
    echo "nginx 安装成功"
    # 启动nginx并设置开机启动
    systemctl start nginx
    systemctl enable nginx
    if systemctl is-active --quiet nginx; then
        echo "nginx 服务已启动并设置开机启动"
    else
        echo "警告: nginx 服务启动失败，请手动检查"
    fi
else
    echo "nginx 已安装"
fi

# 交互式输入域名、IP、端口和密码
read -p "请输入域名 （trojan需要有https域名）证书文件请提前放到/etc/ssl文件夹中：" DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "错误: 域名不能为空"
    exit 1
fi

read -p "请输入服务器IP地址（如 192.168.1.1）: " SERVER_IP
if [ -z "$SERVER_IP" ]; then
    echo "错误: IP地址不能为空"
    exit 1
fi

read -p "请输入占用端口（如 1080）: " PORT
if [ -z "$PORT" ]; then
    echo "错误: 端口不能为空"
    exit 1
fi
# 验证端口是否为数字
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "错误: 端口必须是数字"
    exit 1
fi

read -p "请输入trojan-go密码: " PASSWORD
if [ -z "$PASSWORD" ]; then
    echo "错误: 密码不能为空"
    exit 1
fi

# 构建SSL证书文件名，使用域名变量，并用花括号明确变量边界
CERT_FILE="${DOMAIN}_bundle.crt"
KEY_FILE="${DOMAIN}.key"

# 创建临时目录
mkdir -p "$TEMP_DIR"

# 获取架构并下载对应Trojan-Go
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    DOWNLOAD_URL="https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    DOWNLOAD_URL="https://github.com/p4gefau1t/trojan-go/releases/download/v0.10.6/trojan-go-linux-arm.zip"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

echo "检测到系统架构: $ARCH"
echo "将下载: $DOWNLOAD_URL"

# 下载trojan-go
echo "从 $DOWNLOAD_URL 下载trojan-go..."
curl -L -o "$TEMP_DIR/trojan-go.zip" "$DOWNLOAD_URL"
if [ $? -ne 0 ]; then
    echo "错误: 下载trojan-go失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 解压文件
echo "解压trojan-go..."
unzip -o "$TEMP_DIR/trojan-go.zip" -d "$TEMP_DIR/"
if [ $? -ne 0 ]; then
    echo "错误: 解压失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 创建安装目录
echo "创建安装目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# 移动文件到安装目录
echo "移动trojan-go文件到 $INSTALL_DIR"
mv "$TEMP_DIR"/* "$INSTALL_DIR/"
if [ $? -ne 0 ]; then
    echo "错误: 文件移动失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 清理临时文件
rm -rf "$TEMP_DIR"

# 设置权限
echo "设置文件权限"
chmod 755 "$INSTALL_DIR/trojan-go"
chown root:root -R "$INSTALL_DIR"

# 创建或修改配置文件
CONFIG_FILE="$INSTALL_DIR/config.json"
echo "创建默认配置文件，端口设置为 $PORT，域名设置为 $DOMAIN，IP设置为 $SERVER_IP"
cat > "$CONFIG_FILE" << EOF
{
    "run_type": "server",
    "local_addr": "$SERVER_IP",
    "local_port": $PORT,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$PASSWORD"
    ],
    "ssl": {
        "cert": "$CERT_DIR/$CERT_FILE",
        "key": "$CERT_DIR/$KEY_FILE",
        "sni": "$DOMAIN"
    },
    "router": {
        "enabled": true,
        "bypass": [
            "geoip:cn",
            "geoip:private",
            "full:localhost"
        ],
        "block": [
            "geoip:private"
        ],
        "geoip": "$INSTALL_DIR/geoip.dat",
        "geosite": "$INSTALL_DIR/geosite.dat"
    }
}
EOF

# 创建systemd服务文件
echo "创建systemd服务文件: $SYSTEMD_FILE"
cat > "$SYSTEMD_FILE" << EOF
[Unit]
Description=Trojan-Go Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/trojan-go -config $INSTALL_DIR/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 重载systemd配置
echo "重载systemd配置"
systemctl daemon-reload

# 启用服务（开机启动）
echo "启用 $SERVICE_NAME 服务"
systemctl enable "$SERVICE_NAME"

# 启动服务
echo "启动 $SERVICE_NAME 服务"
systemctl start "$SERVICE_NAME"

# 检查服务状态
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "$SERVICE_NAME 服务已成功启动"
    echo "监听端口: $PORT"
    echo "域名: $DOMAIN"
    echo "服务器IP: $SERVER_IP"
    echo "可以通过以下命令查看服务状态："
    echo "  systemctl status $SERVICE_NAME"
    echo "可以通过以下命令停止服务："
    echo "  systemctl stop $SERVICE_NAME"
else
    echo "错误: $SERVICE_NAME 服务启动失败"
    echo "请检查日志：journalctl -u $SERVICE_NAME"
    exit 1
fi

echo "安装完成！"
echo "注意：请确保 $CERT_DIR 目录下有正确的SSL证书文件（$CERT_FILE 和 $KEY_FILE）"
echo "如果需要调整路由规则或其他配置，请编辑 $CONFIG_FILE"
echo "nginx 已安装，如果需要配置反向代理或SSL，请编辑nginx配置文件（通常在 /etc/nginx/）"
