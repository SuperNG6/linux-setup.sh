#!/bin/bash

# 安装必要组件
install_components() {
    echo "正在安装必要组件..."

    # 检查是否具有足够的权限
    if [ "$(id -u)" != "0" ]; then
        echo "需要管理员权限来安装必要组件。请使用sudo运行脚本。"
        exit 1
    fi

    # 更新软件包列表，如果失败则退出
    apt -y update || { echo "更新软件包列表失败"; exit 1; }
    # 安装组件，如果失败则退出
    apt -y install docker.io docker-compose fail2ban vim curl || { echo "安装组件失败"; exit 1; }

    echo "关键组件安装成功。"
}

# 添加已登记设备的公钥
add_public_key() {
    echo "请输入公钥："
    read public_key

    # 检查是否具有足够的权限
    if [ "$(id -u)" != "0" ]; then
        echo "需要管理员权限来添加公钥。请使用sudo运行脚本。"
        exit 1
    fi

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

    # 检查是否具有足够的权限
    if [ "$(id -u)" != "0" ]; then
        echo "需要管理员权限来关闭SSH密码登录。请使用sudo运行脚本。"
        exit 1
    fi

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

    # 检查是否具有足够的权限
    if [ "$(id -u)" != "0" ]; then
        echo "需要管理员权限来设置虚拟内存。请使用sudo运行脚本。"
        exit 1
    fi

    # 检查是否已经存在交换文件
    if [ -e "/swap" ]; then
        echo "已经存在交换文件。删除现有的交换文件..."
        swapoff /swap
        rm -rf /swap
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
    echo "net.ipv4.tcp_slow_start_after_idle=0" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_notsent_lowat=16384" >> /etc/sysctl.conf

    # 重新加载系统设置
    sysctl -p

    # 检查修改是否成功
    if grep -q "^net.ipv4.tcp_slow_start_after_idle=0" /etc/sysctl.conf &&
       grep -q "^net.ipv4.tcp_notsent_lowat=16384" /etc/sysctl.conf; then
        echo "内核参数优化成功。"
    else
        echo "内核参数优化失败，请检查配置文件。"
        # 恢复备份文件
        mv /etc/sysctl.conf.bak /etc/sysctl.conf
        exit 1
    fi
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
            q|Q)
                break
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
