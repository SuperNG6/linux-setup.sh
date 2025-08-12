#!/bin/bash

# 检测docker compose的版本，并设置compose_cmd变量
check_docker_compose_version() {
    if command -v docker compose &>/dev/null && command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
    elif command -v docker compose &>/dev/null; then
        compose_cmd="docker compose"
    elif command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
    else
        echo "未找到 Docker Compose。请确保已安装 Docker Compose。" >&2
        exit 1
    fi
}

# 函数：选择Docker Compose目录
select_docker_compose_dir() {
    # 检查当前目录是否包含docker-compose.yml或docker-compose.yaml
    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        selected_folder="$PWD"
        return 0
    fi

    # 初始化一个数组来存储包含docker-compose.yml或docker-compose.yaml的子文件夹
    local folders=()

    # 遍历当前目录下的一层子目录
    for dir in */; do
        # 检查子目录中是否有docker-compose.yml或docker-compose.yaml文件
        if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
            folders+=("$dir")
        fi
    done

    # 检查是否找到至少一个有效的子目录
    if [ ${#folders[@]} -eq 0 ]; then
        echo "当前目录下以及子文件夹中没有找到 Docker Compose 配置文件。" >&2
        return 1
    fi

    # 显示找到的文件夹并编号
    echo "找到以下子文件夹包含 Docker Compose 配置文件："
    for i in "${!folders[@]}"; do
        echo "$((i+1)). ${folders[$i]}"
    done

    # 提示用户选择文件夹
    local choice
    read -p "请选择 Docker Compose 项目的文件夹（输入编号）: " choice

    # 检查用户输入是否为有效的编号
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#folders[@]} ]; then
        echo "无效选择，请输入有效的编号。" >&2
        return 1
    fi

    # 获取用户选择的文件夹
    selected_folder=${folders[$((choice-1))]}

    # 输出选择的文件夹路径
    cd "$selected_folder" || {
        echo "无法进入目录 $selected_folder，请检查路径是否正确。" >&2
        exit 1
    }
}

select_container() {
    local prompt="$1"
    local selected_container=""
    local containers=($(docker ps --format "{{.Names}}"))

    if [ ${#containers[@]} -eq 0 ]; then
        echo "没有正在运行的Docker容器。" >&2
        return 1
    fi

    echo "可用的容器：" >&2
    for i in "${!containers[@]}"; do
        echo "$((i + 1)). ${containers[$i]}" >&2
    done
    echo >&2

    while true; do
        read -p "$prompt (输入数字或容器名称): " input

        if [ -z "$input" ]; then
            continue
        fi

        if [[ "$input" =~ ^[0-9]+$ ]]; then
            if ((input > 0 && input <= ${#containers[@]})); then
                selected_container="${containers[$((input-1))]}"
                break
            else
                echo "输入的数字无效，请输入 1 到 ${#containers[@]} 之间的数字。" >&2
            fi
        elif [[ " ${containers[@]} " =~ " ${input} " ]]; then
            selected_container="$input"
            break
        else
            echo "无效的输入。请从下面的列表中选择。" >&2
            echo "可用的容器：" >&2
            for i in "${!containers[@]}"; do
                echo "$((i + 1)). ${containers[$i]}" >&2
            done
            echo >&2
        fi
    done

    echo "$selected_container"
}
