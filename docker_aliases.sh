#!/bin/bash

alias nginx="docker exec -i docker_nginx nginx"
alias docker-compose="docker compose"
alias dc="docker-compose"
alias dspa="docker system prune -a"
alias dcs="docker-compose ps -q | xargs docker stats"
alias dcps="docker ps \$((docker-compose ps -q  || echo "#") | while read line; do echo "--filter id=\$line"; done)"
alias dcip="bash /root/.docker_tools/dcip.sh"
alias dlogs="bash /root/.docker_tools/dlogs.sh"
