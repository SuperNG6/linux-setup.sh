#!/bin/bash

# 检查IP地址是否在中国并相应地设置镜像
set_mirror() {
    # 使用超时以防止长时间等待
    echo "正在检查网络位置以设置镜像..."
    COUNTRY=$(curl -s --max-time 5 ipinfo.io/country)

    if [ "$COUNTRY" = "CN" ]; then
        YES_CN="https://ghfast.top/"
        echo "检测到在中国，已设置代理镜像。"
    else
        YES_CN=""
        echo "未在中国，将使用官方源。"
    fi
}

# 调用函数设置镜像变量
set_mirror

# --- 使用变量和常量，让脚本更清晰，易于维护 ---
# 使用 $HOME 代替 /root，使其对所有用户都可用
# 注意: 如果使用sudo, $HOME 可能会指向 /root, 这是预期的行为。
tools_dir="$HOME/.docker_tools"
bashrc_file="$HOME/.bashrc"
# 使用 YES_CN 变量设置仓库URL
repo_base_url="${YES_CN}https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/docker_tools"

# --- 使用数组管理脚本列表，避免重复的 wget 命令 ---
scripts_to_download=(
    "docker_utils.sh"
    "dlogs.sh"
    "dcip.sh"
    "dclogs.sh"
    "dc.sh"
    "drestart.sh"
    "dcrestart.sh"
    "dcps.sh"
    "dcstats.sh"
    "dexec.sh"
)

# --- 使用 "Here Document" (cat <<EOF) 来格式化多行输出，更美观 ---

cat << EOF

安装 Docker 工具箱
添加一系列便捷的别名和脚本来简化 Docker 操作。

-----------------------------------
功能列表：
- nginx: 直接执行容器内的 nginx -t, reload 等命令
- dlogs: [容器名] - 查看指定容器的日志
- dclogs: [服务名] - 查看 docker-compose 服务的日志
- dspa: 清理不再使用的 Docker 镜像、容器和网络
- dc: 等同于 'docker-compose'
- dcs: 查看 docker-compose 容器状态
- dcps: 查看 docker-compose 容器列表
- dcip: [容器名] - 查看容器 IP 并尝试添加到 hosts
- dr: [容器名] - 重启指定容器
- dcr: [服务名] - 重启指定的 compose 服务
- dexec: [容器名] - 进入指定容器的 shell 环境

工具脚本将保存在 "${tools_dir}" 文件夹中。
-----------------------------------

EOF

# -p 选项可以直接在同一行显示提示信息
read -p "是否安装？请输入 y (是) 或 n (否): " install_choice

# --- case 语句中使用小写转换，兼容更多输入 ---
case "${install_choice,,}" in
y | yes)
    echo "开始安装 Docker 工具箱..."

    # 如果 .bashrc 存在，则创建一个带时间戳的备份，更安全
    if [ -f "$bashrc_file" ]; then
        backup_file="${bashrc_file}.bak"
        echo "正在备份当前的 .bashrc 文件到 ${backup_file}"
        cp "$bashrc_file" "$backup_file"
    fi

    # 创建工具目录
    echo "创建工具目录: ${tools_dir}"
    mkdir -p "$tools_dir"

    # --- 直接创建 docker_aliases.sh 文件 ---
    echo "正在创建别名配置文件 (docker_aliases.sh)..."
    cat <<EOF > "${tools_dir}/docker_aliases.sh"
#!/bin/bash

# Alias definitions for Docker tools

alias nginx="docker exec -i docker_nginx nginx"
alias dspa="docker system prune -a"
alias dc="bash ${tools_dir}/dc.sh"
alias dcs="bash ${tools_dir}/dcstats.sh"
alias dcps="bash ${tools_dir}/dcps.sh"
alias dcip="bash ${tools_dir}/dcip.sh"
alias dlogs="bash ${tools_dir}/dlogs.sh"
alias dclogs="bash ${tools_dir}/dclogs.sh"
alias dr="bash ${tools_dir}/drestart.sh"
alias dcr="bash ${tools_dir}/dcrestart.sh"
alias dexec="bash ${tools_dir}/dexec.sh"
EOF

    # --- 使用循环下载其余的脚本，并进行错误检查 ---
    echo "正在从 GitHub 下载支持脚本..."
    for script in "${scripts_to_download[@]}"; do
        url="${repo_base_url}/${script}"
        dest="${tools_dir}/${script}"
        echo " -> 下载 ${script}"
        # -q (quiet) 安静模式, -O (output) 指定输出文件
        if ! wget -qO "$dest" "$url"; then
            echo "错误: 下载 ${script} 失败。请检查您的网络连接或 URL 是否正确。" >&2
            # 下载失败时，删除已创建的目录并退出
            rm -rf "$tools_dir"
            exit 1
        fi
    done

    # --- 更简洁的权限设置方式 ---
    echo "为所有脚本添加可执行权限..."
    chmod +x "${tools_dir}"/*.sh

    echo "下载和权限设置完成。"

    # --- 正确、安全地向 .bashrc 添加配置 ---
    # 定义要添加到 .bashrc 的内容
    source_line="[ -f \"${tools_dir}/docker_aliases.sh\" ] && . \"${tools_dir}/docker_aliases.sh\""
    # 检查 .bashrc 中是否已存在这一行，避免重复添加
    # 使用 grep -F 表示按固定字符串搜索，-q 表示静默模式
    if grep -Fq "docker_aliases.sh" "$bashrc_file"; then
        echo "配置信息已存在于 ${bashrc_file}，无需再次添加。"
    else
        echo "正在将配置信息添加到 ${bashrc_file}..."
        # 使用 >> 追加到文件末尾，而不是 > 覆盖
        # 添加注释，方便以后识别
        cat <<EOF >> "$bashrc_file"

# Docker Tools - 由安装脚本自动添加
${source_line}
EOF
    fi

    cat << EOF

Docker 工具箱已成功安装！

要使新命令立即生效，请执行以下命令之一：
1. source ${bashrc_file}
2. 重新打开一个新的终端窗口

EOF
    ;;
n | no)
    echo "已取消安装 Docker 工具箱。"
    ;;
*)
    echo "无效的选项。已取消安装。"
    ;;
esac

exit 0
