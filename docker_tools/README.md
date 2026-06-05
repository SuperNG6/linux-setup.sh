# Synology Docker Tools

这是一套给群晖 NAS 使用的 Docker / Docker Compose 快捷命令。

默认安装目录按群晖常见路径设计为：

```bash
/volume5/docker/docker_tools
```

如果你放在其他目录，需要修改 `docker_aliases.sh` 里的 `FUNCTIONS_FILE` 路径。

## 文件

| 文件 | 说明 |
| :--- | :--- |
| `docker_aliases.sh` | 别名、函数入口和 `dlogs` / `dexec` 补全 |
| `docker_functions.sh` | Docker 和 Docker Compose 的实际操作函数 |

## 安装

把 `docker_tools` 目录放到群晖上：

```bash
/volume5/docker/docker_tools
```

确保脚本可读：

```bash
chmod +x /volume5/docker/docker_tools/*.sh
```

在 `~/.profile`、`~/.bashrc` 或你实际使用的 shell 初始化文件中加入：

```bash
if [ -f /volume5/docker/docker_tools/docker_aliases.sh ]; then
    source /volume5/docker/docker_tools/docker_aliases.sh
fi
```

重新登录 SSH，或手动加载：

```bash
source /volume5/docker/docker_tools/docker_aliases.sh
```

## 命令

| 命令 | 功能 |
| :--- | :--- |
| `dc <参数...>` | 在当前或子目录中的 Compose 项目里执行 `docker-compose <参数...>` |
| `dcps` | 查看 Compose 项目容器状态 |
| `dclogs` | 查看 Compose 项目日志 |
| `dcs` | 查看 Compose 项目容器资源占用 |
| `dcr` | 快速重启 Compose 项目 |
| `dcr R` / `dcr -R` | 完全重建 Compose 项目，执行 `down` 后再 `up -d` |
| `dlogs` | 选择容器并查看日志 |
| `dlogs <编号/容器名>` | 直接查看指定容器日志 |
| `dr` | 选择并重启容器 |
| `dexec` | 选择容器并进入 shell |
| `dexec <编号/容器名>` | 直接进入指定容器 shell |
| `dcip` | 将运行中容器的 IP 写入 `/etc/hosts` |
| `dspa` | 清理未使用的 Docker 资源 |
| `dps` | 查看所有容器 |
| `di` | 查看镜像 |

## 容器补全

`dlogs` 和 `dexec` 支持容器名补全：

```bash
dlogs <Tab>
dexec <Tab>
```

候选格式是：

```text
1. container-name
2. another-container
```

这几种输入都支持：

```bash
dlogs 1
dlogs container-name
dlogs '1. container-name'

dexec 1
dexec container-name
dexec '1. container-name'
```

编号顺序与 `docker ps --format '{{.Names}}'` 的输出顺序一致。

补全功能只在 bash 中加载。群晖默认 `sh` 下可以正常使用 `dlogs` / `dexec` 命令，但不会加载 Tab 补全。

## 注意

- 这些函数默认通过 `sudo docker` 和 `sudo docker-compose` 执行。
- Tab 补全会先尝试 `docker ps`，失败后再尝试 `sudo -n docker ps`，避免补全时卡在 sudo 密码输入。
- `docker_aliases.sh` 是给 bash `source` 的，不建议直接执行。
