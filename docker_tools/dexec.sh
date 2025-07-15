#!/bin/bash

# 获取正在运行的容器名
containers=($(docker ps --format "{{.Names}}"))

# 检查是否有正在运行的容器
if [ ${#containers[@]} -eq 0 ]; then
    echo "没有正在运行的Docker容器。"
    exit 1
fi

# 打印选项菜单
echo "请选择要进入的容器："
for i in "${!containers[@]}"; do
    echo "$((i + 1)). ${containers[$i]}"
done

# 读取用户输入
read -p "请输入数字选择容器: " choice

# 检查用户输入是否合法
if ! [[ "$choice" =~ ^[0-9]+$ ]] || ! ((choice > 0 && choice <= ${#containers[@]})); then
    echo "输入无效，请输入 1 到 ${#containers[@]} 之间的数字。"
    exit 1
fi

# 获取目标容器名
target_container="${containers[$((choice - 1))]}"
echo "正在尝试进入容器 ${target_container}..."

# 1. 检查 'bash' 是否存在于容器中
# 我们使用 `docker exec ... which` 命令，并将其输出重定向到 /dev/null
# 这样可以安静地检查命令是否存在，我们只关心它的退出状态码
if docker exec "${target_container}" which bash &>/dev/null; then
    echo "找到 'bash', 正在进入..."
    docker exec -it "${target_container}" bash

# 2. 如果 'bash' 不存在, 则检查 'sh'
elif docker exec "${target_container}" which sh &>/dev/null; then
    echo "未找到 'bash', 但找到了 'sh', 正在进入..."
    docker exec -it "${target_container}" sh

# 3. 如果 'bash' 和 'sh' 都不存在
else
    echo "错误：在容器 ${target_container} 中未找到 'bash' 或 'sh'。无法进入容器。"
    exit 1
fi

# 检查上一个 exec 命令的退出状态码
if [ $? -ne 0 ]; then
    echo "已退出容器 ${target_container}."
fi
