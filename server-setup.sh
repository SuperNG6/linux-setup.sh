#!/bin/bash

# 检查是否具有足够的权限
if [ "$(id -u)" != "0" ]; then
    echo "需要管理员权限，请使用sudo运行此脚本。"
    exit 1
fi


# 获取操作系统信息
get_os_info() {
    # 忽略大小写匹配

    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ $ID == "debian" || $ID == "ubuntu" ]]; then
            echo "Debian/Ubuntu"
        elif [ $ID == "centos" ]; then
            echo "CentOS"
        elif [ $ID == "fedora" ]; then
            echo "Fedora"
        elif [ $ID == "arch" ]; then
            echo "Arch"
        # 添加更多的操作系统判断
        # elif [ $ID == "some-other-os" ]; then
        #     echo "Some Other OS"
        else
            echo "Unknown"
        fi
    elif [ -f /etc/centos-release ]; then
        echo "CentOS"
    elif [ -f /etc/fedora-release ]; then
        echo "Fedora"
    elif [ -f /etc/arch-release ]; then
        echo "Arch"
    else
        echo "Unknown"
    fi
}


# 检查已安装的防火墙类型
check_firewall() {
    if command -v ufw &>/dev/null; then
        echo "ufw"  # 返回 ufw 表示安装了 ufw 防火墙
    elif command -v firewalld &>/dev/null; then
        echo "firewalld"  # 返回 firewalld 表示安装了 firewalld 防火墙
    elif command -v iptables &>/dev/null; then
        echo "iptables"  # 返回 iptables 表示安装了 iptables 防火墙
    elif command -v nft &>/dev/null; then
        echo "nftables"  # 返回 nftables 表示安装了 nftables 防火墙
    else
        echo "unknown"  # 返回 unknown 表示未安装支持的防火墙工具
    fi
}


# 根据已安装的防火墙显示当前开放的端口
display_open_ports() {
    firewall=$(check_firewall)

    case $firewall in
        "ufw")
            echo "当前开放的防火墙端口 (TCP):"
            ufw status | grep "ALLOW" | grep -oP '\d+/tcp' | sort -u
            echo "当前开放的防火墙端口 (UDP):"
            ufw status | grep "ALLOW" | grep -oP '\d+/udp' | sort -u
            ;;
        "firewalld")
            echo "当前开放的防火墙端口 (TCP):"
            firewall-cmd --list-ports | grep "tcp"
            echo "当前开放的防火墙端口 (UDP):"
            firewall-cmd --list-ports | grep "udp"
            ;;
        "iptables")
            echo "当前开放的防火墙端口 (TCP):"
            iptables-legacy -L INPUT -n --line-numbers | grep "tcp" | grep -oP '\d+' | sort -u
            echo "当前开放的防火墙端口 (UDP):"
            iptables-legacy -L INPUT -n --line-numbers | grep "udp" | grep -oP '\d+' | sort -u
            ;;
        "nftables")
            echo "当前开放的防火墙端口 (TCP):"
            nft list ruleset | grep "tcp" | grep -oP '\d+' | sort -u
            echo "当前开放的防火墙端口 (UDP):"
            nft list ruleset | grep "udp" | grep -oP '\d+' | sort -u
            ;;
        *)
            echo "找不到支持的防火墙。"
            return 1
            ;;
    esac
}


# 安装必要组件
install_components() {
    echo "是否需要安装必要组件？(y/n)"
    echo "docker.io docker-compose fail2ban vim curl"
    read choice

    if [ "$choice" != "y" ] && [ "$choice" != "Y" ]; then
        echo "取消安装。"
        return 1
    fi

    echo "正在安装必要组件..."

    # 获取操作系统信息
    os_type=$(get_os_info)
    
    case $os_type in
        Debian/Ubuntu)
            # 更新软件包列表，如果失败则退出
            apt -y update || { echo "更新软件包列表失败"; return 1; }
            # 安装组件，如果失败则退出
            apt -y install docker.io docker-compose fail2ban vim curl || { echo "安装组件失败"; return 1; }
            ;;
        CentOS)
            # 更新软件包列表，如果失败则退出
            yum -y update || { echo "更新软件包列表失败"; return 1; }
            # 安装组件，如果失败则退出
            yum -y install docker docker-compose fail2ban vim curl || { echo "安装组件失败"; return 1; }
            ;;
        Fedora)
            # 更新软件包列表，如果失败则退出
            dnf -y update || { echo "更新软件包列表失败"; return 1; }
            # 安装组件，如果失败则退出
            dnf -y install docker docker-compose fail2ban vim curl || { echo "安装组件失败"; return 1; }
            ;;
        Arch)
            # 更新软件包列表，如果失败则退出
            pacman -Syu --noconfirm || { echo "更新软件包列表失败"; return 1; }
            # 安装组件，如果失败则退出
            pacman -S --noconfirm docker docker-compose fail2ban vim curl || { echo "安装组件失败"; return 1; }
            ;;
        *)
            echo "无法确定操作系统类型，无法安装组件。"
            return 1
            ;;
    esac

    echo "关键组件安装成功。"
}


# 添加要登记设备的公钥
add_public_key() {
    echo "请输入公钥："
    read public_key

    # 检查公钥是否为空
    if [ -z "$public_key" ]; then
        echo "无效的公钥。"
        return 1
    fi

    # 检查公钥格式
    if [[ ! "$public_key" =~ ^ssh-rsa[[:space:]]+[A-Za-z0-9+/]+[=]{0,3}(\s*.+)? ]]; then
        echo "无效的公钥格式。"
        return 1
    fi

    # 备份原始authorized_keys文件
    cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak

    # 追加公钥到authorized_keys文件
    echo "$public_key" >> ~/.ssh/authorized_keys

    # 检查是否成功追加公钥
    if [ $? -eq 0 ]; then
        echo "公钥添加成功。"
    else
        echo "公钥添加失败。"
        # 恢复备份的authorized_keys文件
        mv ~/.ssh/authorized_keys.bak ~/.ssh/authorized_keys
        return 1
    fi
}


# 关闭SSH密码登录
disable_ssh_password_login() {
    echo "正在关闭SSH密码登录..."

    # 备份原始sshd_config文件
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # 检查是否存在sshd_config文件
    if [ -f /etc/ssh/sshd_config ]; then
        chmod 600 ~/.ssh/authorized_keys
        sed -i 's/#\?PasswordAuthentication\s\+yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
        systemctl restart sshd
        if [ $? -eq 0 ]; then
            echo "SSH密码登录已关闭。"
        else
            echo "SSH密码登录关闭失败。"
            # 恢复备份的sshd_config文件
            mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
            return 1
        fi
    else
        echo "sshd_config 文件不存在"
        return 1
    fi
}


# 添加docker工具脚本
add_docker_tools() {
    echo "你是否希望安装docker工具箱？（包括常用的docker命令和自定义脚本）"
    echo "-----------------------------------"
    echo "docker工具箱，添加便捷指令."
    echo "功能1、nginx命令=docker nginx"
    echo "功能2、dlogs命令=查看docker容器日志"
    echo "功能3、dc命令=docker-compose"
    echo "功能4、dcs命令=查看docker-compose容器状态（需要在compose.yml文件夹内执行）"
    echo "功能5、dcps命令=查看docker-compose容器（需要在compose.yml文件夹内执行）"
    echo "功能6、dcip命令=查看容器ip，并添加到宿主机hosts中"
<<<<<<< HEAD
    echo "工具脚本保存在"/root/.docker_tools"文件夹中，请勿删除"
=======
    echo "工具脚本保存在""/root/.docker_tools"文件夹中，请勿删除
>>>>>>> 7e676e4e54ca948781414716c67d3dc8eda6bf58
    echo "-----------------------------------"

    read -p "是否安装，请输入 y 或 n：" install_choice

    case $install_choice in
        y|Y)
            # 检查是否已经存在.bashrc文件
            if [ -e "/root/.bashrc" ]; then
                # 备份原始.bashrc文件
                cp /root/.bashrc /root/.bashrc.bak
            fi

            # 创建存放工具脚本的文件夹
            tools_folder="/root/.docker_tools"
            mkdir -p "$tools_folder"

            # 下载dlogs.sh脚本
            wget -qO "$tools_folder/dlogs.sh" "https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/dlogs.sh"
            if [ $? -eq 0 ]; then
                chmod +x "$tools_folder/dlogs.sh"
                echo "dlogs.sh脚本已下载并添加到 $tools_folder 文件夹。"
            else
                echo "下载dlogs.sh脚本失败。"
            fi

            # 下载dcip.sh脚本
            wget -qO "$tools_folder/dcip.sh" "https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/dcip.sh"
            if [ $? -eq 0 ]; then
                chmod +x "$tools_folder/dcip.sh"
                echo "dcip.sh脚本已下载并添加到 $tools_folder 文件夹。"
            else
                echo "下载dcip.sh脚本失败。"
            fi

            # 检查是否已经存在别名，避免重复添加
            if grep -q "alias nginx=" /root/.bashrc; then
                echo "别名已存在，无需重复添加。"
            else
                # 追加alias到.bashrc文件
                echo 'alias nginx="docker exec -i docker_nginx nginx"' >> /root/.bashrc
                echo 'alias dc="docker-compose"' >> /root/.bashrc
                echo 'alias dcs="docker-compose ps -q | xargs docker stats"' >> /root/.bashrc
                echo 'alias dcps="docker ps $((docker-compose ps -q  || echo "#") | while read line; do echo "--filter id=$line"; done)"' >> /root/.bashrc
                echo 'alias dcip="bash /root/.docker_tools/dcip.sh"' >> /root/.bashrc
                echo 'alias dlogs="bash /root/.docker_tools/dlogs.sh"' >> /root/.bashrc
            fi
            echo "docker工具箱已成功安装。"
            ;;
        n|N)
            echo "取消安装docker工具箱。"
            ;;
        *)
            echo "无效的选项，取消安装docker工具箱。"
            ;;
    esac
}


# 删除所有 swap 文件和分区
remove_all_swap() {
    # 获取所有 swap 文件的列表
    swap_files=$(swapon -s | awk '{if($1!~"^Filename"){print $1}}')

    # 获取所有 swap 分区的列表
    swap_partitions=$(grep -E '^\S+\s+\S+\sswap\s+' /proc/swaps | awk '{print $1}')

    # 遍历并禁用、删除每个 swap 文件和分区
    for item in $swap_files $swap_partitions; do
        echo "正在禁用并删除 swap ：$item"
        swapoff "$item"
        rm -f "$item"
        echo "已删除 swap ：$item"
    done

    echo "所有 swap 文件和分区已删除。"
}


# 清理 swap 缓存
cleanup_swap() {
    echo "正在检查当前交换空间..."
    echo "=========================================="
    # 获取所有交换空间文件的列表
    swap_files=$(swapon -s | awk '{if($1!~"^Filename"){print $1}}')

    # 获取所有交换分区的列表
    swap_partitions=$(grep -E '^\S+\s+\S+\sswap\s+' /proc/swaps | awk '{print $1}')

    # 获取物理内存和已使用的物理内存
    total_memory=$(free -m | awk 'NR==2{print $2}')
    used_memory=$(free -m | awk 'NR==2{print $3}')

    # 获取已使用的交换空间
    used_swap=$(free -m | awk 'NR==3{print $3}')

    # 计算已使用的物理内存和虚拟内存占物理内存的百分比
    used_memory_percent=$(( (used_memory) * 100 / total_memory ))
    total_used_percent=$(( (used_memory + used_swap) * 100 / total_memory ))

    if [ -n "$swap_files" ]; then
        echo "当前交换空间大小如下："
        swapon --show
        echo "=========================================="
        echo "物理内存使用率：$used_memory_percent% ( $used_memory MB/ $total_memory MB )"
        echo "已使用的物理内存和虚拟内存占物理内存的百分比: $total_used_percent% ( $((used_memory + used_swap)) MB / $total_memory MB )"

        # 检测是否可以清理 swap 缓存
        if [ $total_used_percent -gt 80 ]; then
            echo "不建议清理 swap 缓存，因为物理内存使用量和 swap 使用量总和已经超过物理内存的80%。"
            echo "如果清理 swap 缓存，可能导致系统内存不足，影响性能和稳定性。"
        else
            echo "是否要清理 swap 缓存"
            read -p "请输入 y 或 n：" cleanup_choice

            case $cleanup_choice in
                y|Y)
                    # 遍历并清理每个交换空间文件和分区
                    for item in $swap_files $swap_partitions; do
                        echo "正在清理 swap 缓存：$item"
                        swapoff "$item"
                        echo "已清理 swap 缓存：$item"
                        swapon "$item"
                    done

                    echo "所有的 swap 缓存已清理。"
                    ;;
                n|N)
                    echo "不需要清理 swap 缓存"
                    ;;
                *)
                    echo "无效的选项，保留已存在的交换空间。"
                    ;;
            esac
        fi
    fi
}



# 设置虚拟内存
set_virtual_memory() {
    echo "正在检查当前 swap ..."
    swap_files=$(swapon -s | awk '{if($1!~"^Filename"){print $1}}')

    if [ -n "$swap_files" ]; then
        echo "当前 swap 大小如下："
        swapon --show
        echo "是否要删除已存在的 swap ？"
        read -p "请输入 y 或 n：" remove_choice

        case $remove_choice in
            y|Y)
                # 调用函数以删除所有 swap 文件和分区
                remove_all_swap
                ;;
            n|N)
                echo "保留已存在的 swap 。"
                ;;
            *)
                echo "无效的选项，保留已存在的 swap 。"
                ;;
        esac
    fi

    echo "请选择虚拟内存的大小或手动输入值："
    echo "1. 256M"
    echo "2. 512M"
    echo "3. 1GB"
    echo "4. 2GB"
    echo "5. 4GB"
    echo "6. 手动输入值"
    
    read -p "请输入选项数字（按q退出）：" choice

    case $choice in
        1)
            swap_size="256M"
            ;;
        2)
            swap_size="512M"
            ;;
        3)
            swap_size="1G"
            ;;
        4)
            swap_size="2G"
            ;;
        5)
            swap_size="4G"
            ;;
        6)
            read -p "请输入虚拟内存大小（例如：256M、1G、2G等）：" swap_size_input
            swap_size="$swap_size_input"
            ;;
        q|Q)
            echo "返回主菜单..."
            return 1
            ;;
        *)
            echo "无效的选项。"
            return 1
            ;;
    esac

    echo "正在设置虚拟内存..."

    # 检查是否已经存在交换文件
    if [ -n "$swap_files" ]; then
        echo "已经存在交换文件。删除现有的交换文件..."
        # 调用函数以删除所有 swap 文件和分区
        remove_all_swap
    fi

    # 将单位转换为KB
    case $swap_size in
        *M)
            swap_size_kb=$(( ${swap_size//[^0-9]/} * 1024 ))  # Convert MB to KB
            ;;
        *G)
            swap_size_kb=$(( ${swap_size//[^0-9]/} * 1024 * 1024 ))  # Convert GB to KB
            ;;
        *)
            echo "无效的虚拟内存大小单位。"
            return 1
            ;;
    esac

    # 使用dd创建交换文件
    dd if=/dev/zero of=/swap bs=1k count=$swap_size_kb

    if [ $? -eq 0 ]; then
        chmod 600 /swap
        mkswap /swap
        swapon /swap

        if [ $? -eq 0 ]; then
            echo "/swap swap swap defaults 0 0" >> /etc/fstab
            echo "虚拟内存设置成功。"
            echo "当前 swap 大小如下："
            swapon -s | grep '/swap'
        else
            echo "交换文件创建成功，但启用交换失败，请检查命令是否执行成功。"
            return 1
        fi
    else
        echo "创建交换文件失败，请检查命令是否执行成功。"
        return 1
    fi
}


# 修改swap使用阈值
modify_swap_usage_threshold() {

    echo "当前系统的vm.swappiness值：$(cat /proc/sys/vm/swappiness)"

    echo "正在修改swap使用阈值..."

    read -p "请输入要设置的vm.swappiness值（0-100之间）：" swap_value

    # 检查输入是否为数字且在0-100范围内
    if ! [[ "$swap_value" =~ ^[0-9]+$ ]] || [ "$swap_value" -lt 0 ] || [ "$swap_value" -gt 100 ]; then
        echo "无效的输入，请输入0-100之间的数字。"
        return 1
    fi

    # 备份原始配置文件
    cp /etc/sysctl.conf /etc/sysctl.conf.bak

    # 检查是否存在vm.swappiness设置
    if grep -q "^vm.swappiness" /etc/sysctl.conf; then
        # 更新现有的vm.swappiness值
        sed -i "s/^vm.swappiness=.*/vm.swappiness=$swap_value/" /etc/sysctl.conf
    else
        # 追加vm.swappiness值到/etc/sysctl.conf
        echo "vm.swappiness=$swap_value" >> /etc/sysctl.conf
    fi

    # 重新加载系统设置
    sysctl -p

    # 检查修改是否成功
    if grep -q "^vm.swappiness=$swap_value" /etc/sysctl.conf; then
        echo "swap使用阈值修改成功。"
        echo "vm.swappiness值已设置为 $swap_value"
    else
        echo "swap使用阈值修改失败，请检查配置文件。"
        # 恢复备份文件
        mv /etc/sysctl.conf.bak /etc/sysctl.conf
        return 1
    fi
}


# 优化内核参数
optimize_kernel_parameters() {
  # 询问用户是否继续
  read -p "您确定要优化内核参数吗？(y/n): " choice

  case $choice in
    y | Y)
        echo "正在备份原始内核参数..."
        cp /etc/sysctl.conf /etc/sysctl.conf.bak

        echo "正在优化内核参数..."

        # 定义需要设置的参数
        parameters=(
            "net.ipv4.tcp_slow_start_after_idle=0"
            "net.ipv4.tcp_notsent_lowat=16384"
            "net.core.default_qdisc=fq"
            "net.ipv4.tcp_congestion_control=bbr"
            "net.ipv4.tcp_no_metrics_save=1"
            "net.ipv4.tcp_ecn=0"
            "net.ipv4.tcp_frto=0"
            "net.ipv4.tcp_mtu_probing=0"
            "net.ipv4.tcp_rfc1337=0"
            "net.ipv4.tcp_sack=1"
            "net.ipv4.tcp_fack=1"
            "net.ipv4.tcp_window_scaling=1"
            "net.ipv4.tcp_adv_win_scale=1"
            "net.ipv4.tcp_moderate_rcvbuf=1"
            "net.core.rmem_max=33554432"
            "net.core.wmem_max=33554432"
            "net.ipv4.tcp_rmem='4096 87380 33554432'"
            "net.ipv4.tcp_wmem='4096 16384 33554432'"
            "net.ipv4.udp_rmem_min=8192"
            "net.ipv4.udp_wmem_min=8192"
        )

        # 注释掉 net.ipv4.tcp_fastopen=3
        sed -i 's/^net.ipv4.tcp_fastopen=3/#net.ipv4.tcp_fastopen=3/' /etc/sysctl.conf

        # 设置或更新参数
        for param in "${parameters[@]}"; do
            key="${param%=*}"
            value="${param#*=}"
            if grep -q "^$key" /etc/sysctl.conf; then
                sed -i "s/^$key=.*/$param/" /etc/sysctl.conf
            else
                echo "$param" >> /etc/sysctl.conf
            fi
        done

        # 重新加载系统设置
        sysctl -p

        echo "内核参数优化完成。"
        ;;
    n | N)
        echo "取消内核参数优化。"
        ;;
    *)
        echo "无效的选项。"
        return 1
        ;;
  esac
}


# 安装XanMod内核
install_xanmod_kernel() {
    echo "当前内核版本：$(uname -r)"

    # 检查 CPU 支持的指令集级别
    cpu_support_info=$(/usr/bin/awk -f <(wget -qO - https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/check_x86-64_psabi.sh))
    if [[ $cpu_support_info == "CPU supports x86-64-v"* ]]; then
        cpu_support_level=${cpu_support_info#CPU supports x86-64-v}
        echo "你的CPU支持XanMod内核，级别为 x86-64-v$cpu_support_level"
    else
        echo "你的CPU不受XanMod内核支持，无法安装。"
        return 1
    fi

    read -p "是否继续下载并安装XanMod内核？ (y/n): " continue_choice

    case $continue_choice in
        y|Y)
            echo "正在从GitHub下载XanMod内核..."
            echo "XanMod内核官网 https://xanmod.org"
            echo "内核来自 https://sourceforge.net/projects/xanmod/files/releases/lts/"

            # 创建临时文件夹
            temp_folder=$(mktemp -d)
            cd $temp_folder

            # 根据CPU支持级别选择下载的内核
            case $cpu_support_level in
                2)
                    headers_file="linux-headers-6.1.46-x64v2-xanmod1_6.1.46-x64v2-xanmod1-0.20230816.g11dcd23_amd64.deb"
                    image_file="linux-image-6.1.46-x64v2-xanmod1_6.1.46-x64v2-xanmod1-0.20230816.g11dcd23_amd64.deb"
                    headers_md5="45c85d1bcb07bf171006a3e34b804db0"
                    image_md5="63c359cef963a2e9f1b7181829521fc3"
                    ;;
                3)
                    headers_file="linux-headers-6.1.46-x64v3-xanmod1_6.1.46-x64v3-xanmod1-0.20230816.g11dcd23_amd64.deb"
                    image_file="linux-image-6.1.46-x64v3-xanmod1_6.1.46-x64v3-xanmod1-0.20230816.g11dcd23_amd64.deb"
                    headers_md5="6ae3e253a8aeabd80458df4cb4da70cf"
                    image_md5="d6ea43a2a6686b86e0ac23f800eb95a4"
                    ;;
                4)
                    headers_file="linux-headers-6.1.46-x64v4-xanmod1_6.1.46-x64v4-xanmod1-0.20230816.g11dcd23_amd64.deb"
                    image_file="linux-image-6.1.46-x64v4-xanmod1_6.1.46-x64v4-xanmod1-0.20230816.g11dcd23_amd64.deb"
                    headers_md5="9c41a4090a8068333b7dd56b87dd01df"
                    image_md5="7d30eef4b9094522fc067dc19f7cc92e"
                    ;;
                *)
                    echo "你的CPU不受XanMod内核支持，无法安装。"
                    return 1
                    ;;
            esac

            # 下载内核文件
            wget "https://github.com/SuperNG6/linux-setup.sh/releases/download/0816/$headers_file"
            wget "https://github.com/SuperNG6/linux-setup.sh/releases/download/0816/$image_file"

            # 校验 MD5 值
            if [ "$(md5sum $headers_file | awk '{print $1}')" != "$headers_md5" ]; then
                echo "下载的 $headers_file MD5 值不匹配，可能文件已被篡改。"
                return 1
            fi

            if [ "$(md5sum $image_file | awk '{print $1}')" != "$image_md5" ]; then
                echo "下载的 $image_file MD5 值不匹配，可能文件已被篡改。"
                return 1
            fi

            # 安装内核
            dpkg -i linux-image-*xanmod*.deb linux-headers-*xanmod*.deb

            # 检查安装是否成功
            if [ $? -eq 0 ]; then
                echo "XanMod内核安装成功。"
                read -p "是否需要更新grub引导配置？ (y/n): " update_grub_choice

                case $update_grub_choice in
                    y|Y)
                        update-grub
                        echo "Grub引导配置已更新，重启后生效。"
                        echo "若需要开启BBRv3，请重启后执行脚本-内核优化选项"
                        ;;
                    n|N)
                        echo "跳过Grub引导配置更新。"
                        ;;
                    *)
                        echo "无效的选项，跳过Grub引导配置更新。"
                        ;;
                esac
            else
                echo "XanMod内核安装失败。"
            fi

            # 清理下载的deb文件
            rm -f linux-image-*xanmod*.deb linux-headers-*xanmod*.deb
            ;;
        n|N)
            echo "取消下载和安装XanMod内核。"
            ;;
        *)
            echo "无效的选项，取消下载和安装XanMod内核。"
            ;;
    esac
}


# 卸载XanMod内核并恢复原有内核，并更新Grub引导配置
uninstall_xanmod_kernel() {
    echo "正在检查当前内核...$(uname -r)"

    # 获取当前内核的版本号
    current_kernel_version=$(uname -r)

    # 检查是否为XanMod内核
    if [[ $current_kernel_version == *-xanmod* ]]; then
        echo "当前内核为 XanMod 内核：$current_kernel_version"
        
        # 显示卸载提示
        read -p "确定要卸载XanMod内核并恢复原有内核吗？(y/n): " confirm
        if [[ $confirm == [yY] ]]; then
            echo "正在卸载XanMod内核并恢复原有内核..."

            # 卸载XanMod内核
            apt-get purge linux-image-*xanmod* linux-headers-*xanmod* -y
            apt-get autoremove -y

            # 更新Grub引导配置
            update-grub

            echo "XanMod内核已卸载并恢复原有内核。Grub引导配置已更新，重启后生效。"
        else
            echo "取消卸载操作。"
        fi
    else
        echo "当前内核不是XanMod内核，无法执行卸载操作。"
    fi
}

# 安装 Debian Cloud 内核
install_debian_cloud_kernel() {
    echo "INFO" "开始安装 Debian Cloud 内核"
    echo "正在更新软件包列表..."
    apt update -y

    echo "当前系统内核版本："
    dpkg -l | grep linux-image

    echo "查找最新的 Cloud 内核版本..."
    latest_cloud_kernel=$(apt-cache search linux-image | grep -E 'linux-image-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-cloud-amd64 ' | grep -v unsigned | sort -V | tail -n 1 | awk '{print $1}')
    latest_cloud_headers=${latest_cloud_kernel/image/headers}

    if [ -z "$latest_cloud_kernel" ]; then
        log "ERROR" "未找到可用的 Cloud 内核版本"
        echo "未找到可用的 Cloud 内核版本。"
        return 1
    fi

    echo "找到最新的 Cloud 内核版本：$latest_cloud_kernel"
    read -p "是否安装此版本？(y/n): " install_choice

    if [[ $install_choice == [yY] ]]; then
        echo "正在安装 Cloud 内核..."
        apt install $latest_cloud_headers $latest_cloud_kernel -y
        if [ $? -eq 0 ]; then
            echo "更新 GRUB..."
            update-grub
            log "INFO" "Debian  Cloud 内核安装成功"
            echo "Debian  Cloud 内核安装成功。请重启系统以使用新内核。"
        else
            log "ERROR" "Debian  Cloud 内核安装失败"
            echo "Debian  Cloud 内核安装失败。"
        fi
    else
        echo "取消安装 Cloud 内核。"
    fi
}

# 卸载 Debian Cloud 内核
uninstall_debian_cloud_kernel() {
    echo "INFO" "开始卸载 Debian Cloud 内核"
    echo "当前系统内核版本："
    dpkg -l | grep linux-image

    cloud_kernels=$(dpkg -l | grep -E 'linux-image-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-cloud-amd64' | awk '{print $2}')
    cloud_headers=$(echo "$cloud_kernels" | sed 's/image/headers/g')

    if [ -z "$cloud_kernels" ]; then
        echo "未检测到已安装的 Cloud 内核。"
        return
    fi

    echo "检测到以下 Cloud 内核："
    echo "$cloud_kernels"
    echo "对应的 headers："
    echo "$cloud_headers"
    read -p "是否卸载这些 Cloud 内核并恢复原有内核？(y/n): " uninstall_choice

    if [[ $uninstall_choice == [yY] ]]; then
        echo "正在卸载 Cloud 内核..."
        apt remove $cloud_kernels $cloud_headers -y
        apt autoremove -y
        if [ $? -eq 0 ]; then
            echo "更新 GRUB..."
            update-grub
            log "INFO" "Debian Cloud 内核卸载成功"
            echo "Debian Cloud 内核卸载成功。请重启系统以使用原有内核。"
        else
            log "ERROR" "Debian Cloud 内核卸载失败"
            echo "Debian Cloud 内核卸载失败。"
        fi
    else
        echo "取消卸载 Cloud 内核。"
    fi
}

# 修改SSH端口号
modify_ssh_port() {
    current_port=$(grep -oP '^Port \K\d+' /etc/ssh/sshd_config)

    if [ -z "$current_port" ]; then
        echo "当前SSH端口号未设置（被注释），请输入要设置的新SSH端口号："
    else
        echo "当前SSH端口号：$current_port，请输入新的SSH端口号："
    fi

    read -p "新SSH端口号：" new_port

    if ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
        echo "无效的输入，请输入有效的端口号。"
        return 1 # 返回非零退出状态码表示错误
    fi

    if [ -z "$current_port" ]; then
        # 添加新的端口号配置
        sed -i "/^#Port/a Port $new_port" /etc/ssh/sshd_config
    else
        # 更新现有的端口号配置
        sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config
    fi
    chmod 644 /etc/ssh/sshd_config
    systemctl restart sshd

    echo "SSH端口号已修改为：$new_port"

    # 开放新端口号根据不同的防火墙
    firewall=$(check_firewall)
    case $firewall in
        "ufw")
            ufw allow $new_port/tcp
            echo "开放防火墙SSH端口 $new_port"
            ;;
        "firewalld")
            firewall-cmd --add-port=$new_port/tcp --permanent
            firewall-cmd --reload
            echo "开放防火墙SSH端口 $new_port"
            ;;
        "iptables")
            iptables -A INPUT -p tcp --dport $new_port -j ACCEPT
            service iptables save
            service iptables restart
            echo "开放防火墙SSH端口 $new_port"
            ;;
        "nftables")
            nft add rule ip filter input tcp dport $new_port accept
            echo "开放防火墙SSH端口 $new_port"
            ;;
        *)
            echo "不支持的防火墙或找不到防火墙。"
            ;;
    esac
}


# 设置防火墙端口
set_firewall_ports() {
    firewall=$(check_firewall)

    case $firewall in
        "ufw")
            firewall_cmd="ufw"
            ;;
        "firewalld")
            firewall_cmd="firewall-cmd"
            ;;
        "iptables")
            firewall_cmd="iptables-legacy"
            ;;
        "nftables")
            firewall_cmd="nft"
            ;;
        *)
            echo "找不到支持的防火墙。"
            return 1
            ;;
    esac

    echo "当前系统安装的防火墙为：$(check_firewall)"
    echo "=========================================="
    display_open_ports
    echo -e "============================================="
    echo "请选择要执行的操作:"
    echo -e "============================================="
    echo "1. 开放防火墙端口"
    echo "2. 关闭防火墙端口"
    echo "q. 返回主菜单"
    read -p "请输入操作选项 (1/2): " action

    case $action in
        1)
            echo -e "============================================="
            echo -e "','逗号为分隔符，支持一次输入多个tcp，udp端口"
            echo -e "============================================="
            read -p "请输入要开放的新防火墙端口，如80t,443t,53u（t代表TCP，u代表UDP）：" new_ports_input
            
            # 设置 IFS（内部字段分隔符）为逗号，将输入字符串按逗号分割成数组
            IFS=',' read -ra new_ports <<< "$new_ports_input"

            for port_input in "${new_ports[@]}"; do
                if [[ ! "$port_input" =~ ^[0-9]+[tu]$ ]]; then
                    echo "无效的输入，请按照格式输入端口号和协议缩写（例如：80t 或 443u）。"
                    return 1
                fi

                port="${port_input%[tu]}"
                case "${port_input: -1}" in
                    t)
                        protocol="tcp"
                        ;;
                    u)
                        protocol="udp"
                        ;;
                    *)
                        echo "无效的协议缩写。"
                        return 1
                        ;;
                esac

                $firewall_cmd allow $port/$protocol
                echo "开放 $protocol 端口 $port 成功。"
            done
            ;;
        2)
            echo -e "============================================="
            echo -e "','逗号为分隔符，支持一次输入多个tcp，udp端口"
            echo -e "============================================="
            read -p "请输入要关闭的防火墙端口，如80t,53u（t代表TCP，u代表UDP）：" ports_to_close_input

            # 设置 IFS（内部字段分隔符）为逗号，将输入字符串按逗号分割成数组
            IFS=',' read -ra ports_to_close <<< "$ports_to_close_input"

            for port_input in "${ports_to_close[@]}"; do
                if [[ ! "$port_input" =~ ^[0-9]+[tu]$ ]]; then
                    echo "无效的输入，请按照格式输入端口号和协议缩写（例如：80t 或 443u）。"
                    return 1
                fi

                port="${port_input%[tu]}"
                case "${port_input: -1}" in
                    t)
                        protocol="tcp"
                        ;;
                    u)
                        protocol="udp"
                        ;;
                    *)
                        echo "无效的协议缩写。"
                        return 1
                        ;;
                esac

                $firewall_cmd deny $port/$protocol
                echo "关闭 $protocol 端口 $port 成功。"
            done
            ;;
        q|Q)
            return 1
            ;;
        *)
            echo "无效的操作选项。"
            return 1
            ;;
    esac
}

# 检查系统是否支持ZRAM
check_zram_support() {
    if [ -d "/sys/class/zram-control" ]; then
        return 0  # 支持ZRAM
    else
        return 1  # 不支持ZRAM
    fi
}

# 检查ZRAM是否已安装
is_zram_installed() {
    if lsmod | grep -q zram && command -v zramctl > /dev/null; then
        return 0  # ZRAM已安装
    else
        return 1  # ZRAM未安装
    fi
}

# 安装ZRAM
install_zram() {
    os_type=$(get_os_info)
    case $os_type in
        Debian/Ubuntu)
            apt update && apt install -y zram-tools
            ;;
        CentOS|Fedora)
            dnf install -y zram-generator
            ;;
        Arch)
            pacman -Sy --noconfirm zram-generator
            ;;
        *)
            echo "不支持的操作系统: $os_type"
            return 1
            ;;
    esac
}

# 显示当前ZRAM配置和使用情况
display_zram_status() {
    if is_zram_installed; then
        echo "当前 ZRAM 配置:"
        zramctl
        
        os_type=$(get_os_info)
        case $os_type in
            Debian/Ubuntu)
                echo "当前配置参数:"
                grep -E "PERCENT|ALGO|DEVICES" /etc/default/zramswap
                ;;
            CentOS|Fedora|Arch)
                echo "当前配置参数:"
                cat /etc/systemd/zram-generator.conf
                ;;
        esac
    else
        echo "ZRAM 未安装或未配置。"
    fi
}

# 配置ZRAM
configure_zram() {
    if ! is_zram_installed; then
        echo "正在安装ZRAM..."
        install_zram
        if [ $? -ne 0 ]; then
            echo "ZRAM安装失败。"
            return 1
        fi
    fi

    # 获取当前设置
    os_type=$(get_os_info)
    case $os_type in
        Debian/Ubuntu)
            current_percent=$(grep -oP 'PERCENT=\K\d+' /etc/default/zramswap)
            current_algo=$(grep -oP 'ALGO=\K\w+' /etc/default/zramswap)
            ;;
        CentOS|Fedora|Arch)
            current_percent=$(grep -oP 'zram-size = \K\d+' /etc/systemd/zram-generator.conf | awk '{print $1*100/1048576}')
            current_algo=$(grep -oP 'compression-algorithm = \K\w+' /etc/systemd/zram-generator.conf)
            ;;
    esac

    # 默认设置
    default_percent=${current_percent:-50}
    default_algo=${current_algo:-"zstd"}
    cpu_cores=$(nproc)

    # 询问用户ZRAM大小百分比
    read -p "请输入ZRAM大小占物理内存的百分比 (1-100) [当前/默认: $default_percent]: " zram_percent
    zram_percent=${zram_percent:-$default_percent}

    if ! [[ "$zram_percent" =~ ^[0-9]+$ ]] || [ "$zram_percent" -lt 1 ] || [ "$zram_percent" -gt 100 ]; then
        echo "无效的输入，使用当前/默认值 $default_percent。"
        zram_percent=$default_percent
    fi

    # 询问用户压缩算法
    echo "请选择压缩算法 [当前/默认: $default_algo]："
    echo "1. lzo"
    echo "2. lz4"
    echo "3. zstd (推荐)"
    read -p "请输入选项数字: " algo_choice

    case $algo_choice in
        1) comp_algo="lzo" ;;
        2) comp_algo="lz4" ;;
        3) comp_algo="zstd" ;;
        *) echo "无效的选择，使用当前/默认算法 $default_algo"; comp_algo=$default_algo ;;
    esac

    # 配置ZRAM
    case $os_type in
        Debian/Ubuntu)
            echo "PERCENT=$zram_percent" > /etc/default/zramswap
            echo "ALGO=$comp_algo" >> /etc/default/zramswap
            echo "DEVICES=$cpu_cores" >> /etc/default/zramswap
            systemctl restart zramswap
            ;;
        CentOS|Fedora|Arch)
            zram_size=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') * $zram_percent / 100))
            cat << EOF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ${zram_size}K
compression-algorithm = $comp_algo
EOF
            systemctl restart systemd-zram-setup@zram0.service
            ;;
    esac

    echo "ZRAM配置已更新。"
    echo "大小: ${zram_percent}% 的物理内存"
    echo "压缩算法: $comp_algo"
    echo "ZRAM设备数: $cpu_cores"
}

# 卸载ZRAM
uninstall_zram() {
    if is_zram_installed; then
        echo "正在卸载ZRAM..."
        os_type=$(get_os_info)
        case $os_type in
            Debian/Ubuntu)
                systemctl stop zramswap
                systemctl disable zramswap
                apt remove -y zram-tools
                ;;
            CentOS|Fedora)
                systemctl stop systemd-zram-setup@zram0.service
                systemctl disable systemd-zram-setup@zram0.service
                dnf remove -y zram-generator
                ;;
            Arch)
                systemctl stop systemd-zram-setup@zram0.service
                systemctl disable systemd-zram-setup@zram0.service
                pacman -R --noconfirm zram-generator
                ;;
            *)
                echo "不支持的操作系统: $os_type"
                return 1
                ;;
        esac
        
        # 移除配置文件
        rm -f /etc/default/zramswap /etc/systemd/zram-generator.conf
        
        echo "ZRAM已卸载。"
    else
        echo "ZRAM未安装，无需卸载。"
    fi
}

# ZRAM配置菜单
configure_zram_menu() {
    if ! check_zram_support; then
        echo "您的系统不支持ZRAM。"
        return 1
    fi

    while true; do
        clear
        echo "ZRAM配置菜单"
        echo "----------------"

        if is_zram_installed; then
            display_zram_status
            echo
            echo "1. 修改ZRAM参数"
        else
            echo "1. 安装并配置ZRAM"
        fi
        echo "2. 卸载ZRAM"
        echo "3. 返回主菜单"
        
        read -p "请选择操作: " choice

        case $choice in
            1)
                configure_zram
                ;;
            2)
                uninstall_zram
                ;;
            3)
                return 0
                ;;
            *)
                echo "无效的选择，请重新输入。"
                ;;
        esac

        echo "按Enter键继续..."
        read
    done
}


# 显示操作菜单选项
display_menu() {
    # 获取当前Linux发行版本（包括版本号）
    linux_version=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
    # 获取当前内核版本
    kernel_version=$(uname -r)
    # 获取当前内存使用率（以百分比形式）
    memory_usage=$(free | awk '/Mem/{printf("%.2f", $3/$2 * 100)}')


    # 设置颜色和样式
    GREEN='\033[0;32m'
    BOLD='\033[1m'
    RESET='\033[0m'

    clear
    echo -e "${BOLD}欢迎使用 SuperNG6 的 Linux 配置工具${RESET}"
    echo -e "${BOLD}GitHub：https://github.com/SuperNG6/linux-setup.sh${RESET}"
    # 在一行上显示当前CPU使用率、内存使用率、Linux发行版本和内核版本，并使用预定义的颜色和样式
    echo -e "${BOLD}-----------------------------------"
    echo -e "当前Linux发行版本：${GREEN}${BOLD}${linux_version}${RESET}"
    echo -e "当前内核版本：${GREEN}${BOLD}${kernel_version}${RESET}"
    echo -e "当前内存使用率：${GREEN}${BOLD}${memory_usage}%${RESET}"
    # 菜单选项
    echo -e "${BOLD}-----------------------------------"
    echo -e "请选择以下选项：\n"
    echo -e "${BOLD}选项${RESET}     ${BOLD}描述${RESET}"
    echo "-----------------------------------"
    echo -e "${GREEN} 1${RESET}       安装必要组件"
    echo -e "${GREEN} 2${RESET}       添加要登记设备的公钥"
    echo -e "${GREEN} 3${RESET}       关闭 SSH 密码登录"
    echo -e "${GREEN} 4${RESET}       修改 SSH 端口号"
    echo -e "${GREEN} 5${RESET}       添加 Docker 工具脚本"
    echo -e "${GREEN} 6${RESET}       设置 Swap 大小"
    echo -e "${GREEN} 7${RESET}       修改 Swap 使用阈值"
    echo -e "${GREEN} 8${RESET}       清理 Swap 缓存"
    echo -e "${GREEN} 9${RESET}       优化内核参数"

    os_type=$(get_os_info)
    case $os_type in
        "Debian/Ubuntu")
            echo -e "${GREEN} 10${RESET}      下载并安装 XanMod 内核 (BBRv3)"
            echo -e "${GREEN} 11${RESET}      卸载 XanMod 内核，并恢复原有内核"
            if [[ $os_type == "Debian"* ]]; then
                echo -e "${GREEN} 12${RESET}      安装 Debian Cloud 内核"
                echo -e "${GREEN} 13${RESET}      卸载 Debian Cloud 内核，并恢复原有内核"
            fi
            ;;
    esac

    echo -e "${GREEN} 14${RESET}      设置防火墙端口"
    echo -e "${GREEN} 15${RESET}      配置 ZRAM"
    echo "-----------------------------------"
    echo -e "${BOLD}输入${RESET} 'q' ${BOLD}退出${RESET}"
}


# 根据用户选择执行相应的操作
handle_choice() {
    clear
    case $1 in
        1) install_components ;;
        2) add_public_key ;;
        3) disable_ssh_password_login ;;
        4) modify_ssh_port ;;
        5) add_docker_tools ;;
        6) set_virtual_memory ;;
        7) modify_swap_usage_threshold ;;
        8) cleanup_swap ;;
        9) optimize_kernel_parameters ;;
        10) install_xanmod_kernel ;;
        11) uninstall_xanmod_kernel ;;
        12) install_debian_cloud_kernel ;;
        13) uninstall_debian_cloud_kernel ;;
        14) set_firewall_ports ;;
        15) configure_zram_menu ;;
        q|Q) return 1 ;; # 返回非零值来退出循环
        *) echo "无效的选项，请输入合法的选项数字。" ;;
    esac
    read -p "按 Enter 键回到主菜单..."
}


# 主函数，接受选项并执行相应的脚本  
main() {
    trap cleanup EXIT
    
    while true; do
        display_menu
        read -p "请输入选项数字：" choice
        # 根据用户选择执行相应的操作
        handle_choice "$choice" || break
    done
    echo "欢迎再次使用本脚本！"
    sleep 0.5s
}


# 清理函数，在脚本退出时执行
cleanup() {
    echo "正在退出脚本..."
    sleep 1s
    tput reset
}

main "$@"