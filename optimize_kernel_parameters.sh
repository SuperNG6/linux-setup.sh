#!/bin/bash

# ===================================================================================
# Linux 服务器网络性能优化脚本 (TCP+UDP)
#
# 适用场景:
#   - 服务: 优化 Sing-box, V2Ray, Xray 网络吞吐 (同时支持 VLESS/VMess 和 Hysteria2/QUIC)
#   - 网络: 优化高带宽、高延迟的跨国网络 (如中美, 中日, 中欧等)
#
# 核心思路:
#   1. TCP优化: 检测BBR+FQ，按较大方向三倍BDP计算收发上限，保留32/16MiB下限。
#   2. UDP优化: 为QUIC协议(Hysteria2)提供足够大的系统级UDP缓冲区。
#   3. 磁盘I/O优化: 优化脏页回写策略，避免I/O抖动影响网络服务。
#   4. 基础安全: 加入基本的网络安全加固参数。
#   5. 写入逻辑: 直接覆盖本次管理的参数；先应用，再原子保存，失败时恢复运行值及文件。
#
# 参数语义参考（容量倍数是本项目经验基线，不是内核文档推荐最优值）：
# https://www.kernel.org/doc/html/v6.1/networking/ip-sysctl.html
# https://www.kernel.org/doc/html/v6.1/admin-guide/sysctl/net.html
# https://www.kernel.org/doc/html/v6.1/admin-guide/sysctl/vm.html
# ===================================================================================

optimize_kernel_parameters() (
    set -e
    set -o pipefail
    export LC_ALL=C
    if [ "$(uname -s)" != Linux ] || [ "$(id -u)" -ne 0 ]; then
        echo "[错误] 请在Linux服务器上以root运行。"
        return 1
    fi
    is_positive_number() {
        [[ "$1" =~ ^[0-9]{1,6}([.][0-9]{1,3})?$ ]] &&
            awk -v n="$1" 'BEGIN {exit !(n > 0 && n <= 100000)}'
    }

    # 确认操作
    read -r -p "您确定要优化Linux内核网络与内存参数吗？这将修改 '/etc/sysctl.conf'。 (y/n): " choice
    case "$choice" in
        [Yy]*)
            echo "--> 操作确认，开始网络&内存优化..."
            ;;
        *)
            echo "--> 操作已取消。"
            return 0
            ;;
    esac

    # --- 步骤 1: 确认配置文件；输入校验完成后再备份 ---
    if [ -L /etc/sysctl.conf ]; then
        echo "[错误] /etc/sysctl.conf是符号链接，请先确认其管理方式。"
        return 1
    fi

    # --- 步骤 2: 检测系统内存 ---
    echo "--> 正在检测系统内存..."
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    if [[ ! "$mem_kb" =~ ^[0-9]+$ ]] || [ "$mem_kb" -eq 0 ]; then
        echo "[错误] 无法读取系统内存。"
        return 1
    fi
    page_size=$(getconf PAGESIZE)
    if [[ ! "$page_size" =~ ^[0-9]+$ ]] || [ "$page_size" -lt 4096 ]; then
        echo "[错误] 无法读取有效页大小。"
        return 1
    fi
    mem_mb=$((mem_kb / 1024))
    echo "    系统内存: ${mem_mb} MB"

    # --- 步骤 3: 获取用户网络环境信息 ---
    echo "--> 填写客户端可持续吞吐与空闲RTT；客户端下行对应服务器发送。"
    read -r -p "--> 是否需要手动输入网络参数? [y/N]: " manual_input
    if [[ $manual_input =~ ^[Yy]$ ]]; then
        read -r -p "    请输入您的客户端到服务器的空闲网络延迟 (RTT, 单位ms, 例如 170): " rtt
        read -r -p "    请输入客户端下行目标 (单位Mbit/s, 例如 1000): " download_bw
        read -r -p "    请输入客户端上行目标 (单位Mbit/s, 例如 100): " upload_bw
    else
        rtt=170
        download_bw=1000
        upload_bw=100
        echo "--> 使用默认值: RTT=${rtt}ms, 下载=${download_bw}Mbit/s, 上传=${upload_bw}Mbit/s"
    fi

    # 确保输入不为空，提供一个最终的默认值
    : "${rtt:=170}"
    : "${download_bw:=1000}"
    : "${upload_bw:=100}"

    if ! is_positive_number "$rtt" || ! is_positive_number "$download_bw" || ! is_positive_number "$upload_bw"; then
        echo "====== [错误] RTT、带宽须大于0且不超过100000，最多3位小数。 ======"
        return 1
    fi

    if ! awk -v rtt="$rtt" 'BEGIN {exit !(rtt <= 5000)}'; then
        echo "[错误] RTT不能超过5000ms。"
        return 1
    fi

    # --- 步骤 4: 计算客户端链路BDP ---
    download_bdp_bytes=$(awk -v bw="$download_bw" -v rtt="$rtt" 'BEGIN {printf "%.0f", bw * rtt * 125}')
    upload_bdp_bytes=$(awk -v bw="$upload_bw" -v rtt="$rtt" 'BEGIN {printf "%.0f", bw * rtt * 125}')
    echo "--> 下行BDP=${download_bdp_bytes}字节，上行BDP=${upload_bdp_bytes}字节。"

    # --- 步骤 5: 计算收发缓冲上限 ---
    # 代理有客户端、目标站两侧连接，下载同时涉及服务器接收与发送。
    # 这里只输入客户端RTT；目标站一侧BDP更大时需另行评估。
    target_buffer_bytes=$(awk -v down="$download_bw" -v up="$upload_bw" -v rtt="$rtt" '
        BEGIN {bw = down > up ? down : up; printf "%.0f", bw * rtt * 125 * 3}')
    rounding_step=4194304
    target_buffer_bytes=$(((target_buffer_bytes + rounding_step - 1) / rounding_step * rounding_step))
    # Linux socket缓冲存在加倍记账；这是整数表示保护，不是物理内存限额。
    if [ "$target_buffer_bytes" -gt 1073741823 ]; then
        echo "[错误] 三倍BDP超过socket缓冲安全表示范围，请核对带宽与RTT。"
        return 1
    fi
    final_recv_buffer_bytes=$target_buffer_bytes
    final_send_buffer_bytes=$target_buffer_bytes
    [ "$final_recv_buffer_bytes" -ge 33554432 ] || final_recv_buffer_bytes=33554432
    [ "$final_send_buffer_bytes" -ge 16777216 ] || final_send_buffer_bytes=16777216
    echo "--> 接收上限=$((final_recv_buffer_bytes / 1048576))MiB，发送上限=$((final_send_buffer_bytes / 1048576))MiB。"
    echo "    默认接收16MiB、发送2MiB；上限不是预分配，也不等于目标排队长度。"

    # --- 步骤 6: TCP/UDP总额度 ---
    # 延续旧版UDP四倍接收上限的容量思路；不是由BDP推导出的并发最优值。
    # TCP采用八倍较大缓冲上限，至少1GiB；UDP至少256MiB。不按内存比例截断。
    tcp_budget_bytes=$((final_recv_buffer_bytes * 8))
    [ "$tcp_budget_bytes" -ge 1073741824 ] || tcp_budget_bytes=1073741824
    udp_budget_bytes=$((final_recv_buffer_bytes * 4))
    [ "$udp_budget_bytes" -ge 268435456 ] || udp_budget_bytes=268435456
    tcp_mem_max_pages=$((tcp_budget_bytes / page_size))
    tcp_mem_min_pages=$((tcp_mem_max_pages / 2))
    tcp_mem_pressure_pages=$((tcp_mem_max_pages * 3 / 4))
    udp_mem_pages=$((udp_budget_bytes / page_size))
    echo "--> TCP总额度=$((tcp_budget_bytes / 1048576))MiB，UDP接收总额度=$((udp_budget_bytes / 1048576))MiB。"
    echo "    总额度为并发容量起点，需结合高峰占用、丢包和满载延迟验证。"

    # --- 步骤 7: 根据内存大小设置dirty_bytes参数 ---
    echo "--> 正在根据系统内存计算脏页回写参数..."

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
    # 1GB以上沿用64MiB/16MiB脏页阈值，实际效果取决于存储与写入负载
    else
        dirty_bytes=67108864        # 64MB
        dirty_background_bytes=16777216  # 16MB
        echo "    [内存档位] 1024MB以上: 脏页=${dirty_bytes}字节(64MB), 后台=${dirty_background_bytes}字节(16MB) - 字节阈值策略"
    fi

    # --- 步骤 8: 备份、校验并清理完整旧配置块 ---
    work_dir=$(mktemp -d /etc/.network-tuning.XXXXXX)
    backup_file=""
    runtime_backup=""
    applying=0
    installing=0
    committed=0
    cleanup() {
        status=$?
        trap - EXIT HUP INT TERM
        if [ "$applying" -eq 1 ] && [ "$committed" -eq 0 ]; then
            echo "[错误] 应用未完成，正在恢复修改前的运行参数。"
            if ! sysctl -p "$runtime_backup"; then
                echo "[错误] 部分运行值恢复失败，请检查：$runtime_backup"
            fi
            # 也覆盖完成原子替换、尚未标记提交时收到信号的情况。
            if [ "$installing" -eq 1 ]; then
                if [ -n "$backup_file" ]; then
                    if ! { cp -p -- "$backup_file" "$work_dir/restore" &&
                           mv -f -- "$work_dir/restore" /etc/sysctl.conf; }; then
                        echo "[错误] 配置恢复失败，请从 $backup_file 手动恢复。"
                    fi
                elif ! rm -f -- /etc/sysctl.conf; then
                    echo "[错误] 无法删除本次新建的 /etc/sysctl.conf。"
                fi
            fi
        fi
        rm -rf -- "$work_dir"
        exit "$status"
    }
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    config=/etc/sysctl.conf
    if [ -L "$config" ]; then
        echo "[错误] /etc/sysctl.conf 是符号链接，请先确认其配置管理方式。"
        return 1
    fi
    if [ -e "$config" ]; then
        backup_file=$(mktemp /etc/sysctl.conf.bak.XXXXXX)
        cp -p -- "$config" "$backup_file"
        cp -p -- "$config" "$work_dir/original"
    else
        : > "$work_dir/original"
        chmod 644 "$work_dir/original"
    fi

    # 只移除有完整边界的旧脚本块，保留用户在块外的设置及注释。
    if ! awk '
        /^# === 内核参数优化 === *$/ {
            if (inside) exit 2; inside=1; next
        }
        /^# === 参数优化 end === *$/ {
            if (!inside) exit 2; inside=0; next
        }
        !inside {print}
        END {if (inside) exit 2}
    ' "$work_dir/original" > "$work_dir/base"; then
        echo "[错误] 旧配置块标记不完整，未修改配置。"
        return 1
    fi
    if grep -q '^# === 内核参数优化 ===' "$work_dir/original"; then
        echo "[提示] 将替换旧脚本块；本次管理的参数按新策略应用。"
        echo "       未再配置的旧参数不会自动恢复，需安排维护重启并排查其他配置覆盖。"
    fi

    : > "$work_dir/settings"
    runtime_backup=$(mktemp /etc/sysctl.runtime.bak.XXXXXX)
    : > "$runtime_backup"
    # IP转发最先处理；切换它可能重置IPv4接口参数，回滚时一并恢复。
    old_forward=$(sysctl -n net.ipv4.ip_forward)
    printf 'net.ipv4.ip_forward = %s\n' "$old_forward" >> "$runtime_backup"
    if [ "$old_forward" != 1 ]; then
        for path in /proc/sys/net/ipv4/conf/*/*; do
            # 使用斜杠键名，避免把eth0.100等接口名里的点误当作目录。
            key=${path#/proc/sys/}
            old_value=$(cat "$path")
            printf '%s = %s\n' "$key" "$old_value" >> "$runtime_backup"
        done
    fi
    printf '\n# === 内核参数优化 ===\n# 保留IPv4转发，先于接口参数应用。\nnet.ipv4.ip_forward = 1\n' >> "$work_dir/settings"

    add_setting() {
        local key=$1 new_value=$2 comment=$3 old_value old_ratio ratio_key
        if ! old_value=$(sysctl -n "$key" 2>/dev/null); then
            echo "[提示] 内核不支持 $key，跳过。"
            return 0
        fi
        case "$key" in
            vm.dirty_bytes|vm.dirty_background_bytes)
                ratio_key=${key%_bytes}_ratio
                old_ratio=$(sysctl -n "$ratio_key")
                # bytes=0可能被内核拒绝；用ratio写入来恢复比例模式。
                # dirty_ratio为相同值时未必清除bytes，先写另一值确保触发切换。
                printf '%s = 1\n%s = %s\n' "$ratio_key" "$ratio_key" "$old_ratio" >> "$runtime_backup"
                if [ "$old_value" -gt 0 ]; then
                    printf '%s = %s\n' "$key" "$old_value" >> "$runtime_backup"
                fi
                ;;
            *) printf '%s = %s\n' "$key" "$old_value" >> "$runtime_backup" ;;
        esac
        printf '# %s\n%s = %s\n' "$comment" "$key" "$new_value" >> "$work_dir/settings"
    }

    raise_setting() {
        local key=$1 target=$2 comment=$3 current
        if ! current=$(sysctl -n "$key" 2>/dev/null); then
            echo "[提示] 内核不支持 $key，跳过。"
            return 0
        fi
        if [[ ! "$current" =~ ^[0-9]+$ ]]; then
            echo "[错误] 无法解析 $key。"
            return 1
        fi
        [ "$target" -ge "$current" ] || target=$current
        add_setting "$key" "$target" "$comment"
    }

    # 可选功能先检测；不支持的键在生成配置后跳过。
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control)
    if [[ " $available " != *" bbr "* ]] && command -v modprobe >/dev/null 2>&1; then
        modprobe tcp_bbr 2>/dev/null || true
        available=$(sysctl -n net.ipv4.tcp_available_congestion_control)
    fi
    congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control)
    if [[ " $available " == *" bbr "* ]]; then
        congestion_control=bbr
    else
        echo "[提示] BBR不可用，保留当前拥塞控制。"
    fi
    fq_available=0
    if [ -d /sys/module/sch_fq ] || { command -v modprobe >/dev/null 2>&1 && modprobe sch_fq 2>/dev/null; }; then
        fq_available=1
    else
        echo "[提示] 未确认fq可用，不修改default_qdisc。"
    fi
    tw_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse)
    swappiness=5
    if awk 'NR > 1 && $1 ~ /zram/ {found=1} END {exit !found}' /proc/swaps ||
       { [ -r /sys/module/zswap/parameters/enabled ] && grep -Eq '^[Yy1]$' /sys/module/zswap/parameters/enabled; }; then
        swappiness=$(sysctl -n vm.swappiness)
    fi

    # --- 步骤 9: 构建新的配置块 ---
    # 使用heredoc来创建配置块，包含逐行注释，更清晰易读
    cat > "$work_dir/requested" << EOM

# == 由高级网络优化脚本于 $(date) 生成
# == 优化目标: 最大化网络吞吐量 (TCP + UDP)
# == 适用服务: Sing-box, Xray (VLESS/VMess), Hysteria2 (QUIC) 等
# == 网络环境: 下载RTT=${rtt}ms,${download_bw}Mbps / 上传RTT=${rtt}ms,${upload_bw}Mbps
# == 系统内存: ${mem_mb}MB, 接收缓冲区: ${final_recv_buffer_bytes}字节, 发送缓冲区: ${final_send_buffer_bytes}字节
# == 脏页策略: ${dirty_bytes}字节($(awk "BEGIN{printf \"%.0f\", ${dirty_bytes}/1024/1024}")MB)/$(awk "BEGIN{printf \"%.0f\", ${dirty_background_bytes}/1024/1024}")MB - 减少磁盘I/O对网络的干扰
# ===================================================================================

# ---- A. 核心拥塞控制与队列管理 (优化BBR性能) ----
# 设置默认的TCP拥塞控制算法为BBR。
net.ipv4.tcp_congestion_control = ${congestion_control}
# 设置默认的网络包调度算法为FQ。
net.core.default_qdisc = fq
# 启用 TCP 接收缓冲区自动调整，适配不同连接的带宽延迟积。
net.ipv4.tcp_moderate_rcvbuf = 1

# ---- B. 全局套接字缓冲区核心参数 ----
# 收发都覆盖较大方向BDP，兼顾代理两侧连接。
net.core.rmem_max = ${final_recv_buffer_bytes}
net.core.wmem_max = ${final_send_buffer_bytes}
# 默认值：接收16MiB、发送2MiB，应用可主动覆盖
net.core.rmem_default = 16777216
net.core.wmem_default = 2097152

# ---- C. TCP 专用行为调优 ----
# 直接覆盖TCP最小/默认值；最大值按链路容量计算，不迁移旧值。
net.ipv4.tcp_rmem = 16384 1048576 ${final_recv_buffer_bytes}
net.ipv4.tcp_wmem = 8192 131072 ${final_send_buffer_bytes}
# 启用TCP窗口缩放，高带宽必须。
net.ipv4.tcp_window_scaling = 1
# 启用TCP时间戳，用于RTT测量和PAWS。
net.ipv4.tcp_timestamps = 1
# 启用SACK，快速丢包恢复。
net.ipv4.tcp_sack = 1
# 沿用旧版空闲后保留拥塞窗口策略；各拥塞控制算法仍有独立行为。
net.ipv4.tcp_slow_start_after_idle = 0
# 保守MTU探测，稳定性优先。
net.ipv4.tcp_mtu_probing = 1
# 不设全局小阈值限制应用写入；应用可单独设置TCP_NOTSENT_LOWAT。
net.ipv4.tcp_notsent_lowat = 4294967295
# Linux 6.1窗口开销比例采用其基线1，不由上下行是否对称决定。
net.ipv4.tcp_adv_win_scale = 1
# DSACK辅助识别伪重传；RACK与TLP用于丢包及尾丢包恢复。
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_recovery = 1
net.ipv4.tcp_early_retrans = 3
# 突发建连时允许重试，不因监听队列溢出主动复位。
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.tcp_syncookies = 1
# 适中的孤儿连接数
net.ipv4.tcp_max_orphans = 32768
# TCP全部socket的页数阈值：低水位、压力、最大值。
net.ipv4.tcp_mem = ${tcp_mem_min_pages} ${tcp_mem_pressure_pages} ${tcp_mem_max_pages}
# 保留链路短暂中断时的重试容忍时间；不以缩短超时减少重传计数。
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 15
# 启用F-RTO处理伪超时。
net.ipv4.tcp_frto = 2
# ---- D. UDP/QUIC 性能优化 (针对 Hysteria2) ----
# 设置系统所有UDP套接字可以占用的内存大小(单位: page)。
# Linux 6.1接收路径的第一项是关键额度；三项一致，不套用TCP压力比例。
net.ipv4.udp_mem = ${udp_mem_pages} ${udp_mem_pages} ${udp_mem_pages}

# ---- E. 连接管理与系统资源 (并发优化) ----
# 增大系统级监听队列的最大长度。
net.core.somaxconn = 262144
# 接收backlog取16384包作为突发基线，需结合softnet丢包和延迟验证。
net.core.netdev_max_backlog = 16384
# 保留当前安全复用策略，不把复用等同于强制回收。
net.ipv4.tcp_tw_reuse = ${tw_reuse}
# TIME_WAIT容量基线，写入前只提高已有值，避免提前销毁状态。
net.ipv4.tcp_max_tw_buckets = 262144
# 无应用持有的FIN_WAIT_2连接保留60秒，不控制TIME_WAIT。
net.ipv4.tcp_fin_timeout = 60
# 开启TCP Fast Open (TFO)。
net.ipv4.tcp_fastopen = 3
# 增大SYN队列的最大长度。
net.ipv4.tcp_max_syn_backlog = 65536
# 仅对启用SO_KEEPALIVE的连接有效，给短暂链路波动留出余量。
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
# 临时端口范围不改动，避免占用服务或管理工具预留端口。
# 开启IP转发。
# ip_forward已在其他IPv4参数之前应用。

# ---- F. 内存与系统相关 (内存策略) ----
# 磁盘swap沿用5；检测到zram/zswap时保留其现有策略。
vm.swappiness = ${swappiness}
# 允许内核"过度承诺"内存。
vm.overcommit_memory = 1
# 模式1不设置仅模式2有效的overcommit_ratio。
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
# bytes与ratio互斥，不再随后写ratio，以免清除bytes阈值。
# 脏页老化30秒后可参与周期回写，阈值触发的回写不必等30秒。
vm.dirty_expire_centisecs = 3000
# 后台写线程间隔 = 5 秒
vm.dirty_writeback_centisecs = 500

# ---- H. 网络安全加固 ----
# 忽略ICMP广播请求。
net.ipv4.icmp_echo_ignore_broadcasts = 1
# 抑制无效ICMP错误响应产生的告警。
net.ipv4.icmp_ignore_bogus_error_responses = 1
# 固定宽松反向路径过滤，允许来源可达但收发接口不同的非对称路径。
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2

# === 参数优化 end ===
EOM

    # --- 步骤 10: 检查支持情况、备份运行值并生成最终配置 ---
    while IFS= read -r line; do
        case "$line" in
            ''|\#*) printf '%s\n' "$line" >> "$work_dir/settings"; continue ;;
        esac
        key=${line%% = *}
        value=${line#* = }
        if [ "$key" = net.core.default_qdisc ] && [ "$fq_available" -eq 0 ]; then
            continue
        fi
        case "$key" in
            fs.file-max|fs.nr_open|fs.inotify.max_user_watches|net.ipv4.tcp_max_orphans|net.ipv4.tcp_max_tw_buckets)
                raise_setting "$key" "$value" "资源额度仅提高，不压低当前上限。" ;;
            *) add_setting "$key" "$value" "本次脚本配置。" ;;
        esac
    done < "$work_dir/requested"

    # 本次配置末尾原本就会覆盖同名键；将前面的重复项注释留存，明确生效来源。
    # 不清理未管理的参数，也不删除用户原有注释。斜杠/点号形式按sysctl规则归一化。
    awk '
        function config_key(line, pos, key) {
            sub(/#.*/, "", line)
            pos=index(line, "=")
            if (!pos) return ""
            key=substr(line, 1, pos-1)
            gsub(/[[:space:]]/, "", key)
            sub(/^-/, "", key)
            if (index(key, "/") && (!index(key, ".") || index(key, "/") < index(key, "."))) {
                # 先用临时字符保存接口名中的点，再交换两种分隔符。
                gsub(/\./, "\034", key)
                gsub(/\//, ".", key)
                gsub(/\034/, "/", key)
            }
            return key
        }
        FNR == NR {
            key=config_key($0)
            if (key != "") managed[key]=1
            next
        }
        {
            key=config_key($0)
            if (key != "" && key in managed)
                print "# 已由下方内核参数优化块接管，原值保留: " $0
            else
                print
        }
    ' "$work_dir/settings" "$work_dir/base" > "$work_dir/deduplicated"
    cp -p -- "$work_dir/original" "$work_dir/candidate"
    cat "$work_dir/deduplicated" > "$work_dir/candidate"
    cat "$work_dir/settings" >> "$work_dir/candidate"

    # --- 步骤 11: 先应用本次参数，再原子保存 ---
    echo "--> 配置备份：${backup_file:-原文件不存在}"
    echo "--> 运行值备份：$runtime_backup"
    applying=1
    sysctl -p "$work_dir/settings"
    installing=1
    mv -f -- "$work_dir/candidate" "$config"
    committed=1
    echo "====== 内核参数已应用并保存 ======"

)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    optimize_kernel_parameters
fi
