#!/bin/bash

# ===================================================================================
# Linux 服务器网络性能优化脚本 (TCP+UDP)
#
# 适用场景:
#   - 服务: 优化 Sing-box, V2Ray, Xray 网络吞吐 (同时支持 VLESS/VMess 和 Hysteria2/QUIC)
#   - 网络: 优化高带宽、高延迟的跨国网络 (如中美, 中日, 中欧等)
#
# 核心思路:
#   1. TCP优化: 启用BBR+FQ，并根据BDP动态计算TCP缓冲区。
#   2. UDP优化: 为QUIC协议(Hysteria2)提供足够大的系统级UDP缓冲区。
#   3. 磁盘I/O优化: 优化脏页回写策略，避免I/O抖动影响网络服务。
#   4. 基础安全: 加入基本的网络安全加固参数。
#   5. 写入逻辑: 采用"先清理后追加"策略，确保配置不重复且带有逐行注释。
#
# ===================================================================================

optimize_kernel_parameters() {
    # 确认操作
    read -p "您确定要优化Linux内核网络参数吗？这将修改 '/etc/sysctl.conf'。 (y/n): " choice
    case "$choice" in
        [Yy]*)
            echo "--> 操作确认，开始网络优化..."
            ;;
        *)
            echo "--> 操作已取消。"
            exit 0
            ;;
    esac

    # --- 步骤 1: 备份原始配置文件 ---
    if [ -f /etc/sysctl.conf ]; then
        backup_file="/etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)"
        echo "--> 正在备份当前配置到: ${backup_file}"
        cp /etc/sysctl.conf "${backup_file}"
    fi

    # --- 步骤 2: 检测系统内存 ---
    echo "--> 正在检测系统内存..."
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    mem_mb=$((mem_kb / 1024))
    echo "    系统内存: ${mem_mb} MB"

    # --- 步骤 3: 获取用户网络环境信息 (支持不对称带宽) ---
    read -p "--> 是否需要手动输入网络参数? [y/N]: " manual_input
    if [[ $manual_input =~ ^[Yy]$ ]]; then
        read -p "    请输入您的客户端到服务器的平均网络延迟 (RTT, 单位ms, 例如 170): " rtt
        read -p "    请输入服务器的下载带宽 (单位Mbit/s, 例如 1000): " download_bw
        read -p "    请输入服务器的上传带宽 (单位Mbit/s, 例如 100): " upload_bw
    else
        rtt=170
        download_bw=1000
        upload_bw=100
        echo "--> 使用不对称带宽默认值: RTT=${rtt}ms, 下载=${download_bw}Mbit/s, 上传=${upload_bw}Mbit/s"
    fi

    # 确保输入不为空，提供一个最终的默认值
    : ${rtt:=170}
    : ${download_bw:=1000}
    : ${upload_bw:=100}

    # --- 步骤 4: 分别计算下载和上传的BDP (带宽延迟积) ---
    # 下载BDP (接收方向)
    download_bw_bytes_per_sec=$(awk "BEGIN{printf \"%.0f\", ${download_bw} * 1000 * 1000 / 8}")
    download_bdp_bytes=$(awk "BEGIN{printf \"%.0f\", ${download_bw_bytes_per_sec} * ${rtt} / 1000}")
    
    # 上传BDP (发送方向)  
    upload_bw_bytes_per_sec=$(awk "BEGIN{printf \"%.0f\", ${upload_bw} * 1000 * 1000 / 8}")
    upload_bdp_bytes=$(awk "BEGIN{printf \"%.0f\", ${upload_bw_bytes_per_sec} * ${rtt} / 1000}")
    
    echo "--> 下载方向BDP: ${download_bdp_bytes} 字节 (约 $(awk "BEGIN{printf \"%.2f\", ${download_bdp_bytes}/1024/1024}") MB)"
    echo "    上传方向BDP: ${upload_bdp_bytes} 字节 (约 $(awk "BEGIN{printf \"%.2f\", ${upload_bdp_bytes}/1024/1024}") MB)"

    # --- 步骤 5: 不对称带宽优化策略 ---
    # 目标：下载优先，上传确保能跑满100M即可
    # 策略：接收缓冲区优化，发送缓冲区保守优化

    # 下载优化：接收缓冲区 = 3倍下载BDP（确保下载性能）
    recv_multiplier=3
    # 上传优化：发送缓冲区 = 1.5倍上传BDP（确保上传速率，避免bufferbloat）
    send_multiplier=1.5
    
    # 计算目标缓冲区大小
    target_recv_buffer_bytes=$(awk "BEGIN{printf \"%.0f\", ${download_bdp_bytes} * ${recv_multiplier}}")
    target_send_buffer_bytes=$(awk "BEGIN{printf \"%.0f\", ${upload_bdp_bytes} * ${send_multiplier}}")
    
    # 设置合理的最小值（基于实际带宽）
    min_recv_buffer_bytes=$((32 * 1024 * 1024))  # 下载最小32MB
    min_send_buffer_bytes=$((4 * 1024 * 1024))   # 上传最小4MB

    # 确保不小于最小值
    if [ "$target_recv_buffer_bytes" -lt "$min_recv_buffer_bytes" ]; then
        echo "    [信息] 接收缓冲区提升至最小值: ${min_recv_buffer_bytes} 字节"
        target_recv_buffer_bytes=$min_recv_buffer_bytes
    fi
    
    if [ "$target_send_buffer_bytes" -lt "$min_send_buffer_bytes" ]; then
        echo "    [信息] 发送缓冲区提升至最小值: ${min_send_buffer_bytes} 字节"
        target_send_buffer_bytes=$min_send_buffer_bytes
    fi

    # 内存限制检查：总缓冲区不超过60%系统内存（下载优先策略）
    max_total_buffer_bytes=$((mem_kb * 1024 * 3 / 5))
    total_target_bytes=$((target_recv_buffer_bytes + target_send_buffer_bytes))
    
    if [ "$total_target_bytes" -gt "$max_total_buffer_bytes" ]; then
        echo "    [警告] 总缓冲区大小超限，按比例缩减..."
        # 优先保证下载性能：接收缓冲区占总限制的80%，发送缓冲区占20%
        final_recv_buffer_bytes=$((max_total_buffer_bytes * 4 / 5))
        final_send_buffer_bytes=$((max_total_buffer_bytes * 1 / 5))
        echo "           [不对称优化] 接收=${final_recv_buffer_bytes}字节, 发送=${final_send_buffer_bytes}字节"
    else
        final_recv_buffer_bytes=$target_recv_buffer_bytes
        final_send_buffer_bytes=$target_send_buffer_bytes
    fi
    
    # 兼容性：设置全局最大值为接收缓冲区大小（因为下载是主要需求）
    final_buffer_bytes=$final_recv_buffer_bytes

    echo "--> [不对称优化] 接收缓冲区(下载): ${final_recv_buffer_bytes} 字节 (约 $(awk "BEGIN{printf \"%.1f\", ${final_recv_buffer_bytes}/1024/1024}") MB)"
    echo "    [不对称优化] 发送缓冲区(上传): ${final_send_buffer_bytes} 字节 (约 $(awk "BEGIN{printf \"%.1f\", ${final_send_buffer_bytes}/1024/1024}") MB)"
    echo "    [带宽分析] 下载=${download_bw}Mbps→缓冲区倍数=$(awk "BEGIN{printf \"%.1f\", ${final_recv_buffer_bytes}/${download_bdp_bytes}}"), 上传=${upload_bw}Mbps→缓冲区倍数=$(awk "BEGIN{printf \"%.1f\", ${final_send_buffer_bytes}/${upload_bdp_bytes}}")"

    # --- 步骤 6: 计算UDP总缓冲区大小 ---
    # net.ipv4.udp_mem 的单位是内存页 (page)，通常为4KB。
    # 我们设置max值为单个连接最大缓冲区的4倍，以应对多个并发连接。
    udp_mem_max_pages=$(( final_buffer_bytes * 4 / 4096 ))
    udp_mem_pressure_pages=$(( udp_mem_max_pages * 3 / 4 ))
    udp_mem_min_pages=$(( udp_mem_max_pages / 2 ))

    # --- 步骤 7: 根据内存大小设置dirty_bytes参数 ---
    echo "--> 正在根据系统内存计算最佳的脏页参数..."
    
    # 512MB内存档位：保守设置，避免内存压力
    if [ "$mem_mb" -le 512 ]; then
        dirty_bytes=16777216        # 16MB
        dirty_background_bytes=4194304  # 4MB
        echo "    [内存档位] 512MB及以下: 脏页=${dirty_bytes}字节(16MB), 后台=${dirty_background_bytes}字节(4MB)"
    # 512MB-1024MB档位：适中设置，兼顾性能和稳定性
    elif [ "$mem_mb" -le 1024 ]; then
        dirty_bytes=31457280        # 30MB  
        dirty_background_bytes=6291456   # 6MB
        echo "    [内存档位] 512MB-1024MB: 脏页=${dirty_bytes}字节(30MB), 后台=${dirty_background_bytes}字节(6MB)"
    # 1GB以上内存档位：激进设置，最大化网络性能，减少磁盘I/O干扰
    else
        dirty_bytes=67108864        # 64MB
        dirty_background_bytes=16777216  # 16MB
        echo "    [内存档位] 1024MB以上: 脏页=${dirty_bytes}字节(64MB), 后台=${dirty_background_bytes}字节(16MB) - 网络优先策略"
    fi

    # --- 步骤 8: 清理旧配置块 (修复重复注释问题) ---
    echo "--> 正在清理 /etc/sysctl.conf 中的旧配置块..."
    
    # 使用临时文件来安全地处理配置文件
    temp_file=$(mktemp)
    
    # 检查是否存在脚本生成的配置块标记
    if grep -q "=== 内核参数优化 ===" /etc/sysctl.conf; then
        echo "    [检测] 发现之前由脚本生成的配置块，正在删除..."
        # 删除从开始标记到结束标记之间的所有内容（包括边界）
        awk '
        /^# === 内核参数优化 === *$/ {
            in_block = 1
            next
        }
        /^# === 参数优化 end === *$/ && in_block {
            in_block = 0
            next
        }
        !in_block {print}
        ' /etc/sysctl.conf > "$temp_file"
    else
        echo "    [检测] 未发现之前的脚本配置块，进行常规清理..."
        # 如果没有脚本标记，则进行常规清理
        cp /etc/sysctl.conf "$temp_file"
    fi
    
    # 额外清理：删除可能残留的单独参数行（防止之前版本遗留的配置）
    managed_keys=(
        "net.ipv4.tcp_congestion_control" "net.core.default_qdisc" "net.ipv4.tcp_moderate_rcvbuf"
        "net.core.rmem_max" "net.core.wmem_max" "net.core.rmem_default" "net.core.wmem_default"
        "net.ipv4.tcp_rmem" "net.ipv4.tcp_wmem" "net.ipv4.tcp_window_scaling" "net.ipv4.tcp_timestamps"
        "net.ipv4.tcp_sack" "net.ipv4.tcp_slow_start_after_idle" "net.ipv4.tcp_mtu_probing"
        "net.ipv4.tcp_notsent_lowat" "net.ipv4.tcp_adv_win_scale" "net.ipv4.tcp_max_orphans" "net.ipv4.tcp_mem"
        "net.ipv4.tcp_retries1" "net.ipv4.tcp_retries2" "net.ipv4.tcp_frto"
        "net.ipv4.udp_mem" "net.core.somaxconn" "net.core.netdev_max_backlog" "net.ipv4.tcp_tw_reuse"
        "net.ipv4.tcp_max_tw_buckets" "net.ipv4.tcp_fin_timeout" "net.ipv4.tcp_fastopen" "net.ipv4.tcp_max_syn_backlog"
        "net.ipv4.tcp_keepalive_time" "net.ipv4.tcp_keepalive_intvl" "net.ipv4.tcp_keepalive_probes" "net.ipv4.ip_local_port_range"
        "vm.swappiness" "vm.overcommit_memory" "vm.overcommit_ratio" "net.ipv4.ip_forward" "fs.inotify.max_user_watches"
        "fs.file-max" "fs.nr_open" "vm.dirty_bytes" "vm.dirty_background_bytes" "vm.dirty_ratio" "vm.dirty_background_ratio"
        "vm.dirty_expire_centisecs" "vm.dirty_writeback_centisecs"
        "net.ipv4.icmp_echo_ignore_broadcasts" "net.ipv4.icmp_ignore_bogus_error_responses"
        "net.ipv4.conf.all.rp_filter" "net.ipv4.conf.default.rp_filter"
    )
    
    # 从临时文件中删除可能残留的单独参数行
    for key in "${managed_keys[@]}"; do
        sed -i -E "/^\s*#?\s*${key//./\\.}\s*=/d" "$temp_file"
    done
    
    # 将清理后的内容写回原文件
    mv "$temp_file" /etc/sysctl.conf

    # --- 步骤 9: 构建新的配置块 ---
    # 使用heredoc来创建配置块，包含逐行注释，更清晰易读
    read -r -d '' sysctl_config_block << EOM

# === 内核参数优化 ===
# == 由高级网络优化脚本于 $(date) 生成
# == 优化目标: 最大化网络吞吐量 (TCP + UDP)
# == 适用服务: Sing-box, Xray (VLESS/VMess), Hysteria2 (QUIC) 等
# == 网络环境: 下载RTT=${rtt}ms,${download_bw}Mbps / 上传RTT=${rtt}ms,${upload_bw}Mbps
# == 系统内存: ${mem_mb}MB, 接收缓冲区: ${final_recv_buffer_bytes}字节, 发送缓冲区: ${final_send_buffer_bytes}字节
# == 脏页策略: ${dirty_bytes}字节($(awk "BEGIN{printf \"%.0f\", ${dirty_bytes}/1024/1024}")MB)/$(awk "BEGIN{printf \"%.0f\", ${dirty_background_bytes}/1024/1024}")MB - 减少磁盘I/O对网络的干扰
# ===================================================================================

# ---- A. 核心拥塞控制与队列管理 (优化BBR性能) ----
# 设置默认的TCP拥塞控制算法为BBR。
net.ipv4.tcp_congestion_control = bbr
# 设置默认的网络包调度算法为FQ。
net.core.default_qdisc = fq
# 设置：优化拥塞控制行为，减少保守性
net.ipv4.tcp_moderate_rcvbuf = 0

# ---- B. 全局套接字缓冲区核心参数 ----
# 针对不对称网络：下载优先，上传够用即可
net.core.rmem_max = ${final_recv_buffer_bytes}
net.core.wmem_max = ${final_send_buffer_bytes}
# 不对称默认值：下载默认更大，上传适中
net.core.rmem_default = 16777216
net.core.wmem_default = 2097152

# ---- C. TCP 专用行为调优 ----
# 优化：接收缓冲区(下载)，发送缓冲区(上传)
net.ipv4.tcp_rmem = 16384 1048576 ${final_recv_buffer_bytes}
net.ipv4.tcp_wmem = 8192 131072 ${final_send_buffer_bytes}
# 启用TCP窗口缩放，高带宽必须。
net.ipv4.tcp_window_scaling = 1
# 启用TCP时间戳，BBR必需。
net.ipv4.tcp_timestamps = 1
# 启用SACK，快速丢包恢复。
net.ipv4.tcp_sack = 1
# 禁用空闲慢启动，保持BBR控制。
net.ipv4.tcp_slow_start_after_idle = 0
# 保守MTU探测，稳定性优先。
net.ipv4.tcp_mtu_probing = 1
# 上传优化：较小的发送队列下限，避免积压
net.ipv4.tcp_notsent_lowat = 32768
# 接收窗口分配优化，下载优先。
net.ipv4.tcp_adv_win_scale = 2
# 适中的孤儿连接数
net.ipv4.tcp_max_orphans = 32768
# 不对称内存分配：更多给接收
net.ipv4.tcp_mem = 524288 1048576 2097152
# 保守重传策略，避免上传抖动
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 10
# 适度丢包检测
net.ipv4.tcp_frto = 1
# 不对称优化：禁用发送缓冲区的自动调整，避免上传波动
net.ipv4.tcp_moderate_rcvbuf = 1

# ---- D. UDP/QUIC 性能优化 (针对 Hysteria2) ----
# 设置系统所有UDP套接字可以占用的内存大小(单位: page)。
net.ipv4.udp_mem = ${udp_mem_min_pages} ${udp_mem_pressure_pages} ${udp_mem_max_pages}

# ---- E. 连接管理与系统资源 (并发优化) ----
# 增大系统级监听队列的最大长度。
net.core.somaxconn = 262144
# 增大网卡接收数据包的队列最大长度。
net.core.netdev_max_backlog = 1048576
# 开启TIME_WAIT状态连接的快速回收和重用。
net.ipv4.tcp_tw_reuse = 1
# 减少系统中TIME_WAIT状态连接的最大数量，更快释放资源。
net.ipv4.tcp_max_tw_buckets = 32768
# 减少FIN_WAIT_2状态的超时时间。
net.ipv4.tcp_fin_timeout = 10
# 开启TCP Fast Open (TFO)。
net.ipv4.tcp_fastopen = 3
# 增大SYN队列的最大长度。
net.ipv4.tcp_max_syn_backlog = 65536
# 设置：减少保活探测间隔，更快检测死连接
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 3
# 设置：优化端口重用
net.ipv4.ip_local_port_range = 1024 65535
# 开启IP转发。
net.ipv4.ip_forward = 1

# ---- F. 内存与系统相关 (内存策略) ----
# 降低内核使用Swap分区的倾向。
vm.swappiness = 1
# 允许内核"过度承诺"内存。
vm.overcommit_memory = 1
# 设置：允许更大的过度承诺比例
vm.overcommit_ratio = 100
# 增加用户可以监视的文件/目录数量。
fs.inotify.max_user_watches = 65536
# 增加文件描述符限制
fs.file-max = 1048576
# 增加进程可打开的文件数
fs.nr_open = 524288

# ---- G. 磁盘I/O与脏页优化 (基于内存大小的智能配置) ----
# 启用字节模式：使用 dirty_bytes / dirty_background_bytes，使阈值固定一致
# 最大脏页阈值：${mem_mb}MB内存 → ${dirty_bytes}字节($(awk "BEGIN{printf \"%.0f\", ${dirty_bytes}/1024/1024}")MB)
vm.dirty_bytes = ${dirty_bytes}
# 后台异步刷脏页触发阈值：$(awk "BEGIN{printf \"%.0f\", ${dirty_background_bytes}/1024/1024}")MB
vm.dirty_background_bytes = ${dirty_background_bytes}
# 禁用百分比模式，避免与字节模式冲突
vm.dirty_ratio = 0
vm.dirty_background_ratio = 0
# 脏页最短留存时间 = 30 秒，然后可被刷写
vm.dirty_expire_centisecs = 3000
# 后台写线程间隔 = 5 秒
vm.dirty_writeback_centisecs = 500

# ---- H. 网络安全加固 ----
# 忽略ICMP广播请求。
net.ipv4.icmp_echo_ignore_broadcasts = 1
# 忽略格式错误的ICMP响应。
net.ipv4.icmp_ignore_bogus_error_responses = 1
# 开启反向路径过滤，防IP欺骗。
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# === 参数优化 end ===
EOM

    # --- 步骤 10: 将新配置追加到文件 ---
    echo "--> 正在将新的优化配置追加到 /etc/sysctl.conf..."
    echo "${sysctl_config_block}" >> /etc/sysctl.conf

    # --- 步骤 11: 应用新的内核参数 ---
    echo "--> 正在应用新的内核参数..."
    # 执行sysctl -p并显示其输出，以便用户确认
    sysctl -p /etc/sysctl.conf
    if [ $? -eq 0 ]; then
        echo "====== 内核参数优化成功并已生效！ ======"
        echo "====== 配置信息已记录在配置块的注释中，便于后续维护。 ======"
        echo "====== 脏页参数已根据${mem_mb}MB内存进行优化配置。 ======"
        echo "====== 为确保所有网络相关设置完全应用，建议您重启服务器。 ======"
    else
        echo "====== [错误] 应用内核参数时出错，请检查 /etc/sysctl.conf 的语法。 ======"
    fi
}

# 运行主函数
optimize_kernel_parameters
