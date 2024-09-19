#!/bin/bash

# 引用docker_compose_utils脚本
source /root/.docker_tools/docker_compose_utils.sh
# 版本监测
check_docker_compose_version

# 设置默认重启模式
RESTART_MODE="-r"

# 解析命令行参数
while getopts "rR" opt; do
  case ${opt} in
    r )
      RESTART_MODE="-r"
      ;;
    R )
      RESTART_MODE="-R"
      ;;
    \? )
      echo "用法: $0 [-r] [-R]"
      echo "  -r: 快速重启 (默认, 使用 $compose_cmd restart)"
      echo "  -R: 完全重建 (使用 $compose_cmd down 和 up)"
      exit 1
      ;;
  esac
done

# 文件夹选择
select_docker_compose_dir

# 执行重启
if [ "$RESTART_MODE" = "-r" ]; then
    echo "执行快速重启..."
    $compose_cmd restart
else
    echo "执行完全重建..."
    $compose_cmd down && $compose_cmd up -d
fi

if [ $? -eq 0 ]; then
    echo "容器已成功重启。"
else
    echo "重启容器时出错。"
    exit 1
fi