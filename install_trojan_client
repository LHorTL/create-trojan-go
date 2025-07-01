#!/bin/bash

# 安装目录
INSTALL_DIR="/usr/local/trojan-go"
# 服务名称
SERVICE_NAME="trojan-go-client"
# systemd服务文件路径
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
# trojan-go下载链接
DOWNLOAD_URL="https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip"
# 临时目录
TEMP_DIR="/tmp/trojan-go-download"

if [ "$EUID" -ne 0 ]; then
    echo "错误: 此脚本需要以root权限运行"
    echo "请使用 sudo $0"
    exit 1
fi

if command -v apt &> /dev/null; then
    UPDATE_CMD="apt update"
    INSTALL_CMD="apt install -y"
elif command -v yum &> /dev/null; then
    UPDATE_CMD="yum makecache"
    INSTALL_CMD="yum install -y"
else
    echo "错误: 不支持的系统，未找到apt或yum包管理器"
    exit 1
fi

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

read -p "请输入trojan-go服务器IP: " SERVER_IP
if [ -z "$SERVER_IP" ]; then
    echo "错误: 服务器IP不能为空"
    exit 1
fi

read -p "请输入trojan-go服务器端口（如 443）: " SERVER_PORT
if [ -z "$SERVER_PORT" ]; then
    echo "错误: 服务器端口不能为空"
    exit 1
fi
if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]]; then
    echo "错误: 端口必须是数字"
    exit 1
fi

read -p "请输入trojan-go连接密码: " PASSWORD
if [ -z "$PASSWORD" ]; then
    echo "错误: 密码不能为空"
    exit 1
fi

read -p "请输入服务器域名（可选，留空则回车）: " SERVER_DOMAIN

mkdir -p "$TEMP_DIR"

echo "从 $DOWNLOAD_URL 下载trojan-go..."
curl -L -o "$TEMP_DIR/trojan-go.zip" "$DOWNLOAD_URL"
if [ $? -ne 0 ]; then
    echo "错误: 下载trojan-go失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "解压trojan-go..."
unzip -o "$TEMP_DIR/trojan-go.zip" -d "$TEMP_DIR/"
if [ $? -ne 0 ]; then
    echo "错误: 解压失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "创建安装目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

echo "移动trojan-go文件到 $INSTALL_DIR"
mv "$TEMP_DIR"/* "$INSTALL_DIR/"
if [ $? -ne 0 ]; then
    echo "错误: 文件移动失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

rm -rf "$TEMP_DIR"

chmod 755 "$INSTALL_DIR/trojan-go"
chown root:root -R "$INSTALL_DIR"

# 生成client.json
CONFIG_FILE="$INSTALL_DIR/client.json"
echo "生成trojan-go客户端配置文件: $CONFIG_FILE"
cat > "$CONFIG_FILE" <<EOF
{
    "run_type": "client",
    "local_addr": "0.0.0.0",
    "local_port": 1080,
    "remote_addr": "$SERVER_IP",
    "remote_port": $SERVER_PORT,
    "password": [
        "$PASSWORD"
    ],
    "ssl": {
        "sni": "$SERVER_DOMAIN",
        "alpn": [
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "verify": false,
        "verify_hostname": false,
        "cert": "",
        "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA:AES128-SHA:AES256-SHA:DES-CBC3-SHA",
        "cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "fast_open": false,
        "fast_open_qlen": 20
    }
}
EOF

echo "创建systemd服务文件: $SYSTEMD_FILE"
cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=Trojan-Go Client Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/trojan-go -config $INSTALL_DIR/client.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "$SERVICE_NAME 客户端服务已成功启动"
    echo "本地监听端口: 0.0.0.0:1080"
    echo "服务器: $SERVER_IP"
    echo "服务器端口: $SERVER_PORT"
    if [ -n "$SERVER_DOMAIN" ]; then
        echo "SNI 域名: $SERVER_DOMAIN"
    fi
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
echo "使用方式：将本地代理（如浏览器、系统代理、终端等）指向 127.0.0.1:1080 或 0.0.0.0:1080"
echo "如需修改配置，请编辑 $CONFIG_FILE 后重启服务（systemctl restart $SERVICE_NAME）"
