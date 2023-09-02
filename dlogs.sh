#!/bin/bash

# 获取正在运行的容器名
containers=($(docker ps --format "{{.Names}}"))

# 检查是否有正在运行的容器
if [ ${#containers[@]} -eq 0 ]; then
  echo "没有正在运行的Docker容器。"
  exit 1
fi


# 打印选项菜单
echo "请选择要查看日志的容器："
for i in "${!containers[@]}"; do
  echo "$((i+1)). ${containers[$i]}"
done

# 读取用户输入
read -p "请输入数字选择容器: " choice

# 检查用户输入是否合法
if ! [[ "$choice" =~ ^[1-9]+$ ]] || (( choice > ${#containers[@]} )); then
  echo "输入无效，请重新运行脚本并输入正确的数字。"
  exit 1
fi

# 执行docker命令查看日志
docker logs -f -n10 "${containers[$((choice-1))]}"

