#!/bin/bash

# 检测docker compose的版本，并设置compose_cmd变量
check_docker_compose_version() {
    if command -v docker compose &>/dev/null; then
        compose_cmd="docker compose"
    elif command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
    else
        exit 1
    fi
}

# 执行版本检测
check_docker_compose_version
