#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# 引用docker_utils脚本
source "${SCRIPT_DIR}/docker_utils.sh"

# 版本监测
check_docker_compose_version
# 文件夹选择
select_docker_compose_dir

# 显示docker-compose信息
echo "正在检查 $selected_folder 的 $compose_cmd 容器信息..."
$compose_cmd ps

# 检查命令是否执行成功
if [ $? -ne 0 ]; then
    exit 1
fi
