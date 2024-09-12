#!/bin/bash

# 引用compose_cmd检测脚本
source /root/.docker_tools/docker_compose_cmd.sh

# 检查当前目录是否包含docker-compose.yml或docker-compose.yaml
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    echo "当前目录包含 docker-compose 配置文件，正在显示容器状态..."
    $compose_cmd stats
    if [ $? -ne 0 ]; then
        exit 1
    fi
    exit 0
fi

# 初始化一个数组来存储包含docker-compose.yml或docker-compose.yaml的子文件夹
folders=()

# 遍历当前目录下的一层子目录
for dir in */; do
    # 检查子目录中是否有docker-compose.yml或docker-compose.yaml文件
    if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
        folders+=("$dir")
    fi
done

# 检查是否找到至少一个有效的子目录
if [ ${#folders[@]} -eq 0 ]; then
    echo "当前目录下以及子文件夹中没有找到 $compose_cmd 配置文件。"
    exit 1
fi

# 显示找到的文件夹并编号
echo "找到以下子文件夹包含 $compose_cmd 配置文件："
for i in "${!folders[@]}"; do
    echo "$((i+1)). ${folders[$i]}"
done

# 提示用户选择文件夹
read -p "请选择要查看 $compose_cmd 状态的文件夹（输入编号）: " choice

# 检查用户输入是否为有效的编号
if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#folders[@]} ]; then
    echo "无效选择，请输入有效的编号。"
    exit 1
fi

# 获取用户选择的文件夹
selected_folder=${folders[$((choice-1))]}

# 进入用户选择的文件夹
cd "$selected_folder" || {
    echo "无法进入目录 $selected_folder，请检查路径是否正确。"
    exit 1
}

# 显示$compose_cmd状态
echo "正在检查 $selected_folder 的 $compose_cmd 容器状态..."
$compose_cmd stats

# 检查命令是否执行成功
if [ $? -ne 0 ]; then
    exit 1
fi
