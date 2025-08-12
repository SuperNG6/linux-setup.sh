#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# 引用docker_utils脚本
source "${SCRIPT_DIR}/docker_utils.sh"

# 选择容器
container=$(select_container "请选择要重启的容器：")

# 执行docker restart命令
docker restart "$container"

echo "容器已重启"
