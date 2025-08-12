#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# 引用docker_utils脚本
source "${SCRIPT_DIR}/docker_utils.sh"

# 选择容器并获取容器名
container=$(select_container "请选择要进入的容器：")

echo "正在尝试进入容器 ${container}..."

# 1. 检查 'bash' 是否存在于容器中
# 我们使用 `docker exec ... which` 命令，并将其输出重定向到 /dev/null
# 这样可以安静地检查命令是否存在，我们只关心它的退出状态码
if docker exec "${container}" which bash &>/dev/null; then
    echo "找到 'bash', 正在进入..."
    docker exec -it "${container}" bash

# 2. 如果 'bash' 不存在, 则检查 'sh'
elif docker exec "${container}" which sh &>/dev/null; then
    echo "未找到 'bash', 但找到了 'sh', 正在进入..."
    docker exec -it "${container}" sh

# 3. 如果 'bash' 和 'sh' 都不存在
else
    echo "错误：在容器 ${container} 中未找到 'bash' 或 'sh'。无法进入容器。"
    exit 1
fi

# 检查上一个 exec 命令的退出状态码
if [ $? -ne 0 ]; then
    echo "已退出容器 ${container}."
fi