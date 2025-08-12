#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# 引用docker_utils脚本
source "${SCRIPT_DIR}/docker_utils.sh"

# 版本监测
check_docker_compose_version
# 文件夹选择
select_docker_compose_dir

# 构建命令,将所有传入的参数添加到$compose_cmd后
full_command="$compose_cmd ${@}"

# 执行构建的命令
eval $full_command

# 检查命令是否执行成功
if [ $? -ne 0 ]; then
    exit 1
fi