#!/bin/bash

# ==== 配置区域：脚本运行时将提示用户输入以下信息 ====
# DP_Id (DNSPod API Id)
# DP_Key (DNSPod API Key)
# CERT_DIR (证书及私钥存放的基础目录)
# DOMAIN_NAME (主域名 - 必填)
# RELOAD_CMD (证书更新后执行的命令)

# ==== 默认证书及私钥存放路径（用户可覆盖） ====
DEFAULT_CERT_DIR="/etc/nginx/ssl" # 证书将存放在 $CERT_DIR/$DOMAIN_NAME/
DEFAULT_RELOAD_CMD="systemctl reload nginx" # 默认只重载 Nginx

# ----------------------------------------------------
# 以下部分通常无需修改
# ----------------------------------------------------

# acme.sh 绝对路径
ACME_BIN="$HOME/.acme.sh/acme.sh"

# ==== 提示用户输入配置信息 ====
read -p "请输入你的 DNSPod API Id (DP_Id): " DP_Id
if [[ -z "$DP_Id" ]]; then
  echo "错误：DNSPod API Id 未提供。脚本终止。"
  exit 1
fi

read -s -p "请输入你的 DNSPod API Key (DP_Key) (输入不会显示): " DP_Key
echo # 换行
if [[ -z "$DP_Key" ]]; then
  echo "错误：DNSPod API Key 未提供。脚本终止。"
  exit 1
fi

read -p "请输入证书和私钥存放的基础目录 [默认: $DEFAULT_CERT_DIR]: " CERT_DIR
CERT_DIR="${CERT_DIR:-$DEFAULT_CERT_DIR}"

read -p "请输入你要申请证书的主域名 (例如: qinglin.love): " DOMAIN_NAME
if [[ -z "$DOMAIN_NAME" ]]; then
  echo "错误：主域名未提供。脚本终止。"
  exit 1
fi

read -p "请输入证书更新后需要执行的重载命令 [默认: '$DEFAULT_RELOAD_CMD']: " RELOAD_CMD
RELOAD_CMD="${RELOAD_CMD:-$DEFAULT_RELOAD_CMD}"

# ==== 检查 acme.sh 是否安装 ====
if [ ! -f "$ACME_BIN" ]; then
  echo "acme.sh 未安装，正在尝试自动安装..."
  curl https://get.acme.sh | sh
fi
if [ ! -f "$ACME_BIN" ]; then
  echo "错误：acme.sh 安装后仍未找到。请检查安装日志。"
  exit 1
fi
echo "acme.sh 检测通过。"

# ==== 自动切换默认 CA 到 Let's Encrypt (如果当前不是) ====
echo "检查当前 acme.sh 默认 CA..."
default_ca_output=$($ACME_BIN --get-default-ca 2>/dev/null)
current_ca_name=$(echo "$default_ca_output" | awk -F': ' '/Default CA:/ {print $2}')

if [[ "$current_ca_name" != "letsencrypt" && "$current_ca_name" != "LetsEncrypt.org" ]]; then
  echo "当前默认 CA 是 '$current_ca_name'，正在尝试切换到 Let's Encrypt..."
  $ACME_BIN --set-default-ca --server letsencrypt
  if [ $? -ne 0 ]; then
    echo "错误：切换默认 CA 到 Let's Encrypt 失败。请检查 acme.sh 日志。"
    echo "您也可以在申请证书时通过 --server letsencrypt 参数强制使用 Let's Encrypt。"
  else
    echo "默认 CA 已成功切换到 Let's Encrypt。"
  fi
else
  echo "当前默认 CA 已经是 Let's Encrypt ('$current_ca_name')。"
fi

# ==== 写入 DNSPod 环境变量 (acme.sh 会读取这些变量) ====
export DP_Id="$DP_Id"
export DP_Key="$DP_Key"

# ==== 处理域名参数 ====
DOMAIN_ARGS="-d $DOMAIN_NAME" # 主域名是必须的
SUBS_STRING=""

read -p "是否需要为泛域名申请证书 (例如 *.${DOMAIN_NAME})？(y/N) [默认: N]: " NEED_WILDCARD
NEED_WILDCARD="${NEED_WILDCARD:-N}" # 如果用户直接回车，默认为N

if [[ "$NEED_WILDCARD" =~ ^[Yy]$ ]]; then
  DOMAIN_ARGS="$DOMAIN_ARGS -d *.$DOMAIN_NAME"
  echo "将为 $DOMAIN_NAME 和 *.$DOMAIN_NAME 申请证书。"
else
  read -p "请输入其他需要包含在此证书中的子域名 (例如: www.${DOMAIN_NAME} blog.${DOMAIN_NAME}，多个用空格分隔，如果不需要请留空): " SUBS_STRING
  if [[ -n "$SUBS_STRING" ]]; then
    IFS=' ' read -r -a subs_array <<< "$SUBS_STRING"
    for sub in "${subs_array[@]}"; do
      if [[ -n "$sub" ]]; then # 确保子域名不为空
        if [[ "$sub" == *".$DOMAIN_NAME" ]] && [[ "$sub" != "$DOMAIN_NAME" ]]; then
            is_already_added=0
            # shellcheck disable=SC2086
            for existing_arg_part in $DOMAIN_ARGS; do
                if [[ "$existing_arg_part" == "$sub" ]]; then
                    is_already_added=1
                    break
                fi
            done
            if [[ "$is_already_added" -eq 0 ]]; then
                DOMAIN_ARGS="$DOMAIN_ARGS -d $sub"
            fi
        elif [[ "$sub" == "$DOMAIN_NAME" ]]; then
             : # 主域名已默认添加
        else
            echo "警告：输入的子域名 '$sub' 似乎不属于主域名 '$DOMAIN_NAME' 或格式不正确，将忽略此子域名。"
        fi
      fi
    done
  fi
fi

# ==== 创建证书存放的完整路径 ====
# 证书将存放在 $CERT_DIR/$DOMAIN_NAME/ 目录下
FULL_CERT_DIR="$CERT_DIR/$DOMAIN_NAME"
echo "证书文件将存放在: $FULL_CERT_DIR"
mkdir -p "$FULL_CERT_DIR"

# ==== 申请证书 ====
echo "开始证书申请过程..."
echo "将执行: $ACME_BIN --issue --dns dns_dp $DOMAIN_ARGS --debug"
# shellcheck disable=SC2086
$ACME_BIN --issue --dns dns_dp $DOMAIN_ARGS --debug

if [ $? -ne 0 ]; then
  echo "错误：证书申请失败。请检查上面的 acme.sh 输出日志。"
  unset DP_Id # 清理环境变量
  unset DP_Key
  exit 1
fi

# ==== 自动部署证书到指定路径，并自动重载服务 ====
echo "证书申请成功，开始安装证书到指定目录并重载服务..."
$ACME_BIN --install-cert -d "$DOMAIN_NAME" \
  --key-file       "$FULL_CERT_DIR/$DOMAIN_NAME.key" \
  --fullchain-file "$FULL_CERT_DIR/${DOMAIN_NAME}_bundle.pem" \
  --reloadcmd "$RELOAD_CMD"

if [ $? -ne 0 ]; then
  echo "错误：证书安装或服务重载失败。请检查 acme.sh 输出和相关服务日志。"
else
  echo "证书安装和服务重载成功。"
fi

# ==== 清理环境变量 ====
unset DP_Id
unset DP_Key

# ==== 输出证书文件路径和部署提醒 ====
echo ""
echo "====== 操作完成 ======"
echo "证书和私钥已部署到以下位置："
echo "  完整证书链 (Fullchain): $FULL_CERT_DIR/${DOMAIN_NAME}_bundle.pem"
echo "  私钥 (Key):            $FULL_CERT_DIR/$DOMAIN_NAME.key"
echo ""
echo "请确保您的 Nginx (或其他Web服务器) 配置指向以上文件路径。"
echo "Nginx 配置参考："
echo "  ssl_certificate     $FULL_CERT_DIR/${DOMAIN_NAME}_bundle.pem;"
echo "  ssl_certificate_key $FULL_CERT_DIR/$DOMAIN_NAME.key;"
echo ""
echo "acme.sh 会自动处理证书的续期。"
echo "续期成功后，您指定的 reloadcmd ('$RELOAD_CMD') 会被自动执行。"
echo "======================"
