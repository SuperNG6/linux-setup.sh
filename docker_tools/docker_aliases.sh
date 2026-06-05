#!/bin/bash

# ==============================================================================
#
#                         群晖 Docker & Compose 别名配置
#
#  说明:
#  此脚本用于定义一系列简化的别名，方便操作 Docker。
#  它会首先加载 'docker_functions.sh' 文件中的所有功能函数。
#
#  使用方法:
#  在您的 .bashrc 或 .profile 文件中添加以下行来加载此脚本:
#  if [ -f /path/to/your/docker_aliases.sh ]; then
#      source /path/to/your/docker_aliases.sh
#  fi
#
# ==============================================================================

# 定义函数库文件的路径 (请根据您的实际情况修改)
FUNCTIONS_FILE="/volume5/docker/docker_tools/docker_functions.sh"

# 加载功能函数库
if [ -f "$FUNCTIONS_FILE" ]; then
    # shellcheck disable=SC1090
    . "$FUNCTIONS_FILE"
else
    echo "警告: Docker 功能函数库未找到: $FUNCTIONS_FILE"
    return
fi

# --- 定义别名 ---

# Docker Compose 相关别名
alias dc='run_compose_command'      # 执行任意 docker-compose 命令, e.g., dc up -d
alias dcps='run_compose_ps'         # 显示 compose 项目状态
alias dclogs='run_compose_logs'     # 查看 compose 项目日志
alias dcs='run_compose_stats'       # 查看 compose 项目资源占用
alias dcr='run_compose_restart'     # 重启 compose 项目 (dcr R 为完全重建)

# 单个容器相关别名
unalias dlogs dexec 2>/dev/null || true

dlogs() {
    run_container_logs "$@"
}

dexec() {
    run_container_exec "$@"
}

alias dr='run_container_restart'    # 选择并重启容器

# 系统工具别名
alias dcip='run_ip_update'          # 更新 /etc/hosts 文件
alias dspa='sudo docker system prune -a' # 清理所有未使用的 Docker 资源

# 其他常用别名
alias dps='sudo docker ps -a'
alias di='sudo docker images'

if [ -n "${BASH_VERSION:-}" ] && command -v complete >/dev/null 2>&1; then
    eval '
_DOCKER_TOOLS_COMPLETION_USE_SUDO=0
_DOCKER_TOOLS_COMPLETION_JUST_AUTH=0
_DOCKER_TOOLS_CONTAINER_LIST=""

_docker_tools_load_container_list() {
    _DOCKER_TOOLS_COMPLETION_JUST_AUTH=0
    _DOCKER_TOOLS_CONTAINER_LIST=""

    if [ "${_DOCKER_TOOLS_COMPLETION_USE_SUDO:-0}" != "1" ]; then
        _DOCKER_TOOLS_CONTAINER_LIST=$(docker ps --format "{{.Names}}" 2>/dev/null || true)
        if [ -n "$_DOCKER_TOOLS_CONTAINER_LIST" ]; then
            return 0
        fi
    fi

    if sudo -n true 2>/dev/null; then
        _DOCKER_TOOLS_COMPLETION_USE_SUDO=1
    else
        if tty >/dev/null 2>&1; then
            printf "\n需要 sudo 权限获取 Docker 容器列表，请输入密码。\n" >/dev/tty
        fi
        if sudo -v; then
            _DOCKER_TOOLS_COMPLETION_USE_SUDO=1
            _DOCKER_TOOLS_COMPLETION_JUST_AUTH=1
        else
            return 1
        fi
    fi

    _DOCKER_TOOLS_CONTAINER_LIST=$(sudo docker ps --format "{{.Names}}" 2>/dev/null || true)
    return 0
}

_docker_tools_print_completion_candidates() {
    local candidates="$1"
    if [ -n "$candidates" ]; then
        printf "\n%s\n" "$candidates" >/dev/tty 2>/dev/null || true
    fi
}

_docker_tools_container_names() {
    local current="${COMP_WORDS[COMP_CWORD]}"
    local name candidate index candidates
    _docker_tools_load_container_list || return 0
    compopt -o nosort 2>/dev/null || true
    COMPREPLY=()
    candidates=""
    index=1
    for name in $_DOCKER_TOOLS_CONTAINER_LIST; do
        candidate="${index}. ${name}"
        if [ -z "$current" ] || [[ "$candidate" == "$current"* ]] || [[ "$name" == "$current"* ]] || [[ "$index" == "$current"* ]]; then
            COMPREPLY+=("$candidate")
            if [ -z "$candidates" ]; then
                candidates="$candidate"
            else
                candidates="${candidates}
${candidate}"
            fi
        fi
        index=$((index + 1))
    done
    if [ "${_DOCKER_TOOLS_COMPLETION_JUST_AUTH:-0}" = "1" ]; then
        _docker_tools_print_completion_candidates "$candidates"
        COMPREPLY=()
    fi
}

complete -F _docker_tools_container_names dlogs dexec
'
fi

# echo "Docker 工具别名已加载。"
