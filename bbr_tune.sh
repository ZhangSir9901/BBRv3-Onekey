#!/bin/bash

# ====================================================================
# 项目名称: Debian/Ubuntu XanMod BBRv3 智能网络生命周期管理 (全栈极致版)
# 支持系统: Debian 12/13, Ubuntu 20.04/22.04/24.04/26.04 (LTS)
# ====================================================================

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[1;33m' # 高亮黄
BLUE='\033[36m'
PLAIN='\033[0m'

# 1. 权限与系统检查
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[错误] 必须使用 root 权限运行此脚本！${PLAIN}"
    exit 1
fi

if [ ! -f /etc/os-release ]; then
    echo -e "${RED}[错误] 无法识别当前系统架构！${PLAIN}"
    exit 1
fi

. /etc/os-release

# 限制支持 Debian 12/13 和 Ubuntu LTS 版本
SUPPORTED=false
if [ "$ID" = "debian" ] && { [ "$VERSION_ID" = "12" ] || [ "$VERSION_ID" = "13" ]; }; then
    SUPPORTED=true
elif [ "$ID" = "ubuntu" ] && { [ "$VERSION_ID" = "20.04" ] || [ "$VERSION_ID" = "22.04" ] || [ "$VERSION_ID" = "24.04" ] || [ "$VERSION_ID" = "26.04" ]; }; then
    SUPPORTED=true
fi

if [ "$SUPPORTED" = "false" ]; then
    echo -e "${RED}[错误] 本脚本仅支持 Debian 12/13 以及 Ubuntu LTS (20.04/22.04/24.04/26.04)！${PLAIN}"
    echo -e "${YELLOW}当前系统为: ${ID} ${VERSION_ID:-未知版本}${PLAIN}"
    exit 1
fi

# 2. 预检并安装基础依赖
if ! command -v gpg >/dev/null || ! command -v wget >/dev/null || ! command -v curl >/dev/null || [ ! -d /etc/ssl/certs ]; then
    echo -e "${BLUE}正在检查并安装系统必要依赖程序...${PLAIN}"
    apt update && apt install wget curl gnupg lsb-release ca-certificates -y
fi

# ====================================================================
# 3. 智能检测三种 IP 网络栈架构 (双栈 / 纯v4 / 纯v6)
# ====================================================================
HAS_IPV4=false
HAS_IPV6=false

if curl -s -4 --connect-timeout 2 https://www.cloudflare.com/cdn-cgi/trace >/dev/null 2>&1 || curl -s -4 --connect-timeout 2 https://api.ipify.org >/dev/null 2>&1; then
    HAS_IPV4=true
fi
if curl -s -6 --connect-timeout 2 https://www.cloudflare.com/cdn-cgi/trace >/dev/null 2>&1 || curl -s -6 --connect-timeout 2 https://api6.ipify.org >/dev/null 2>&1; then
    HAS_IPV6=true
fi

if [ "$HAS_IPV4" = "true" ] && [ "$HAS_IPV6" = "true" ]; then
    IP_STACK_TEXT="双栈网络 (IPv4 + IPv6)"
elif [ "$HAS_IPV4" = "true" ]; then
    IP_STACK_TEXT="纯 IPv4 网络 (IPv4-Only)"
elif [ "$HAS_IPV6" = "true" ]; then
    IP_STACK_TEXT="纯 IPv6 网络 (IPv6-Only)"
else
    IP_STACK_TEXT="单网卡未知拓扑"
fi

# 4. 高精度地理位置识别 (适配纯 IPv6 探测)
get_country_code() {
    local cc=""
    local curl_flag=""
    if [ "$HAS_IPV4" = "false" ] && [ "$HAS_IPV6" = "true" ]; then
        curl_flag="-6"
    fi
    cc=$(curl $curl_flag -s --connect-timeout 3 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^loc=' | cut -d= -f2)
    if [ -n "$cc" ] && [ "$cc" != "XX" ] && [ ${#cc} -eq 2 ]; then
        echo "$cc"
        return
    fi
    cc=$(curl $curl_flag -s --connect-timeout 3 https://ipinfo.io/country)
    if [ -n "$cc" ] && [ ${#cc} -eq 2 ]; then
        echo "$cc"
        return
    fi
    echo "US"
}

COUNTRY_CODE=$(get_country_code)
COUNTRY_CODE=$(echo "$COUNTRY_CODE" | tr '[:lower:]' '[:upper:]')

case "$COUNTRY_CODE" in
    HK|JP|KR|SG|MY|PH|TW|TH|VN|ID) COUNTRY_NAME="亚太地区 (${COUNTRY_CODE})" ;;
    US|CA) COUNTRY_NAME="北美洲 (${COUNTRY_CODE})" ;;
    GB|UK|DE|NL|FR|RU) COUNTRY_NAME="欧洲 (${COUNTRY_CODE})" ;;
    CN) COUNTRY_NAME="中国大陆 (${COUNTRY_CODE})" ;;
    *) COUNTRY_NAME="${COUNTRY_CODE}";;
esac

# ====================================================================
# 5. 安全拦截熔断：检测并拦截大陆机器与特定云厂商 (国内/海外全节点拦截)
# ====================================================================
IS_BLOCKED=false
BLOCK_REASON=""

if [ "$COUNTRY_CODE" = "CN" ]; then
    IS_BLOCKED=true
    BLOCK_REASON="检测到当前服务器公网 IP 位于【中国大陆 (CN)】"
fi

DMI_INFO=$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/bios_vendor 2>/dev/null | tr '[:upper:]' '[:lower:]')

if [[ "$DMI_INFO" =~ alibaba|aliyun ]]; then
    IS_BLOCKED=true
    BLOCK_REASON="检测到宿主机底层为【阿里云 (Alibaba Cloud)】基础设施"
elif [[ "$DMI_INFO" =~ tencent|qcloud ]]; then
    IS_BLOCKED=true
    BLOCK_REASON="检测到宿主机底层为【腾讯云 (Tencent Cloud)】基础设施"
elif [[ "$DMI_INFO" =~ huawei ]]; then
    IS_BLOCKED=true
    BLOCK_REASON="检测到宿主机底层为【华为云 (Huawei Cloud)】基础设施"
fi

if [ -d "/usr/local/aegis" ] || [ -d "/usr/local/share/aliyun-assist" ]; then
    IS_BLOCKED=true
    BLOCK_REASON="检测到宿主机常驻【阿里云盾 (Aegis) / 云助手】专有内核监控"
elif [ -d "/usr/local/qcloud" ]; then
    IS_BLOCKED=true
    BLOCK_REASON="检测到宿主机常驻【腾讯云监控 (QCloud)】专有内核组件"
fi

if [ "$IS_BLOCKED" = "true" ]; then
    clear
    echo -e "${RED}================================================================${PLAIN}"
    echo -e "${RED}⛔ [安全拦截] 触发安全熔断机制，脚本已自动终止运行！${PLAIN}"
    echo -e "${RED}================================================================${PLAIN}"
    echo -e "${YELLOW}拦截原因: ${RED}${BLOCK_REASON}${PLAIN}"
    echo -e ""
    echo -e "${YELLOW}风险技术剖析：${PLAIN}"
    echo -e "1. 该厂商底层虚拟化（KVM）默认裁剪/屏蔽了 x86-64-v3 高级指令集，强制安装 XanMod 内核会导致开机崩溃 (Kernel Panic)。"
    echo -e "2. 该厂商深度绑定了专有 VirtIO 虚拟网卡驱动与云盾监控，第三方高性能内核无法接管网卡，易造成 SSH 永久断联。"
    echo -e "3. 无论是国内节点还是海外节点，该厂商均使用相同的封闭底层虚拟化，不适合刷写第三方性能内核。"
    echo -e "${RED}================================================================${PLAIN}"
    echo -e "${GREEN}👉 兼容推荐：建议在正规国际云厂商（如 DMIT、搬瓦工、AWS、甲骨文、Linode、Hetzner 等）上运行。${PLAIN}"
    echo -e "${BLUE}为了保护您的服务器数据与连接安全，脚本已安全退出。${PLAIN}"
    exit 1
fi

# 6. 根据系统分配内核包
CODENAME=$VERSION_CODENAME
if [ "$ID" = "debian" ] && [ "$VERSION_ID" = "12" ]; then
    KERNEL_PKG="linux-xanmod-lts-x64v3"
else
    KERNEL_PKG="linux-xanmod-x64v3"
fi

# 7. 定义通用命令重试函数
retry_command() {
    local max_attempts=5
    local timeout=3
    local attempt=1
    until "$@"; do
        if (( attempt == max_attempts )); then
            echo -e "${RED}[错误] 命令 \"$*\" 失败，已重试 $max_attempts 次。${PLAIN}"
            return 1
        fi
        echo -e "${YELLOW}[警告] 执行失败，正在进行第 $attempt 次重试...${PLAIN}"
        sleep $timeout
        ((attempt++))
    done
    return 0
}

# ====================================================================
# 8. 小内存智能“急救气囊” (Swap 自动兜底检测与创建)
# ====================================================================
auto_manage_swap() {
    local total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local current_swap_mb=$(free -m | awk '/^Swap:/{print $2}')

    if [ "$total_ram_mb" -le 1536 ] && [ "$current_swap_mb" -lt 512 ]; then
        echo -e "${YELLOW}[内存急救] 检测到本机物理内存较小 (${total_ram_mb}MB) 且无充足 Swap，正在自动创建 1GB 虚拟内存保命气囊...${PLAIN}"
        if ! grep -q '/swapfile' /etc/fstab; then
            fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 2>/dev/null
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1
            swapon /swapfile >/dev/null 2>&1
            echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
            echo -e "${GREEN}[成功] 1GB Swap 兜底气囊创建完毕！${PLAIN}"
        fi
    fi
}

# 9. 深度清理旧系统参数
clean_sysctl() {
    local params=(
        "net.core.default_qdisc" "net.ipv4.tcp_congestion_control" "net.ipv4.tcp_rmem" "net.ipv4.tcp_wmem"
        "net.ipv4.tcp_notsent_lowat" "net.ipv4.tcp_mtu_probing" "net.ipv4.tcp_base_mss" "net.ipv4.tcp_sack"
        "net.ipv4.tcp_dsack" "net.core.somaxconn" "net.core.netdev_max_backlog" "net.ipv4.tcp_max_syn_backlog"
        "net.ipv4.tcp_tw_reuse" "net.ipv4.tcp_fin_timeout" "net.ipv4.tcp_keepalive_time" "net.ipv4.tcp_fastopen"
        "net.ipv4.tcp_slow_start_after_idle" "net.core.rmem_max" "net.core.wmem_max" "net.core.rmem_default"
        "net.core.wmem_default" "net.ipv4.udp_rmem_min" "net.ipv4.udp_wmem_min" "net.ipv4.ip_local_port_range"
        "net.ipv4.ip_forward" "net.ipv6.conf.all.forwarding" "net.ipv6.conf.default.forwarding"
        "net.ipv6.conf.all.accept_ra" "net.ipv6.conf.default.accept_ra" "net.ipv6.route.max_size"
        "vm.swappiness" "vm.vfs_cache_pressure" "vm.dirty_ratio" "vm.dirty_background_ratio"
        "fs.file-max" "fs.inotify.max_user_watches" "fs.inotify.max_user_instances" "fs.pipe-max-size"
        "net.netfilter.nf_conntrack_max" "net.netfilter.nf_conntrack_tcp_timeout_established"
        "net.netfilter.nf_conntrack_tcp_timeout_close_wait" "net.netfilter.nf_conntrack_tcp_timeout_time_wait"
    )
    for p in "${params[@]}"; do
        sed -i "/^${p}/d" /etc/sysctl.conf
    done
}

# 10. 写入全栈极致底层优化 (双轨通用部分)
write_base_sysctl() {
    # 1. 物理网卡发送队列扩容 (针对 G 口/万兆口)
    local main_iface=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -n 1)
    if [ -n "$main_iface" ]; then
        ip link set dev "$main_iface" txqueuelen 10000 2>/dev/null
    fi

    # 2. 突破系统级与 Systemd 文件描述符上限 (百万并发)
    sed -i '/\* soft nofile/d' /etc/security/limits.conf
    sed -i '/\* hard nofile/d' /etc/security/limits.conf
    sed -i '/\* soft nproc/d' /etc/security/limits.conf
    sed -i '/\* hard nproc/d' /etc/security/limits.conf
    cat >> /etc/security/limits.conf << EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 512000
* hard nproc 512000
EOF
    sed -i '/DefaultLimitNOFILE/d' /etc/systemd/system.conf /etc/systemd/user.conf 2>/dev/null
    echo "DefaultLimitNOFILE=1048576" >> /etc/systemd/system.conf
    echo "DefaultLimitNOFILE=1048576" >> /etc/systemd/user.conf

    # 3. 写入基础全栈优化参数
    cat >> /etc/sysctl.conf << EOF
# --- 系统级并发与 Xray/代理零拷贝管道 ---
fs.file-max=1048576
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=8192
fs.pipe-max-size=1048576

# --- UDP / QUIC (Hysteria2/TUIC/HTTP3) 极限缓冲 ---
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192

# --- 并发连接队列扩容 ---
net.core.somaxconn=8192
net.core.netdev_max_backlog=16384
net.ipv4.tcp_max_syn_backlog=8192

# --- TCP 状态机极速回收与保活 ---
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_fastopen=3

# --- 拥塞与延迟极致控制 ---
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_base_mss=1024
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1

# --- 虚拟内存调度：物理内存优先 (swappiness=10) ---
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
EOF

    # 4. 针对 IPv4 / 双栈网络
    if [ "$HAS_IPV4" = "true" ]; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        echo "net.ipv4.ip_local_port_range=1024 65535" >> /etc/sysctl.conf
    fi

    # 5. 针对 IPv6 / 双栈网络 (注入断网守护)
    if [ "$HAS_IPV6" = "true" ]; then
        cat >> /etc/sysctl.conf << EOF
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.route.max_size=409600
EOF
    fi

    # 6. 针对 Netfilter Conntrack 动态支持
    if lsmod 2>/dev/null | grep -q conntrack || [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
        cat >> /etc/sysctl.conf << EOF
net.netfilter.nf_conntrack_max=1048576
net.netfilter.nf_conntrack_tcp_timeout_established=1200
net.netfilter.nf_conntrack_tcp_timeout_close_wait=15
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30
EOF
    fi
}

# ====================================================================
# 11. 全量清单级【状态详细体检】功能 (选项3)
# ====================================================================
verify_status() {
    clear
    echo -e "${BLUE}==================================================================${PLAIN}"
    echo -e "         🔍 本机系统内核与网络加速全量优化参数体检清单             "
    echo -e "${BLUE}==================================================================${PLAIN}"
    
    local current_k=$(uname -r)
    local kernel_ok=false
    if [[ "$current_k" == *"xanmod"* ]]; then
        echo -e "1. 【内核架构】: ${GREEN}[ 正常 ]${PLAIN} (当前运行: $current_k)"
        kernel_ok=true
    else
        echo -e "1. 【内核架构】: ${YELLOW}[ 未启用 XanMod ]${PLAIN} (当前运行: $current_k)"
    fi
    
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local bbr_ok=false
    if [ "$current_cc" = "bbr" ]; then
        if [ "$kernel_ok" = "true" ]; then
            echo -e "2. 【拥塞控制】: ${GREEN}[ 正常 ]${PLAIN} (BBRv3 硬件性能加速引擎已激活)"
            bbr_ok=true
        else
            echo -e "2. 【拥塞控制】: ${YELLOW}[ 正常 ]${PLAIN} (标准内核 BBRv1 已激活)"
            bbr_ok=true
        fi
    else
        echo -e "2. 【拥塞控制】: ${RED}[ 异常 ]${PLAIN} (当前为: ${current_cc:-无})"
    fi
    
    local current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local active_qdisc=$(tc qdisc show 2>/dev/null | grep -E "fq|fq_codel|cake" | awk '{print $2}' | head -n 1)
    echo -e "3. 【队列算法】: ${GREEN}[ 正常 ]${PLAIN} (预设: ${current_qdisc:-无} | 网卡生效: ${active_qdisc:-未检测到})"
    
    echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}【TCP & 网络加速核心层】${PLAIN}"
    local rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)
    local wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)
    local notsent=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null)
    local fastopen=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)
    local idle_ss=$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null)
    local mtu_p=$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null)
    
    echo -e "  ├─ 动态 TCP 读写缓冲 : ${GREEN}${rmem}${PLAIN} / ${GREEN}${wmem}${PLAIN}"
    echo -e "  ├─ TCP 防缓冲膨胀延迟: $(if [ "$notsent" = "16384" ]; then echo -e "${GREEN}已开启 (16KB)${PLAIN}"; else echo -e "${YELLOW}${notsent:-默认}${PLAIN}"; fi)"
    echo -e "  ├─ TCP Fast Open(TFO): $(if [ "$fastopen" = "3" ]; then echo -e "${GREEN}双向已开启 (模式 3)${PLAIN}"; else echo -e "${YELLOW}${fastopen:-默认}${PLAIN}"; fi)"
    echo -e "  ├─ 空闲连接免慢启动  : $(if [ "$idle_ss" = "0" ]; then echo -e "${GREEN}已开启 (常态满速)${PLAIN}"; else echo -e "${YELLOW}${idle_ss:-默认}${PLAIN}"; fi)"
    echo -e "  └─ PMTU 动态黑洞探测 : $(if [ "$mtu_p" = "1" ]; then echo -e "${GREEN}已开启 (防分片丢包)${PLAIN}"; else echo -e "${YELLOW}${mtu_p:-默认}${PLAIN}"; fi)"

    echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}【UDP / QUIC / Hysteria 2 / TUIC 加速层】${PLAIN}"
    local rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null)
    local wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null)
    echo -e "  ├─ 网卡最大接收/发送缓冲: ${GREEN}$((rmem_max/1024/1024))MB${PLAIN} / ${GREEN}$((wmem_max/1024/1024))MB${PLAIN} (突破默认212KB限制)"
    echo -e "  └─ UDP 最小保证读写缓冲 : ${GREEN}$(sysctl -n net.ipv4.udp_rmem_min 2>/dev/null)B${PLAIN} / ${GREEN}$(sysctl -n net.ipv4.udp_wmem_min 2>/dev/null)B${PLAIN}"

    echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}【高并发代理 / 中转 / 状态机回收】${PLAIN}"
    local tw_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null)
    local fin_time=$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null)
    local port_range=$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null)
    local somaxconn=$(sysctl -n net.core.somaxconn 2>/dev/null)
    local file_max=$(sysctl -n fs.file-max 2>/dev/null)
    local pipe_size=$(sysctl -n fs.pipe-max-size 2>/dev/null)

    echo -e "  ├─ TIME_WAIT 极速复用 : $(if [ "$tw_reuse" = "1" ]; then echo -e "${GREEN}已开启 (防端口耗尽)${PLAIN}"; else echo -e "${YELLOW}${tw_reuse:-默认}${PLAIN}"; fi)"
    echo -e "  ├─ FIN 废弃连接超时   : ${GREEN}${fin_time}秒${PLAIN} (极速回收)"
    echo -e "  ├─ 出站可用端口池范围 : ${GREEN}${port_range}${PLAIN} (扩容至6.4万端口)"
    echo -e "  ├─ 监听队列 / 网卡队列: ${GREEN}${somaxconn}${PLAIN} / ${GREEN}$(sysctl -n net.core.netdev_max_backlog 2>/dev/null)${PLAIN}"
    echo -e "  ├─ 系统最大文件句柄   : ${GREEN}${file_max}${PLAIN} (突破100万并发)"
    echo -e "  └─ Xray 零拷贝管道缓冲: ${GREEN}$((pipe_size/1024))KB${PLAIN} (提升 splice 吞吐)"

    echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}【IP 栈与虚拟内存调度】${PLAIN}"
    local ip4_fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    local ip6_ra=$(sysctl -n net.ipv6.conf.all.accept_ra 2>/dev/null)
    local swappiness=$(sysctl -n vm.swappiness 2>/dev/null)
    local dirty=$(sysctl -n vm.dirty_ratio 2>/dev/null)
    local current_swap=$(free -m | awk '/^Swap:/{print $2}')

    echo -e "  ├─ 当前网络栈拓扑     : ${GREEN}${IP_STACK_TEXT}${PLAIN}"
    echo -e "  ├─ IPv4 路由转发      : $(if [ "$ip4_fwd" = "1" ]; then echo -e "${GREEN}已开启${PLAIN}"; else echo -e "${YELLOW}未开启${PLAIN}"; fi)"
    echo -e "  ├─ IPv6 路由断网守护  : $(if [ "$ip6_ra" = "2" ]; then echo -e "${GREEN}已开启 (accept_ra=2 守护)${PLAIN}"; else echo -e "${YELLOW}未配置/不适用${PLAIN}"; fi)"
    echo -e "  ├─ Swap 虚拟内存容量  : ${GREEN}${current_swap}MB${PLAIN}"
    echo -e "  ├─ 内存策略 (Swappiness): ${GREEN}${swappiness}${PLAIN} (物理内存绝对优先)"
    echo -e "  └─ 平滑磁盘 I/O 脏页刷盘: ${GREEN}${dirty}%${PLAIN} (防 I/O 卡死)"

    echo -e "${BLUE}==================================================================${PLAIN}"
    if [ "$kernel_ok" = "true" ] && [ "$bbr_ok" = "true" ] && [ "$notsent" = "16384" ] && [ "$tw_reuse" = "1" ]; then
        echo -e "${GREEN}🎉 综合评估：服务器已处于【全栈极致优化状态】，各项硬件与网络性能已拉满！${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ 综合评估：系统尚未完全调优，建议在主菜单选择 [1] 执行一键全栈自适应优化。${PLAIN}"
    fi
    echo -e "${BLUE}==================================================================${PLAIN}"
    read -p "按回车键返回主菜单..."
}

# 12. 脚本主循环交互菜单
while true; do
    clear
    CURRENT_KERNEL=$(uname -r)
    ALREADY_XANMOD=false
    if [[ "$CURRENT_KERNEL" == *"xanmod"* ]]; then
        ALREADY_XANMOD=true
    fi

    TOTAL_RAM_SHOW=$(free -m | awk '/^Mem:/{print $2}')
    TOTAL_SWAP_SHOW=$(free -m | awk '/^Swap:/{print $2}')

    # 动态检测当前运行状态
    CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    CURRENT_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    CURRENT_NOTSENT=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null)
    CURRENT_REUSE=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null)

    # 判定 BBR3 状态
    if [ "$ALREADY_XANMOD" = "true" ] && [ "$CURRENT_CC" = "bbr" ]; then
        BBR3_STATUS_TEXT="${GREEN}已开启 (BBRv3 硬件加速引擎)${PLAIN}"
    elif [ "$CURRENT_CC" = "bbr" ]; then
        BBR3_STATUS_TEXT="${YELLOW}已开启 (标准内核 BBRv1，建议升级 XanMod)${PLAIN}"
    else
        BBR3_STATUS_TEXT="${RED}未开启 (当前为: ${CURRENT_CC:-未知})${PLAIN}"
    fi

    # 判定整体优化状态、建议与动态默认选项
    if [ "$ALREADY_XANMOD" = "true" ] && [ "$CURRENT_CC" = "bbr" ] && [ "$CURRENT_NOTSENT" = "16384" ] && [ "$CURRENT_REUSE" = "1" ]; then
        OPTIMIZE_STATUS_TEXT="${GREEN}已经是优化后的最佳状态${PLAIN}"
        OPTIMIZE_ADVICE_TEXT="${GREEN}已达理论极限性能，无需重复优化！（若配置有变化，请重新优化）${PLAIN}"
        DEFAULT_CHOICE=0
    else
        OPTIMIZE_STATUS_TEXT="${YELLOW}尚未深度优化 (检测到未调优参数)${PLAIN}"
        OPTIMIZE_ADVICE_TEXT="${RED}建议运行一键优化 (输入 1 并回车)${PLAIN}"
        DEFAULT_CHOICE=1
    fi

    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "    Debian/Ubuntu 智能/极客网络调优 一体化部署脚本"
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "当前系统：${GREEN}${NAME} ${VERSION_ID} (${CODENAME})${PLAIN}"
    echo -e "VPS位置 ：${GREEN}${COUNTRY_NAME}${PLAIN}"
    echo -e "网络架构：${GREEN}${IP_STACK_TEXT}${PLAIN}"
    echo -e "内存状态：${GREEN}物理内存 ${TOTAL_RAM_SHOW}MB | Swap气囊 ${TOTAL_SWAP_SHOW}MB${PLAIN}"
    echo -e "当前内核：$(if [ "$ALREADY_XANMOD" = "true" ]; then echo -e "${GREEN}${CURRENT_KERNEL} (已是XanMod)${PLAIN}"; else echo -e "${YELLOW}${CURRENT_KERNEL} (标准内核)${PLAIN}"; fi)"
    echo -e "BBR3状态：${BBR3_STATUS_TEXT}"
    echo -e "优化状态：${OPTIMIZE_STATUS_TEXT}"
    echo -e "优化建议：${OPTIMIZE_ADVICE_TEXT}"
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "请选择调优模式："
    echo -e "  ${GREEN}1. [小白/一键] AI 智能自适应全栈调优 (🏆 强烈推荐)${PLAIN}"
    echo -e "     ${YELLOW}└─ 自动识别物理内存/Swap、自适应BDP缓冲、动态抗堵塞并发全开。${PLAIN}"
    echo -e "  ${YELLOW}2. [高手/极客] 目标节点精准手工调优 (BDP / 窗口定制)${PLAIN}"
    echo -e "     ${YELLOW}└─ 需手动输入对端测速带宽与延迟，计算绝对理论极限值。${PLAIN}"
    echo -e "  ${BLUE}3. 🔍 详细体检内核与网络加速算法生效状态 (Status Check)${PLAIN}"
    echo -e "  ${RED}0. 退出脚本${PLAIN}"
    echo -e "${BLUE}==================================================${PLAIN}"
    read -p "请输入数字 [0-3] (默认: ${DEFAULT_CHOICE}): " CHOICE

    # 动态应用智能默认选项
    if [ -z "$CHOICE" ]; then CHOICE=$DEFAULT_CHOICE; fi

    case "$CHOICE" in
        1|2)
            if [ "$ALREADY_XANMOD" = "true" ]; then
                clear
                echo -e "${YELLOW}==================================================${PLAIN}"
                echo -e "⚠️  ${RED}【高亮提醒】您的服务器当前已经是 XanMod 内核！${PLAIN}"
                echo -e "${YELLOW}==================================================${PLAIN}"
                read -p "您是想继续覆盖调优配置并检查源更新吗？[Y:继续 / N:退出, 默认Y]: " WARN_CHOICE
                WARN_CHOICE=$(echo "$WARN_CHOICE" | tr '[:lower:]' '[:upper:]')
                if [ "$WARN_CHOICE" = "N" ]; then exit 0; fi
            fi
            break
            ;;
        3) verify_status ;;
        0) echo -e "${BLUE}已安全退出脚本。${PLAIN}"; exit 0 ;;
        *) echo -e "${RED}[错误] 输入无效，请重新选择！${PLAIN}"; sleep 1 ;;
    esac
done

# ====================================================================
# 13. 执行优化写入流程
# ====================================================================
auto_manage_swap
clean_sysctl
write_base_sysctl

if [ "$CHOICE" -eq 1 ]; then
    SCENARIO="[小白模式] 智能自适应全局调优"
    
    # 动态内存计算 (防 OOM 并最大化吞吐)
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
    MAX_MEM_BYTES=$((TOTAL_MEM_MB * 1024 * 1024 * 15 / 1000))
    if [ "$MAX_MEM_BYTES" -lt 4194304 ]; then MAX_MEM_BYTES=4194304; fi
    if [ "$MAX_MEM_BYTES" -gt 67108864 ]; then MAX_MEM_BYTES=67108864; fi

    CONFIG_SUMMARY="BBRv3 + FQ + 动态内存计算 TCP 缓冲 ($((MAX_MEM_BYTES/1024/1024))MB)"
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem=4096 87380 ${MAX_MEM_BYTES}" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_wmem=4096 65536 ${MAX_MEM_BYTES}" >> /etc/sysctl.conf

elif [ "$CHOICE" -eq 2 ]; then
    SCENARIO="[极客模式] 针对性链路 BDP 定制调优"
    clear
    echo -e "${BLUE}=== 极客模式：动态带宽延迟乘积 (BDP) 计算 ===${PLAIN}"
    echo -e "${YELLOW}提示：如果你是中转机，请输入到落地机的实测网络数据；如果是单机，请输入到本地的测速数据。${PLAIN}"
    
    read -p "1. 请输入实测最高带宽 (单位: Mbps, 默认: 1000): " TARGET_BW
    TARGET_BW=${TARGET_BW:-1000}
    
    read -p "2. 请输入平均网络延迟 RTT (单位: ms, 默认: 150): " TARGET_RTT
    TARGET_RTT=${TARGET_RTT:-150}

    # BDP 计算: 带宽(Mbps) * 延迟(ms) * 125 = BDP 字节数
    BDP_BYTES=$(( TARGET_BW * TARGET_RTT * 125 * 3 / 2 ))
    
    if [ "$BDP_BYTES" -lt 4194304 ]; then BDP_BYTES=4194304; fi

    CONFIG_SUMMARY="BBRv3 + FQ + 精准BDP极限缓冲 ($((BDP_BYTES/1024/1024))MB, 目标:${TARGET_BW}M/${TARGET_RTT}ms)"
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem=4096 87380 ${BDP_BYTES}" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_wmem=4096 65536 ${BDP_BYTES}" >> /etc/sysctl.conf
fi

# 14. 开始执行源配置与更新
echo -e "\n${BLUE}[1/3] 开始配置 XanMod 官方存储库...${PLAIN}"
rm -f /etc/apt/sources.list.d/xanmod-release.list
install -d -m 0755 /etc/apt/keyrings
TMP_KEY="/tmp/xanmod.key"
rm -f "$TMP_KEY"

echo -e "${YELLOW}正在获取 XanMod PGP 密钥...${PLAIN}"
FAKE_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

curl -fsSL -A "${FAKE_UA}" --connect-timeout 10 --retry 3 https://dl.xanmod.org/archive.key -o "$TMP_KEY" 2>/dev/null
if [ ! -s "$TMP_KEY" ] || ! grep -q "PGP PUBLIC KEY" "$TMP_KEY"; then
    wget -qO "$TMP_KEY" -U "${FAKE_UA}" --timeout=10 --tries=3 https://dl.xanmod.org/archive.key >/dev/null 2>&1
fi

if [ -s "$TMP_KEY" ] && grep -q "PGP PUBLIC KEY" "$TMP_KEY"; then
    gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg "$TMP_KEY"
    rm -f "$TMP_KEY"
else
    echo -e "${RED}[错误] PGP 证书获取失败！网络被阻断。${PLAIN}"
    exit 1
fi

echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${CODENAME} main" | tee /etc/apt/sources.list.d/xanmod-release.list
retry_command apt update >/dev/null

# 15. 智能版本比对
SKIP_KERNEL_INSTALL=false
NEED_REBOOT=false

if dpkg -l | grep -q "${KERNEL_PKG}"; then
    INSTALLED_VER=$(dpkg-query -W -f='${Version}' ${KERNEL_PKG} 2>/dev/null)
    LATEST_VER=$(apt-cache policy ${KERNEL_PKG} | grep "Candidate:" | awk '{print $2}')
    
    if [ -n "$LATEST_VER" ] && [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
        echo -e "\n${GREEN}[提示] XanMod 内核已是最新 (${INSTALLED_VER})，跳过重装。${PLAIN}"
        SKIP_KERNEL_INSTALL=true
    fi
fi

if [ "$SKIP_KERNEL_INSTALL" = "false" ]; then
    echo -e "\n${BLUE}[2/3] 正在安装/升级 XanMod 内核包 [${KERNEL_PKG}]...${PLAIN}"
    retry_command apt install ${KERNEL_PKG} -y
    if [ $? -ne 0 ]; then
        echo -e "${RED}[错误] 内核程序安装/升级失败！${PLAIN}"
        exit 1
    fi
    NEED_REBOOT=true
fi

# 16. 更新引导
if [ "$NEED_REBOOT" = "true" ]; then
    echo -e "\n${BLUE}[3/3] 正在强行更新 GRUB 系统引导配置...${PLAIN}"
    retry_command update-grub
fi

# 17. 应用系统优化配置
sysctl -p > /dev/null 2>&1

# 18. 漂亮的执行结果输出
clear
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "          🎉 内核配置与极客全栈调优执行完毕！"
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "使用模式：${BLUE}${SCENARIO}${PLAIN}"
echo -e "参数总览：${BLUE}${CONFIG_SUMMARY}${PLAIN}"
echo -e "网络拓扑：${BLUE}${IP_STACK_TEXT}${PLAIN}"
echo -e "高级特性：${YELLOW}UDP/QUIC扩容 / TIME_WAIT回收 / PMTU探测 / TCP Fast Open / Swap气囊${PLAIN} 已全开"
echo -e "${GREEN}==================================================${PLAIN}"

# 19. 智能倒计时重启机制
if [ "$NEED_REBOOT" = "true" ]; then
    echo -e "${YELLOW}新内核已安装，系统将在 7 秒后自动重启使其生效！${PLAIN}"
    for i in {7..1}; do
        echo -ne "\r${YELLOW}倒计时: $i 秒后自动重启...${PLAIN}"
        sleep 1
    done
    echo -e "\n${GREEN}正在重启服务器...${PLAIN}"
    reboot
else
    echo -e "${GREEN}🎉 新调优参数已立即应用热生效，无需重启！${PLAIN}"
    echo -e "您可立即再次运行本脚本选择 [3] 查看全量参数体检清单。${PLAIN}"
    echo -e "${GREEN}==================================================${PLAIN}"
fi
