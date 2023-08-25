# 自用Linux服务器配置优化脚本

适用于Debian10、11、12  
Ubuntu请自测，目测兼容  
CentOS、Fedora 和 Arch Linux 请自测，已做兼容处理，未测试，并且不支持XanMod内核  

```markdown
# 介绍

这是一个用于在Linux系统上执行一系列设置操作的脚本。它可以帮助完成一些常见的配置任务，如安装必要组件、添加SSH公钥、关闭SSH密码登录、设置虚拟内存等。此外，还提供了优化内核参数和下载安装XanMod内核的选项。

# 功能说明

## 选项 1：安装必要组件

选择此选项可以安装一些关键的组件，组件包括 Docker、Docker Compose、Fail2Ban、Vim和Curl。在选择此选项后，脚本会自动更新软件包列表并安装这些组件。

## 选项 2：添加已登记设备的公钥

使用此选项，可以将已登记设备的SSH公钥添加到系统的授权密钥文件中。脚本会要求输入公钥，然后检查格式和有效性。公钥将追加到`~/.ssh/authorized_keys`文件中。

## 选项 3：关闭SSH密码登录

选择此选项将禁用SSH的密码登录功能，增强系统的安全性。脚本将在`/etc/ssh/sshd_config`文件中设置`PasswordAuthentication no`，然后重新启动SSH服务。

## 选项 4：添加docker工具脚本

使用此选项，可以为bash环境添加一些有用的别名，以便更方便地执行常用命令。这些别名包括对Docker、Docker Compose和其他一些命令的快捷方式。

    功能1、nginx命令=docker nginx
    功能2、dlogs命令=查看docker容器日志
    功能3、dc命令=docker-compose
    功能4、dcs命令=查看docker-compose容器状态（需要在compose.yml文件夹内执行）
    功能5、dcps命令=查看docker-compose容器（需要在compose.yml文件夹内执行）
    功能6、dcip命令=查看容器ip，并添加到宿主机hosts中

## 选项 5：设置虚拟内存

选择此选项可以配置系统的虚拟内存（交换空间）。可以选择预定义的虚拟内存大小（如256M、512M、1G等），或者手动输入值。脚本会创建交换文件，并在需要时更新`/etc/fstab`文件。

## 选项 6：修改swap使用阈值

选择此选项可以修改系统的swap使用阈值，即`vm.swappiness`值。可以输入0到100之间的值，其中0表示最少使用swap，100表示最常使用swap。

## 选项 7：优化内核参数

选择此选项将优化内核参数以提升系统性能。脚本会修改`/etc/sysctl.conf`文件，包括注释掉现有的`net.ipv4.tcp_fastopen`设置，添加或更新`net.ipv4.tcp_slow_start_after_idle`和`net.ipv4.tcp_notsent_lowat`设置，以及添加`net.core.default_qdisc=fq`和`net.ipv4.tcp_congestion_control=bbr`设置。

## 选项 8：下载并安装XanMod内核

选择此选项可以从GitHub下载并安装XanMod内核。脚本会下载预编译的内核deb文件，校验其MD5值，然后安装内核。还可以选择是否更新Grub引导配置。

## 选项 9：卸载XanMod内核，并恢复原有内核

选择此选项可以卸载XanMod内核，并恢复原有内核。

## 选项 10：修改SSH端口号

选择此选项可以卸修改SSH端口号。

## 选项 11：设置防火墙端口

选择此选项可以设置防火墙端口（少部分VPS需要该功能，如Vultr的ubuntu系统）。

```
## 使用方法

1. 使用终端进入到的Linux系统。
2. 运行脚本：
   ```bash
   /bin/bash <(wget -qO - bit.ly/ls-set)
   ```
   或
   ```bash
   /bin/bash <(wget -qO - https://tinyurl.com/server-setup)
   ```
   或
   ```bash
   /bin/bash <(wget -qO - https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/server-setup.sh)
   ```

   或者，也可以克隆整个仓库：

   ```bash
   git clone https://github.com/SuperNG6/linux-setup.sh.git
   ```

3. 给脚本文件添加执行权限：

   ```bash
   chmod +x server-setup.sh
   ```

4. 运行脚本：

   ```bash
   ./server-setup.sh
   ```

5. 根据菜单选项选择要执行的操作。每个选项都有相应的说明，按照提示操作即可。

## 注意事项

- 在执行脚本之前，请确保具有管理员权限。可以使用`sudo`命令运行脚本。

- 脚本执行过程中可能会对系统进行一些更改。请在理解脚本操作的情况下使用。

- 如果在脚本执行过程中遇到任何问题，请及时查看终端输出以获取更多信息。

- 如果对脚本有任何建议或反馈，请在项目仓库中提交Issue。


