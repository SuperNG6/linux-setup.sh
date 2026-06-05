#!/bin/bash

# ==============================================================================
#
#                       群晖 Docker & Compose 功能函数库
#
#  说明:
#  此脚本是一个函数库，包含了所有用于操作 Docker 和 Docker Compose 的核心函数。
#  它不应被直接执行，而是由 docker_aliases.sh 文件加载，以便为别名提供功能。
#   
# ==============================================================================

# Docker 和 Compose 命令变量
# 所有命令已内置 sudo，将在需要时自动提权
# shellcheck disable=SC2034
DOCKER_CMD="sudo docker"
COMPOSE_CMD="sudo docker-compose"

docker_cmd() {
    sudo docker "$@"
}

compose_cmd() {
    sudo docker-compose "$@"
}


# --- 核心功能函数 ---
# 函数: 选择 Docker Container
# (sh 兼容)

select_container() {
    # 1. 接收传入的提示信息作为参数。
    local prompt_message="$1"
    
    # 2. 以 sh 兼容的方式获取正在运行的容器列表。
    local container_list
    container_list=$(docker_cmd ps --format "{{.Names}}")

    # 3. 处理没有容器正在运行的情况。
    if [ -z "$container_list" ]; then
        # 将错误信息打印到 stderr (>_2)，这样它们就不会被命令替换 `$(...)` 捕获。
        echo "错误：未找到正在运行的 Docker 容器。" >&2
        return 1
    fi

    # 4. 将提示和带编号的列表显示到 STDERR。
    #    这是关键的修复，以防止它们被 `$(...)` 捕获。
    echo "$prompt_message" >&2
    echo "$container_list" | nl -w 2 -s '. ' >&2
    local container_count
    container_count=$(echo "$container_list" | wc -l | sed 's/ //g')

    # 5. 读取用户输入。`read` 命令的提示符默认也发送到 stderr。
    local choice
    printf "请输入数字或容器名称: " >&2
    read -r choice

    local container_to_return=""

    # 6. 验证输入（必须是有效的数字或有效的名称）。
    if echo "$choice" | grep -qE '^[0-9]+$'; then
        # 输入是数字，检查它是否在有效范围内。
        if [ "$choice" -ge 1 ] && [ "$choice" -le "$container_count" ]; then
            container_to_return=$(echo "$container_list" | sed -n "${choice}p")
        fi
    else
        # 输入不是数字，检查它是否与某个容器名称完全匹配。
        if printf '%s\n' "$container_list" | grep -Fxq "$choice"; then
            container_to_return="$choice"
        fi
    fi

    # 7. 最终验证并返回。
    if [ -z "$container_to_return" ]; then
        echo "错误：输入无效。找不到容器 '$choice'。" >&2
        return 1
    fi

    # 将结果打印到 STDOUT，以便调用函数可以捕获它。
    echo "$container_to_return"
    return 0
}

resolve_container_arg() {
    local input="$*"
    local container_list
    container_list=$(docker_cmd ps --format "{{.Names}}")

    if [ -z "$container_list" ]; then
        echo "错误：未找到正在运行的 Docker 容器。" >&2
        return 1
    fi

    input=$(printf '%s' "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$input" ]; then
        return 1
    fi

    if echo "$input" | grep -qE '^[0-9]+[.][[:space:]]+'; then
        input=$(printf '%s\n' "$input" | sed 's/^[0-9][0-9]*\.[[:space:]]*//')
    elif echo "$input" | grep -qE '^[0-9]+[.]$'; then
        input=${input%.}
    fi

    if echo "$input" | grep -qE '^[0-9]+$'; then
        local container_count
        container_count=$(printf '%s\n' "$container_list" | wc -l | sed 's/ //g')
        if [ "$input" -ge 1 ] && [ "$input" -le "$container_count" ]; then
            printf '%s\n' "$container_list" | sed -n "${input}p"
            return 0
        fi
    elif printf '%s\n' "$container_list" | grep -Fxq "$input"; then
        printf '%s\n' "$input"
        return 0
    fi

    echo "错误：输入无效。找不到容器 '$input'。" >&2
    return 1
}

# 函数: 选择 Docker Compose 项目目录
select_docker_compose_dir() {
    local selected_folder

    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        selected_folder="$PWD"
        return 0
    fi

    local dir
    local temp_file
    if ! temp_file=$(mktemp); then
        echo "错误: 无法创建临时文件。" >&2
        return 1
    fi

    # 查找所有包含 docker-compose 文件的子目录
    find . -maxdepth 2 -mindepth 1 -type d | while IFS= read -r dir; do
        if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
            printf '%s\n' "$dir" >> "$temp_file"
        fi
    done

    local folder_count
    folder_count=$(wc -l < "$temp_file" | sed 's/ //g')

    if [ "$folder_count" -eq 0 ]; then
        echo "错误: 当前目录及子文件夹中没有找到 Docker Compose 配置文件。" >&2
        rm "$temp_file"
        return 1
    fi

    if [ "$folder_count" -eq 1 ]; then
        selected_folder=$(sed -n '1p' "$temp_file")
        echo "自动选择唯一的 Compose 项目目录: ${selected_folder#./}"
        rm "$temp_file"
        cd "$selected_folder" || { echo "错误: 无法进入目录 $selected_folder。" >&2; exit 1; }
        return 0
    fi

    echo "找到以下包含 Docker Compose 配置文件的项目:"
    local index=1
    while IFS= read -r dir; do
        printf '%2d. %s\n' "$index" "${dir#./}"
        index=$((index + 1))
    done < "$temp_file"

    local choice
    printf "请输入数字选择要操作的项目: "
    read -r choice

    if ! echo "$choice" | grep -qE '^[0-9]+$' || [ "$choice" -lt 1 ] || [ "$choice" -gt "$folder_count" ]; then
        echo "错误: 无效的选择。" >&2
        rm "$temp_file"
        return 1
    fi

    selected_folder=$(sed -n "${choice}p" "$temp_file")
    rm "$temp_file"
    cd "$selected_folder" || { echo "错误: 无法进入目录 $selected_folder。" >&2; exit 1; }
    echo "已进入目录: $PWD"
}

# 函数: 执行任意 Docker Compose 命令
run_compose_command() {
    select_docker_compose_dir
    if [ $? -ne 0 ]; then return 1; fi
    echo "在目录 '$PWD' 中执行: $COMPOSE_CMD $*"
    compose_cmd "$@"
}

# 函数: 显示 Compose 项目的容器列表
run_compose_ps() {
    select_docker_compose_dir
    if [ $? -ne 0 ]; then return 1; fi
    echo "正在检查 '$PWD' 的容器状态..."
    compose_cmd ps
}

# 函数: 查看 Compose 项目的日志
run_compose_logs() {
    select_docker_compose_dir
    if [ $? -ne 0 ]; then return 1; fi
    echo "正在查看 '$PWD' 的容器日志 (按 Ctrl+C 退出)..."
    compose_cmd logs -f --tail 100
}

# 函数: 显示 Compose 项目的资源使用情况
run_compose_stats() {
    select_docker_compose_dir
    if [ $? -ne 0 ]; then return 1; fi

    local container_ids
    if ! container_ids=$(compose_cmd ps -q); then
        echo "错误: 无法获取当前 Compose 项目的容器列表。"
        return 1
    fi

    if [ -z "$container_ids" ]; then
        echo "错误: 当前 Compose 项目没有找到容器。"
        return 1
    fi

    echo "正在检查 '$PWD' 的容器资源使用情况 (按 Ctrl+C 退出)..."
    # shellcheck disable=SC2086
    docker_cmd stats $container_ids
}

# 函数: 重启 Compose 项目
run_compose_restart() {
    local restart_mode="fast"
    if [ "$1" = "R" ] || [ "$1" = "-R" ]; then
        restart_mode="full"
    fi

    select_docker_compose_dir
    if [ $? -ne 0 ]; then return 1; fi

    if [ "$restart_mode" = "fast" ]; then
        echo "在 '$PWD' 中执行快速重启..."
        compose_cmd restart
    else
        echo "在 '$PWD' 中执行完全重建 (down -> up)..."
        compose_cmd down && compose_cmd up -d
    fi

    if [ $? -eq 0 ]; then
        echo "项目已成功重启。"
    else
        echo "错误: 重启项目时发生错误。"
        return 1
    fi
}

# 函数: 选择并查看单个容器的日志
run_container_logs() {
    local selected_container
    if [ $# -gt 0 ]; then
        selected_container=$(resolve_container_arg "$@")
    else
        selected_container=$(select_container "请选择要查看日志的容器:")
    fi

    if [ -z "$selected_container" ]; then
        return 1
    fi

    echo "正在查看 '$selected_container' 的日志 (按 Ctrl+C 退出)..."
    docker_cmd logs -f --tail 100 "$selected_container"
}

# 函数: 选择并重启单个容器
run_container_restart() {
    # 调用核心函数，并传入定制的提示语
    local selected_container
    selected_container=$(select_container "请选择要重启的容器:")

    if [ -z "$selected_container" ]; then
        return 1
    fi

    echo "正在重启容器 '$selected_container'..."
    if docker_cmd restart "$selected_container"; then
        echo "容器 '$selected_container' 已重启。"
    else
        echo "错误: 容器 '$selected_container' 重启失败。"
        return 1
    fi
}

# 函数: 选择并进入容器
run_container_exec() {
    local selected_container
    if [ $# -gt 0 ]; then
        selected_container=$(resolve_container_arg "$@")
    else
        selected_container=$(select_container "请选择要进入的容器:")
    fi

    if [ -z "$selected_container" ]; then
        return 1
    fi

    echo "正在尝试进入容器 ${selected_container}..."
    # 1. 检查 'bash' 是否存在于容器中
    # 我们使用 `docker exec ... which` 命令，并将其输出重定向到 /dev/null
    # 这样可以安静地检查命令是否存在，我们只关心它的退出状态码
    if docker_cmd exec "${selected_container}" which bash >/dev/null 2>&1; then
        echo "找到 'bash', 正在进入..."
        docker_cmd exec -it "${selected_container}" bash

    # 2. 如果 'bash' 不存在, 则检查 'sh'
    elif docker_cmd exec "${selected_container}" which sh >/dev/null 2>&1; then
        echo "未找到 'bash', 但找到了 'sh', 正在进入..."
        docker_cmd exec -it "${selected_container}" sh

    # 3. 如果 'bash' 和 'sh' 都不存在
    else
        echo "错误：在容器 ${selected_container} 中未找到 'bash' 或 'sh'。无法进入容器。"
        exit 1
    fi

    # 检查上一个 exec 命令的退出状态码
    if [ $? -ne 0 ]; then
        echo "已退出容器 ${selected_container}."
    fi
}


# 函数: 更新 /etc/hosts 文件
run_ip_update() {
    if ! docker_cmd info > /dev/null 2>&1; then echo "错误: Docker 服务未运行。"; return 1; fi

    local hosts_file="/etc/hosts"
    local comment_start="# BEGIN Docker container IPs"
    local comment_end="# END Docker container IPs"
    local tmp_file
    if ! tmp_file=$(mktemp); then echo "错误: 无法创建临时文件。"; return 1; fi

    echo "正在获取所有容器的 IP 地址..."
    local id
    local container_name
    local container_ips
    local ip
    docker_cmd ps -q | while read -r id; do
        container_name=$(docker_cmd inspect -f '{{.Name}}' "$id" | sed 's/^\///')
        container_ips=$(docker_cmd inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$id")
        for ip in $container_ips; do
            if [ -n "$container_name" ] && [ -n "$ip" ]; then
                echo "找到映射: $ip -> $container_name"
                printf '%s\t%s\n' "$ip" "$container_name" >>"$tmp_file"
            fi
        done
    done

    if [ -s "$tmp_file" ]; then
        echo "正在更新 $hosts_file..."
        # 在 Synology 上 sed 可能需要 -i'' 参数
        sudo sed -i'' "/$comment_start/,/$comment_end/d" "$hosts_file"
        { echo ""; echo "$comment_start"; cat "$tmp_file"; echo "$comment_end"; } | sudo tee -a "$hosts_file" > /dev/null
        echo "Hosts 文件更新完成。"
    else
        echo "未找到任何正在运行的容器，无需更新 Hosts 文件。"
        sudo sed -i'' "/$comment_start/,/$comment_end/d" "$hosts_file"
    fi
    rm "$tmp_file"
}
