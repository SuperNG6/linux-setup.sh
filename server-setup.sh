#!/bin/bash

# 检查是否具有足够的权限
if [ "$(id -u)" != "0" ]; then
    echo "需要管理员权限，请使用sudo运行此脚本。"
    exit 1
fi

# 获取操作系统信息
get_os_info() {
    # 判断是否是Debian/Ubuntu
    if [ -f /etc/debian_version ]; then
        echo "debian"
    # 判断是否是CentOS
    elif [ -f /etc/centos-release ]; then
        echo "centos"
    else
        echo "unknown"
    fi
}


# 安装必要组件
install_components() {
    echo "正在安装必要组件..."

    # 获取操作系统信息
    os_type=$(get_os_info)

    case $os_type in
        debian)
            # 更新软件包列表，如果失败则退出
            apt -y update || { echo "更新软件包列表失败"; exit 1; }
            # 安装组件，如果失败则退出
            apt -y install docker.io docker-compose fail2ban vim curl || { echo "安装组件失败"; exit 1; }
            ;;
        centos)
            # 更新软件包列表，如果失败则退出
            yum -y update || { echo "更新软件包列表失败"; exit 1; }
            # 安装组件，如果失败则退出
            yum -y install docker docker-compose fail2ban vim curl || { echo "安装组件失败"; exit 1; }
            ;;
        *)
            echo "无法确定操作系统类型，无法安装组件。"
            exit 1
            ;;
    esac

    echo "关键组件安装成功。"
}

# 添加已登记设备的公钥
add_public_key() {
    echo "请输入公钥："
    read public_key

    # 检查公钥是否为空
    if [ -z "$public_key" ]; then
        echo "无效的公钥。"
        exit 1
    fi

    # 检查公钥格式
    if [[ ! "$public_key" =~ ^ssh-rsa[[:space:]]+[A-Za-z0-9+/]+[=]{0,3}(\s*.+)? ]]; then
        echo "无效的公钥格式。"
        exit 1
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
        exit 1
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
            exit 1
        fi
    else
        echo "sshd_config 文件不存在"
        exit 1
    fi
}

# bash 环境变量加入alias
add_bash_aliases() {
    echo "正在为bash环境添加别名..."

    # 检查是否已经存在.bashrc文件
    if [ -e "/root/.bashrc" ]; then
        # 备份原始.bashrc文件
        cp /root/.bashrc /root/.bashrc.bak
    fi

    # 检查是否已经存在别名，避免重复添加
    if grep -q "alias nginx=" /root/.bashrc; then
        echo "别名已存在，无需重复添加。"
    else
        # 追加alias到.bashrc文件
        echo '# ~/.bashrc: executed by bash(1) for non-login shells.' >> /root/.bashrc
        echo 'alias nginx="docker exec -i docker_nginx nginx"' >> /root/.bashrc
        echo 'alias dc="docker-compose"' >> /root/.bashrc
        echo 'alias dcs="docker-compose ps -q | xargs docker stats"' >> /root/.bashrc
        echo 'alias dcps="docker ps $((docker-compose ps -q  || echo "#") | while read line; do echo "--filter id=$line"; done)"' >> /root/.bashrc
        echo 'alias dcip="bash /root/dcip/dcip.sh"' >> /root/.bashrc
        echo "别名添加成功。"
    fi
}

# 设置虚拟内存
set_virtual_memory() {
    echo "正在检查当前交换空间..."
    if swapon -s | grep -q '/swap'; then
        echo "当前交换空间大小如下："
        swapon -s | grep '/swap'
        echo "是否要删除已存在的交换空间？"
        read -p "请输入 y 或 n：" remove_choice

        case $remove_choice in
            y|Y)
                swapoff /swap
                rm -rf /swap
                echo "已删除交换空间。"
                ;;
            n|N)
                echo "保留已存在的交换空间。"
                ;;
            *)
                echo "无效的选项，保留已存在的交换空间。"
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
            echo "正在退出脚本..."
            exit 0
            ;;
        *)
            echo "无效的选项。"
            exit 1
            ;;
    esac

    echo "正在设置虚拟内存..."

    # 检查是否已经存在交换文件
    if [ -e "/swap" ]; then
        echo "已经存在交换文件。删除现有的交换文件..."
        swapoff /swap
        rm -rf /swap
    fi

    if [ -e "/swapfile" ]; then
        echo "已经存在交换文件。删除现有的交换文件..."
        swapoff /swapfile
        rm -rf /swapfile
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
            exit 1
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
            echo "当前交换空间大小如下："
            swapon -s | grep '/swap'
        else
            echo "交换文件创建成功，但启用交换失败，请检查命令是否执行成功。"
            exit 1
        fi
    else
        echo "创建交换文件失败，请检查命令是否执行成功。"
        exit 1
    fi
}

# 修改swap使用阈值
modify_swap_usage_threshold() {
    echo "正在修改swap使用阈值..."

    read -p "请输入要设置的vm.swappiness值（0-100之间）：" swap_value

    # 检查输入是否为数字且在0-100范围内
    if ! [[ "$swap_value" =~ ^[0-9]+$ ]] || [ "$swap_value" -lt 0 ] || [ "$swap_value" -gt 100 ]; then
        echo "无效的输入，请输入0-100之间的数字。"
        exit 1
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
        exit 1
    fi
}

# 优化内核参数
optimize_kernel_parameters() {
    echo "正在优化内核参数..."
    
    # 备份原始配置文件
    cp /etc/sysctl.conf /etc/sysctl.conf.bak

    # 检查是否存在net.ipv4.tcp_fastopen=3，如果存在则注释掉
    if grep -q "^net.ipv4.tcp_fastopen=3" /etc/sysctl.conf; then
        sed -i 's/^net.ipv4.tcp_fastopen=3/#net.ipv4.tcp_fastopen=3/' /etc/sysctl.conf
    fi

    # 添加net.ipv4.tcp_slow_start_after_idle=0和net.ipv4.tcp_notsent_lowat=16384到/etc/sysctl.conf
    if ! grep -q "^net.ipv4.tcp_slow_start_after_idle" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_slow_start_after_idle=0" >> /etc/sysctl.conf
    else
        sed -i 's/^net.ipv4.tcp_slow_start_after_idle=.*/net.ipv4.tcp_slow_start_after_idle=0/' /etc/sysctl.conf
    fi

    if ! grep -q "^net.ipv4.tcp_notsent_lowat" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_notsent_lowat=16384" >> /etc/sysctl.conf
    else
        sed -i 's/^net.ipv4.tcp_notsent_lowat=.*/net.ipv4.tcp_notsent_lowat=16384/' /etc/sysctl.conf
    fi

    # 添加net.core.default_qdisc=fq和net.ipv4.tcp_congestion_control=bbr到/etc/sysctl.conf
    if ! grep -q "^net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi

    if ! grep -q "^net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi

    # 重新加载系统设置
    sysctl -p

    # 检查修改是否成功
    if grep -q "^net.ipv4.tcp_slow_start_after_idle=0" /etc/sysctl.conf &&
       grep -q "^net.ipv4.tcp_notsent_lowat=16384" /etc/sysctl.conf &&
       grep -q "^net.core.default_qdisc=fq" /etc/sysctl.conf &&
       grep -q "^net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
       echo "内核参数优化成功。"
    else
        echo "内核参数优化失败，请检查配置文件。"
        # 恢复备份文件
        mv /etc/sysctl.conf.bak /etc/sysctl.conf
        exit 1
    fi
}


install_xanmod_kernel() {
    echo "当前内核版本：$(uname -r)"

    # 检查 CPU 支持的指令集级别
    cpu_support_info=$(/usr/bin/awk -f <(wget -qO - https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/check_x86-64_psabi.sh))
    if [[ $cpu_support_info == "CPU supports x86-64-v"* ]]; then
        cpu_support_level=${cpu_support_info#CPU supports x86-64-v}
        echo "你的CPU支持XanMod内核，级别为 x86-64-v$cpu_support_level"
    else
        echo "你的CPU不受XanMod内核支持，无法安装。"
        exit 1
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
                    exit 1
                    ;;
            esac

            # 下载内核文件
            wget "https://github.com/SuperNG6/linux-setup.sh/releases/download/0816/$headers_file"
            wget "https://github.com/SuperNG6/linux-setup.sh/releases/download/0816/$image_file"

            # 校验 MD5 值
            if [ "$(md5sum $headers_file | awk '{print $1}')" != "$headers_md5" ]; then
                echo "下载的 $headers_file MD5 值不匹配，可能文件已被篡改。"
                exit 1
            fi

            if [ "$(md5sum $image_file | awk '{print $1}')" != "$image_md5" ]; then
                echo "下载的 $image_file MD5 值不匹配，可能文件已被篡改。"
                exit 1
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
    echo "正在检查当前内核..."

    # 获取当前内核的版本号
    current_kernel_version=$(uname -r)

    # 检查是否为XanMod内核
    if [[ $current_kernel_version == *-xanmod* ]]; then
        echo "当前内核为 XanMod 内核：$current_kernel_version"
        echo "正在卸载XanMod内核并恢复原有内核..."

        # 卸载XanMod内核
        apt-get purge linux-image-*xanmod* linux-headers-*xanmod*
        apt-get autoremove

        # 更新Grub引导配置
        update-grub

        echo "XanMod内核已卸载并恢复原有内核。Grub引导配置已更新，重启后生效。"
    else
        echo "当前内核不是XanMod内核，无法执行卸载操作。"
    fi
}

# 修改SSH端口号
modify_ssh_port() {
    echo "当前SSH端口号：$(grep -oP '^Port \K\d+' /etc/ssh/sshd_config)"

    read -p "请输入新的SSH端口号：" new_ssh_port

    # 检查输入是否为数字
    if ! [[ "$new_ssh_port" =~ ^[0-9]+$ ]]; then
        echo "无效的输入，请输入有效的端口号。"
        exit 1
    fi

    # 更新sshd_config文件中的端口号
    sed -i "s/^Port .*/Port $new_ssh_port/" /etc/ssh/sshd_config

    # 重启SSH服务
    systemctl restart sshd

    echo "SSH端口号已修改为：$new_ssh_port"
}


# 显示操作菜单选项
display_menu() {
    echo "请选择以下选项："
    echo "1. 安装必要组件"
    echo "2. 添加已登记设备的公钥"
    echo "3. 关闭ssh密码登录"
    echo "4. bash 环境变量加入alias"
    echo "5. 设置虚拟内存"
    echo "6. 修改swap使用阈值"
    echo "7. 优化内核参数"
    # 获取操作系统信息
    os_type=$(get_os_info)
    case $os_type in
        debian)
            echo "8. 下载并安装XanMod内核(BBRv3)"
            echo "9. 卸载XanMod内核，并恢复原有内核"
            ;;
        centos)
            # 在CentOS系统中不显示"下载并安装XanMod内核"、卸载XanMod内核，并恢复原有内核"选项
            ;;
        *)
            echo "无法确定操作系统类型，无法添加相应选项。"
            ;;
    esac
    echo "10. 修改SSH端口号"
}

# 主函数，接受选项并执行相应的脚本
main() {
    trap cleanup EXIT

    # 使用while循环允许用户返回主菜单
    while true; do
        display_menu
        read -p "请输入选项数字（按q退出）：" choice

        case $choice in
            1)
                install_components
                ;;
            2)
                add_public_key
                ;;
            3)
                disable_ssh_password_login
                ;;
            4)
                add_bash_aliases
                ;;
            5)
                set_virtual_memory
                ;;
            6)
                modify_swap_usage_threshold
                ;;
            7)
                optimize_kernel_parameters
                ;;
            8)
                install_xanmod_kernel
                ;;
            9)
                uninstall_xanmod_kernel
                ;;
            10)
                modify_ssh_port
                ;;
            q|Q)
                break  # Exit the loop
                ;;
            *)
                echo "无效的选项，请输入合法的选项数字。"
                ;;
        esac
    done
}

# 清理函数，在脚本退出时执行
cleanup() {
    # 这里可以添加一些清理操作，如还原临时更改等
    echo "正在退出脚本..."
}

main "$@"