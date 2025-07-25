#!/bin/bash

# ==============================================================================
# 脚本名称: manage_xanmod_kernel.sh
# 脚本功能: 独立执行 XanMod 内核的安装与卸载.
#           自动从 SourceForge 下载最新的 LTS 内核版本.
# 调用方式: bash manage_xanmod_kernel.sh [install|uninstall] [--debug]
#           或通过管道执行: bash <(wget ...) [install|uninstall] [--debug]
# ==============================================================================

# 安装 XanMod 内核
install_xanmod() {
    # --- 调试模式设置 ---
    local DEBUG=false
    if [[ "$1" == "--debug" ]]; then
        DEBUG=true
        echo "--- DEBUG MODE ENABLED ---"
    fi

    debug_echo() {
        if [[ "$DEBUG" == "true" ]]; then
            # 使用 >&2 将调试信息输出到标准错误，不影响管道中的正常输出
            echo "DEBUG: $@" >&2
        fi
    }
    # --- 调试模式设置结束 ---

    echo "=========================================="
    echo "  开始安装 XanMod 内核"
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
    
    local cpu_support_level
    if [[ $cpu_support_info == "CPU supports x86-64-v"* ]]; then
        cpu_support_level=${cpu_support_info#CPU supports x86-64-v}
        echo "SUCCESS: 你的CPU支持 XanMod 内核, 级别为 x86-64-v$cpu_support_level"
    else
        echo "ERROR: 你的CPU不受 XanMod 内核支持, 无法安装。"
        return 1
    fi

    echo "INFO: 正在从 SourceForge 查找最新的 LTS 内核版本..."
    local SF_BASE_URL="https://sourceforge.net/projects/xanmod/files/releases/lts/"
    
    # 步骤 1: 解析HTML以查找最新的版本目录 (更健壮的方法)
    local raw_html_main
    raw_html_main=$(curl -sL "$SF_BASE_URL")
    debug_echo "--- Fetched HTML from $SF_BASE_URL ---"
    if [[ "$DEBUG" == "true" ]]; then echo "$raw_html_main" >&2; fi
    
    local LATEST_VERSION_DIR
    LATEST_VERSION_DIR=$(echo "$raw_html_main" | grep -o '<span class="name">[0-9]\+\.[0-9]\+.*-xanmod[0-9]\+</span>' | sed -e 's/<span class="name">//' -e 's,</span>,,' | sort -V | tail -n 1)
    debug_echo "Parsed LATEST_VERSION_DIR: $LATEST_VERSION_DIR"

    if [ -z "$LATEST_VERSION_DIR" ]; then
        echo "ERROR: 无法从 SourceForge 查找到最新的内核版本目录。请检查网络连接或稍后再试。"
        return 1
    fi
    echo "INFO: 找到最新的内核版本系列: $LATEST_VERSION_DIR"
    local LATEST_VERSION_URL="${SF_BASE_URL}${LATEST_VERSION_DIR}/"

    # 步骤 2: 在版本目录中查找对应CPU架构的子目录 (更健壮的方法)
    echo "INFO: 正在查找 v${cpu_support_level} 的架构子目录..."
    local raw_html_version
    raw_html_version=$(curl -sL "$LATEST_VERSION_URL")
    debug_echo "--- Fetched HTML from $LATEST_VERSION_URL ---"
    if [[ "$DEBUG" == "true" ]]; then echo "$raw_html_version" >&2; fi
    
    local ARCH_DIR_SUFFIX
    ARCH_DIR_SUFFIX=$(echo "$raw_html_version" | grep -o '<span class="name">.*x64v'"${cpu_support_level}"'[^<]*</span>' | sed -e 's/<span class="name">//' -e 's,</span>,,' | head -n 1)
    debug_echo "Parsed ARCH_DIR_SUFFIX for v${cpu_support_level}: $ARCH_DIR_SUFFIX"
    
    # ---  如果找不到 v4，则回退到 v3 ---
    if [ -z "$ARCH_DIR_SUFFIX" ] && [ "$cpu_support_level" -eq 4 ]; then
        echo "INFO: 未找到 v4 版本的内核, 正在尝试回退到 v3..."
        cpu_support_level=3 # 将级别降级为 3
        
        # 再次尝试查找 v3 目录
        ARCH_DIR_SUFFIX=$(echo "$raw_html_version" | grep -o '<span class="name">.*x64v'"${cpu_support_level}"'[^<]*</span>' | sed -e 's/<span class="name">//' -e 's,</span>,,' | head -n 1)
        debug_echo "Parsed ARCH_DIR_SUFFIX for fallback v${cpu_support_level}: $ARCH_DIR_SUFFIX"
    fi

    # 在可能的回退之后再次检查
    if [ -z "$ARCH_DIR_SUFFIX" ]; then
        echo "ERROR: 在 $LATEST_VERSION_DIR 中找不到 v${cpu_support_level} 的架构子目录。"
        return 1
    fi
    echo "INFO: 找到架构子目录: $ARCH_DIR_SUFFIX"
    local FILES_PAGE_URL="${LATEST_VERSION_URL}${ARCH_DIR_SUFFIX}/"

    # 步骤 3: 从架构子目录页面获取特定CPU级别的内核文件名 (更健壮的方法)
    echo "INFO: 正在获取内核文件列表..."
    local raw_html_files
    raw_html_files=$(curl -sL "$FILES_PAGE_URL")
    debug_echo "--- Fetched HTML from $FILES_PAGE_URL ---"
    if [[ "$DEBUG" == "true" ]]; then echo "$raw_html_files" >&2; fi
    
    local HEADERS_FILE
    HEADERS_FILE=$(echo "$raw_html_files" | grep -o '<span class="name">linux-headers-.*-x64v'"${cpu_support_level}"'-xanmod.*\.deb</span>' | sed -e 's/<span class="name">//' -e 's,</span>,,' | head -n 1)
    debug_echo "Parsed HEADERS_FILE: $HEADERS_FILE"
    
    local IMAGE_FILE
    IMAGE_FILE=$(echo "$raw_html_files" | grep -o '<span class="name">linux-image-.*-x64v'"${cpu_support_level}"'-xanmod.*\.deb</span>' | sed -e 's/<span class="name">//' -e 's,</span>,,' | head -n 1)
    debug_echo "Parsed IMAGE_FILE: $IMAGE_FILE"

    if [ -z "$HEADERS_FILE" ] || [ -z "$IMAGE_FILE" ]; then
        echo "ERROR: 无法为 x86-64-v${cpu_support_level} 找到对应的内核文件。可能该版本尚未发布或支持已更改。"
        return 1
    fi

    echo "找到内核文件:"
    echo "  - $HEADERS_FILE"
    echo "  - $IMAGE_FILE"

    read -p "是否继续下载并安装以上 XanMod 内核？ (y/n): " continue_choice
    if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
        echo "操作已取消。"
        return 0
    fi

    local temp_folder
    temp_folder=$(mktemp -d)
    if [ ! -d "$temp_folder" ]; then
        echo "ERROR: 无法创建临时目录。"
        return 1
    fi
    cd "$temp_folder" || return 1

    local HEADERS_URL="${FILES_PAGE_URL}${HEADERS_FILE}/download"
    local IMAGE_URL="${FILES_PAGE_URL}${IMAGE_FILE}/download"
    
    debug_echo "HEADERS_URL: $HEADERS_URL"
    debug_echo "IMAGE_URL: $IMAGE_URL"

    echo "INFO: 开始下载 XanMod 内核..."
    echo "INFO: 从 $HEADERS_URL 下载..."
    # 使用 -O 参数指定输出文件名，避免URL中的参数污染文件名
    wget -O "$HEADERS_FILE" "$HEADERS_URL"
    if [ $? -ne 0 ]; then
        echo "ERROR: headers 文件下载失败。"
        cd / && rm -rf "$temp_folder"
        return 1
    fi

    echo "INFO: 从 $IMAGE_URL 下载..."
    # 使用 -O 参数指定输出文件名
    wget -O "$IMAGE_FILE" "$IMAGE_URL"
    if [ $? -ne 0 ]; then
        echo "ERROR: image 文件下载失败。"
        cd / && rm -rf "$temp_folder"
        return 1
    fi
    
    echo "SUCCESS: 文件下载成功。"

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
    local debug_flag="$2"
    
    if [ -z "$action" ]; then
        echo "错误: 脚本需要一个操作参数。" >&2
        echo "用法: $0 [install|uninstall] [--debug]" >&2
        exit 1
    fi
    
    case "$action" in
        install)
            install_xanmod "$debug_flag"
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
