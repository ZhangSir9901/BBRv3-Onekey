#!/bin/bash # 核心作用：Debian/Ubuntu 一键安装 XanMod BBRv3 与全栈网络极致性能动态调优生命周期管理
# SCRIPT_VERSION="2.4.0"

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

# 系统自愈机制：自动解决历史中断遗留的 dpkg 锁死与未完成配置状态
if command -v dpkg >/dev/null 2>&1; then
    dpkg --configure -a >/dev/null 2>&1
fi

if [ ! -f /etc/os-release ]; then
    echo -e "${RED}[错误] 无法识别当前系统架构！${PLAIN}"
    exit 1
fi

. /etc/os-release

# 标准化 Debian / Ubuntu 版本信息与代号兼容 (增强对 Debian 13 Trixie 测试/滚动/云镜像的识别)
SUPPORTED=false

OS_ID="${ID:-}"
OS_ID_LIKE="${ID_LIKE:-}"
OS_VER_ID="${VERSION_ID:-}"
OS_CODENAME="${VERSION_CODENAME:-}"

# 尝试通过 /etc/debian_version 兜底检测 Debian 测试版/衍生版本
if [ -z "$OS_CODENAME" ] && [ -f /etc/debian_version ]; then
    DEB_VER=$(cat /etc/debian_version 2>/dev/null)
    if [[ "$DEB_VER" == 13* ]] || [[ "$DEB_VER" == *"trixie"* ]]; then
        OS_CODENAME="trixie"
        [ -z "$OS_VER_ID" ] && OS_VER_ID="13"
    elif [[ "$DEB_VER" == 12* ]] || [[ "$DEB_VER" == *"bookworm"* ]]; then
        OS_CODENAME="bookworm"
        [ -z "$OS_VER_ID" ] && OS_VER_ID="12"
    fi
fi

# 若为 trixie 且未带版本号，规范化为 Debian 13
if [ "$OS_CODENAME" = "trixie" ] || [[ "${VERSION:-}" == *"trixie"* ]]; then
    OS_ID="debian"
    OS_VER_ID="13"
    OS_CODENAME="trixie"
elif [ "$OS_CODENAME" = "bookworm" ] || [[ "${VERSION:-}" == *"bookworm"* ]]; then
    OS_ID="debian"
    OS_VER_ID="12"
    OS_CODENAME="bookworm"
fi

if [ "$OS_ID" = "debian" ] || [[ "$OS_ID_LIKE" =~ debian ]]; then
    if [ "$OS_VER_ID" = "12" ] || [ "$OS_VER_ID" = "13" ]; then
        SUPPORTED=true
        ID="debian"
        VERSION_ID="$OS_VER_ID"
        VERSION_CODENAME="${OS_CODENAME:-$VERSION_CODENAME}"
    fi
elif [ "$OS_ID" = "ubuntu" ] || [[ "$OS_ID_LIKE" =~ ubuntu ]]; then
    if [ "$OS_VER_ID" = "20.04" ] || [ "$OS_VER_ID" = "22.04" ] || [ "$OS_VER_ID" = "24.04" ] || [ "$OS_VER_ID" = "26.04" ]; then
        SUPPORTED=true
        ID="ubuntu"
        VERSION_ID="$OS_VER_ID"
        VERSION_CODENAME="${OS_CODENAME:-$VERSION_CODENAME}"
    fi
fi

if [ "$SUPPORTED" = "false" ]; then
    echo -e "${RED}[错误] 本脚本仅支持 Debian 12/13 以及 Ubuntu LTS (20.04/22.04/24.04/26.04)！${PLAIN}"
    echo -e "${YELLOW}当前系统为: ${ID:-未知} ${VERSION_ID:-未知版本} (${VERSION_CODENAME:-未知代号})${PLAIN}"
    exit 1
fi

# 2. 预检并安装基础依赖
if ! command -v gpg >/dev/null 2>&1 || ! command -v wget >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || [ ! -d /etc/ssl/certs ]; then
    echo -e "${BLUE}正在修复包管理器状态并安装基础必要依赖...${PLAIN}"
    dpkg --configure -a >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get --fix-broken install -y >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install wget curl gpg gnupg lsb-release ca-certificates -y >/dev/null 2>&1
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
    cc=$(curl $curl_flag -s --connect-timeout 4 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^loc=' | cut -d= -f2)
    if [ -n "$cc" ] && [ "$cc" != "XX" ] && [ ${#cc} -eq 2 ]; then
        echo "$cc"
        return
    fi
    cc=$(curl $curl_flag -s --connect-timeout 4 https://ipinfo.io/country)
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
    echo -e "1. 该厂商底层虚拟化（KVM）默认裁剪/屏蔽了 x86-64-v3 高级指令集，强制安装第三方内核会导致开机崩溃 (Kernel Panic)。"
    echo -e "2. 该厂商深度绑定了专有 VirtIO 虚拟网卡驱动与云盾监控，第三方内核无法正常接管网卡，易造成 SSH 永久断联。"
    echo -e "3. 无论是国内节点还是海外节点，该厂商均使用相同的封闭底层虚拟化，不适合刷写第三方性能内核。"
    echo -e "${RED}================================================================${PLAIN}"
    echo -e "${GREEN}👉 兼容推荐：建议在正规国际云厂商（如 DMIT、搬瓦工、AWS、甲骨文、Linode、Hetzner 等）上运行。${PLAIN}"
    echo -e "${BLUE}为了保护您的服务器数据与连接安全，脚本已安全退出。${PLAIN}"
    exit 1
fi

# ====================================================================
# 6. CPU 指令集智能动态探测与降级匹配 (AVX2 / x86-64-v1 ~ v3)
# ====================================================================
detect_cpu_tier() {
    local ld_bin=""
    [ -f /lib/ld-linux-x86-64.so.2 ] && ld_bin="/lib/ld-linux-x86-64.so.2"
    [ -f /lib64/ld-linux-x86-64.so.2 ] && ld_bin="/lib64/ld-linux-x86-64.so.2"

    if [ -n "$ld_bin" ]; then
        local supported_tiers
        supported_tiers=$($ld_bin --help 2>/dev/null | grep -E "x86-64-v[234] \(supported")
        if echo "$supported_tiers" | grep -q "x86-64-v3"; then echo "x64v3"; return; fi
        if echo "$supported_tiers" | grep -q "x86-64-v2"; then echo "x64v2"; return; fi
    fi

    # 兜底探测: 检查 /proc/cpuinfo 标志位
    if grep -q -E "\bavx2\b" /proc/cpuinfo 2>/dev/null && grep -q -E "\bbmi2\b" /proc/cpuinfo 2>/dev/null; then
        echo "x64v3"
    elif grep -q -E "\bsse4_2\b" /proc/cpuinfo 2>/dev/null && grep -q -E "\bpopcnt\b" /proc/cpuinfo 2>/dev/null; then
        echo "x64v2"
    else
        echo "x64v1"
    fi
}

CPU_TIER=$(detect_cpu_tier)
case "$CPU_TIER" in
    x64v3) CPU_TIER_TEXT="x86-64-v3 (🚀 支持 AVX2/BMI2 满血指令集)" ;;
    x64v2) CPU_TIER_TEXT="x86-64-v2 (🛡️ 无 AVX2，已智能降级兼容内核)" ;;
    x64v1) CPU_TIER_TEXT="x86-64-v1 (⚙️ 基础通用兜底指令集)" ;;
esac

# 规范化 Codename
CODENAME="${VERSION_CODENAME}"
if [ -z "$CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
    CODENAME=$(lsb_release -sc 2>/dev/null)
fi
if [ -z "$CODENAME" ]; then
    if [ "$ID" = "debian" ] && [ "$VERSION_ID" = "13" ]; then CODENAME="trixie"
    elif [ "$ID" = "debian" ] && [ "$VERSION_ID" = "12" ]; then CODENAME="bookworm"
    fi
fi

# 内核策略智能初选 (老旧 CPU 强制默认锁定 LTS，满血硬件统一默认选用 MAIN 最新主线 7.2.x 版)
if [ "$CPU_TIER" = "x64v1" ]; then
    # XanMod 官方仓库仅在 LTS 分支提供 x64v1 兜底支持
    KERNEL_PKG="linux-xanmod-lts-x64v1"
    KERNEL_BRANCH_NAME="LTS (6.18.x 长期维护稳定版)"
else
    # 满血硬件 (x64v2 / x64v3): 统一默认选用 MAIN 最新主线稳定版 (当前 7.2.x，极速吞吐与最新 BBRv3)
    KERNEL_PKG="linux-xanmod-${CPU_TIER}"
    KERNEL_BRANCH_NAME="MAIN (7.2.x 最新主线稳定版)"
fi
KERNEL_EXTRA_PKG=""
KERNEL_HOLD=false

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
# 8. 内存查询助手与小内存智能“急救气囊” (Swap 自动兜底检测与创建)
# ====================================================================
get_ram_mb() {
    free -m | awk '/^Mem:/{print $2}'
}

get_swap_mb() {
    free -m | awk '/^Swap:/{print $2}'
}

auto_manage_swap() {
    local total_ram_mb=$(get_ram_mb)
    local current_swap_mb=$(get_swap_mb)

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

# ====================================================================
# 9. VirtIO 核心驱动固化 (针对所有海外 KVM VPS 防断网/防丢盘)
# ====================================================================
solidify_virtio_drivers() {
    if [ -d /etc/initramfs-tools ]; then
        touch /etc/initramfs-tools/modules
        for mod in virtio virtio_pci virtio_net virtio_blk virtio_scsi virtio_ring; do
            if ! grep -q "^$mod" /etc/initramfs-tools/modules 2>/dev/null; then
                echo "$mod" >> /etc/initramfs-tools/modules
            fi
        done
    fi
}

# 常量与状态存储路径定义 (解耦独立配置与出厂快照)
BBR_SYSCTL_FILE="/etc/sysctl.d/99-bbr-tune.conf"
SNAPSHOT_DIR="/var/lib/bbr_tune"
SNAPSHOT_FILE="/var/lib/bbr_tune/factory.snapshot"
INITCWND_SCRIPT="/usr/local/sbin/bbr-initcwnd.sh"
INITCWND_SERVICE="/etc/systemd/system/bbr-initcwnd.service"

# ====================================================================
# 出厂网络配置快照自动备份 (为一键安全回滚提供坚实基石)
# ====================================================================
take_factory_snapshot() {
    if [ -f "$SNAPSHOT_FILE" ]; then
        return 0
    fi
    mkdir -p "$SNAPSHOT_DIR"
    local tmp_snap
    tmp_snap=$(mktemp "${SNAPSHOT_FILE}.XXXXXX" 2>/dev/null) || return 1
    {
        echo "# BBRv3-Onekey 出厂网络配置快照 $(date -u +%FT%TZ)"
        echo "KERNEL=$(uname -r)"
        local default_route
        default_route=$(ip -4 route show default 2>/dev/null | head -n 1)
        echo "DEFAULT_ROUTE=${default_route}"

        local check_keys=(
            "net.core.default_qdisc" "net.ipv4.tcp_congestion_control" "net.ipv4.tcp_rmem" "net.ipv4.tcp_wmem"
            "net.core.rmem_max" "net.core.wmem_max" "net.core.somaxconn" "net.core.netdev_max_backlog"
            "net.core.netdev_budget" "net.core.optmem_max" "net.ipv4.tcp_tw_reuse" "net.ipv4.tcp_fastopen"
            "net.ipv4.tcp_slow_start_after_idle" "net.ipv4.tcp_notsent_lowat" "net.ipv4.ip_forward"
            "vm.swappiness"
        )
        for k in "${check_keys[@]}"; do
            local val
            val=$(sysctl -n "$k" 2>/dev/null)
            if [ -n "$val" ]; then
                echo "SYSCTL:${k}=${val}"
            fi
        done
    } > "$tmp_snap"
    mv -f "$tmp_snap" "$SNAPSHOT_FILE"
}

# ====================================================================
# initcwnd 32 起步满速注入与持久化 (免 RTT 等待，TLS 握手与首屏秒开)
# ====================================================================
apply_and_persist_initcwnd() {
    local default_route
    default_route=$(ip -4 route show default 2>/dev/null | head -n 1)
    if [ -z "$default_route" ]; then
        return 1
    fi

    local -a args=() clean_args=()
    read -r -a args <<< "$default_route"
    local skip=0
    for token in "${args[@]}"; do
        if [ "$skip" -eq 1 ]; then skip=0; continue; fi
        case "$token" in
            initcwnd|initrwnd) skip=1 ;;
            *) clean_args+=("$token") ;;
        esac
    done

    if [ "${#clean_args[@]}" -gt 1 ]; then
        ip -4 route replace "${clean_args[@]}" initcwnd 32 initrwnd 32 2>/dev/null
    fi

    cat > "$INITCWND_SCRIPT" << 'EOF'
#!/bin/bash # 核心作用：开机与网络就绪后自动注入并维持 initcwnd 32 首包秒开
route=$(ip -4 route show default 2>/dev/null | head -n 1)
if [ -n "$route" ]; then
    read -r -a args <<< "$route"
    clean=()
    skip=0
    for t in "${args[@]}"; do
        if [ "$skip" -eq 1 ]; then skip=0; continue; fi
        case "$t" in initcwnd|initrwnd) skip=1 ;; *) clean+=("$t") ;; esac
    done
    [ "${#clean[@]}" -gt 1 ] && ip -4 route replace "${clean[@]}" initcwnd 32 initrwnd 32 2>/dev/null
fi
EOF
    chmod +x "$INITCWND_SCRIPT"

    cat > "$INITCWND_SERVICE" << EOF
[Unit]
Description=BBRv3 Initcwnd 32 Performance Accelerator
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${INITCWND_SCRIPT}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable bbr-initcwnd.service >/dev/null 2>&1
    systemctl start bbr-initcwnd.service >/dev/null 2>&1
}

# ====================================================================
# 一键回滚还原到系统出厂网络配置 (安全零残留)
# ====================================================================
rollback_to_factory() {
    clear
    echo -e "${YELLOW}==================================================================${PLAIN}"
    echo -e "       ⏪ 一键回滚还原到系统出厂网络配置 (Rollback to Factory)      "
    echo -e "${YELLOW}==================================================================${PLAIN}"
    echo -e "此操作将执行以下恢复动作："
    echo -e "  1. 移除独立调优配置文件 ${GREEN}${BBR_SYSCTL_FILE}${PLAIN}；"
    echo -e "  2. 停止并注销 ${GREEN}bbr-initcwnd.service${PLAIN}，恢复出厂默认路由初始窗口；"
    echo -e "  3. 还原出厂快照记录的基础 sysctl 参数并重新加载生效；"
    echo -e "  4. 绝不卸载已安装的内核程序（保持系统可用引导）。"
    echo -e "${YELLOW}------------------------------------------------------------------${PLAIN}"
    read -p "您确认要回滚还原到出厂网络配置吗？[Y:确认回滚 / N:取消返回, 默认N]: " CONFIRM_RB
    CONFIRM_RB=${CONFIRM_RB:-N}
    CONFIRM_RB=$(echo "$CONFIRM_RB" | tr '[:lower:]' '[:upper:]')
    if [ "$CONFIRM_RB" != "Y" ]; then
        echo -e "${BLUE}已取消回滚操作，返回主菜单。${PLAIN}"
        sleep 1
        return 0
    fi

    echo -e "\n${BLUE}正在停止并注销 initcwnd 32 持久化服务...${PLAIN}"
    systemctl disable --now bbr-initcwnd.service >/dev/null 2>&1
    rm -f "$INITCWND_SERVICE" "$INITCWND_SCRIPT"
    systemctl daemon-reload >/dev/null 2>&1

    # 恢复默认路由初始窗口
    local default_route
    default_route=$(ip -4 route show default 2>/dev/null | head -n 1)
    if [ -n "$default_route" ]; then
        local -a args=() clean_args=()
        read -r -a args <<< "$default_route"
        local skip=0
        for token in "${args[@]}"; do
            if [ "$skip" -eq 1 ]; then skip=0; continue; fi
            case "$token" in
                initcwnd|initrwnd) skip=1 ;;
                *) clean_args+=("$token") ;;
            esac
        done
        if [ "${#clean_args[@]}" -gt 1 ]; then
            ip -4 route replace "${clean_args[@]}" 2>/dev/null
        fi
    fi

    echo -e "${BLUE}正在清除 BBRv3 独立调优参数文件...${PLAIN}"
    rm -f "$BBR_SYSCTL_FILE"

    # 如果有出厂快照，按快照逐项写回
    if [ -f "$SNAPSHOT_FILE" ]; then
        echo -e "${BLUE}正在从出厂快照恢复系统原始参数...${PLAIN}"
        while IFS= read -r line; do
            if [[ "$line" =~ ^SYSCTL:(.+)=(.+)$ ]]; then
                local k="${BASH_REMATCH[1]}"
                local v="${BASH_REMATCH[2]}"
                sysctl -w "${k}=${v}" >/dev/null 2>&1
            fi
        done < "$SNAPSHOT_FILE"
    else
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
        sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1
    fi

    sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1
    echo -e "\n${GREEN}🎉 系统网络配置已成功回滚恢复至出厂状态！${PLAIN}"
    echo -e "${BLUE}==================================================================${PLAIN}"
    read -p "按回车键返回主菜单..."
}

# 10. 深度清理旧系统参数 (单次批量 sed 减少磁盘 I/O 损耗)
clean_sysctl() {
    local params=(
        "net.core.default_qdisc" "net.ipv4.tcp_congestion_control" "net.ipv4.tcp_rmem" "net.ipv4.tcp_wmem"
        "net.ipv4.tcp_notsent_lowat" "net.ipv4.tcp_mtu_probing" "net.ipv4.tcp_base_mss" "net.ipv4.tcp_sack"
        "net.ipv4.tcp_dsack" "net.core.somaxconn" "net.core.netdev_max_backlog" "net.core.netdev_budget"
        "net.core.optmem_max" "net.ipv4.tcp_max_syn_backlog" "net.ipv4.tcp_tw_reuse" "net.ipv4.tcp_fin_timeout"
        "net.ipv4.tcp_keepalive_time" "net.ipv4.tcp_fastopen" "net.ipv4.tcp_slow_start_after_idle"
        "net.core.rmem_max" "net.core.wmem_max" "net.core.rmem_default" "net.core.wmem_default"
        "net.ipv4.udp_rmem_min" "net.ipv4.udp_wmem_min" "net.ipv4.ip_local_port_range"
        "net.ipv4.ip_forward" "net.ipv6.conf.all.forwarding" "net.ipv6.conf.default.forwarding"
        "net.ipv6.conf.all.accept_ra" "net.ipv6.conf.default.accept_ra" "net.ipv6.route.max_size"
        "vm.swappiness" "vm.vfs_cache_pressure" "vm.dirty_ratio" "vm.dirty_background_ratio"
        "fs.file-max" "fs.inotify.max_user_watches" "fs.inotify.max_user_instances" "fs.pipe-max-size"
        "net.netfilter.nf_conntrack_max" "net.netfilter.nf_conntrack_tcp_timeout_established"
        "net.netfilter.nf_conntrack_tcp_timeout_close_wait" "net.netfilter.nf_conntrack_tcp_timeout_time_wait"
    )
    if [ -f /etc/sysctl.conf ]; then
        local sed_expr=""
        for p in "${params[@]}"; do
            sed_expr+="/^${p}/d;"
        done
        if [ -n "$sed_expr" ]; then
            sed -i "$sed_expr" /etc/sysctl.conf
        fi
    fi
    mkdir -p /etc/sysctl.d
    rm -f "$BBR_SYSCTL_FILE"
}

# 11. 写入全栈底层优化 (解耦写入 /etc/sysctl.d/99-bbr-tune.conf)
write_base_sysctl() {
    local mode=$1

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

    # 差异化配置参数 (模式 1: 综合稳健 | 模式 2: 纯代理极致 | 模式 3: 极客手工)
    local pipe_size=524288
    local udp_max=33554432
    local q_somaxconn=8192
    local q_backlog=16384
    local q_syn_backlog=8192
    local fin_to=20
    local keepalive_t=600

    if [ "$mode" -eq 2 ]; then
        pipe_size=1048576
        udp_max=67108864
        q_somaxconn=16384
        q_backlog=32768
        q_syn_backlog=16384
        fin_to=10
        keepalive_t=300
    elif [ "$mode" -eq 3 ]; then
        pipe_size=1048576
        udp_max=67108864
        q_somaxconn=8192
        q_backlog=16384
        q_syn_backlog=8192
        fin_to=15
        keepalive_t=600
    fi

    # 3. 写入独立全栈优化配置文件 (与系统全局配置彻底解耦)
    cat > "$BBR_SYSCTL_FILE" << EOF
# ====================================================================
# BBRv3-Onekey 全栈网络极客调优独立配置 (v2.4.0)
# ====================================================================

# --- 系统级并发与 Xray/代理零拷贝管道 ---
fs.file-max=1048576
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=8192
fs.pipe-max-size=${pipe_size}

# --- UDP / QUIC (Hysteria2/TUIC/HTTP3) 缓冲配置 ---
net.core.rmem_max=${udp_max}
net.core.wmem_max=${udp_max}
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192

# --- 并发连接队列与软中断吞吐扩容 (吸收 tcpfit 精华) ---
net.core.somaxconn=${q_somaxconn}
net.core.netdev_max_backlog=${q_backlog}
net.core.netdev_budget=600
net.core.optmem_max=65536
net.ipv4.tcp_max_syn_backlog=${q_syn_backlog}

# --- TCP 状态机极速回收与保活 ---
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=${fin_to}
net.ipv4.tcp_keepalive_time=${keepalive_t}
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
        echo "net.ipv4.ip_forward=1" >> "$BBR_SYSCTL_FILE"
        echo "net.ipv4.ip_local_port_range=1024 65535" >> "$BBR_SYSCTL_FILE"
    fi

    # 5. 针对 IPv6 / 双栈网络 (注入断网守护)
    if [ "$HAS_IPV6" = "true" ]; then
        cat >> "$BBR_SYSCTL_FILE" << EOF
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.route.max_size=409600
EOF
    fi

    # 6. 针对 Netfilter Conntrack 动态支持
    if lsmod 2>/dev/null | grep -q conntrack || [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
        cat >> "$BBR_SYSCTL_FILE" << EOF
net.netfilter.nf_conntrack_max=1048576
net.netfilter.nf_conntrack_tcp_timeout_established=1200
net.netfilter.nf_conntrack_tcp_timeout_close_wait=15
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30
EOF
    fi
}

# ====================================================================
# 12. XanMod 官方存储库安全配置与多轨道密钥校验 (双轨 gpg / asc 原生自愈)
# ====================================================================
ensure_xanmod_repo() {
    local keyring_file=""
    if [ -s /etc/apt/keyrings/xanmod-archive-keyring.gpg ]; then
        keyring_file="/etc/apt/keyrings/xanmod-archive-keyring.gpg"
    elif [ -s /etc/apt/keyrings/xanmod-archive-keyring.asc ]; then
        keyring_file="/etc/apt/keyrings/xanmod-archive-keyring.asc"
    fi

    # 校验源配置：若已存在且使用安全 HTTPS，则直接放行
    if [ -n "$keyring_file" ] && [ -f /etc/apt/sources.list.d/xanmod-release.list ] && grep -q "https://deb.xanmod.org" /etc/apt/sources.list.d/xanmod-release.list 2>/dev/null; then
        return 0
    fi

    echo -e "\n${BLUE}[存储库配置] 正在配置 XanMod 官方 APT 存储库与安全密钥...${PLAIN}"
    rm -f /etc/apt/sources.list.d/xanmod-release.list
    install -d -m 0755 /etc/apt/keyrings
    local tmp_key="/tmp/xanmod.key"
    rm -f "$tmp_key"

    local fake_ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    curl -fsSL -A "${fake_ua}" --connect-timeout 10 --retry 3 https://dl.xanmod.org/archive.key -o "$tmp_key" 2>/dev/null
    if [ ! -s "$tmp_key" ] || ! grep -q "PGP PUBLIC KEY" "$tmp_key"; then
        wget -qO "$tmp_key" -U "${fake_ua}" --timeout=10 --tries=3 https://dl.xanmod.org/archive.key >/dev/null 2>&1
    fi
    if [ ! -s "$tmp_key" ] || ! grep -q "PGP PUBLIC KEY" "$tmp_key"; then
        curl -fsSL -A "${fake_ua}" --connect-timeout 10 --retry 3 https://gitlab.com/afrd.gpg -o "$tmp_key" 2>/dev/null
    fi

    if [ -s "$tmp_key" ] && grep -q "PGP PUBLIC KEY" "$tmp_key"; then
        if command -v gpg >/dev/null 2>&1; then
            keyring_file="/etc/apt/keyrings/xanmod-archive-keyring.gpg"
            gpg --dearmor --yes -o "$keyring_file" "$tmp_key" >/dev/null 2>&1
        fi
        if [ ! -s "$keyring_file" ]; then
            keyring_file="/etc/apt/keyrings/xanmod-archive-keyring.asc"
            cp -f "$tmp_key" "$keyring_file"
        fi
        chmod 644 "$keyring_file" 2>/dev/null || true
        rm -f "$tmp_key"
    else
        echo -e "${RED}[错误] XanMod PGP 证书获取失败，请检查网络！${PLAIN}"
        return 1
    fi

    # 强制采用 HTTPS 加密传输，杜绝 HTTP 透明缓存污染与 Hash Mismatch
    echo "deb [signed-by=${keyring_file}] https://deb.xanmod.org ${CODENAME} main" | tee /etc/apt/sources.list.d/xanmod-release.list >/dev/null
    dpkg --configure -a >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive retry_command apt update >/dev/null
    return 0
}

# ====================================================================
# APT 缓存自愈与云端索引强制对齐 (根治 Hash Sum mismatch / Partial 损坏)
# ====================================================================
heal_apt_cache() {
    rm -rf /var/lib/apt/lists/*xanmod* /var/cache/apt/archives/partial/* /var/cache/apt/archives/*xanmod* >/dev/null 2>&1
    apt-get clean >/dev/null 2>&1
    dpkg --configure -a >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get update --fix-missing -y >/dev/null 2>&1
}

# 内核高可靠自愈安装引擎 (发生异常自动清洗脏缓存，并支持官方空壳元包脱节穿透直装)
install_kernel_with_self_healing() {
    local target_pkg="$1"
    local extra_pkg="$2"
    local max_attempts=5
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        dpkg --configure -a >/dev/null 2>&1
        if DEBIAN_FRONTEND=noninteractive apt-get install ${target_pkg} ${extra_pkg} -y; then
            return 0
        fi

        # 尝试 1: 清理脏缓存并强制对齐云端索引
        if [ "$attempt" -eq 1 ]; then
            echo -e "${YELLOW}[自愈机制触发] 检测到安装异常 (可能存在 Hash Mismatch 或分片损坏)，正在自动清理脏缓存并重新对齐官方索引...${PLAIN}"
            heal_apt_cache
            sleep 1
        fi

        # 尝试 2 及以上: 针对官方 meta 包索引脱节进行底层真实内核大包穿透直装
        if [ "$attempt" -ge 2 ]; then
            echo -e "${YELLOW}[智能穿透激活] 正在探查 [${target_pkg}] 对应的底层真实内核镜像与头文件...${PLAIN}"
            local real_img="" real_hdr=""
            
            # 策略 A: 从 apt-cache 获取元包的直接依赖大包
            real_img=$(apt-cache depends "$target_pkg" 2>/dev/null | grep -E "Depends:.*linux-image-" | awk '{print $2}' | head -n 1)
            real_hdr=$(apt-cache depends "$target_pkg" 2>/dev/null | grep -E "Depends:.*linux-headers-" | awk '{print $2}' | head -n 1)

            # 策略 B: 兜底从 candidate 候选池正则匹配对应版本的真实大包
            if [ -z "$real_img" ]; then
                local cand_ver
                cand_ver=$(apt-cache madison "$target_pkg" 2>/dev/null | head -n 1 | awk '{print $3}' | cut -d'-' -f1)
                [ -n "$cand_ver" ] && real_img=$(apt-cache search linux-image-"$cand_ver" 2>/dev/null | grep "$CPU_TIER" | awk '{print $1}' | head -n 1)
                [ -n "$cand_ver" ] && real_hdr=$(apt-cache search linux-headers-"$cand_ver" 2>/dev/null | grep "$CPU_TIER" | awk '{print $1}' | head -n 1)
            fi

            if [ -n "$real_img" ]; then
                echo -e "${BLUE}成功锁定真实内核镜像: ${GREEN}${real_img}${PLAIN} 与头文件: ${GREEN}${real_hdr:-无}${PLAIN}"
                echo -e "${BLUE}正在直接部署真实内核大包 (完全绕过官方损坏空壳)...${PLAIN}"
                dpkg --configure -a >/dev/null 2>&1
                if DEBIAN_FRONTEND=noninteractive apt-get install ${real_img} ${real_hdr} -y; then
                    # 尝试拉取元包直装补全依赖标记 (忽略哈希校验)
                    local meta_path
                    meta_path=$(apt-cache show "$target_pkg" 2>/dev/null | grep "^Filename:" | head -n 1 | awk '{print $2}')
                    if [ -n "$meta_path" ]; then
                        curl -fsSL --connect-timeout 8 "https://deb.xanmod.org/${meta_path}" -o /tmp/xanmod_meta.deb 2>/dev/null
                        if [ -s /tmp/xanmod_meta.deb ]; then
                            dpkg -i --force-all /tmp/xanmod_meta.deb >/dev/null 2>&1
                            rm -f /tmp/xanmod_meta.deb
                        fi
                    fi
                    echo -e "${GREEN}🎉 真实内核镜像部署成功！${PLAIN}"
                    return 0
                fi
            fi

            # 策略 C: 直接从官方 pool 下载元包 deb 文件并以 dpkg 本地绕过校验安装
            local pool_file
            pool_file=$(apt-cache show "$target_pkg" 2>/dev/null | grep "^Filename:" | head -n 1 | awk '{print $2}')
            if [ -n "$pool_file" ]; then
                echo -e "${YELLOW}正在尝试本地绕过校验直装模式...${PLAIN}"
                curl -fsSL --connect-timeout 10 "https://deb.xanmod.org/${pool_file}" -o /tmp/meta_bypass.deb 2>/dev/null
                if [ -s /tmp/meta_bypass.deb ]; then
                    dpkg -i --force-all /tmp/meta_bypass.deb >/dev/null 2>&1
                    rm -f /tmp/meta_bypass.deb
                    DEBIAN_FRONTEND=noninteractive apt-get install -f -y >/dev/null 2>&1
                    if dpkg -l | grep -q "$target_pkg"; then
                        echo -e "${GREEN}🎉 本地穿透模式部署成功！${PLAIN}"
                        return 0
                    fi
                fi
            fi
        fi

        sleep 1
        ((attempt++))
    done

    echo -e "${RED}[错误] 内核程序 [${target_pkg}] 安装失败，已重试 ${max_attempts} 次！${PLAIN}"
    return 1
}

# ====================================================================
# 13. 系统当前 XanMod 内核策略智能探测 (同策略升级核心基石)
# ====================================================================
detect_installed_xanmod_pkg() {
    # 1. 优先查已安装的 meta 包 (如 linux-xanmod-x64v3, linux-xanmod-lts-x64v3 等)
    local installed_meta
    installed_meta=$(dpkg -l 'linux-xanmod*' 2>/dev/null | grep -E '^ii\s+linux-xanmod(-[a-z0-9]+)?-x64v[123]' | awk '{print $2}' | head -n 1)
    if [ -n "$installed_meta" ]; then
        echo "$installed_meta"
        return
    fi

    # 2. 若无 meta 包，则根据当前运行内核特征推断本地策略
    local current_k=$(uname -r)
    if [[ "$current_k" == *"edge"* ]]; then
        echo "linux-xanmod-edge-${CPU_TIER}"
        return
    elif [[ "$current_k" == *"-rt-"* ]] || [[ "$current_k" == *"rt"* ]]; then
        echo "linux-xanmod-rt-${CPU_TIER}"
        return
    elif [[ "$current_k" =~ ^6\. ]] || [ "$CPU_TIER" = "x64v1" ]; then
        echo "linux-xanmod-lts-${CPU_TIER}"
        return
    fi

    # 3. 兜底返回主线包
    echo "linux-xanmod-${CPU_TIER}"
}

# ====================================================================
# 14. 硬件自适应内核分支选择与自定义版本定制子菜单
# ====================================================================
select_custom_kernel_menu() {
    while true; do
        clear
        echo -e "${BLUE}==================================================================${PLAIN}"
        echo -e "       ⚙️  XanMod 内核分支自选与自定义版本管理子菜单"
        echo -e "${BLUE}==================================================================${PLAIN}"
        echo -e "当前硬件架构：${GREEN}${CPU_TIER_TEXT}${PLAIN}"
        echo -e "当前选用策略：${YELLOW}${KERNEL_PKG}${PLAIN} (${KERNEL_BRANCH_NAME})"
        echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"

        if [ "$CPU_TIER" = "x64v1" ]; then
            echo -e "${YELLOW}⚠️  【硬件架构受限通知】${PLAIN}"
            echo -e "检测到本机 CPU 为基础指令集架构 (x86-64-v1)。"
            echo -e "XanMod 官方 MAIN、EDGE、RT 分支已全面彻底废止 x64v1 编译支持，"
            echo -e "强行安装将导致无法引导或 APT 404 错误。"
            echo -e "官方仓库仅在 LTS (长期维护) 分支保留了 x64v1 专属兼容包："
            echo -e "  ${GREEN}1. LTS (Long Term Support 6.18.x 长期维护稳定版) [唯一受支持]${PLAIN}"
            echo -e "  ${RED}0. 返回主菜单${PLAIN}"
            echo -e "${BLUE}==================================================================${PLAIN}"
            read -p "请输入选项 [0-1] (默认: 1): " sub_choice
            sub_choice=${sub_choice:-1}
            case "$sub_choice" in
                1)
                    KERNEL_PKG="linux-xanmod-lts-x64v1"
                    KERNEL_BRANCH_NAME="LTS (6.18.x 长期维护稳定版)"
                    KERNEL_EXTRA_PKG=""
                    KERNEL_HOLD=false
                    echo -e "${GREEN}已确认锁定 LTS 稳定版！${PLAIN}"
                    sleep 1
                    return 0
                    ;;
                0) return 0 ;;
                *) echo -e "${RED}输入无效！${PLAIN}"; sleep 1 ;;
            esac
        else
            # 满血架构 x64v2 / x64v3
            echo -e "请根据您的业务场景选择内核分支："
            echo -e "  ${GREEN}1. MAIN (Stable Mainline 7.2.x 最新主线版) [🚀 性能之王 - 默认推荐]${PLAIN}"
            echo -e "     ${YELLOW}└─ 最新协议栈 + 最新 BBRv3 + LLVM 深度编译优化，绝大多数网络场景首选。${PLAIN}"
            echo -e "  ${GREEN}2. LTS  (Long Term Support 6.18.x 长期维护稳定版) [🛡️ 企业稳健]${PLAIN}"
            echo -e "     ${YELLOW}└─ 极致稳定性优先，企业级生产系统、Docker、建站共存首选。${PLAIN}"
            echo -e "  ${BLUE}3. EDGE (Rolling Release 7.3.x 激进尝鲜滚动版) [⚡ 极客折腾]${PLAIN}"
            echo -e "     ${YELLOW}└─ 尝鲜最新调度器与实验性特性，适合发烧友测试体验。${PLAIN}"
            echo -e "  ${BLUE}4. RT   (Stable Real-time 6.18.x-rt 全抢占实时内核) [⏱️ 极致低抖动]${PLAIN}"
            echo -e "     ${YELLOW}└─ PREEMPT_RT 硬实时补丁，确定性零抖动微秒级延迟，适合游戏/低延迟专用。${PLAIN}"
            echo -e "  ${YELLOW}5. 📌 自定义指定历史版本号 (例如指定 7.2.15-xanmod1 / 支持版本锁定)${PLAIN}"
            echo -e "     ${YELLOW}└─ 手动输入精确版本号，支持 apt-mark hold 防止意外被系统更新覆盖。${PLAIN}"
            echo -e "  ${RED}0. 返回主菜单 (保持当前选择)${PLAIN}"
            echo -e "${BLUE}==================================================================${PLAIN}"
            read -p "请输入选项 [0-5] (默认: 1): " sub_choice
            sub_choice=${sub_choice:-1}
            case "$sub_choice" in
                1)
                    KERNEL_PKG="linux-xanmod-${CPU_TIER}"
                    KERNEL_BRANCH_NAME="MAIN (7.2.x 最新主线稳定版)"
                    KERNEL_EXTRA_PKG=""
                    KERNEL_HOLD=false
                    echo -e "${GREEN}已切换为: MAIN 最新主线稳定版 (${KERNEL_PKG})${PLAIN}"
                    sleep 1
                    return 0
                    ;;
                2)
                    KERNEL_PKG="linux-xanmod-lts-${CPU_TIER}"
                    KERNEL_BRANCH_NAME="LTS (6.18.x 长期维护稳定版)"
                    KERNEL_EXTRA_PKG=""
                    KERNEL_HOLD=false
                    echo -e "${GREEN}已切换为: LTS 长期维护稳定版 (${KERNEL_PKG})${PLAIN}"
                    sleep 1
                    return 0
                    ;;
                3)
                    KERNEL_PKG="linux-xanmod-edge-${CPU_TIER}"
                    KERNEL_BRANCH_NAME="EDGE (7.3.x 激进滚动尝鲜版)"
                    KERNEL_EXTRA_PKG=""
                    KERNEL_HOLD=false
                    echo -e "${GREEN}已切换为: EDGE 激进滚动尝鲜版 (${KERNEL_PKG})${PLAIN}"
                    sleep 1
                    return 0
                    ;;
                4)
                    KERNEL_PKG="linux-xanmod-rt-${CPU_TIER}"
                    KERNEL_BRANCH_NAME="RT (6.18.x-rt 全抢占实时内核)"
                    KERNEL_EXTRA_PKG=""
                    KERNEL_HOLD=false
                    echo -e "${GREEN}已切换为: RT 全抢占实时内核 (${KERNEL_PKG})${PLAIN}"
                    sleep 1
                    return 0
                    ;;
                5)
                    ensure_xanmod_repo
                    echo -e "\n${BLUE}正在从官方源检索可用 XanMod 内核镜像列表...${PLAIN}"
                    local available_imgs
                    available_imgs=$(apt-cache madison linux-image-*-xanmod* 2>/dev/null | awk '{print $1}' | sort -u)
                    if [ -z "$available_imgs" ]; then
                        echo -e "${RED}[错误] 暂未获取到仓库中的版本列表，请稍后重试！${PLAIN}"
                        sleep 2
                        continue
                    fi
                    echo -e "${YELLOW}官方仓库匹配当前架构的近期常用版本参考：${PLAIN}"
                    apt-cache madison linux-image-*-xanmod* 2>/dev/null | grep "${CPU_TIER}" | head -n 8 | awk '{printf "  • %-40s | 版本: %s\n", $1, $3}'
                    echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
                    read -p "请输入您想指定的版本号或关键词 (例如 7.2.15 或完整包名): " custom_ver_input
                    if [ -z "$custom_ver_input" ]; then
                        echo -e "${YELLOW}已取消自定义版本输入。${PLAIN}"
                        sleep 1
                        continue
                    fi
                    local matched_pkg
                    matched_pkg=$(apt-cache madison linux-image-*-xanmod* 2>/dev/null | grep "${CPU_TIER}" | grep "${custom_ver_input}" | awk '{print $1}' | head -n 1)
                    if [ -z "$matched_pkg" ]; then
                        matched_pkg=$(apt-cache madison linux-image-*-xanmod* 2>/dev/null | grep "${custom_ver_input}" | awk '{print $1}' | head -n 1)
                    fi
                    if [ -z "$matched_pkg" ]; then
                        echo -e "${RED}[错误] 仓库中未找到包含 \"${custom_ver_input}\" 的内核包，请核对后重试！${PLAIN}"
                        sleep 2
                        continue
                    fi
                    local matched_headers="${matched_pkg/linux-image-/linux-headers-}"
                    echo -e "${GREEN}成功匹配到内核包: ${matched_pkg}${PLAIN}"
                    if apt-cache show "$matched_headers" >/dev/null 2>&1; then
                        KERNEL_EXTRA_PKG="$matched_headers"
                        echo -e "${GREEN}成功匹配到伴随头文件: ${matched_headers}${PLAIN}"
                    else
                        KERNEL_EXTRA_PKG=""
                    fi
                    read -p "是否在安装后执行 apt-mark hold 锁定此版本（防止 apt upgrade 被覆盖）？[Y:锁定 / N:不锁, 默认Y]: " hold_choice
                    hold_choice=${hold_choice:-Y}
                    hold_choice=$(echo "$hold_choice" | tr '[:lower:]' '[:upper:]')
                    if [ "$hold_choice" = "Y" ]; then
                        KERNEL_HOLD=true
                        KERNEL_BRANCH_NAME="自定义锁定版 (${custom_ver_input} [Pinning])"
                    else
                        KERNEL_HOLD=false
                        KERNEL_BRANCH_NAME="自定义指定版 (${custom_ver_input})"
                    fi
                    KERNEL_PKG="$matched_pkg"
                    echo -e "${GREEN}自定义内核配置完成！${PLAIN}"
                    sleep 1
                    return 0
                    ;;
                0) return 0 ;;
                *) echo -e "${RED}输入无效，请重新选择！${PLAIN}"; sleep 1 ;;
            esac
        fi
    done
}

# ====================================================================
# 15. 一键检查与在线升级 (选项4: 脚本 & XanMod 内核)
# ====================================================================
check_and_upgrade() {
    clear
    echo -e "${BLUE}==================================================================${PLAIN}"
    echo -e "       🔄 一键检查与在线升级 (调优脚本 & XanMod 内核)              "
    echo -e "${BLUE}==================================================================${PLAIN}"

    # 1. 检查调优脚本云端更新
    echo -e "\n${YELLOW}[1/2] 正在检索 GitHub 官方仓库调优脚本版本...${PLAIN}"
    local remote_ver=$(curl -fsSL --connect-timeout 4 https://raw.githubusercontent.com/ZhangSir9901/BBRv3-Onekey/main/bbr_tune.sh 2>/dev/null | grep -m1 '^# SCRIPT_VERSION=' | cut -d= -f2 | tr -d '"\r\n ')
    
    local need_upgrade_script=false
    if [ -n "$remote_ver" ] && [ "$remote_ver" != "$SCRIPT_VERSION" ]; then
        echo -e "${GREEN}🚀 检测到调优脚本新版本: v${remote_ver}${PLAIN} (当前运行版本: v${SCRIPT_VERSION})"
        need_upgrade_script=true
    else
        echo -e "${GREEN}✅ 当前调优脚本已是最新版 (v${SCRIPT_VERSION})${PLAIN}"
    fi

    if [ "$need_upgrade_script" = "true" ]; then
        read -p "是否立即升级调优脚本至最新版？[Y:升级 / N:跳过, 默认Y]: " UP_SCRIPT_CHOICE
        UP_SCRIPT_CHOICE=${UP_SCRIPT_CHOICE:-Y}
        UP_SCRIPT_CHOICE=$(echo "$UP_SCRIPT_CHOICE" | tr '[:lower:]' '[:upper:]')
        if [ "$UP_SCRIPT_CHOICE" = "Y" ]; then
            echo -e "${BLUE}正在下载最新脚本并执行热重载...${PLAIN}"
            local script_path="/tmp/bbr_tune_latest.sh"
            if curl -fsSL --connect-timeout 8 https://raw.githubusercontent.com/ZhangSir9901/BBRv3-Onekey/main/bbr_tune.sh -o "$script_path"; then
                chmod +x "$script_path"
                if [ -f "$0" ] && [[ "$0" != "/dev/fd/"* ]]; then
                    cp -f "$script_path" "$0"
                fi
                echo -e "${GREEN}✅ 脚本升级成功，正在重启进入新版...${PLAIN}"
                sleep 1
                exec bash "$script_path" "$@"
            else
                echo -e "${RED}[错误] 新版脚本下载失败，请检查网络连接！${PLAIN}"
            fi
        fi
    fi

    # 2. 检查 XanMod 内核更新 (严格遵循同策略内核更新逻辑)
    echo -e "\n${YELLOW}[2/2] 正在检索 XanMod 官方仓库内核更新...${PLAIN}"
    local current_k=$(uname -r)
    if [[ "$current_k" != *"xanmod"* ]]; then
        echo -e "${YELLOW}⚠️ 当前系统正在运行标准发行版内核 (${current_k})，未安装 XanMod 内核！${PLAIN}"
        echo -e "${BLUE}💡 提示：内核升级功能仅面向已部署 XanMod 的系统。${PLAIN}"
        echo -e "   若需将系统升级为 XanMod BBRv3，请返回主菜单选择 [1]、[2] 或 [5] 进行一键安装。"
    else
        ensure_xanmod_repo
        
        # 精准获取本地系统当前运行/安装的同策略 XanMod 包
        local target_k_pkg=$(detect_installed_xanmod_pkg)
        echo -e "${BLUE}正在匹配已安装的同策略 XanMod 内核包: ${GREEN}${target_k_pkg}${PLAIN}"
        
        local installed_k_ver=$(dpkg-query -W -f='${Version}' "${target_k_pkg}" 2>/dev/null)
        local latest_k_ver=$(apt-cache madison "${target_k_pkg}" 2>/dev/null | head -n 1 | awk '{print $3}')
        [ -z "$latest_k_ver" ] && latest_k_ver=$(LC_ALL=C apt-cache policy "${target_k_pkg}" 2>/dev/null | grep "Candidate:" | awk '{print $2}')

        if [ -n "$latest_k_ver" ] && [ -n "$installed_k_ver" ] && [ "$installed_k_ver" != "$latest_k_ver" ]; then
            echo -e "${GREEN}🚀 检测到 XanMod 同策略 [${target_k_pkg}] 新版本内核发布: ${latest_k_ver}${PLAIN}"
            echo -e "   (当前安装版本: ${installed_k_ver})"
            read -p "是否立即升级内核并更新引导镜像？[Y:升级 / N:跳过, 默认Y]: " UP_K_CHOICE
            UP_K_CHOICE=${UP_K_CHOICE:-Y}
            UP_K_CHOICE=$(echo "$UP_K_CHOICE" | tr '[:lower:]' '[:upper:]')
            if [ "$UP_K_CHOICE" = "Y" ]; then
                echo -e "\n${BLUE}正在安装 XanMod [${target_k_pkg}] 新内核 (全自动自愈机制已激活)...${PLAIN}"
                install_kernel_with_self_healing "${target_k_pkg}"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}[错误] 内核升级失败，请检查网络！${PLAIN}"
                    read -p "按回车键返回主菜单..."
                    return 1
                fi
                echo -e "\n${BLUE}正在重新生成完整 Initramfs 镜像并更新 GRUB 引导...${PLAIN}"
                solidify_virtio_drivers
                update-initramfs -u -k all >/dev/null 2>&1
                retry_command update-grub
                echo -e "\n${GREEN}🎉 XanMod 内核升级完成！${PLAIN}"
                read -p "是否立即重启服务器使新内核生效？[Y:重启 / N:稍后, 默认Y]: " REBOOT_NOW
                REBOOT_NOW=${REBOOT_NOW:-Y}
                REBOOT_NOW=$(echo "$REBOOT_NOW" | tr '[:lower:]' '[:upper:]')
                if [ "$REBOOT_NOW" = "Y" ]; then
                    echo -e "${GREEN}正在重启服务器...${PLAIN}"
                    reboot
                fi
            fi
        else
            echo -e "${GREEN}✅ 当前运行的同策略 XanMod [${target_k_pkg}] 已是官方最新版本 (${installed_k_ver:-$current_k})，无需重复升级！${PLAIN}"
        fi
    fi

    echo -e "${BLUE}==================================================================${PLAIN}"
    read -p "按回车键返回主菜单..."
}

# ====================================================================
# 13. 全量清单级【状态详细体检】功能 (选项9)
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

    echo -e "  └─ CPU 架构支持 : ${GREEN}${CPU_TIER_TEXT}${PLAIN}"
    
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
    local initcwnd_val=$(ip -4 route show default 2>/dev/null | grep -oE 'initcwnd [0-9]+' || echo "默认 (10)")
    
    echo -e "  ├─ 动态 TCP 读写缓冲 : ${GREEN}${rmem}${PLAIN} / ${GREEN}${wmem}${PLAIN}"
    echo -e "  ├─ TCP 防缓冲膨胀延迟: $(if [ "$notsent" = "16384" ]; then echo -e "${GREEN}已开启 (16KB)${PLAIN}"; else echo -e "${YELLOW}${notsent:-默认}${PLAIN}"; fi)"
    echo -e "  ├─ TCP Fast Open(TFO): $(if [ "$fastopen" = "3" ]; then echo -e "${GREEN}双向已开启 (模式 3)${PLAIN}"; else echo -e "${YELLOW}${fastopen:-默认}${PLAIN}"; fi)"
    echo -e "  ├─ 初始窗口首包秒开  : $(if [[ "$initcwnd_val" =~ "32" ]]; then echo -e "${GREEN}${initcwnd_val} (免RTT秒开握手)${PLAIN}"; else echo -e "${YELLOW}${initcwnd_val}${PLAIN}"; fi)"
    echo -e "  ├─ 空闲连接免慢启动  : $(if [ "$idle_ss" = "0" ]; then echo -e "${GREEN}已开启 (常态满速)${PLAIN}"; else echo -e "${YELLOW}${idle_ss:-默认}${PLAIN}"; fi)"
    echo -e "  └─ PMTU 动态黑洞探测 : $(if [ "$mtu_p" = "1" ]; then echo -e "${GREEN}已开启 (防分片丢包)${PLAIN}"; else echo -e "${YELLOW}${mtu_p:-默认}${PLAIN}"; fi)"

    echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}【UDP / QUIC / Hysteria 2 / TUIC 加速层】${PLAIN}"
    local rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null)
    local wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null)
    echo -e "  ├─ 网卡最大接收/发送缓冲: ${GREEN}$((rmem_max/1024/1024))MB${PLAIN} / ${GREEN}$((wmem_max/1024/1024))MB${PLAIN}"
    echo -e "  └─ UDP 最小保证读写缓冲 : ${GREEN}$(sysctl -n net.ipv4.udp_rmem_min 2>/dev/null)B${PLAIN} / ${GREEN}$(sysctl -n net.ipv4.udp_wmem_min 2>/dev/null)B${PLAIN}"

    echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}【高并发代理 / 中转 / 状态机回收】${PLAIN}"
    local tw_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null)
    local fin_time=$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null)
    local port_range=$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null)
    local somaxconn=$(sysctl -n net.core.somaxconn 2>/dev/null)
    local file_max=$(sysctl -n fs.file-max 2>/dev/null)
    local pipe_size=$(sysctl -n fs.pipe-max-size 2>/dev/null)
    local budget=$(sysctl -n net.core.netdev_budget 2>/dev/null)

    echo -e "  ├─ TIME_WAIT 极速复用 : $(if [ "$tw_reuse" = "1" ]; then echo -e "${GREEN}已开启 (防端口耗尽)${PLAIN}"; else echo -e "${YELLOW}${tw_reuse:-默认}${PLAIN}"; fi)"
    echo -e "  ├─ FIN 废弃连接超时   : ${GREEN}${fin_time}秒${PLAIN}"
    echo -e "  ├─ 出站可用端口池范围 : ${GREEN}${port_range}${PLAIN} (扩容至6.4万端口)"
    echo -e "  ├─ 监听队列 / 网卡队列: ${GREEN}${somaxconn}${PLAIN} / ${GREEN}$(sysctl -n net.core.netdev_max_backlog 2>/dev/null)${PLAIN}"
    echo -e "  ├─ 软中断单轮处理配额 : ${GREEN}${budget:-300}${PLAIN} (netdev_budget 扩容防丢包)"
    echo -e "  ├─ 系统最大文件句柄   : ${GREEN}${file_max}${PLAIN} (突破100万并发)"
    echo -e "  └─ Xray 零拷贝管道缓冲: ${GREEN}$((pipe_size/1024))KB${PLAIN} (提升 splice 吞吐)"

    echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}【独立配置架构与出厂容灾快照】${PLAIN}"
    echo -e "  ├─ 独立调优参数文件   : $(if [ -f "$BBR_SYSCTL_FILE" ]; then echo -e "${GREEN}已配置 ($BBR_SYSCTL_FILE)${PLAIN}"; else echo -e "${YELLOW}未配置/使用全局${PLAIN}"; fi)"
    echo -e "  ├─ 出厂系统原始快照   : $(if [ -f "$SNAPSHOT_FILE" ]; then echo -e "${GREEN}已就绪 ($SNAPSHOT_FILE)${PLAIN}"; else echo -e "${YELLOW}尚未生成${PLAIN}"; fi)"
    echo -e "  └─ initcwnd 32 守护服务: $(if systemctl is-enabled bbr-initcwnd.service >/dev/null 2>&1; then echo -e "${GREEN}运行中 (开机自启注入)${PLAIN}"; else echo -e "${YELLOW}未启用${PLAIN}"; fi)"

    echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}【IP 栈与虚拟内存调度】${PLAIN}"
    local ip4_fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    local ip6_ra=$(sysctl -n net.ipv6.conf.all.accept_ra 2>/dev/null)
    local swappiness=$(sysctl -n vm.swappiness 2>/dev/null)
    local dirty=$(sysctl -n vm.dirty_ratio 2>/dev/null)
    local current_swap=$(get_swap_mb)

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
        echo -e "${YELLOW}⚠️ 综合评估：系统尚未完全调优，建议在主菜单选择相应模式执行一键调优。${PLAIN}"
    fi
    echo -e "${BLUE}==================================================================${PLAIN}"
    read -p "按回车键返回主菜单..."
}

# 14. 脚本主循环交互菜单
while true; do
    clear
    CURRENT_KERNEL=$(uname -r)
    ALREADY_XANMOD=false
    if [[ "$CURRENT_KERNEL" == *"xanmod"* ]]; then
        ALREADY_XANMOD=true
    fi

    TOTAL_RAM_SHOW=$(get_ram_mb)
    TOTAL_SWAP_SHOW=$(get_swap_mb)

    # 动态检测当前运行状态
    CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
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
        OPTIMIZE_ADVICE_TEXT="${RED}建议运行一键优化 (输入 1 或 2 并回车)${PLAIN}"
        DEFAULT_CHOICE=1
    fi

    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "    Debian/Ubuntu 智能网络全栈调优 一体化部署工具"
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "当前系统：${GREEN}${NAME} ${VERSION_ID} (${CODENAME})${PLAIN}"
    echo -e "VPS位置 ：${GREEN}${COUNTRY_NAME}${PLAIN}"
    echo -e "CPU架构 ：${GREEN}${CPU_TIER_TEXT}${PLAIN}"
    echo -e "网络架构：${GREEN}${IP_STACK_TEXT}${PLAIN}"
    echo -e "内存状态：${GREEN}物理内存 ${TOTAL_RAM_SHOW}MB | Swap气囊 ${TOTAL_SWAP_SHOW}MB${PLAIN}"
    echo -e "当前内核：$(if [ "$ALREADY_XANMOD" = "true" ]; then echo -e "${GREEN}${CURRENT_KERNEL} (已是XanMod)${PLAIN}"; else echo -e "${YELLOW}${CURRENT_KERNEL} (标准内核)${PLAIN}"; fi)"
    echo -e "BBR3状态：${BBR3_STATUS_TEXT}"
    echo -e "优化状态：${OPTIMIZE_STATUS_TEXT}"
    echo -e "优化建议：${OPTIMIZE_ADVICE_TEXT}"
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "请选择调优模式："
    echo -e "  ${GREEN}1. [小白/一键] 综合环境稳健全栈调优 (🏆 适合建站+代理)${PLAIN}"
    echo -e "     ${YELLOW}└─ 多业务共存均衡调优，满血硬件默认配 MAIN(7.2)，老旧硬件自动锁定 LTS(6.18)。${PLAIN}"
    echo -e "  ${GREEN}2. [新机/开荒] 纯代理极致加速全栈调优 (🚀 适合翻墙专机)${PLAIN}"
    echo -e "     ${YELLOW}└─ 专为代理/专线/中转打造，UDP/QUIC极限扩容64M，榨干单兵网络极限。${PLAIN}"
    echo -e "  ${YELLOW}3. [高手/极客] 目标节点精准手工调优 (BDP / 窗口定制)${PLAIN}"
    echo -e "     ${YELLOW}└─ 需手动输入对端测速带宽与延迟，计算绝对理论极限值。${PLAIN}"
    echo -e "  ${BLUE}4. 🔄 一键检查与在线升级 (脚本 & XanMod内核)${PLAIN}"
    echo -e "     ${YELLOW}└─ 严格遵循同策略内核精准检测，一键热升级云端脚本与内核。${PLAIN}"
    echo -e "  ${BLUE}5. 🛠️ 自定义选择内核分支与版本 (MAIN / LTS / EDGE / RT / 锁定版本)${PLAIN}"
    echo -e "     ${YELLOW}└─ 硬件自适应定制子菜单，自由切换 4 大分支或精确安装并锁定指定版本号。${PLAIN}"
    echo -e "  ${YELLOW}8. ⏪ 一键回滚还原到系统出厂网络配置 (Rollback to Factory)${PLAIN}"
    echo -e "     ${YELLOW}└─ 安全一键卸载调优配置、撤销 initcwnd 32，还原系统出厂默认网络参数。${PLAIN}"
    echo -e "  ${BLUE}9. 🔍 详细体检内核与网络加速算法生效状态 (Status Check)${PLAIN}"
    echo -e "  ${RED}0. 退出脚本${PLAIN}"
    echo -e "${BLUE}==================================================${PLAIN}"
    read -p "请输入数字 [0-5, 8-9] (默认: ${DEFAULT_CHOICE}): " CHOICE

    # 动态应用智能默认选项
    if [ -z "$CHOICE" ]; then CHOICE=$DEFAULT_CHOICE; fi

    case "$CHOICE" in
        1|2|3)
            if [ "$ALREADY_XANMOD" = "true" ]; then
                clear
                echo -e "${YELLOW}==================================================${PLAIN}"
                echo -e "⚠️  ${RED}【高亮提醒】您的服务器当前已经是 XanMod 内核！${PLAIN}"
                echo -e "${YELLOW}==================================================${PLAIN}"
                read -p "您是想继续覆盖调优配置并检查源更新吗？[Y:继续 / N:退出, 默认Y]: " WARN_CHOICE
                WARN_CHOICE=${WARN_CHOICE:-Y}
                WARN_CHOICE=$(echo "$WARN_CHOICE" | tr '[:lower:]' '[:upper:]')
                if [ "$WARN_CHOICE" = "N" ]; then exit 0; fi
            fi

            # 小白模式与开荒模式的内核自适应确认交互
            if [ "$CPU_TIER" = "x64v1" ]; then
                echo -e "\n${YELLOW}ℹ️  [内核自适应] 检测到当前 CPU 为基础架构 (x64v1)，官方仅在 LTS 分支提供兼容支持。${PLAIN}"
                echo -e "   系统已自动锁定安装 LTS 稳定版 (linux-xanmod-lts-x64v1)，不提供其它版本安装选项以防死机。"
            else
                echo -e "\n${BLUE}------------------------------------------------------------------${PLAIN}"
                echo -e "当前硬件架构：${GREEN}${CPU_TIER_TEXT}${PLAIN}"
                echo -e "默认优选内核：${GREEN}${KERNEL_PKG}${PLAIN} (${KERNEL_BRANCH_NAME})"
                echo -e "💡 提示：按 [回车] 直接采用默认优选内核；或输入 [C] 打开内核分支自选子菜单"
                echo -e "${BLUE}------------------------------------------------------------------${PLAIN}"
                read -p "请确认内核选择 [回车直接继续 / C:选择其它内核]: " K_CUSTOM_INPUT
                if [[ "$K_CUSTOM_INPUT" =~ ^[Cc]$ ]]; then
                    select_custom_kernel_menu
                fi
            fi
            break
            ;;
        4) check_and_upgrade ;;
        5)
            select_custom_kernel_menu
            read -p "是否立即以此内核开始全栈网络调优并安装？[Y:开始 / N:返回主菜单, 默认Y]: " START_NOW
            START_NOW=${START_NOW:-Y}
            START_NOW=$(echo "$START_NOW" | tr '[:lower:]' '[:upper:]')
            if [ "$START_NOW" = "Y" ]; then
                CHOICE=1
                break
            fi
            ;;
        8) rollback_to_factory ;;
        9) verify_status ;;
        0) echo -e "${BLUE}已安全退出脚本。${PLAIN}"; exit 0 ;;
        *) echo -e "${RED}[错误] 输入无效，请重新选择！${PLAIN}"; sleep 1 ;;
    esac
done

# ====================================================================
# 15. 执行优化写入流程 (自动出厂快照备份 + 解耦独立配置 + initcwnd 32 注入)
# ====================================================================
take_factory_snapshot
auto_manage_swap
solidify_virtio_drivers
clean_sysctl
write_base_sysctl "$CHOICE"
apply_and_persist_initcwnd

if [ "$CHOICE" -eq 1 ]; then
    SCENARIO="[小白/一键] 综合环境稳健全栈调优 (建站+代理)"
    
    # 动态内存计算 (稳健分配 ~1.5%，截断 32MB 防 OOM)
    TOTAL_MEM_MB=$(get_ram_mb)
    MAX_MEM_BYTES=$((TOTAL_MEM_MB * 1024 * 1024 * 15 / 1000))
    if [ "$MAX_MEM_BYTES" -lt 4194304 ]; then MAX_MEM_BYTES=4194304; fi
    if [ "$MAX_MEM_BYTES" -gt 33554432 ]; then MAX_MEM_BYTES=33554432; fi

    CONFIG_SUMMARY="BBRv3 + FQ + 稳健TCP缓冲($((MAX_MEM_BYTES/1024/1024))MB) + 32MB UDP/QUIC (防OOM保活)"
    
    echo "net.core.default_qdisc=fq" >> "$BBR_SYSCTL_FILE"
    echo "net.ipv4.tcp_congestion_control=bbr" >> "$BBR_SYSCTL_FILE"
    echo "net.ipv4.tcp_rmem=4096 87380 ${MAX_MEM_BYTES}" >> "$BBR_SYSCTL_FILE"
    echo "net.ipv4.tcp_wmem=4096 65536 ${MAX_MEM_BYTES}" >> "$BBR_SYSCTL_FILE"

elif [ "$CHOICE" -eq 2 ]; then
    SCENARIO="[新机/开荒] 纯代理极致加速全栈调优 (翻墙专机)"
    
    # 动态内存计算 (极限分配 ~2.5%，放满 64MB)
    TOTAL_MEM_MB=$(get_ram_mb)
    MAX_MEM_BYTES=$((TOTAL_MEM_MB * 1024 * 1024 * 25 / 1000))
    if [ "$MAX_MEM_BYTES" -lt 4194304 ]; then MAX_MEM_BYTES=4194304; fi
    if [ "$MAX_MEM_BYTES" -gt 67108864 ]; then MAX_MEM_BYTES=67108864; fi

    CONFIG_SUMMARY="BBRv3 + FQ + 满血TCP缓冲($((MAX_MEM_BYTES/1024/1024))MB) + 64MB UDP/QUIC (极速状态机回收)"
    
    echo "net.core.default_qdisc=fq" >> "$BBR_SYSCTL_FILE"
    echo "net.ipv4.tcp_congestion_control=bbr" >> "$BBR_SYSCTL_FILE"
    echo "net.ipv4.tcp_rmem=4096 87380 ${MAX_MEM_BYTES}" >> "$BBR_SYSCTL_FILE"
    echo "net.ipv4.tcp_wmem=4096 65536 ${MAX_MEM_BYTES}" >> "$BBR_SYSCTL_FILE"

elif [ "$CHOICE" -eq 3 ]; then
    SCENARIO="[高手/极客] 目标节点精准手工调优"
    clear
    echo -e "${BLUE}=== 极客模式：动态带宽延迟乘积 (BDP) 计算 ===${PLAIN}"
    echo -e "${YELLOW}提示：如果你是中转机，请输入到落地机的实测网络数据；如果是单机，请输入到本地的测速数据。${PLAIN}"
    
    read -p "1. 请输入实测最高带宽 (单位: Mbps, 默认: 1000): " TARGET_BW
    TARGET_BW=${TARGET_BW:-1000}
    if ! [[ "$TARGET_BW" =~ ^[0-9]+$ ]] || [ "$TARGET_BW" -le 0 ]; then
        echo -e "${YELLOW}[警告] 无效的带宽输入，已重置为默认值 1000 Mbps。${PLAIN}"
        TARGET_BW=1000
    fi
    
    read -p "2. 请输入平均网络延迟 RTT (单位: ms, 默认: 150): " TARGET_RTT
    TARGET_RTT=${TARGET_RTT:-150}
    if ! [[ "$TARGET_RTT" =~ ^[0-9]+$ ]] || [ "$TARGET_RTT" -le 0 ]; then
        echo -e "${YELLOW}[警告] 无效的延迟输入，已重置为默认值 150 ms。${PLAIN}"
        TARGET_RTT=150
    fi

    # BDP 计算: 带宽(Mbps) * 延迟(ms) * 125 = BDP 字节数
    BDP_BYTES=$(( TARGET_BW * TARGET_RTT * 125 * 3 / 2 ))
    if [ "$BDP_BYTES" -lt 4194304 ]; then BDP_BYTES=4194304; fi

    CONFIG_SUMMARY="BBRv3 + FQ + 精准BDP极限缓冲 ($((BDP_BYTES/1024/1024))MB, 目标:${TARGET_BW}M/${TARGET_RTT}ms)"
    
    echo "net.core.default_qdisc=fq" >> "$BBR_SYSCTL_FILE"
    echo "net.ipv4.tcp_congestion_control=bbr" >> "$BBR_SYSCTL_FILE"
    echo "net.ipv4.tcp_rmem=4096 87380 ${BDP_BYTES}" >> "$BBR_SYSCTL_FILE"
    echo "net.ipv4.tcp_wmem=4096 65536 ${BDP_BYTES}" >> "$BBR_SYSCTL_FILE"
fi

# 16. 开始执行源配置与更新
echo -e "\n${BLUE}[1/3] 开始配置并同步 XanMod 官方存储库...${PLAIN}"
ensure_xanmod_repo
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] XanMod 官方源配置失败，无法继续安装内核！${PLAIN}"
    exit 1
fi

# 17. 智能版本比对 (多语言环境自适应，精准追踪当前所选内核包)
SKIP_KERNEL_INSTALL=false
NEED_REBOOT=false

if dpkg -l | grep -q "${KERNEL_PKG}"; then
    INSTALLED_VER=$(dpkg-query -W -f='${Version}' "${KERNEL_PKG}" 2>/dev/null)
    LATEST_VER=$(apt-cache madison "${KERNEL_PKG}" 2>/dev/null | head -n 1 | awk '{print $3}')
    [ -z "$LATEST_VER" ] && LATEST_VER=$(LC_ALL=C apt-cache policy "${KERNEL_PKG}" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
    
    if [ -n "$LATEST_VER" ] && [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
        echo -e "\n${GREEN}[提示] XanMod 目标内核已是最新版 (${INSTALLED_VER})，跳过重装。${PLAIN}"
        SKIP_KERNEL_INSTALL=true
    fi
fi

if [ "$SKIP_KERNEL_INSTALL" = "false" ]; then
    echo -e "\n${BLUE}[2/3] 正在安装/部署 XanMod [${KERNEL_PKG}] 内核包 (全自动自愈机制已激活)...${PLAIN}"
    install_kernel_with_self_healing "${KERNEL_PKG}" "${KERNEL_EXTRA_PKG}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}[错误] 内核程序安装/升级失败！${PLAIN}"
        exit 1
    fi
    if [ "$KERNEL_HOLD" = "true" ]; then
        apt-mark hold ${KERNEL_PKG} ${KERNEL_EXTRA_PKG} >/dev/null 2>&1
        echo -e "${GREEN}[版本锁定] 已成功对 ${KERNEL_PKG} 启用 apt-mark hold，防止被后续自动升级覆盖！${PLAIN}"
    fi
    NEED_REBOOT=true
fi

# 18. 固化驱动镜像与更新引导
if [ "$NEED_REBOOT" = "true" ]; then
    echo -e "\n${BLUE}[3/3] 正在生成完整 Initramfs 镜像并更新 GRUB 引导...${PLAIN}"
    update-initramfs -u -k all >/dev/null 2>&1
    retry_command update-grub
fi

# 19. 应用系统优化配置 (-e 忽略未知参数，解耦加载独立调优文件)
sysctl -e -p "$BBR_SYSCTL_FILE" > /dev/null 2>&1

# 20. 漂亮的执行结果输出
clear
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "          🎉 内核配置与极客全栈调优执行完毕！"
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "使用模式：${BLUE}${SCENARIO}${PLAIN}"
echo -e "匹配内核：${BLUE}${KERNEL_PKG}${PLAIN} (${KERNEL_BRANCH_NAME})"
echo -e "参数总览：${BLUE}${CONFIG_SUMMARY}${PLAIN}"
echo -e "网络拓扑：${BLUE}${IP_STACK_TEXT}${PLAIN}"
echo -e "高级特性：${YELLOW}VirtIO固化 / UDP扩容 / initcwnd 32秒开 / TIME_WAIT回收 / PMTU探测 / Swap气囊${PLAIN} 已全开"
echo -e "${GREEN}==================================================${PLAIN}"

# 21. 智能倒计时重启机制
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
    echo -e "您可立即再次运行本脚本选择 [9] 查看全量参数体检清单。${PLAIN}"
    echo -e "${GREEN}==================================================${PLAIN}"
fi
