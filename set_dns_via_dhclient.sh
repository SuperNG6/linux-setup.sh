#!/bin/bash

# ==============================================================================
# 脚本名称: set_dns_via_dhclient.sh
# 脚本功能: 在不使用 systemd-resolved 的 Debian/Ubuntu 系统上设置持久性 DNS。
#           通过修改 DHCP 客户端配置 (dhclient.conf) 来实现。
# 适用系统: 最小化安装的 Debian 12, Ubuntu 等使用 dhclient 的系统。
# 版本: 2.0
# ==============================================================================

# --- 配置 ---
PRIMARY_DNS="1.1.1.1"
SECONDARY_DNS="8.8.8.8"
DHCLIENT_CONF="/etc/dhcp/dhclient.conf"

# --- 脚本主体 ---

echo "🚀 开始配置静态 DNS (通过 dhclient.conf)..."

# 2. 检查 dhclient.conf 文件是否存在
if [ ! -f "$DHCLIENT_CONF" ]; then
  echo "⚠️  警告：配置文件 ${DHCLIENT_CONF} 不存在。"
  echo "正在尝试创建一个默认的配置文件..."
  # 创建一个最小化的配置文件
  touch "$DHCLIENT_CONF"
fi

# 3. 备份原始配置文件 (如果尚未备份)
BACKUP_FILE="${DHCLIENT_CONF}.bak.$(date +%F)"
if [ ! -f "$BACKUP_FILE" ]; then
  echo "📦 正在备份原始配置文件到 ${BACKUP_FILE}..."
  cp "$DHCLIENT_CONF" "$BACKUP_FILE"
fi

# 4. 修改 dhclient.conf
echo "🔧 正在修改 ${DHCLIENT_CONF}..."

# 使用 sed 命令原地删除所有以 "prepend domain-name-servers" 开头的行，避免重复添加
sed -i '/^prepend domain-name-servers/d' "$DHCLIENT_CONF"

# 在文件末尾添加新的DNS服务器配置
# 'prepend' 确保我们的DNS被优先使用
echo "" >> "$DHCLIENT_CONF" # 添加一个空行以增加可读性
echo "# Custom DNS Servers (added by script)" >> "$DHCLIENT_CONF"
echo "prepend domain-name-servers ${PRIMARY_DNS}, ${SECONDARY_DNS};" >> "$DHCLIENT_CONF"

echo "✅ 配置文件修改完成。"

# 5. 应用网络配置
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

# 6. 验证结果
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
      echo -e "\n melakukan tes DNS dengan 'dig'..."
      dig google.com @${PRIMARY_DNS} | grep "SERVER:"
    elif command -v nslookup &> /dev/null; then
      echo -e "\n melakukan tes DNS dengan 'nslookup'..."
      nslookup google.com ${PRIMARY_DNS} | grep "Server:"
    fi

else
    echo "❌ 错误: /etc/resolv.conf 文件未找到。配置可能未生效。"
fi

echo -e "\n✨ 脚本执行完毕。如果验证成功，您的 DNS 已被修改，并且重启后依然有效。"