<div align="center">

# **Linux 服务器一键配置与优化脚本**

**一个我为自己编写，并持续迭代的服务器自动化工具箱。**

</div>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu%20%7C%20CentOS%20%7C%20Fedora-blue" alt="平台兼容性徽章">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="许可证徽章">
  <a href="https://github.com/SuperNG6/linux-setup.sh">
    <img src="https://img.shields.io/github/stars/SuperNG6/linux-setup.sh?style=social" alt="GitHub stars">
  </a>
</p>

---

这个脚本最初是为了解决我每次配置新服务器时，都要重复执行大量相同命令的烦恼。随着不断地打磨，它已经演变成一个高度自动化和智能化的工具，核心设计在于解决配置过程中的“痛点”。

-   **环境自适应，而非写死命令**
    我不想为每个发行版都维护一个分支。因此，脚本内置了环境检测机制，能自动识别你的操作系统（Debian/Ubuntu, CentOS, Fedora, Arch）和防火墙（UFW, Firewalld, iptables, nftables）。只管选择功能，脚本会用最适合当前环境的方式去执行。

-   **性能优化，而非无脑复制**
    网上很多优化方案都是直接复制粘贴一堆参数，但每个服务器的网络环境都不同。我的优化脚本会引导你输入服务器的实际延迟和带宽，**动态计算带宽延迟积（BDP）**，为每一台服务器量身定制 TCP 缓冲区大小。这才是真正有效的优化。

-   **模块化与自动化，而非一把梭**
    复杂的、独立的功能（如内核管理）被我拆分成了独立的模块化脚本。主脚本负责调度，子脚本负责执行。比如 XanMod 内核安装，它会 **全自动地从官网发现、下载并匹配** 最适合你 CPU 的版本，你无需进行任何手动查找。

---
## 🚀 主要功能

<strong>Ⅰ. 基础环境 & 安全设置</strong>

| 图标 | 功能 | 描述 |
| :--: | :--- | :--- |
| 📦 | **安装常用组件** | 一键装好 Docker, Fail2ban 等我常用的东西，省得一个个 `apt install` 了。 |
| 🔑 | **添加 SSH 公钥** | 把你的公钥加进去，以后就能免密登录，方便又安全。 |
| 🛡️ | **关闭密码登录** | 安全第一。关掉密码登录，只用密钥，能防掉绝大多数脚本小子。 |
| 🚪 | **修改 SSH 端口** | 默认的 22 端口天天被扫，换个不常用的清净点。 |
| 🔥 | **统一防火墙管理** | 自动识别并适配防火墙，提供统一的端口操作界面。 |
| 🐳 | **添加 Docker 工具脚本** | 装一套我写的 Docker 别名，比如 `dclogs`、`dcip`，用起来顺手多了。 |
| 🌐 | **配置公共 DNS** | 换上 CF 和谷歌的 DNS，解析又快又稳。 |


<strong>Ⅱ. 性能 & 资源优化</strong>

| 图标 | 功能 | 描述 |
| :--: | :--- | :--- |
| 💾 | **设置 Swap** | 小内存 VPS 救星。搞个 Swap，防止内存一满就死机。 |
| ⚡ | **配置 ZRAM** | Swap 的 Pro Max 版。在内存里搞压缩交换，速度飞快，高负载下体验提升明显。 |
| 📊 | **修改 Swappiness** | 让系统别那么爱用 Swap，物理内存多的时候就别去碰硬盘了。 |
| 🧹 | **清理 Swap 缓存** | 手动把 Swap 里的东西倒回内存，看着清爽。 |
| 🚀 | **优化内核参数** | 启用 BBR+FQ_PIE，并根据你的网络环境动态计算 BDP，量身定制内核参数优化方案。 |


<strong>Ⅲ. 内核管理 (Debian/Ubuntu 专属)</strong>

| 图标 | 功能 | 描述 |
| :--: | :--- | :--- |
| ⚙️ | **装/卸 XanMod 内核** | 自动从官网拉最新的 LTS 内核，还能根据你的 CPU 选 v2/v3/v4 优化版。 |
| ☁️ | **装/卸 Cloud 内核** | Debian 官方的 Cloud 内核，更轻量，占用内存少，跑服务器挺合适。 |

---

### **：Docker 工具箱使用说明 🐳**

| 命令 | 原始命令 | 功能说明 |
| :--- | :--- | :--- |
| `nginx` | `docker nginx ...` | 快捷执行 `docker nginx` 相关命令。 |
| `dc` | `docker-compose` | `docker-compose` 的缩写，核心提效工具。 |
| `dlogs <容器>` | `docker logs -f <容器>` | 实时追踪指定容器的日志。 |
| `dclogs <服务>` | `docker-compose logs -f <服务>` | 实时追踪指定 Compose 服务的日志。 |
| `dcs` | `docker-compose ps` | 查看 Compose 项目中各个服务的状态。 |
| `dcps` | `docker-compose stats` | 查看 Compose 项目中各个服务的cpu ram 使用情况 |
| `dr <容器>` | `docker restart <容器>` | 快速重启单个 Docker 容器。 |
| `dcr [-r/-R] <服务>` | `docker-compose restart/up -d --force-recreate <服务>` | 重启 Compose 服务。`-r` 普通重启，`-R` 则强制重建。 |
| `dexec <容器>` | `docker exec -it <容器> /bin/bash` | 快速进入指定容器的 Shell 环境，方便调试。 |
| `dspa` | `docker system prune -af` | 一键清理所有不再使用的镜像、容器、网络，释放磁盘空间。 |
| `dcip` | (自定义函数) | 遍历所有容器 IP，并自动添加到宿主机的 `/etc/hosts`，让你能直接通过容器名 `ping` 通或访问。 |

---
## 快速上手

请使用 `root` 或具有 `sudo` 权限的用户执行：

```bash
/bin/bash <(wget -qO - [https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/server-setup.sh](https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/server-setup.sh))
````

**备用链接与国内加速:**

```bash
# 短链接
/bin/bash <(wget -qO - bit.ly/ls-set)
/bin/bash <(wget -qO - [https://tinyurl.com/server-setup](https://tinyurl.com/server-setup))

# 国内服务器专用加速
/bin/bash <(wget -qO - [https://mirror.ghproxy.com/https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/server-setup.sh](https://mirror.ghproxy.com/https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/server-setup.sh))
```

启动后，根据菜单提示输入数字选择相应功能即可。

## 注意事项 ⚠️

  - **权限**: 脚本需要 `root` 权限才能进行系统级修改。
  - **安全操作**: 修改 SSH 端口、禁用密码登录等操作不可逆，请在操作前确保你已有新的、可靠的连接方式。
  - **反馈**: 如果你觉得这个脚本对你有帮助，或者发现了 Bug，欢迎来 [GitHub Issues](https://github.com/SuperNG6/linux-setup.sh/issues) 给我提建议！
