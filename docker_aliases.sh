#!/bin/bash
# 引用compose_cmd检测脚本
source /root/.docker_tools/docker_compose_cmd.sh

alias nginx="docker exec -i docker_nginx nginx"
alias dc="$compose_cmd"
alias dspa="docker system prune -a"
alias dcs="bash /root/.docker_tools/dcstats.sh"
alias dcps="bash /root/.docker_tools/dcps.sh"
alias dcip="bash /root/.docker_tools/dcip.sh"
alias dlogs="bash /root/.docker_tools/dlogs.sh"
alias dr="bash /root/.docker_tools/drestart.sh"