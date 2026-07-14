#!/bin/bash

# ====================================================================
# 项目名称: Debian 12/13 XanMod BBRv3 智能生命周期管理脚本 (终极高亮版)
# 支持系统: Debian 12 (bookworm) / Debian 13 (trixie)
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

# 限制仅支持 Debian 12 和 13
if [ "$ID" != "debian" ] || { [ "$VERSION_ID" != "12" ] && [ "$VERSION_ID" != "13" ]; }; then
    echo -e "${RED}[错误] 本脚本仅支持 Debian 12 (bookworm) 和 Debian 13 (trixie)！${PLAIN}"
    echo -e "${YELLOW}当前系统为: ${ID} ${VERSION_ID:-未知版本}${PLAIN}"
    exit 1
fi

# 2. 预检并安装基础依赖 (新增 ca-certificates 修复 HTTPS 验证报错)
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
    HK) COUNTRY_NAME="中国香港"; IS_ASIA_PACIFIC=true ;;
    JP) COUNTRY_NAME="日本"; IS_ASIA_PACIFIC=true ;;
    KR) COUNTRY_NAME="韩国"; IS_ASIA_PACIFIC=true ;;
    SG) COUNTRY_NAME="新加坡"; IS_ASIA_PACIFIC=true ;;
    MY) COUNTRY_NAME="马来西亚"; IS_ASIA_PACIFIC=true ;;
    PH) COUNTRY_NAME="菲律宾"; IS_ASIA_PACIFIC=true ;;
    TW) COUNTRY_NAME="中国台湾"; IS_ASIA_PACIFIC=true ;;
    TH) COUNTRY_NAME="泰国"; IS_ASIA_PACIFIC=true ;;
    VN) COUNTRY_NAME="越南"; IS_ASIA_PACIFIC=true ;;
    ID) COUNTRY_NAME="印度尼西亚"; IS_ASIA_PACIFIC=true ;;
    US) COUNTRY_NAME="美国" ;;
    CA) COUNTRY_NAME="加拿大" ;;
    GB|UK) COUNTRY_NAME="英国" ;;
    DE) COUNTRY_NAME="德国" ;;
    NL) COUNTRY_NAME="荷兰" ;;
    FR) COUNTRY_NAME="法国" ;;
    RU) COUNTRY_NAME="俄罗斯" ;;
    AU) COUNTRY_NAME="澳大利亚" ;;
    IN) COUNTRY_NAME="印度" ;;
    CN) COUNTRY_NAME="中国大陆" ;;
    *) COUNTRY_NAME="${COUNTRY_CODE}";;
esac

# 4. 根据战区计算高亮和推荐
OPT1_COLOR="${GREEN}"
OPT2_COLOR="${GREEN}"
OPT3_COLOR="${GREEN}"
OPT4_COLOR="${GREEN}"
OPT1_TAG=""
OPT2_TAG=""
OPT3_TAG=""
OPT4_TAG=""

if [ "$IS_ASIA_PACIFIC" = "true" ]; then
    OPT1_COLOR="${YELLOW}"
    OPT3_COLOR="${YELLOW}"
    OPT1_TAG=" ${RED}[⭐ 亚太建站推荐]${PLAIN}"
    OPT3_TAG=" ${RED}[⭐ 亚太翻墙推荐]${PLAIN}"
    RECOMMENDED_TIP="您的 VPS 位于【亚太低延迟区】，已为您高亮推荐 1 和 3 方案。"
else
    OPT2_COLOR="${YELLOW}"
    OPT4_COLOR="${YELLOW}"
    OPT2_TAG=" ${RED}[⭐ 远距离建站推荐]${PLAIN}"
    OPT4_TAG=" ${RED}[⭐ 远距离翻墙推荐]${PLAIN}"
    RECOMMENDED_TIP="您的 VPS 位于【美欧/远距离区】，已为您高亮推荐 2 和 4 方案。"
fi

# 5. 自动匹配内核包名称
CODENAME=$VERSION_CODENAME
if [ "$VERSION_ID" = "12" ]; then
    KERNEL_PKG="linux-xanmod-lts-x64v3"
else
    KERNEL_PKG="linux-xanmod-x64v3"
fi

# 6. 定义通用命令重试函数
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

# 7. 清理旧的系统参数配置
clean_sysctl() {
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_notsent_lowat/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_adv_win_scale/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_collapse_max_bytes/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_frto/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_sack/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_dsack/d' /etc/sysctl.conf
}

# 8. 闭合状态体检菜单项（验证与高亮状态评估）
verify_status() {
    clear
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "         🔍 正在检测内核及网络加速算法生效状态...     "
    echo -e "${BLUE}==================================================${PLAIN}"
    
    # 1. 检测内核是否为 XanMod
    local kernel_active=false
    local current_k=$(uname -r)
    if [[ "$current_k" == *"xanmod"* ]]; then
        echo -e "1. 内核检测: ${GREEN}[ 正常 ]${PLAIN} (当前运行: $current_k)"
        kernel_active=true
    else
        echo -e "1. 内核检测: ${RED}[ 异常 ]${PLAIN} (未检测到 XanMod，当前为: $current_k)"
    fi
    
    # 2. 检测拥塞控制算法
    local bbr_active=false
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$current_cc" = "bbr" ]; then
        echo -e "2. 拥塞控制: ${GREEN}[ 正常 ]${PLAIN} (已启用 BBR 算法)"
        bbr_active=true
    else
        echo -e "2. 拥塞控制: ${RED}[ 异常 ]${PLAIN} (未启用 BBR，当前为: ${current_cc:-无})"
    fi
    
    # 3. 检测实时网卡队列调度算法 (qdisc)
    local current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local active_qdisc=$(tc qdisc show | grep -E "fq|fq_codel|cake" | awk '{print $2}' | head -n 1)
    
    echo -e "3. 队列算法: ${GREEN}[ 正常 ]${PLAIN} (预设: $current_qdisc | 生效: ${active_qdisc:-未检测到})"
    
    echo -e "${BLUE}==================================================${PLAIN}"
    # 状态评估输出（包含内核与BBR加速状态显式高亮显示）
    if [ "$kernel_active" = "true" ] && [ "$bbr_active" = "true" ]; then
        echo -e "${GREEN}🎉 状态评估：BBRv3 网络加速调优已完美生效！${PLAIN}"
        echo -e "   👉 ${GREEN}当前内核: $current_k (XanMod 性能内核)${PLAIN}"
        echo -e "   👉 ${GREEN}加速状态: BBR 拥塞控制算法正常运行 (底蕴 BBRv3 驱动)${PLAIN}"
    else
        echo -e "${RED}⚠️  状态评估：网络加速调优未完全生效！${PLAIN}"
        echo -e "   👉 当前内核: ${YELLOW}$current_k${PLAIN} (期待: XanMod 内核)"
        echo -e "   👉 加速状态: ${YELLOW}BBR 当前处于 [ ${current_cc:-未激活} ] 状态${PLAIN}"
        echo -e "   提示：若您刚刚完成了内核升级，请务必重启服务器！"
    fi
    echo -e "${BLUE}==================================================${PLAIN}"
    read -p "按回车键返回主菜单..."
}

# 9. 脚本主循环交互菜单
while true; do
    clear
    # 动态检测当前运行内核
    CURRENT_KERNEL=$(uname -r)
    ALREADY_XANMOD=false
    if [[ "$CURRENT_KERNEL" == *"xanmod"* ]]; then
        ALREADY_XANMOD=true
    fi

    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "       Debian 12/13 XanMod BBRv3 一体化部署脚本"
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "当前系统：${GREEN}Debian ${VERSION_ID} (${CODENAME})${PLAIN}"
    echo -e "VPS位置 ：${GREEN}${COUNTRY_NAME} (${COUNTRY_CODE})${PLAIN}"
    if [ "$ALREADY_XANMOD" = "true" ]; then
        echo -e "当前内核：${YELLOW}${CURRENT_KERNEL} (已是XanMod)${PLAIN}"
    else
        echo -e "当前内核：${GREEN}${CURRENT_KERNEL} (标准内核)${PLAIN}"
    fi
    echo -e "智能提示：${YELLOW}${RECOMMENDED_TIP}${PLAIN}"
    echo -e "${BLUE}==================================================${PLAIN}"
    echo -e "请选择使用场景与更换方案："
    echo -e "  ${OPT1_COLOR}1. [建站+翻墙] 亚太低延迟区优化 (BBRv3 + FQ_CODEL + 适度缓存)${OPT1_TAG}"
    echo -e "  ${OPT2_COLOR}2. [建站+翻墙] 欧美/远距离区优化 (BBRv3 + FQ_CODEL + 标准缓存)${OPT2_TAG}"
    echo -e "  ${OPT3_COLOR}3. [纯翻墙机] 亚太低延迟区极限优化 (BBRv3 + CAKE + 亚太TCP调优)${OPT3_TAG}"
    echo -e "  ${OPT4_COLOR}4. [纯翻墙机] 欧美/远距离区吞吐优化 (BBRv3 + FQ + 远距离调优)${OPT4_TAG}"
    echo -e "  ${BLUE}5. 🔍 验证内核与网络加速算法是否成功生效 (Status Check)${PLAIN}"
    echo -e "  ${RED}0. 退出脚本${PLAIN}"
    echo -e "${BLUE}==================================================${PLAIN}"
    read -p "请输入数字 [0-5]: " CHOICE

    if [ -z "$CHOICE" ]; then
        CHOICE=$RECOMMENDED_OPTION
    fi

    case "$CHOICE" in
        1|2|3|4)
            # 如果已经是 XanMod，高亮提醒
            if [ "$ALREADY_XANMOD" = "true" ]; then
                clear
                echo -e "${YELLOW}==================================================${PLAIN}"
                echo -e "⚠️  ${RED}【高亮提醒】您的服务器当前已经是 XanMod 内核！${PLAIN}"
                echo -e "当前内核版本为: ${GREEN}${CURRENT_KERNEL}${PLAIN}"
                echo -e "${YELLOW}==================================================${PLAIN}"
                read -p "您是想继续调整配置并检查内核升级，还是安全退出？[Y:继续 / N:退出, 默认退出]: " WARN_CHOICE
                WARN_CHOICE=$(echo "$WARN_CHOICE" | tr '[:lower:]' '[:upper:]')
                if [ "$WARN_CHOICE" != "Y" ]; then
                    echo -e "${BLUE}已自动安全退出脚本。${PLAIN}"
                    exit 0
                fi
            fi
            break # 跳出菜单循环，向下执行安装
            ;;
        5)
            verify_status
            ;;
        0)
            echo -e "${BLUE}已安全退出脚本。${PLAIN}"
            exit 0
            ;;
        *)
            echo -e "${RED}[错误] 输入无效，请重新选择！${PLAIN}"
            sleep 1
            ;;
    esac
done

# 根据选择写入不同的配置参数
case "$CHOICE" in
    1)
        SCENARIO="[建站+翻墙] 亚太低延迟平衡型"
        CONFIG_SUMMARY="BBRv3 + FQ_CODEL + 适度亚太网络优化"
        clean_sysctl
        echo "net.core.default_qdisc=fq_codel" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_rmem=4096 87380 6291456" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_wmem=4096 65536 6291456" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_sack=1" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_dsack=1" >> /etc/sysctl.conf
        ;;
    2)
        SCENARIO="[建站+翻墙] 远距离标准平衡型"
        CONFIG_SUMMARY="BBRv3 + FQ_CODEL + 标准TCP缓存配置"
        clean_sysctl
        echo "net.core.default_qdisc=fq_codel" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_sack=1" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_dsack=1" >> /etc/sysctl.conf
        ;;
    3)
        SCENARIO="[纯翻墙] 亚太低延迟极限型"
        CONFIG_SUMMARY="BBRv3 + CAKE + 亚太TCP窗口极限优化"
        clean_sysctl
        echo "net.core.default_qdisc=cake" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_notsent_lowat=16384" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_rmem=4096 87380 16777216" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_wmem=4096 65536 16777216" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_adv_win_scale=-2" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_collapse_max_bytes=6291456" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_frto=2" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_sack=1" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_dsack=1" >> /etc/sysctl.conf
        ;;
    4)
        SCENARIO="[纯翻墙] 远距离吞吐极限型"
        CONFIG_SUMMARY="BBRv3 + FQ + 远距离吞吐量优化"
        clean_sysctl
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_notsent_lowat=16384" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_sack=1" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_dsack=1" >> /etc/sysctl.conf
        ;;
esac

# 10. 开始执行源配置与更新 (修复 PGP 下载机制)
echo -e "\n${BLUE}[3/5] 开始配置 XanMod 官方存储库...${PLAIN}"
rm -f /etc/apt/sources.list.d/xanmod-release.list

install -d -m 0755 /etc/apt/keyrings
TMP_KEY="/tmp/xanmod.key"
rm -f "$TMP_KEY"

echo -e "${YELLOW}正在获取 XanMod PGP 密钥 (多重冗余机制)...${PLAIN}"
# 冗余策略1: curl 默认
curl -fsSL --connect-timeout 10 --retry 3 https://dl.xanmod.org/archive.key -o "$TMP_KEY"
# 冗余策略2: wget 默认
if [ ! -s "$TMP_KEY" ] || ! grep -q "PGP PUBLIC KEY" "$TMP_KEY"; then
    wget -qO "$TMP_KEY" --timeout=10 --tries=3 https://dl.xanmod.org/archive.key
fi
# 冗余策略3: curl 强制 IPv4 (对抗 IPv6 黑洞)
if [ ! -s "$TMP_KEY" ] || ! grep -q "PGP PUBLIC KEY" "$TMP_KEY"; then
    curl -fsSL -4 --connect-timeout 10 --retry 3 https://dl.xanmod.org/archive.key -o "$TMP_KEY"
fi
# 冗余策略4: wget 强制 IPv4
if [ ! -s "$TMP_KEY" ] || ! grep -q "PGP PUBLIC KEY" "$TMP_KEY"; then
    wget -4 -qO "$TMP_KEY" --timeout=10 --tries=3 https://dl.xanmod.org/archive.key
fi

# 最终文件合法性校验
if [ -s "$TMP_KEY" ] && grep -q "PGP PUBLIC KEY" "$TMP_KEY"; then
    gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg "$TMP_KEY"
    rm -f "$TMP_KEY"
    echo -e "${GREEN}[成功] PGP 证书导入完成！${PLAIN}"
else
    echo -e "${RED}[错误] PGP 证书获取失败！可能原因：${PLAIN}"
    echo -e "${RED}1. VPS 无法连接到 dl.xanmod.org (被墙或无 IPv4 路由)${PLAIN}"
    echo -e "${RED}2. 系统仍缺少有效 CA 证书${PLAIN}"
    exit 1
fi

echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${CODENAME} main" | tee /etc/apt/sources.list.d/xanmod-release.list

# 执行源更新
retry_command apt update
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] 软件源更新失败！${PLAIN}"
    exit 1
fi

# 11. 智能版本比对
SKIP_KERNEL_INSTALL=false
NEED_REBOOT=false

if dpkg -l | grep -q "${KERNEL_PKG}"; then
    INSTALLED_VER=$(dpkg-query -W -f='${Version}' ${KERNEL_PKG} 2>/dev/null)
    LATEST_VER=$(apt-cache policy ${KERNEL_PKG} | grep "Candidate:" | awk '{print $2}')
    
    if [ -n "$LATEST_VER" ] && [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
        echo -e "\n${GREEN}[提示] 检测到您当前的 XanMod 内核已经是最新版本 (${INSTALLED_VER})，跳过内核重装。${PLAIN}"
        SKIP_KERNEL_INSTALL=true
    else
        echo -e "\n${YELLOW}[提示] 检测到新版本 XanMod 内核！${PLAIN}"
        echo -e "当前安装版本: ${INSTALLED_VER}"
        echo -e "最新可用版本: ${LATEST_VER}"
        echo -e "正在执行内核升级操作...${PLAIN}"
    fi
fi

if [ "$SKIP_KERNEL_INSTALL" = "false" ]; then
    echo -e "\n${BLUE}[4/5] 正在安装/升级 XanMod 内核包 [${KERNEL_PKG}]...${PLAIN}"
    retry_command apt install ${KERNEL_PKG} -y
    if [ $? -ne 0 ]; then
        echo -e "${RED}[错误] 内核程序安装/升级失败！${PLAIN}"
        exit 1
    fi
    NEED_REBOOT=true
fi

# 12. 更新引导（仅在真正安装/升级了内核时执行）
if [ "$NEED_REBOOT" = "true" ]; then
    echo -e "\n${BLUE}[5/5] 正在强行更新 GRUB 系统引导配置...${PLAIN}"
    retry_command update-grub
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}[警告] update-grub 执行异常，正在尝试备份方案生成 grub.cfg...${PLAIN}"
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
fi

# 13. 应用系统优化配置
sysctl -p > /dev/null

# 14. 漂亮的执行结果输出
clear
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "          🎉 内核配置与网络调优执行完毕！"
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "当前系统：${BLUE}Debian ${VERSION_ID} ${CODENAME}${PLAIN}，VPS位置：${BLUE}${COUNTRY_NAME}${PLAIN}；"
echo -e "部署内核：${BLUE}${KERNEL_PKG}${PLAIN}；"
echo -e "使用场景：${BLUE}${SCENARIO}${PLAIN}；"
echo -e "调优配置：${BLUE}${CONFIG_SUMMARY}${PLAIN}。"
echo -e "${GREEN}==================================================${PLAIN}"

# 15. 智能倒计时重启机制
if [ "$NEED_REBOOT" = "true" ]; then
    echo -e "${YELLOW}由于安装/升级了新内核，系统将在 7 秒后自动重启使其生效！${PLAIN}"
    echo -e "${YELLOW}重启后请重新运行本脚本，选择选项 5 进行状态验证。${PLAIN}"
    echo -e "${GREEN}==================================================${PLAIN}"
    for i in {7..1}; do
        echo -ne "\r${YELLOW}倒计时: $i 秒后自动重启...${PLAIN}"
        sleep 1
    done
    echo -e "\n${GREEN}正在重启服务器...${PLAIN}"
    reboot
else
    # 获取实时运行内核名
    REAL_K=$(uname -r)
    echo -e "${GREEN}🎉 提示：由于内核已是最新，新调优参数已立即应用，无需重启！${PLAIN}"
    echo -e "当前运行内核：${BLUE}${REAL_K}${PLAIN}"
    echo -e "BBR加速状态 ：${BLUE}已立即热应用最新网络调优配置${PLAIN}"
    echo -e "您可立即使用 `tc qdisc show` 或再次运行本脚本选项 5 进行实时验证。${PLAIN}"
    echo -e "${GREEN}==================================================${PLAIN}"
fi
