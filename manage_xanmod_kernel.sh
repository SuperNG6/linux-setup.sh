#!/bin/bash

# ==============================================================================
# 脚本名称: manage_xanmod_kernel.sh
# 脚本功能: 独立执行 XanMod 内核的安装与卸载.
# 调用方式: bash manage_xanmod_kernel.sh [install|uninstall]
#           或通过管道执行: bash <(wget ...) [install|uninstall]
# ==============================================================================

# 安装 XanMod 内核
install_xanmod() {
    echo "=========================================="
    echo "  准备安装 XanMod 内核"
    echo "=========================================="
    echo "当前内核版本: $(uname -r)"

    # 检查 CPU 支持的指令集级别 (内置 awk 脚本)
    echo "INFO: 正在检查CPU支持级别..."
    local cpu_support_info
    cpu_support_info=$(/usr/bin/awk '
    BEGIN {
        while (!/flags/) if (getline < "/proc/cpuinfo" != 1) exit 1
        if (/lm/&&/cmov/&&/cx8/&&/fpu/&&/fxsr/&&/mmx/&&/syscall/&&/sse2/) level = 1
        if (level == 1 && /cx16/&&/lahf/&&/popcnt/&&/sse4_1/&&/sse4_2/&&/ssse3/) level = 2
        if (level == 2 && /avx/&&/avx2/&&/bmi1/&&/bmi2/&&/f16c/&&/fma/&&/abm/&&/movbe/&&/xsave/) level = 3
        if (level == 3 && /avx512f/&&/avx512bw/&&/avx512cd/&&/avx512dq/&&/avx512vl/) level = 4
        if (level > 0) { print "CPU supports x86-64-v" level; exit level + 1 }
        exit 1
    }')
    
    if [[ $cpu_support_info == "CPU supports x86-64-v"* ]]; then
        local cpu_support_level=${cpu_support_info#CPU supports x86-64-v}
        echo "SUCCESS: 你的CPU支持 XanMod 内核, 级别为 x86-64-v$cpu_support_level"
    else
        echo "ERROR: 你的CPU不受 XanMod 内核支持, 无法安装。"
        return 1
    fi

    read -p "是否继续下载并安装 XanMod 内核 (v$cpu_support_level)？ (y/n): " continue_choice
    if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
        echo "操作已取消。"
        return 0
    fi

    echo "INFO: 开始下载 XanMod 内核..."
    echo "INFO: XanMod内核官网 https://xanmod.org"
    echo "INFO: 内核来自 https://sourceforge.net/projects/xanmod/files/releases/lts/"

    local temp_folder
    temp_folder=$(mktemp -d)
    if [ ! -d "$temp_folder" ]; then
        echo "ERROR: 无法创建临时目录。"
        return 1
    fi
    cd "$temp_folder" || return 1

    local headers_file image_file headers_md5 image_md5
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
            echo "ERROR: 你的CPU不受 XanMod 内核支持, 无法安装。"
            cd / && rm -rf "$temp_folder"
            return 1
            ;;
    esac

    local download_url_base="${YES_CN}https://github.com/SuperNG6/linux-setup.sh/releases/download/0816/"
    echo "INFO: 正在下载内核文件..."
    wget "${download_url_base}${headers_file}" && wget "${download_url_base}${image_file}"
    if [ $? -ne 0 ]; then
        echo "ERROR: 文件下载失败。"
        cd / && rm -rf "$temp_folder"
        return 1
    fi

    echo "INFO: 正在校验文件 MD5..."
    if [ "$(md5sum "$headers_file" | awk '{print $1}')" != "$headers_md5" ] || \
       [ "$(md5sum "$image_file" | awk '{print $1}')" != "$image_md5" ]; then
        echo "ERROR: 下载的文件 MD5 校验失败, 可能文件已损坏或被篡改。"
        cd / && rm -rf "$temp_folder"
        return 1
    fi
    echo "SUCCESS: 文件校验成功。"

    echo "INFO: 正在安装内核, 请稍候..."
    dpkg -i linux-image-*.deb linux-headers-*.deb
    if [ $? -eq 0 ]; then
        echo "SUCCESS: XanMod 内核安装成功。"
        read -p "是否需要立即更新 GRUB 引导配置？ (y/n): " update_grub_choice
        if [[ "$update_grub_choice" =~ ^[Yy]$ ]]; then
            update-grub
            echo "SUCCESS: GRUB 引导配置已更新。"
            echo "提示: 请重启系统以启用新内核。若要开启 BBRv3, 请在重启后再次运行主脚本并选择 '优化内核参数'。"
        else
            echo "INFO: 跳过 GRUB 引导配置更新。您可能需要稍后手动运行 'sudo update-grub'。"
        fi
    else
        echo "ERROR: XanMod 内核安装失败。"
    fi

    echo "INFO: 正在清理临时文件..."
    cd / && rm -rf "$temp_folder"
}

# 卸载 XanMod 内核
uninstall_xanmod() {
    echo "=========================================="
    echo "  开始卸载 XanMod 内核"
    echo "=========================================="
    echo "正在检查已安装的 XanMod 内核..."

    local installed_xanmod
    installed_xanmod=$(dpkg -l | grep -E 'linux-(image|headers)-[0-9].*-xanmod')
    
    if [ -z "$installed_xanmod" ]; then
        echo "INFO: 未检测到任何已安装的 XanMod 内核, 无需卸载。"
        return 0
    fi
    
    echo "检测到以下已安装的 XanMod 内核及相关组件:"
    echo "$installed_xanmod"
    echo "------------------------------------------"
    
    read -p "确定要卸载所有 XanMod 内核并恢复系统默认内核吗？(y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "操作已取消。"
        return 0
    fi

    echo "INFO: 正在卸载 XanMod 内核 (使用 purge 彻底删除)..."
    apt-get purge -y 'linux-image-*-xanmod*' 'linux-headers-*-xanmod*'
    if [ $? -ne 0 ]; then
        echo "WARNING: apt purge 命令可能遇到问题, 仍将继续执行后续步骤。"
    fi

    echo "INFO: 正在执行 autoremove 清理依赖..."
    apt-get autoremove -y

    echo "INFO: 正在更新 GRUB 引导配置..."
    update-grub

    echo "SUCCESS: 所有 XanMod 内核已卸载。GRUB 引导配置已更新, 请重启系统以使更改生效。"
}

# --- 主逻辑 ---
main() {    
    local action="$1"
    
    if [ -z "$action" ]; then
        echo "错误: 脚本需要一个操作参数。" >&2
        echo "用法: $0 [install|uninstall]" >&2
        exit 1
    fi
    
    case "$action" in
        install)
            install_xanmod
            ;;
        uninstall)
            uninstall_xanmod
            ;;
        *)
            echo "错误: 无效的参数 '$action'。请使用 'install' 或 'uninstall'。" >&2
            exit 1
            ;;
    esac
}

# 将所有命令行参数传递给 main 函数执行
main "$@"
