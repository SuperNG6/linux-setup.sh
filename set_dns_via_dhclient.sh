#!/bin/bash

# ==============================================================================
# 脚本名称: set_dns_via_dhclient.sh
# 脚本功能: 在不使用 systemd-resolved 的 Debian/Ubuntu 系统上设置持久性 DNS。
#           通过修改 DHCP 客户端配置 (dhclient.conf) 来实现。
# 适用系统: 最小化安装的 Debian 12, Ubuntu 等使用 dhclient 的系统。
# 版本: 2.1 (改进版)
# ==============================================================================

# --- 配置 ---
PRIMARY_DNS="1.1.1.1"
SECONDARY_DNS="8.8.8.8"
DHCLIENT_CONF="/etc/dhcp/dhclient.conf"
# 定义一个唯一的注释，用于识别脚本添加的内容
CUSTOM_DNS_COMMENT="# Custom DNS servers added by script (set_dns_via_dhclient.sh)"

# --- 脚本主体 ---

echo "🚀 开始配置静态 DNS (通过 dhclient.conf)..."

# 1. 检查 dhclient.conf 文件是否存在
if [ ! -f "$DHCLIENT_CONF" ]; then
  echo "⚠️  警告：配置文件 ${DHCLIENT_CONF} 不存在。"
  echo "正在尝试创建一个最小化的配置文件..."
  touch "$DHCLIENT_CONF"
fi

# 2. 备份原始配置文件 (如果尚未备份)
BACKUP_FILE="${DHCLIENT_CONF}.bak.$(date +%F)"
if [ ! -f "$BACKUP_FILE" ]; then
  echo "📦 正在备份原始配置文件到 ${BACKUP_FILE}..."
  cp "$DHCLIENT_CONF" "$BACKUP_FILE"
fi

# 3. 核心修改逻辑
echo "🔧 正在修改 ${DHCLIENT_CONF}..."

# 步骤 3.1: 为了实现幂等性，先删除之前由本脚本添加的所有DNS配置。
# 我们通过搜索唯一的注释来定位并删除整个块。
# 使用awk比sed处理多行删除更安全可靠。
awk -v comment="$CUSTOM_DNS_COMMENT" '
  BEGIN { p=1 }
  $0 == comment { p=0; next }
  /prepend domain-name-servers.*\;/ { if (!p) { p=1; next } }
  p { print }
' "$DHCLIENT_CONF" > "${DHCLIENT_CONF}.tmp" && mv "${DHCLIENT_CONF}.tmp" "$DHCLIENT_CONF"

# 步骤 3.2: 注释掉文件中任何现存的、活跃的`prepend`或`supersede` DNS 配置。
# 这样做是为了避免冲突，而不是直接删除它们。
# -E: 使用扩展正则表达式
# /^\s*[^#]/: 匹配不是以'#'开头的行（即未注释的行）
# s/.../# &/: 将找到的行替换为 '# ' 加上原来的行内容 (&)
sed -i -E '/^\s*[^#]/ s/^\s*((prepend|supersede)\s+domain-name-servers.*)/# &/' "$DHCLIENT_CONF"

# 步骤 3.3: 在文件末尾添加新的、我们期望的DNS服务器配置。
echo "➕ 正在添加新的 DNS 配置..."
{
  echo "" # 添加一个空行以增加可读性
  echo "$CUSTOM_DNS_COMMENT"
  echo "prepend domain-name-servers ${PRIMARY_DNS}, ${SECONDARY_DNS};"
} >> "$DHCLIENT_CONF"

echo "✅ 配置文件修改完成。"

# 4. 应用网络配置
echo "🔄 正在重新应用网络配置以使 DNS 生效..."
# 这会短暂中断网络连接，通常几秒钟内恢复
# 首先尝试重启 networking.service，这是Debian的经典方式
if command -v systemctl &> /dev/null && systemctl is-active networking.service &> /dev/null; then
    systemctl restart networking.service
    sleep 3 # 等待网络稳定
else
    # 如果 networking.service 不可用，尝试用 ifupdown 重启主接口
    INTERFACE=$(ip -4 route ls | grep default | grep -Eo 'dev [^ ]+' | awk '{print $2}' | head -n1)
    if [ -n "$INTERFACE" ] && command -v ifdown &> /dev/null && command -v ifup &> /dev/null; then
        echo "检测到主网络接口为: ${INTERFACE}。正在使用 ifdown/ifup 重启..."
        ifdown "$INTERFACE" && ifup "$INTERFACE"
        sleep 5 # 等待更长时间，因为 ifup/ifdown 可能更慢
    else
        echo "⚠️  警告: 无法自动重启网络服务。"
        echo "👉 请手动重启VPS ('sudo reboot') 来应用更改。"
    fi
fi

chmod 644 /etc/resolv.conf
# 5. 验证结果
echo "-----------------------------------------------------"
echo "🎉 配置完成！正在验证..."

if [ -f "/etc/resolv.conf" ]; then
    echo "
📜 --- 当前 /etc/resolv.conf 内容 ---"
    cat /etc/resolv.conf
    echo "----------------------------------------"
    echo "🔍 检查: 'nameserver' 行是否以 ${PRIMARY_DNS} 和/或 ${SECONDARY_DNS} 开头。"
    
    # 使用 `dig` 或 `nslookup` 进行真实查询测试
    if command -v dig &> /dev/null; then
      echo -e "\n 使用 'dig' 进行DNS测试..."
      dig google.com @${PRIMARY_DNS} | grep "SERVER:"
    elif command -v nslookup &> /dev/null; then
      echo -e "\n 使用 'nslookup' 进行DNS测试..."
      nslookup google.com ${PRIMARY_DNS} | grep "Server:"
    fi

else
    echo "❌ 错误: /etc/resolv.conf 文件未找到。配置可能未生效。"
fi

echo -e "\n✨ 脚本执行完毕。如果验证成功，您的 DNS 已被修改，并且重启后依然有效。"
