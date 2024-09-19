#!/bin/bash

# 引用docker_compose_utils脚本
source /root/.docker_tools/docker_compose_utils.sh
# 版本监测
check_docker_compose_version
# 文件夹选择
select_docker_compose_dir

# 显示$compose_cmd状态
echo "正在检查 $selected_folder 的 $compose_cmd 容器状态..."
$compose_cmd stats

# 检查命令是否执行成功
if [ $? -ne 0 ]; then
    exit 1
fi
