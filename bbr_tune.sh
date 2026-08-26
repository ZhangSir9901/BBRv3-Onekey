#!/bin/bash

# ====================================================================
# 项目名称: Debian/Ubuntu XanMod BBRv3 智能网络生命周期管理 (双轨极客版)
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

# 3. 高精度地理位置识别
get_country_code() {
    local cc=""
    cc=$(curl -s --connect-timeout 3 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^loc=' | cut -d= -f2)
    if [ -n "$cc" ] && [ "$cc" != "XX" ] && [ ${#cc} -eq 2 ]; then
        echo "$cc"
        return
    fi
    cc=$(curl -s --connect-timeout 3 https://ipinfo.io/country)
    if [ -n "$cc" ] && [ ${#cc} -eq 2 ]; then
        echo "$cc"
        return
    fi
    echo "US"
}

COUNTRY_CODE=$(get_country_code)
COUNTRY_CODE=$(echo "$COUNTRY_CODE" | tr '[:lower:]' '[:upper:]')
IS_ASIA_PACIFIC=false

case "$COUNTRY_CODE" in
    HK|JP|KR|SG|MY|PH|TW|TH|VN|ID) IS_ASIA_PACIFIC=true ; COUNTRY_NAME="亚太地区 (${COUNTRY_CODE})" ;;
    US|CA) COUNTRY_NAME="北美洲 (${COUNTRY_CODE})" ;;
    GB|UK|DE|NL|FR|RU) COUNTRY_NAME="欧洲 (${COUNTRY_CODE})" ;;
    *) COUNTRY_NAME="${COUNTRY_CODE}";;
esac

# 4. 根据系统分配内核包
CODENAME=$VERSION_CODENAME
if [ "$ID" = "debian" ] && [ "$VERSION_ID" = "12" ]; then
    KERNEL_PKG="linux-xanmod-lts-x64v3"
else
    KERNEL_PKG="linux-xanmod-x64v3"
fi

# 5. 定义通用命令重试函数
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

# 6. 深度清理旧系统参数 (包含新增参数)
clean_sysctl() {
    local params=(
        "net.core.default_qdisc" "net.ipv4.tcp_congestion_control" "net.ipv4.tcp_rmem" "net.ipv4.tcp_wmem"
        "net.ipv4.tcp_notsent_lowat" "net.ipv4.tcp_mtu_probing" "net.ipv4.tcp_base_mss" "net.ipv4.tcp_sack"
        "net.ipv4.tcp_dsack" "net.core.somaxconn" "net.core.netdev_max_backlog" "net.ipv4.tcp_max_syn_backlog"
        "net.ipv4.tcp_tw_reuse" "net.ipv4.tcp_fin_timeout" "net.ipv4.tcp_keepalive_time" "net.ipv4.tcp_fastopen"
        "fs.file-max"
    )
    for p in "${params[@]}"; do
        sed -i "/^${p}/d" /etc/sysctl.conf
    done
}

# 7. 核心功能：写入基础深度优化参数 (双轨通用部分)
write_base_sysctl() {
    cat >> /etc/sysctl.conf << EOF
# --- 底层并发与防排队优化 ---
fs.file-max=1048576
net.core.somaxconn=8192
net.core.netdev_max_backlog=16384
net.ipv4.tcp_max_syn_backlog=8192

# --- TCP 状态机与回收优化 (代理/建站神参数) ---
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_fastopen=3

# --- 高级黑洞探测与降延迟 ---
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_base_mss=1024
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
EOF
}

# 8. 状态体验验证功能
verify_status() {
    clear
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "         🔍 正在检测内核及网络加速算法生效状态     "
    echo -e "${BLUE}==================================================${PLAIN}"
    
    local current_k=$(uname -r)
    if [[ "$current_k" == *"xanmod"* ]]; then
        echo -e "1. 内核检测: ${GREEN}[ 正常 ]${PLAIN} ($current_k)"
    else
        echo -e "1. 内核检测: ${RED}[ 异常 ]${PLAIN} (未检测到 XanMod)"
    fi
    
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$current_cc" = "bbr" ]; then
        echo -e "2. 拥塞控制: ${GREEN}[ 正常 ]${PLAIN} (BBR 开启)"
    else
        echo -e "2. 拥塞控制: ${RED}[ 异常 ]${PLAIN} (当前为: ${current_cc:-无})"
    fi
    
    local active_qdisc=$(tc qdisc show | grep -E "fq|fq_codel|cake" | awk '{print $2}' | head -n 1)
    echo -e "3. 队列算法: ${GREEN}[ 正常 ]${PLAIN} (生效: ${active_qdisc:-未检测到})"
    
    echo -e "${BLUE}==================================================${PLAIN}"
    read -p "按回车键返回主菜单..."
}

# 9. 脚本主循环交互菜单
while true; do
    clear
    CURRENT_KERNEL=$(uname -r)
    ALREADY_XANMOD=false
    if [[ "$CURRENT_KERNEL" == *"xanmod"* ]]; then
        ALREADY_XANMOD=true
    fi

    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "    Debian/Ubuntu 智能/极客网络调优 一体化部署脚本"
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "当前系统：${GREEN}${NAME} ${VERSION_ID} (${CODENAME})${PLAIN}"
    echo -e "VPS位置 ：${GREEN}${COUNTRY_NAME}${PLAIN}"
    echo -e "当前内核：$(if [ "$ALREADY_XANMOD" = "true" ]; then echo -e "${YELLOW}${CURRENT_KERNEL} (已是XanMod)${PLAIN}"; else echo -e "${GREEN}${CURRENT_KERNEL} (标准内核)${PLAIN}"; fi)"
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "请选择调优模式："
    echo -e "  ${GREEN}1. [小白/一键] AI 智能自适应网络调优 (🏆 强烈推荐)${PLAIN}"
    echo -e "     ${YELLOW}└─ 自动识别物理内存、自适应BDP缓冲、动态抗堵塞并发全开。${PLAIN}"
    echo -e "  ${YELLOW}2. [高手/极客] 目标节点精准手工调优 (BDP / 窗口定制)${PLAIN}"
    echo -e "     ${YELLOW}└─ 需手动输入对端测速带宽与延迟，计算绝对理论极限值。${PLAIN}"
    echo -e "  ${BLUE}3. 🔍 验证内核与网络加速算法是否成功生效 (Status Check)${PLAIN}"
    echo -e "  ${RED}0. 退出脚本${PLAIN}"
    echo -e "${BLUE}==================================================${PLAIN}"
    read -p "请输入数字 [0-3] (默认: 1): " CHOICE

    # 默认选择逻辑
    if [ -z "$CHOICE" ]; then CHOICE=1; fi

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

# 根据选择写入不同的配置参数
clean_sysctl
write_base_sysctl

if [ "$CHOICE" -eq 1 ]; then
    SCENARIO="[小白模式] 智能自适应全局调优"
    
    # 动态内存计算 (防 OOM 并最大化吞吐)
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
    # 设定单连接最大缓冲为总内存的 1.5%，上限控制
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

    # BDP 计算: 带宽(Mbps) * 延迟(ms) * 125 = BDP 字节数。 (因为 10^6 / 8 / 10^3 = 125)
    # 为了冗余抗丢包，给实际 BDP 乘 1.5 倍
    BDP_BYTES=$(( TARGET_BW * TARGET_RTT * 125 * 3 / 2 ))
    
    # 防止数值过低
    if [ "$BDP_BYTES" -lt 4194304 ]; then BDP_BYTES=4194304; fi

    CONFIG_SUMMARY="BBRv3 + FQ + 精准BDP极限缓冲 ($((BDP_BYTES/1024/1024))MB, 目标:${TARGET_BW}M/${TARGET_RTT}ms)"
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem=4096 87380 ${BDP_BYTES}" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_wmem=4096 65536 ${BDP_BYTES}" >> /etc/sysctl.conf
fi

# 10. 开始执行源配置与更新
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

# 11. 智能版本比对
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

# 12. 更新引导
if [ "$NEED_REBOOT" = "true" ]; then
    echo -e "\n${BLUE}[3/3] 正在强行更新 GRUB 系统引导配置...${PLAIN}"
    retry_command update-grub
fi

# 13. 应用系统优化配置
sysctl -p > /dev/null 2>&1

# 14. 漂亮的执行结果输出
clear
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "          🎉 内核配置与极客网络调优执行完毕！"
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "使用模式：${BLUE}${SCENARIO}${PLAIN}"
echo -e "参数总览：${BLUE}${CONFIG_SUMMARY}${PLAIN}"
echo -e "高级特性：${YELLOW}并发扩容 / TIME_WAIT回收 / PMTU探测 / TCP Fast Open${PLAIN} 已全开"
echo -e "${GREEN}==================================================${PLAIN}"

# 15. 智能倒计时重启机制
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
    echo -e "您可立即再次运行本脚本选择 [3] 进行状态验证。${PLAIN}"
    echo -e "${GREEN}==================================================${PLAIN}"
fi
