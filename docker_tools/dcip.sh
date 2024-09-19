#!/bin/bash

# 检查是否以 root 用户执行脚本
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 用户执行该脚本"
    exit
fi

# 检查 Docker 是否运行
if ! systemctl is-active --quiet docker; then
    echo "Docker 服务未运行，请启动 Docker"
    exit
fi

# 定义 hosts 文件路径
HOSTS_FILE="/etc/hosts"
# 定义注释开始和结束标记
COMMENT_START="# BEGIN Docker container IPs"
COMMENT_END="# END Docker container IPs"

# 使用 mktemp 创建临时文件并检查是否成功
TMP_FILE=$(mktemp)
if [ ! -f "$TMP_FILE" ]; then
    echo "无法创建临时文件"
    exit
fi

echo "获取 Docker 容器的 IP 地址..."

# 遍历所有 Docker 容器
docker ps -q | while read -r id; do
    # 获取容器名称
    container_name=$(docker inspect -f '{{ .Name }}' "$id" | sed 's/^\///')
    # 获取容器所有网络接口的 IP 地址
    container_ips=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$id")
    for ip in $container_ips; do
        # 判断容器名称和 IP 地址是否为空
        if [[ -n "$container_name" ]] && [[ -n "$ip" ]]; then
            echo "添加 $ip 对应的 $container_name"
            # 将容器 IP 地址和名称添加到临时文件中
            echo -e "$ip\t$container_name" >>"$TMP_FILE"
        fi
    done
done

# 检查临时文件是否非空
if [[ -s "$TMP_FILE" ]]; then
    echo "更新 $HOSTS_FILE"
    # 删除原有的 Docker 容器 IP 地址信息，并将新的信息添加到 hosts 文件中
    sed -i "/$COMMENT_START/,/$COMMENT_END/d" "$HOSTS_FILE"
    echo -e "\n$COMMENT_START\n$(cat $TMP_FILE)\n$COMMENT_END\n" >>"$HOSTS_FILE"
    echo "更新完成"
else
    echo "未找到 Docker 容器"
fi

# 删除临时文件
rm "$TMP_FILE"
