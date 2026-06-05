# Synology Docker Tools

群晖 NAS 使用的 Docker / Docker Compose 快捷命令工具。

这个分支只放群晖版 Docker 工具代码，脚本目录是 `docker_tools/`。默认安装路径是 `/volume5/docker/docker_tools`。

## 功能

| 功能 | 说明 |
| :--- | :--- |
| Docker 容器操作 | 查看日志、进入容器、重启容器、查看容器列表和镜像 |
| Docker Compose 操作 | 自动选择 Compose 项目目录，查看状态、日志、资源占用，执行任意 Compose 命令 |
| 容器名补全 | `dlogs` 和 `dexec` 支持 Tab 补全，候选格式为 `1. 容器名` |
| 编号输入 | `dlogs 1`、`dexec 1` 可以直接选择 `docker ps` 列表里的第 1 个容器 |
| Hosts 更新 | 将运行中容器 IP 写入 `/etc/hosts`，方便用容器名访问 |
| sudo 兼容 | 命令默认使用 `sudo docker` / `sudo docker-compose`，补全首次需要权限时会触发 sudo 密码输入并打印候选 |

## 文件

| 文件 | 作用 |
| :--- | :--- |
| `docker_tools/docker_aliases.sh` | 定义命令别名、`dlogs` / `dexec` 函数和 bash 补全 |
| `docker_tools/docker_functions.sh` | Docker / Docker Compose 的实际执行函数 |

## 安装

| 步骤 | 命令或操作 |
| :--- | :--- |
| 1. 放置目录 | 将本分支的 `docker_tools` 目录放到 `/volume5/docker/docker_tools` |
| 2. 检查路径 | 如果不是这个路径，修改 `docker_tools/docker_aliases.sh` 里的 `FUNCTIONS_FILE` |
| 3. 设置权限 | `chmod +x /volume5/docker/docker_tools/*.sh` |
| 4. 加载脚本 | 在 `~/.profile`、`~/.bashrc` 或当前用户实际加载的 shell 配置文件中加入下面的加载代码 |
| 5. 生效 | 重新登录 SSH，或执行 `. /volume5/docker/docker_tools/docker_aliases.sh` |

加载代码：

```bash
if [ -f /volume5/docker/docker_tools/docker_aliases.sh ]; then
    . /volume5/docker/docker_tools/docker_aliases.sh
fi
```

## 命令

| 命令 | 实际行为 | 用法 |
| :--- | :--- | :--- |
| `dc <参数...>` | 在 Compose 项目目录中执行 `sudo docker-compose <参数...>` | `dc up -d`、`dc pull` |
| `dcps` | 查看 Compose 项目容器状态 | `dcps` |
| `dclogs` | 查看 Compose 项目日志，默认 `logs -f --tail 100` | `dclogs` |
| `dcs` | 查看 Compose 项目容器资源占用 | `dcs` |
| `dcr` | 快速重启 Compose 项目，执行 `docker-compose restart` | `dcr` |
| `dcr R` / `dcr -R` | 完全重建 Compose 项目，执行 `down` 后再 `up -d` | `dcr R` |
| `dlogs` | 选择容器并查看日志 | `dlogs` |
| `dlogs <编号>` | 按 `docker ps` 顺序查看指定编号容器日志 | `dlogs 1` |
| `dlogs <容器名>` | 直接查看指定容器日志 | `dlogs docker_nginx` |
| `dexec` | 选择容器并进入 shell，优先 `bash`，没有则用 `sh` | `dexec` |
| `dexec <编号>` | 按 `docker ps` 顺序进入指定编号容器 | `dexec 1` |
| `dexec <容器名>` | 直接进入指定容器 | `dexec docker_nginx` |
| `dr` | 选择容器并重启 | `dr` |
| `dcip` | 获取运行中容器 IP，并更新 `/etc/hosts` | `dcip` |
| `dspa` | 清理未使用的 Docker 资源，执行 `sudo docker system prune -a` | `dspa` |
| `dps` | 查看所有容器，执行 `sudo docker ps -a` | `dps` |
| `di` | 查看镜像，执行 `sudo docker images` | `di` |

## Compose 目录选择

| 场景 | 行为 |
| :--- | :--- |
| 当前目录有 `docker-compose.yml` 或 `docker-compose.yaml` | 直接使用当前目录 |
| 当前目录没有 Compose 文件，但子目录中只有一个 Compose 项目 | 自动进入这个子目录 |
| 当前目录没有 Compose 文件，但子目录中有多个 Compose 项目 | 列出编号，手动选择要操作的项目 |
| 当前目录和子目录都没有 Compose 文件 | 输出错误并退出 |

## 容器补全

| 输入 | 行为 |
| :--- | :--- |
| `dlogs <Tab>` | 补全运行中的容器，候选格式为 `1. 容器名` |
| `dexec <Tab>` | 补全运行中的容器，候选格式为 `1. 容器名` |
| 第一次 Tab 时没有 Docker 权限 | 触发 `sudo -v`，输入密码后立即打印候选；后续 Tab 使用 sudo 缓存，不再重复提示 |
| `dlogs 1` | 使用 `docker ps --format '{{.Names}}'` 输出里的第 1 个容器 |
| `dlogs '1. 容器名'` | 支持直接使用补全候选文本执行命令 |
| `dexec 1` | 使用 `docker ps --format '{{.Names}}'` 输出里的第 1 个容器 |
| `dexec '1. 容器名'` | 支持直接使用补全候选文本执行命令 |

补全只在 bash 中加载。群晖默认 `sh` 下可以正常使用 `dlogs` / `dexec` 命令，但不会加载 Tab 补全。

## 注意

| 项目 | 说明 |
| :--- | :--- |
| Shell | 推荐在 bash 中使用，Tab 补全依赖 bash completion |
| sudo | 脚本默认通过 `sudo docker` 和 `sudo docker-compose` 执行 |
| 路径 | 默认函数库路径是 `/volume5/docker/docker_tools/docker_functions.sh` |
| 直接执行 | `docker_aliases.sh` 是给 shell 加载的，不建议直接执行 |
