#!/bin/bash

#================================================================================
#
#   Linux 服务器一键配置与优化脚本
#
#   作者: SuperNG6
#   GitHub: https://github.com/SuperNG6/linux-setup.sh
#
#================================================================================

# --- 全局变量和初始化 ---

# 脚本启动时检查一次防火墙类型，并存入全局变量，避免重复执行
# 后续所有防火墙操作都将依赖此变量
FIREWALL_TYPE=""

# 脚本启动时检查一次操作系统类型，并存入全局变量
OS_TYPE=""

# --- 基础检查与环境设置 ---

# 检查是否具有足够的权限
if [ "$(id -u)" != "0" ]; then
	echo "错误：此脚本需要管理员权限，请使用 'sudo' 或以 'root' 用户身份运行。"
	exit 1
fi

# 获取操作系统发行版信息
# @return {string} 返回 "Debian/Ubuntu", "CentOS", "Fedora", "Arch" 或 "Unknown"
get_os_info() {
	# 优先使用 /etc/os-release，这是现代 Linux 发行版的标准
	if [ -f /etc/os-release ]; then
		# source 命令会把文件中的 key=value 格式的行作为变量导入
		source /etc/os-release
		case $ID in
		debian | ubuntu)
			echo "Debian/Ubuntu"
			;;
		centos)
			echo "CentOS"
			;;
		fedora)
			echo "Fedora"
			;;
		arch)
			echo "Arch"
			;;
		*)
			echo "Unknown"
			;;
		esac
	# 作为备用方案，检查特定发行版的文件
	elif [ -f /etc/centos-release ]; then
		echo "CentOS"
	elif [ -f /etc/fedora-release ]; then
		echo "Fedora"
	elif [ -f /etc/arch-release ]; then
		echo "Arch"
	else
		echo "Unknown"
	fi
}

# 根据服务器IP地址的地理位置（是否在中国）设置镜像和下载参数
set_mirror() {
	# 使用 ipinfo.io 查询公网 IP 和国家代码
	local country
	country=$(curl -s ipinfo.io/country)

	if [ "$country" = "CN" ]; then
		# 为 GitHub 和 Docker 设置国内加速镜像
		YES_CN="https://ghfast.top/"
		ACC="--mirror AzureChinaCloud"
		echo "检测到服务器位于中国，已启用加速镜像。"
	else
		YES_CN=""
		ACC=""
		echo "服务器不在中国，将使用默认源。"
	fi
}

# --- 防火墙管理模块 (核心重构部分) ---

# 检查系统中安装并激活了哪种防火墙管理工具
# @return {string} 返回 "ufw", "firewalld", "iptables", "nftables" 或 "unknown"
check_firewall() {
	if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
		echo "ufw"
	elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
		echo "firewalld"
	elif command -v iptables &>/dev/null; then
		# iptables 较为特殊，它始终存在，作为 nftables 的后端。
		# 这里我们通过检查 nft 是否存在来优先判断 nftables。
		if command -v nft &>/dev/null && systemctl is-active --quiet nftables; then
			echo "nftables"
		else
			echo "iptables"
		fi
	elif command -v nft &>/dev/null && systemctl is-active --quiet nftables; then
		echo "nftables"
	else
		echo "unknown"
	fi
}

# [适配器] 开放指定端口
# 这是一个抽象函数，它将根据全局变量 $FIREWALL_TYPE 调用正确的底层命令。
# @param {string} $1 - 端口号
# @param {string} $2 - 协议 (tcp 或 udp)
firewall_open_port() {
	local port=$1
	local protocol=$2

	if [[ -z "$port" || -z "$protocol" ]]; then
		echo "错误: 开放端口需要提供端口号和协议。" >&2
		return 1
	fi

	echo "正在为 [$FIREWALL_TYPE] 开放端口 $port/$protocol..."

	case $FIREWALL_TYPE in
	"ufw")
		ufw allow "$port/$protocol" >/dev/null
		;;
	"firewalld")
		firewall-cmd --zone=public --add-port="$port/$protocol" --permanent >/dev/null
		firewall-cmd --reload >/dev/null
		;;
	"iptables")
		iptables -A INPUT -p "$protocol" --dport "$port" -j ACCEPT
		# 尝试持久化规则
		if command -v iptables-save &>/dev/null && [ -d /etc/iptables/ ]; then
			iptables-save >/etc/iptables/rules.v4
		elif command -v service &>/dev/null; then
			service iptables save &>/dev/null
		fi
		;;
	"nftables")
		nft add rule inet filter input "$protocol" dport "$port" accept
		# 尝试持久化规则
		if [ -f /etc/nftables.conf ]; then
			nft list ruleset >/etc/nftables.conf
		fi
		;;
	*)
		echo "错误：不支持的防火墙类型 '$FIREWALL_TYPE' 或未安装防火墙。" >&2
		return 1
		;;
	esac

	if [ $? -eq 0 ]; then
		echo "成功开放端口 $port/$protocol。"
	else
		echo "错误：开放端口 $port/$protocol 失败。" >&2
		return 1
	fi
}

# [适配器] 关闭指定端口
# 这是一个抽象函数，它将根据全局变量 $FIREWALL_TYPE 调用正确的底层命令。
# @param {string} $1 - 端口号
# @param {string} $2 - 协议 (tcp 或 udp)
firewall_close_port() {
	local port=$1
	local protocol=$2

	if [[ -z "$port" || -z "$protocol" ]]; then
		echo "错误: 关闭端口需要提供端口号和协议。" >&2
		return 1
	fi

	echo "正在为 [$FIREWALL_TYPE] 关闭端口 $port/$protocol..."

	case $FIREWALL_TYPE in
	"ufw")
		# 正确的 ufw 操作是删除已有的 allow 规则，而不是添加 deny 规则
		ufw delete allow "$port/$protocol" >/dev/null
		;;
	"firewalld")
		firewall-cmd --zone=public --remove-port="$port/$protocol" --permanent >/dev/null
		firewall-cmd --reload >/dev/null
		;;
	"iptables")
		# -D 表示删除规则
		iptables -D INPUT -p "$protocol" --dport "$port" -j ACCEPT
		# 尝试持久化规则
		if command -v iptables-save &>/dev/null && [ -d /etc/iptables/ ]; then
			iptables-save >/etc/iptables/rules.v4
		elif command -v service &>/dev/null; then
			service iptables save &>/dev/null
		fi
		;;
	"nftables")
		# nftables 删除规则需要先找到规则的 handle
		local handle=$(nft -a list ruleset | grep "dport $port" | grep "$protocol" | grep "accept" | awk '{print $NF}')
		if [ -n "$handle" ]; then
			nft delete rule inet filter input handle "$handle"
			# 尝试持久化规则
			if [ -f /etc/nftables.conf ]; then
				nft list ruleset >/etc/nftables.conf
			fi
		else
			echo "警告：在 nftables 中未找到匹配的规则来关闭端口 $port/$protocol。"
			return 1
		fi
		;;
	*)
		echo "错误：不支持的防火墙类型 '$FIREWALL_TYPE' 或未安装防火墙。" >&2
		return 1
		;;
	esac

	if [ $? -eq 0 ]; then
		echo "成功关闭端口 $port/$protocol。"
	else
		echo "错误：关闭端口 $port/$protocol 失败。" >&2
		return 1
	fi
}

# [适配器] 显示当前所有开放的端口
# 使用更精确的命令来提取端口信息
display_open_ports() {
	echo "当前防火墙为: [$FIREWALL_TYPE]"
	echo "=========================================="
	echo "当前开放的防火墙端口:"

	case $FIREWALL_TYPE in
	"ufw")
		# 使用 --bare 选项获得更简洁的输出
		ufw status | grep "ALLOW"
		;;
	"firewalld")
		firewall-cmd --list-all
		;;
	"iptables")
		# 匹配 --dport 或 --dports 后面的端口号
		iptables -L INPUT -n --line-numbers | grep "ACCEPT" | grep -E 'dpt:|dports'
		;;
	"nftables")
		# 匹配 dport 后面的端口号
		nft list ruleset | grep "dport" | grep "accept"
		;;
	*)
		echo "找不到支持的防火墙，或防火墙未激活。"
		return 1
		;;
	esac
	echo "=========================================="
}

# --- 系统功能模块 ---

# 安装常用基础组件
install_components() {
	echo "此操作将安装: docker, docker-compose, fail2ban, vim, chrony, curl, rsync,, jq"
	read -p "是否继续？(y/n): " choice

	if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
		echo "取消安装。"
		return 1
	fi

	echo "正在安装必要组件..."

	local pkg_manager=""
	local update_cmd=""
	local install_cmd=""

	# 根据操作系统设置包管理器命令
	case $OS_TYPE in
	"Debian/Ubuntu")
		pkg_manager="apt"
		update_cmd="apt-get update -y"
		install_cmd="apt-get install -y"
		;;
	"CentOS")
		pkg_manager="yum"
		update_cmd="yum update -y"
		install_cmd="yum install -y"
		;;
	"Fedora")
		pkg_manager="dnf"
		update_cmd="dnf update -y"
		install_cmd="dnf install -y"
		;;
	"Arch")
		pkg_manager="pacman"
		update_cmd="pacman -Syu --noconfirm"
		install_cmd="pacman -S --noconfirm"
		;;
	*)
		echo "无法确定操作系统类型，无法安装组件。"
		return 1
		;;
	esac

	# 执行更新和安装
	echo "正在更新软件包列表..."
	$update_cmd || {
		echo "更新软件包列表失败"
		return 1
	}

	echo "正在安装 fail2ban chrony vim curl rsync jq..."
	$install_cmd fail2ban chrony vim curl rsync jq || {
		echo "安装基础组件失败"
		return 1
	}

	echo "校准系统时间..."
	chronyc tracking

	echo "其他组件安装成功，现在开始安装 Docker 和 Docker Compose。"

	# 使用加速镜像（如果已设置）安装 Docker
	local docker_url="https://get.docker.com"
	if [ -n "${ACC}" ]; then
		# 在国内使用 Docker 官方脚本时，通过 --mirror 选项指定镜像源
		bash <(curl -sSL "${docker_url}") "${ACC} --version 28" || {
			echo "使用镜像安装 Docker 失败"
			return 1
		}
	else
		bash <(curl -sSL "${docker_url}") --version 28 || {
			echo "安装 Docker 失败"
			return 1
		}
	fi

	echo "Docker 安装成功。"
	echo "所有组件安装完成。"
}

# 添加公钥到 authorized_keys，用于 SSH 免密登录
add_public_keys() {
	local authorized_keys_file backup_file
	local all_keys public_key
	local added_count=0 skipped_count=0 invalid_count=0 failed_count=0 total_count=0

	# 使用 ~ 来确保在所有情况下都能正确解析主目录
	authorized_keys_file=~/.ssh/authorized_keys
	backup_file="${authorized_keys_file}.bak"

	# --- 1. 获取用户输入 ---
	echo "请粘贴一个或多个 SSH 公钥 (每行一个)。"
	echo "粘贴完成后，请按 Ctrl+D 来结束输入并开始添加。"
	# 使用 cat 读取所有标准输入，直到遇到 EOF (Ctrl+D)
	all_keys=$(cat)

	if [[ -z "$all_keys" ]]; then
		echo "错误: 没有输入任何公钥。" >&2
		return 1
	fi

	# --- 2. 准备 SSH 目录和文件 ---
	# 确保 .ssh 目录存在并拥有正确的权限 (700)
	if ! mkdir -p ~/.ssh || ! chmod 700 ~/.ssh; then
		echo "错误: 无法创建或设置 ~/.ssh 目录的权限。" >&2
		return 1
	fi

	# 如果 authorized_keys 文件不存在，创建它并设置正确的权限 (600)
	if ! touch "$authorized_keys_file" || ! chmod 600 "$authorized_keys_file"; then
		echo "错误: 无法创建或设置 authorized_keys 文件的权限。" >&2
		return 1
	fi

	# --- 3. 备份原始文件 ---
	echo "正在备份当前的 authorized_keys 文件到 ${backup_file} ..."
	if ! cp -f "$authorized_keys_file" "$backup_file"; then
		echo "错误: 无法创建备份文件。操作已中止。" >&2
		return 1
	fi

	# --- 4. 逐行处理公钥 ---
	# 使用 while 循环逐行读取 all_keys 变量中的内容
	# `|| [[ -n "$public_key" ]]` 确保即使最后一行没有换行符也能被处理
	while IFS= read -r public_key || [[ -n "$public_key" ]]; do
		# 忽略空行或只包含空格的行
		if [[ -z "${public_key// /}" ]]; then
			continue
		fi

		((total_count++))
		echo "----------------------------------------"
		echo "正在处理第 ${total_count} 个条目..."

		# --- 新增: 公钥格式验证 ---
		# 使用正则表达式检查公钥是否以已知的类型开头，并包含一个有效的密钥主体。
		# 这可以有效地防止将格式错误的字符串或随机乱码添加到文件中。
		if ! [[ "$public_key" =~ ^(ssh-(rsa|dss|ed25519)|ecdsa-sha2-nistp(256|384|521))[[:space:]]+[A-Za-z0-9+/=]+ ]]; then
			echo "错误: 格式无效，看起来不是一个合法的 SSH 公钥。已跳过。"
			echo "      内容: ${public_key:0:40}..."
			((invalid_count++))
			continue
		fi
		# --- 验证结束 ---

		echo "正在处理公钥: ${public_key:0:30}..."

		# 检查公钥是否已存在
		if grep -qF -- "$public_key" "$authorized_keys_file"; then
			echo "警告: 该公钥已存在，将跳过。"
			((skipped_count++))
		else
			# 将公钥追加到文件末尾
			echo "$public_key" >>"$authorized_keys_file"

			# 验证公钥是否成功添加
			if grep -qF -- "$public_key" "$authorized_keys_file"; then
				echo "成功: 公钥已添加。"
				((added_count++))
			else
				echo "错误: 公钥添加失败！(I/O error)" >&2
				((failed_count++))
			fi
		fi
	done <<<"$all_keys" # 使用 Here String 将变量内容重定向到循环

	# --- 5. 显示信息 ---
	echo "========================================"
	echo "操作完成！结果如下："
	echo "  成功添加: ${added_count} 个"
	echo "  跳过 (已存在): ${skipped_count} 个"
	echo "  格式无效: ${invalid_count} 个"
	echo "  写入失败: ${failed_count} 个"
	echo "========================================"

	if [[ $failed_count -gt 0 || $invalid_count -gt 0 ]]; then
		echo "警告: 处理过程中出现问题。"
		if [[ $invalid_count -gt 0 ]]; then
			echo "有 ${invalid_count} 个输入因格式无效被跳过。"
		fi
		if [[ $failed_count -gt 0 ]]; then
			echo "有 ${failed_count} 个公钥写入失败。"
		fi
		echo "原始文件已备份在: ${backup_file}"
		echo "请检查失败的公钥并手动处理。"
		return 1
	elif [[ $added_count -gt 0 ]]; then
		echo "所有新公钥均已成功添加。"
	else
		echo "没有添加任何新公钥。"
	fi

	return 0
}

# 关闭 SSH 的密码登录功能，强制使用密钥登录，提高安全性
disable_ssh_password_login() {
	local sshd_config="/etc/ssh/sshd_config"

	if [ ! -f "$sshd_config" ]; then
		echo "错误: sshd_config 文件不存在于 $sshd_config"
		return 1
	fi

	read -p "此操作将禁止密码登录，请确保您已设置公钥。是否继续？(y/n): " choice
	if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
		echo "操作已取消。"
		return 1
	fi

	echo "正在关闭SSH密码登录..."

	# 备份原始 sshd_config 文件
	cp "$sshd_config" "${sshd_config}.bak"

	# 使用 sed 修改配置
	# s/^[#\s]*PasswordAuthentication\s\+.*/PasswordAuthentication no/g
	# 这个正则表达式会匹配行首任意数量的#和空格，然后是 "PasswordAuthentication" 和任意空格，最后是任意字符
	# 并将其替换为 "PasswordAuthentication no"
	sed -i 's/^[#\s]*PasswordAuthentication\s\+.*/PasswordAuthentication no/g' "$sshd_config"
	# 确保 ChallengeResponseAuthentication 也被禁用
	sed -i 's/^[#\s]*ChallengeResponseAuthentication\s\+.*/ChallengeResponseAuthentication no/g' "$sshd_config"

	# 重启 sshd 服务以应用更改
	if systemctl restart sshd; then
		echo "SSH密码登录已成功关闭。"
	else
		echo "错误: SSH服务重启失败。请检查 'systemctl status sshd' 获取详情。"
		echo "正在从备份恢复 sshd_config 文件..."
		mv "${sshd_config}.bak" "$sshd_config"
		return 1
	fi
}

# 添加docker工具脚本
add_docker_tools() {
	echo "正在准备下载并执行 Docker 工具箱安装脚本..."
	# YES_CN 变量由脚本开头的 set_mirror 函数设置
	local script_url="${YES_CN}https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/add_docker_tools.sh"

	echo "将从以下地址下载脚本: $script_url"

	# 下载并直接通过管道传递给bash执行
	if bash <(wget -qO - "$script_url"); then
		echo "Docker 工具箱脚本执行完成。"
	else
		echo "错误：Docker 工具箱脚本下载或执行失败。"
		return 1
	fi
}

# 删除所有 swap 文件和分区
remove_all_swap() {
	# 获取所有 swap 文件的列表
	swap_files=$(swapon -s | awk '{if($1!~"^Filename"){print $1}}')

	# 获取所有 swap 分区的列表
	swap_partitions=$(grep -E '^\S+\s+\S+\sswap\s+' /proc/swaps | awk '{print $1}')

	# 遍历并禁用、删除每个 swap 文件和分区
	for item in $swap_files $swap_partitions; do
		echo "正在禁用并删除 swap ：$item"
		swapoff "$item"
		rm -f "$item"
		echo "已删除 swap ：$item"
	done

	echo "所有 swap 文件和分区已删除。"
}

# 清理 swap 缓存
cleanup_swap() {
	echo "正在检查当前交换空间..."
	echo "=========================================="
	# 获取所有交换空间文件的列表
	swap_files=$(swapon -s | awk '{if($1!~"^Filename"){print $1}}')

	# 获取所有交换分区的列表
	swap_partitions=$(grep -E '^\S+\s+\S+\sswap\s+' /proc/swaps | awk '{print $1}')

	# 获取物理内存和已使用的物理内存
	total_memory=$(free -m | awk 'NR==2{print $2}')
	used_memory=$(free -m | awk 'NR==2{print $3}')

	# 获取已使用的交换空间
	used_swap=$(free -m | awk 'NR==3{print $3}')

	# 计算已使用的物理内存和虚拟内存占物理内存的百分比
	used_memory_percent=$(((used_memory) * 100 / total_memory))
	total_used_percent=$(((used_memory + used_swap) * 100 / total_memory))

	if [ -n "$swap_files" ]; then
		echo "当前交换空间大小如下："
		swapon --show
		echo "=========================================="
		echo "物理内存使用率：$used_memory_percent% ( $used_memory MB/ $total_memory MB )"
		echo "已使用的物理内存和虚拟内存占物理内存的百分比: $total_used_percent% ( $((used_memory + used_swap)) MB / $total_memory MB )"

		# 检测是否可以清理 swap 缓存
		if [ $total_used_percent -gt 80 ]; then
			echo "不建议清理 swap 缓存，因为物理内存使用量和 swap 使用量总和已经超过物理内存的80%。"
			echo "如果清理 swap 缓存，可能导致系统内存不足，影响性能和稳定性。"
		else
			echo "是否要清理 swap 缓存"
			read -p "请输入 y 或 n：" cleanup_choice

			case $cleanup_choice in
			y | Y)
				# 遍历并清理每个交换空间文件和分区
				for item in $swap_files $swap_partitions; do
					echo "正在清理 swap 缓存：$item"
					swapoff "$item"
					echo "已清理 swap 缓存：$item"
					swapon "$item"
				done

				echo "所有的 swap 缓存已清理。"
				;;
			n | N)
				echo "不需要清理 swap 缓存"
				;;
			*)
				echo "无效的选项，保留已存在的交换空间。"
				;;
			esac
		fi
	fi
}

# 设置虚拟内存 (swap 文件)
set_virtual_memory() {
	if swapon --show | grep -q '.'; then
		echo "检测到已存在的 swap 设备："
		swapon --show
		read -p "是否要先删除所有已存在的 swap？(y/n): " remove_choice
		if [[ "$remove_choice" == "y" || "$remove_choice" == "Y" ]]; then
			remove_all_swap
		else
			echo "操作因存在 swap 而取消。请先手动处理。"
			return 1
		fi
	fi

	echo "请选择虚拟内存的大小或手动输入值："
	echo "1. 512M"
	echo "2. 1GB"
	echo "3. 2GB"
	echo "4. 4GB"
	echo "5. 手动输入值 (如 8G, 1024M)"
	read -p "请输入选项数字 (按q退出)：" choice

	local swap_size=""
	case $choice in
	1) swap_size="512M" ;;
	2) swap_size="1G" ;;
	3) swap_size="2G" ;;
	4) swap_size="4G" ;;
	5) read -p "请输入虚拟内存大小（例如：256M、1G、2G等）：" swap_size ;;
	[qQ])
		echo "返回主菜单..."
		return 0
		;;
	*)
		echo "无效的选项。"
		return 1
		;;
	esac

	if [[ -z "$swap_size" ]]; then
		echo "错误：Swap 大小不能为空。"
		return 1
	fi

	local swap_file="/swapfile"
	echo "正在创建大小为 ${swap_size} 的 swap 文件于 ${swap_file}..."

	# 使用 fallocate 创建文件速度更快，如果失败则回退到 dd
	fallocate -l "$swap_size" "$swap_file" || {
		echo "fallocate 失败，回退到 dd..."
		local count
		local block_size
		# 解析单位
		if [[ $swap_size == *[Gg] ]]; then
			count=$(echo "$swap_size" | sed 's/[Gg]//')
			block_size="1G"
		elif [[ $swap_size == *[Mm] ]]; then
			count=$(echo "$swap_size" | sed 's/[Mm]//')
			block_size="1M"
		else
			echo "错误：无法识别的大小单位。"
			return 1
		fi
		dd if=/dev/zero of="$swap_file" bs="$block_size" count="$count" status=progress
	}

	if [ $? -ne 0 ]; then
		echo "错误：创建 swap 文件失败。"
		rm -f "$swap_file"
		return 1
	fi

	echo "设置 swap 文件权限..."
	chmod 600 "$swap_file"
	echo "格式化为 swap..."
	mkswap "$swap_file"
	echo "启用 swap..."
	swapon "$swap_file"

	if [ $? -eq 0 ]; then
		# 检查是否已存在于 fstab
		if ! grep -q "$swap_file" /etc/fstab; then
			echo "将 swap 添加到 /etc/fstab 以实现开机自启..."
			echo "$swap_file none swap sw 0 0" >>/etc/fstab
		fi
		echo "虚拟内存设置成功。"
		swapon --show
	else
		echo "错误：启用 swap 失败。"
		rm -f "$swap_file"
		return 1
	fi
}

# 修改 swap 使用阈值 (vm.swappiness)
modify_swap_usage_threshold() {
	local current_swappiness
	current_swappiness=$(cat /proc/sys/vm/swappiness)
	echo "当前系统的 vm.swappiness 值为：$current_swappiness"
	echo "（值越低，系统越倾向于使用物理内存，推荐值为 10）"

	read -p "请输入要设置的新 vm.swappiness 值 (0-100) [默认为 10]: " swap_value
	# 如果用户直接回车，则使用默认值 10
	swap_value=${swap_value:-10}

	if ! [[ "$swap_value" =~ ^[0-9]+$ ]] || [ "$swap_value" -lt 0 ] || [ "$swap_value" -gt 100 ]; then
		echo "无效的输入，请输入0-100之间的数字。"
		return 1
	fi

	echo "正在修改 swap 使用阈值为 $swap_value..."

	# 直接在 /etc/sysctl.conf 中设置，没有就添加，有就修改
	if grep -q "^vm.swappiness" /etc/sysctl.conf; then
		sed -i "s/^vm.swappiness=.*/vm.swappiness=$swap_value/" /etc/sysctl.conf
	else
		echo "vm.swappiness=$swap_value" >>/etc/sysctl.conf
	fi

	# 使配置立即生效
	sysctl -p

	echo "swap 使用阈值修改成功。"
	echo "新的 vm.swappiness 值为: $(cat /proc/sys/vm/swappiness)"
}

# --- 内核与网络优化模块 ---
# 优化内核网络相关参数：启用 BBR 并根据 BDP 自适应网络调参
optimize_kernel_parameters() {
	# YES_CN 变量由脚本开头的 set_mirror 函数设置并导出
	local script_url="${YES_CN}https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/optimize_kernel_parameters.sh"

	# 下载并通过管道传递给bash执行,
	if bash <(wget -qO - "$script_url"); then
		echo "内核参数优化器初始化..."
	else
		echo "内核参数优化器初始化失败"
		return 1
	fi
}

# 安装 XanMod 内核 (仅限 Debian/Ubuntu)
install_xanmod_kernel() {
	# YES_CN 变量由脚本开头的 set_mirror 函数设置并导出
	local script_url="${YES_CN}https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/manage_xanmod_kernel.sh"

	# 下载并通过管道传递给bash执行, 传递 'install' 参数
	if bash <(wget -qO - "$script_url") install; then
		echo ""
	else
		echo "错误：XanMod 内核安装脚本下载或执行失败。"
		return 1
	fi
}

# 卸载XanMod内核并恢复原有内核，并更新Grub引导配置
uninstall_xanmod_kernel() {
	# YES_CN 变量由脚本开头的 set_mirror 函数设置并导出
	local script_url="${YES_CN}https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/manage_xanmod_kernel.sh"

	# 下载并通过管道传递给bash执行, 传递 'uninstall' 参数
	if bash <(wget -qO - "$script_url") uninstall; then
		echo ""
	else
		echo "错误：XanMod 内核卸载脚本下载或执行失败。"
		return 1
	fi
}

# 安装 Debian Cloud 内核 (仅限 Debian)
install_debian_cloud_kernel() {
	if [[ ! "$OS_TYPE" == "Debian/Ubuntu" || ! $(grep -i "debian" /etc/os-release) ]]; then
		echo "错误：此功能仅适用于 Debian 系统。"
		return 1
	fi

	echo "INFO" "开始安装 Debian Cloud 内核"
	echo "正在更新软件包列表..."
	apt update -y

	echo "当前系统内核版本："
	dpkg -l | grep linux-image

	echo "查找最新的 Cloud 内核版本..."
	latest_cloud_kernel=$(apt-cache search linux-image | grep -E 'linux-image-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-cloud-amd64 ' | grep -v unsigned | sort -V | tail -n 1 | awk '{print $1}')
	latest_cloud_headers=${latest_cloud_kernel/image/headers}

	if [ -z "$latest_cloud_kernel" ]; then
		echo "ERROR" "未找到可用的 Cloud 内核版本"
		echo "未找到可用的 Cloud 内核版本。"
		return 1
	fi

	echo "找到最新的 Cloud 内核版本：$latest_cloud_kernel"
	read -p "是否安装此版本？(y/n): " install_choice

	if [[ $install_choice == [yY] ]]; then
		echo "正在安装 Cloud 内核..."
		apt install $latest_cloud_headers $latest_cloud_kernel -y
		if [ $? -eq 0 ]; then
			echo "更新 GRUB..."
			update-grub
			echo "INFO" "Debian  Cloud 内核安装成功"
			echo "Debian  Cloud 内核安装成功。请重启系统以使用新内核。"
		else
			echo "ERROR" "Debian  Cloud 内核安装失败"
			echo "Debian  Cloud 内核安装失败。"
		fi
	else
		echo "取消安装 Cloud 内核。"
	fi
}

# 卸载 Debian Cloud 内核
uninstall_debian_cloud_kernel() {
	echo "INFO" "开始卸载 Debian Cloud 内核"
	echo "当前系统内核版本："
	dpkg -l | grep linux-image

	cloud_kernels=$(dpkg -l | grep -E 'linux-image-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-cloud-amd64' | awk '{print $2}')
	cloud_headers=$(echo "$cloud_kernels" | sed 's/image/headers/g')

	if [ -z "$cloud_kernels" ]; then
		echo "未检测到已安装的 Cloud 内核。"
		return
	fi

	echo "检测到以下 Cloud 内核："
	echo "$cloud_kernels"
	echo "对应的 headers："
	echo "$cloud_headers"
	read -p "是否卸载这些 Cloud 内核并恢复原有内核？(y/n): " uninstall_choice

	if [[ $uninstall_choice == [yY] ]]; then
		echo "正在卸载 Cloud 内核..."
		apt remove $cloud_kernels $cloud_headers -y
		apt autoremove -y
		if [ $? -eq 0 ]; then
			echo "更新 GRUB..."
			update-grub
			echo "INFO" "Debian Cloud 内核卸载成功"
			echo "Debian Cloud 内核卸载成功。请重启系统以使用原有内核。"
		else
			echo "ERROR" "Debian Cloud 内核卸载失败"
			echo "Debian Cloud 内核卸载失败。"
		fi
	else
		echo "取消卸载 Cloud 内核。"
	fi
}
# 修改SSH端口号
modify_ssh_port() {
	local sshd_config="/etc/ssh/sshd_config"
	local current_port
	current_port=$(grep -i "^\s*port" "$sshd_config" | awk '{print $2}' | tail -n 1)

	if [ -z "$current_port" ]; then
		current_port=22 # 默认端口
	fi
	echo "当前SSH端口号是：$current_port"

	read -p "请输入新的SSH端口号: " new_port

	if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
		echo "无效的端口号。"
		return 1
	fi

	echo "正在修改 SSH 端口为 $new_port..."
	# 备份配置文件
	cp "$sshd_config" "${sshd_config}.bak"
	# 修改或添加 Port 配置
	if grep -q "^\s*Port" "$sshd_config"; then
		sed -i "s/^\s*Port.*/Port $new_port/" "$sshd_config"
	else
		echo "Port $new_port" >>"$sshd_config"
	fi

	# # 开放新端口
	# firewall_open_port "$new_port" "tcp"
	# if [ $? -ne 0 ]; then
	#     echo "错误：在防火墙中开放新端口失败，操作已回滚。"
	#     mv "${sshd_config}.bak" "$sshd_config"
	#     return 1
	# fi

	# 重启 SSH 服务
	if systemctl restart sshd; then
		echo "SSH 端口修改成功，新端口为 $new_port。"
		echo "请记得使用新端口重新连接！"
		# # 如果旧端口不是22，则可以选择关闭
		# if [ "$current_port" != "22" ] && [ "$current_port" != "$new_port" ]; then
		#     read -p "是否要关闭旧的SSH端口 $current_port？(y/n): " close_old
		#     if [[ "$close_old" == "y" || "$close_old" == "Y" ]]; then
		#         firewall_close_port "$current_port" "tcp"
		#     fi
		# fi
	else
		echo "错误：SSH 服务重启失败。操作已回滚。"
		mv "${sshd_config}.bak" "$sshd_config"
		# firewall_close_port "$new_port" "tcp" # 回滚防火墙规则
		return 1
	fi
}

# 配置 Fail2ban 保护
configure_fail2ban() {
	echo "正在准备下载并执行 Fail2ban 配置脚本..."
	# YES_CN 变量由脚本开头的 set_mirror 函数设置
	local script_url="${YES_CN}https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/configure_fail2ban.sh"

	echo "将从以下地址下载脚本: $script_url"

	# 下载并直接通过管道传递给bash执行
	if bash <(wget -qO - "$script_url"); then
		echo "Fail2ban 配置脚本执行完成。"
	else
		echo "错误：Fail2ban 配置脚本下载或执行失败。"
		return 1
	fi
}

# 设置防火墙端口（用户交互界面）
set_firewall_ports() {
	clear
	display_open_ports

	echo "请选择要执行的操作:"
	echo "1. 开放防火墙端口"
	echo "2. 关闭防火墙端口"
	echo "q. 返回主菜单"
	read -p "请输入操作选项 (1/2/q): " action

	case $action in
	1)
		echo "支持一次输入多个端口，以逗号分隔。"
		read -p "请输入要开放的端口，格式如 80t,443t,53u (t=TCP, u=UDP): " ports_input

		IFS=',' read -ra ports_array <<<"$ports_input"
		for port_info in "${ports_array[@]}"; do
			port_info=$(echo "$port_info" | xargs) # 去除空格
			if [[ "$port_info" =~ ^([0-9]+)([tu])$ ]]; then
				local port="${BASH_REMATCH[1]}"
				local proto_char="${BASH_REMATCH[2]}"
				local protocol="tcp"
				if [ "$proto_char" == "u" ]; then
					protocol="udp"
				fi
				firewall_open_port "$port" "$protocol"
			else
				echo "警告：无效的输入格式 '$port_info'，已跳过。"
			fi
		done
		;;
	2)
		echo "支持一次输入多个端口，以逗号分隔。"
		read -p "请输入要关闭的端口，格式如 80t,53u (t=TCP, u=UDP): " ports_input

		IFS=',' read -ra ports_array <<<"$ports_input"
		for port_info in "${ports_array[@]}"; do
			port_info=$(echo "$port_info" | xargs) # 去除空格
			if [[ "$port_info" =~ ^([0-9]+)([tu])$ ]]; then
				local port="${BASH_REMATCH[1]}"
				local proto_char="${BASH_REMATCH[2]}"
				local protocol="tcp"
				if [ "$proto_char" == "u" ]; then
					protocol="udp"
				fi
				firewall_close_port "$port" "$protocol"
			else
				echo "警告：无效的输入格式 '$port_info'，已跳过。"
			fi
		done
		;;
	[qQ])
		return 0
		;;
	*)
		echo "无效的操作选项。"
		return 1
		;;
	esac
}

# 检查ZRAM是否已安装
is_zram_installed() {
	if lsmod | grep -q zram && command -v zramctl >/dev/null; then
		return 0 # ZRAM已安装
	else
		return 1 # ZRAM未安装
	fi
}

# 安装ZRAM
install_zram() {
	OS_TYPE=$(get_os_info)
	case $OS_TYPE in
	Debian/Ubuntu)
		apt update && apt install -y zram-tools
		;;
	CentOS | Fedora)
		dnf install -y zram-generator
		;;
	Arch)
		pacman -Sy --noconfirm zram-generator
		;;
	*)
		echo "不支持的操作系统: $OS_TYPE"
		return 1
		;;
	esac
}

# 显示当前ZRAM配置和使用情况
display_zram_status() {
	if is_zram_installed; then
		echo "当前 ZRAM 配置:"
		zramctl

		OS_TYPE=$(get_os_info)
		case $OS_TYPE in
		Debian/Ubuntu)
			echo "当前配置参数:"
			grep -E "PERCENT|ALGO|DEVICES" /etc/default/zramswap
			;;
		CentOS | Fedora | Arch)
			echo "当前配置参数:"
			cat /etc/systemd/zram-generator.conf
			;;
		esac
	else
		echo "ZRAM 未安装或未配置。"
	fi
}

# 配置ZRAM
configure_zram() {
	if ! is_zram_installed; then
		echo "正在安装ZRAM..."
		install_zram
		if [ $? -ne 0 ]; then
			echo "ZRAM安装失败。"
			return 1
		fi
	fi

	# 获取当前设置
	case $OS_TYPE in
	Debian/Ubuntu)
		current_percent=$(grep -oP 'PERCENT=\K\d+' /etc/default/zramswap)
		current_algo=$(grep -oP 'ALGO=\K\w+' /etc/default/zramswap)
		;;
	CentOS | Fedora | Arch)
		current_percent=$(grep -oP 'zram-size = \K\d+' /etc/systemd/zram-generator.conf | awk '{print $1*100/1048576}')
		current_algo=$(grep -oP 'compression-algorithm = \K\w+' /etc/systemd/zram-generator.conf)
		;;
	esac

	# 默认设置
	default_percent=${current_percent:-50}
	default_algo=${current_algo:-"zstd"}
	cpu_cores=$(nproc)

	# 询问用户ZRAM大小百分比
	read -p "请输入ZRAM大小占物理内存的百分比 (1-100) [当前/默认: $default_percent]: " zram_percent
	zram_percent=${zram_percent:-$default_percent}

	if ! [[ "$zram_percent" =~ ^[0-9]+$ ]] || [ "$zram_percent" -lt 1 ] || [ "$zram_percent" -gt 100 ]; then
		echo "无效的输入，使用当前/默认值 $default_percent。"
		zram_percent=$default_percent
	fi

	# 询问用户压缩算法
	echo "请选择压缩算法 [当前/默认: $default_algo]："
	echo "1. lzo"
	echo "2. lz4"
	echo "3. zstd (推荐)"
	read -p "请输入选项数字: " algo_choice

	case $algo_choice in
	1) comp_algo="lzo" ;;
	2) comp_algo="lz4" ;;
	3) comp_algo="zstd" ;;
	*)
		echo "无效的选择，使用当前/默认算法 $default_algo"
		comp_algo=$default_algo
		;;
	esac

	# 配置ZRAM
	case $OS_TYPE in
	Debian/Ubuntu)
		echo "PERCENT=$zram_percent" >/etc/default/zramswap
		echo "ALGO=$comp_algo" >>/etc/default/zramswap
		echo "DEVICES=$cpu_cores" >>/etc/default/zramswap
		systemctl restart zramswap
		;;
	CentOS | Fedora | Arch)
		zram_size=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') * $zram_percent / 100))
		cat <<EOF >/etc/systemd/zram-generator.conf
[zram0]
zram-size = ${zram_size}K
compression-algorithm = $comp_algo
EOF
		systemctl restart systemd-zram-setup@zram0.service
		;;
	esac

	echo "ZRAM配置已更新。"
	echo "大小: ${zram_percent}% 的物理内存"
	echo "压缩算法: $comp_algo"
	echo "ZRAM设备数: $cpu_cores"
}

# 卸载ZRAM
uninstall_zram() {
	if is_zram_installed; then
		echo "正在卸载ZRAM..."
		case $OS_TYPE in
		Debian/Ubuntu)
			systemctl stop zramswap
			systemctl disable zramswap
			apt remove -y zram-tools
			;;
		CentOS | Fedora)
			systemctl stop systemd-zram-setup@zram0.service
			systemctl disable systemd-zram-setup@zram0.service
			dnf remove -y zram-generator
			;;
		Arch)
			systemctl stop systemd-zram-setup@zram0.service
			systemctl disable systemd-zram-setup@zram0.service
			pacman -R --noconfirm zram-generator
			;;
		*)
			echo "不支持的操作系统: $OS_TYPE"
			return 1
			;;
		esac

		# 移除配置文件
		rm -f /etc/default/zramswap /etc/systemd/zram-generator.conf

		echo "ZRAM已卸载。"
	else
		echo "ZRAM未安装，无需卸载。"
	fi
}

# ZRAM配置菜单
configure_zram_menu() {
	while true; do
		clear
		echo "ZRAM配置菜单"
		echo "----------------"

		if is_zram_installed; then
			display_zram_status
			echo
			echo "1. 修改ZRAM参数"
		else
			echo "1. 安装并配置ZRAM"
		fi
		echo "2. 卸载ZRAM"
		echo "3. 返回主菜单"

		read -p "请选择操作: " choice

		case $choice in
		1)
			configure_zram
			;;
		2)
			uninstall_zram
			;;
		3)
			return 0
			;;
		*)
			echo "无效的选择，请重新输入。"
			;;
		esac

		echo "按Enter键继续..."
		read
	done
}

# --- 设置 DNS (通过 dhclient) ---
set_dns_dhclient() {
	echo "正在准备通过dhclient设置CF、Google DNS..."

	# 检查是否为 Debian/Ubuntu，因为此方法特定于 dhclient
	if [[ "$OS_TYPE" != "Debian/Ubuntu" ]]; then
		echo "错误：此功能目前仅适用于使用 dhclient 的 Debian/Ubuntu 系统。"
		echo "操作已取消。"
		return 1
	fi

	bash <(wget -qO - "${YES_CN}https://raw.githubusercontent.com/SuperNG6/linux-setup.sh/main/set_dns_via_dhclient.sh")

	if [ $? -eq 0 ]; then
		echo ""
	else
		echo "错误：DNS 设置失败。"
		return 1
	fi
}

# --- 主菜单与主循环 ---

# 显示操作菜单
display_menu() {
	local linux_version
	linux_version=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
	local kernel_version
	kernel_version=$(uname -r)
	local memory_usage
	memory_usage=$(free | awk '/Mem/{printf("%.2f", $3/$2 * 100)}')

	local GREEN='\033[0;32m'
	local BOLD='\033[1m'
	local RESET='\033[0m'

	clear
	echo -e "${BOLD}欢迎使用 SuperNG6 的 Linux 工具箱${RESET}"
	echo -e "${BOLD}GitHub：https://github.com/SuperNG6/linux-setup.sh${RESET}"
	echo -e "-----------------------------------------------------"
	echo -e "系统: ${GREEN}${linux_version}${RESET}"
	echo -e "内核: ${GREEN}${kernel_version}${RESET}"
	echo -e "内存: ${GREEN}${memory_usage}%${RESET} | 防火墙: ${GREEN}${FIREWALL_TYPE}${RESET}"
	echo -e "-----------------------------------------------------"
	echo -e "${BOLD}请选择操作：${RESET}\n"
	echo -e "${BOLD}选项${RESET}     ${BOLD}描述${RESET}"
	# 菜单选项
	echo -e "----------- ${BOLD}基础与安全${RESET} ---------------------------"
	echo -e "${GREEN} 1${RESET}       安装常用组件 (Docker, Fail2ban...)"
	echo -e "${GREEN} 2${RESET}       添加 SSH 公钥 (免密登录)"
	echo -e "${GREEN} 3${RESET}       关闭 SSH 密码登录 (推荐)"
	echo -e "${GREEN} 4${RESET}       修改 SSH 端口号"
	echo -e "${GREEN} 5${RESET}       配置 Fail2ban"
	echo -e "${GREEN} 6${RESET}       设置防火墙端口 (开放/关闭)"
	echo ""
	echo -e "----------- ${BOLD}性能与优化${RESET} ----------------------------"
	echo -e "${GREEN} 7${RESET}       设置 Swap 虚拟内存"
	echo -e "${GREEN} 8${RESET}       配置 ZRAM"
	echo -e "${GREEN} 9${RESET}       修改 Swap 使用阈值 (Swappiness)"
	echo -e "${GREEN} 10${RESET}      清理 Swap 缓存"
	echo -e "${GREEN} 11${RESET}      优化内核参数"
	echo -e "${GREEN} 12${RESET}      添加 Docker 工具脚本"
	echo -e "${GREEN} 13${RESET}      设置公共 DNS (CF/Google)"
	echo ""
	if [[ "$OS_TYPE" == "Debian/Ubuntu" ]]; then
		echo -e "----------- ${BOLD}内核管理 (Debian/Ubuntu)${RESET} -------------"
		echo -e "${GREEN} 14${RESET}      安装 XanMod 内核 (含BBRv3)"
		echo -e "${GREEN} 16${RESET}      卸载 XanMod 内核"
		if [[ $(grep -i "debian" /etc/os-release) ]]; then
			echo -e "${GREEN} 16${RESET}      安装 Debian Cloud 内核"
			echo -e "${GREEN} 17${RESET}      卸载 Debian Cloud 内核"
		fi
	fi

	echo -e "----------------------------------------------------------"
	echo -e "${BOLD}输入${RESET} 'q' ${BOLD}退出${RESET}"
}

# 根据用户选择执行相应的操作
# 处理用户选择
handle_choice() {
	local choice=$1
	clear
	case $choice in
	1) install_components ;;
	2) add_public_keys ;;
	3) disable_ssh_password_login ;;
	4) modify_ssh_port ;;
	5) configure_fail2ban ;;
	6) set_firewall_ports ;;
	7) set_virtual_memory ;;
	8) configure_zram_menu ;;
	9) modify_swap_usage_threshold ;;
	10) cleanup_swap ;;
	11) optimize_kernel_parameters ;;
	12) add_docker_tools ;;
	13) set_dns_dhclient ;;
	14) [[ "$OS_TYPE" == "Debian/Ubuntu" ]] && install_xanmod_kernel || echo "此选项仅适用于 Debian/Ubuntu" ;;
	15) [[ "$OS_TYPE" == "Debian/Ubuntu" ]] && uninstall_xanmod_kernel || echo "此选项仅适用于 Debian/Ubuntu" ;;
	16) [[ $(grep -i "debian" /etc/os-release) ]] && install_debian_cloud_kernel || echo "此选项仅适用于 Debian" ;;
	17) [[ $(grep -i "debian" /etc/os-release) ]] && uninstall_debian_cloud_kernel || echo "此选项仅适用于 Debian" ;;
	[qQ]) return 1 ;; # 返回非零值以退出主循环
	*) echo "无效的选项，请输入正确的数字。" ;;
	esac

	# 每个操作执行后暂停，等待用户确认
	echo ""
	read -p "按 Enter 键回到主菜单..."
	return 0
}

# 主函数
main() {
	# trap 命令用于在接收到指定信号时执行命令。EXIT 是一个特殊的信号，表示脚本即将退出。
	trap cleanup EXIT

	# 在脚本开始时执行一次环境检测
	set_mirror
	FIREWALL_TYPE=$(check_firewall)
	OS_TYPE=$(get_os_info)

	while true; do
		display_menu
		read -p "请输入选项数字: " user_choice
		# 根据用户选择执行相应的操作
		handle_choice "$user_choice" || break # 如果 handle_choice 返回非零值，则退出循环
	done
}

# 清理函数，在脚本退出时执行
cleanup() {
	echo "正在退出脚本..."
	sleep 0.8s
	echo "欢迎再次使用本脚本！"
	sleep 0.5s
	tput reset
}

main "$@"
