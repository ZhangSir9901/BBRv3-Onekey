#!/bin/bash

# ==============================================================================
# AI Agent VPS TCP Auto-Tuner
# 基于《让 AI 帮你调 VPS 网络：中转机和落地机 TCP 调优笔记》的动态计算与应用体系
# 核心逻辑：探测(Probe) -> 计算(Calculate) -> 应用(Apply)
# ==============================================================================

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[1;33m'
BLUE='\033[36m'
PLAIN='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[错误] 请使用 root 权限运行此脚本！${PLAIN}"
    exit 1
fi

echo -e "${BLUE}======================================================${PLAIN}"
echo -e "       VPS TCP 动态智能调优体系 (Measurement-First)    "
echo -e "${BLUE}======================================================${PLAIN}"

# --- 环境依赖检查 ---
if ! command -v iperf3 >/dev/null || ! command -v jq >/dev/null; then
    echo -e "${YELLOW}正在安装必要工具 (iperf3, jq, iproute2)...${PLAIN}"
    apt-get update -qq && apt-get install -yqq iperf3 jq iproute2 bc
fi

# --- 参数输入 ---
PEER_IP=$1
PEER_PORT=${2:-5201}

if [ -z "$PEER_IP" ]; then
    echo -e "${YELLOW}为了进行动态测算，我们需要一个目标测试节点 (Peer)。${PLAIN}"
    echo -e "如果您是中转机，请填入落地机的 IP；如果是落地机，请填入中转机或常用测试点 IP。"
    read -p "请输入对端 IP 或域名 (Peer IP): " PEER_IP
    if [ -z "$PEER_IP" ]; then
        echo -e "${RED}[错误] 未输入对端 IP，退出。也可以通过命令行参数传入：./auto_tune.sh <IP> [PORT]${PLAIN}"
        exit 1
    fi
    read -p "请输入对端 iperf3 端口 (默认 5201): " PEER_PORT
    PEER_PORT=${PEER_PORT:-5201}
fi

# 获取主要网卡
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
echo -e "${BLUE}[信息] 探测到主网卡为: ${MAIN_IFACE}${PLAIN}"

# ==========================================
# 1. MTU 阶梯探测 (PMTU Ladder)
# ==========================================
echo -e "\n${BLUE}[1/4] 开始探测到 $PEER_IP 的最佳 MTU...${PLAIN}"
BEST_PAYLOAD=0
for s in 1472 1452 1432 1412 1392 1352 1332 1312 1292; do
    # DF 标志：禁止分片
    if ping -M do -s "$s" -c 2 -W 1 "$PEER_IP" >/dev/null 2>&1; then
        BEST_PAYLOAD=$s
        break
    fi
done

if [ "$BEST_PAYLOAD" -gt 0 ]; then
    BEST_MTU=$((BEST_PAYLOAD + 28))
    echo -e "${GREEN}[成功] 探测到最佳无分片 MTU 为: $BEST_MTU (Payload: $BEST_PAYLOAD)${PLAIN}"
    # 动态应用 MTU
    ip link set dev "$MAIN_IFACE" mtu "$BEST_MTU"
    echo -e "${GREEN}已将网卡 $MAIN_IFACE MTU 临时设置为 $BEST_MTU。${PLAIN}"
else
    echo -e "${YELLOW}[警告] ICMP 探测失败 (可能被禁 ping)，保留默认 MTU。${PLAIN}"
fi

# ==========================================
# 2. iperf3 测速与重传数据采集 (Probe)
# ==========================================
echo -e "\n${BLUE}[2/4] 正在向 $PEER_IP 运行 10 秒 iperf3 测速，采集 BDP 与重传数据...${PLAIN}"
TMP_JSON="/tmp/iperf3_result.json"
# 单线程，正向测试（测本机发送方向，以评估本机出口队列瓶颈）
iperf3 -c "$PEER_IP" -p "$PEER_PORT" -t 10 -J > "$TMP_JSON" 2>/dev/null

if [ ! -s "$TMP_JSON" ] || ! jq -e '.end' "$TMP_JSON" >/dev/null 2>&1; then
    echo -e "${RED}[错误] iperf3 测试失败！请确保对端已启动 iperf3 -s -p $PEER_PORT 并且防火墙放行。${PLAIN}"
    echo -e "${YELLOW}降级模式：采用保守缓冲配置跳过 BDP 计算。${PLAIN}"
    HAS_BDP_DATA=false
else
    HAS_BDP_DATA=true
    # 解析 JSON
    BANDWIDTH_BPS=$(jq '.end.sum_received.bits_per_second' "$TMP_JSON" | cut -d. -f1)
    # 取 sender 端的 rtt，如果没有，默认给 100000 微秒
    RTT_US=$(jq '.end.streams[0].sender.mean_rtt // 100000' "$TMP_JSON" | cut -d. -f1)
    # 取 retransmits，如果 jq 返回 null，使用 0
    RETRANSMITS=$(jq '.end.sum_sent.retransmits // 0' "$TMP_JSON")

    BANDWIDTH_MBPS=$((BANDWIDTH_BPS / 1000000))
    # 避免 null 导致的 Bash 算术错误
    if [ -z "$RTT_US" ] || [ "$RTT_US" = "null" ]; then
        RTT_US=100000
    fi
    RTT_MS=$((RTT_US / 1000))

    echo -e "  - 实测带宽: ${GREEN}${BANDWIDTH_MBPS} Mbps${PLAIN}"
    echo -e "  - 平均延迟: ${GREEN}${RTT_MS} ms${PLAIN}"
    echo -e "  - 测速重传数: ${YELLOW}${RETRANSMITS}${PLAIN}"
fi

# ==========================================
# 3. 动态计算 TCP Buffer 与内核参数 (Calculate)
# ==========================================
echo -e "\n${BLUE}[3/4] 开始计算并生成动态 TCP 调优参数...${PLAIN}"

# 获取物理内存大小 (MB)
TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
# 安全上限：物理内存的 10% 用于单个连接的最大缓冲
MAX_MEM_BYTES=$((TOTAL_MEM_MB * 1024 * 1024 / 10))

# 写入独立配置文件，避免污染 sysctl.conf
SYSCTL_FILE="/etc/sysctl.d/99-ai-tune.conf"
echo "# === AI Auto-Tune ===" > "$SYSCTL_FILE"
echo "net.core.default_qdisc = fq" >> "$SYSCTL_FILE"
echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYSCTL_FILE"

if [ "$HAS_BDP_DATA" = true ]; then
    # BDP 计算公式：带宽(bps) * 延迟(s) / 8 = 字节
    # 为了冗余，缓冲区大小设为 BDP 的 2 倍。使用 scale=4 进行除法，防止 RTT_MS/1000 变成 0。
    BDP_BYTES=$(echo "scale=4; ${BANDWIDTH_BPS} * (${RTT_MS} / 1000.0) / 8 * 2" | bc | cut -d. -f1)

    # 防御性判断：避免 BDP_BYTES 为空
    if [ -z "$BDP_BYTES" ]; then
        BDP_BYTES=4194304
    fi

    if [ "$BDP_BYTES" -gt "$MAX_MEM_BYTES" ]; then
        echo -e "${YELLOW}  - 计算得出的 BDP ($BDP_BYTES) 超过内存安全限制，截断至 ($MAX_MEM_BYTES)${PLAIN}"
        CALC_BUFFER=$MAX_MEM_BYTES
    else
        CALC_BUFFER=$BDP_BYTES
    fi

    # 确保最小值不低于 4MB (4194304) 以防计算出错导致过小
    if [ "$CALC_BUFFER" -lt 4194304 ]; then
        CALC_BUFFER=4194304
    fi

    echo -e "  - 计算得出的动态 TCP Buffer 上限为: ${GREEN}$CALC_BUFFER 字节 (~$((CALC_BUFFER/1024/1024)) MB)${PLAIN}"

    echo "net.ipv4.tcp_rmem = 4096 87380 $CALC_BUFFER" >> "$SYSCTL_FILE"
    echo "net.ipv4.tcp_wmem = 4096 65536 $CALC_BUFFER" >> "$SYSCTL_FILE"

else
    # 降级保守配置 (16MB)
    echo "net.ipv4.tcp_rmem = 4096 87380 16777216" >> "$SYSCTL_FILE"
    echo "net.ipv4.tcp_wmem = 4096 65536 16777216" >> "$SYSCTL_FILE"
fi

# 应用 sysctl
sysctl --system >/dev/null 2>&1
echo -e "${GREEN}[成功] 已写入配置 $SYSCTL_FILE 并应用动态内核参数。${PLAIN}"

# ==========================================
# 4. 智能流量整形诊断 (TBF Shaping)
# ==========================================
echo -e "\n${BLUE}[4/4] 评估出口限速 (基于丢包与重传分析)...${PLAIN}"

if [ "$HAS_BDP_DATA" = true ]; then
    if [ "$RETRANSMITS" -gt 100 ]; then
        echo -e "${YELLOW}检测到高重传 (${RETRANSMITS})！可能存在网卡出口队列瓶颈。${PLAIN}"
        # 取实测带宽的 90% 作为阶梯限速。如果计算结果为空或非纯数字，默认设为 0。
        TARGET_LIMIT=$(echo "${BANDWIDTH_MBPS} * 0.9" | bc | cut -d. -f1)
        if [ -z "$TARGET_LIMIT" ]; then
            TARGET_LIMIT=0
        fi

        if [ "$TARGET_LIMIT" -gt 10 ]; then
            echo -e "${YELLOW}正在网卡 ${MAIN_IFACE} 尝试应用 TBF 限速 (${TARGET_LIMIT}mbit)...${PLAIN}"
            tc qdisc del dev "$MAIN_IFACE" root 2>/dev/null
            tc qdisc add dev "$MAIN_IFACE" root tbf rate "${TARGET_LIMIT}mbit" burst 32k latency 50ms
            echo -e "${GREEN}[成功] 已应用 ${TARGET_LIMIT}mbit 流量整形！请再次运行 iperf3 观察重传是否下降。${PLAIN}"
        fi
    else
        echo -e "${GREEN}重传率正常 (${RETRANSMITS})，当前无需应用 TBF 流量整形，以免损失吞吐量。${PLAIN}"
        tc qdisc del dev "$MAIN_IFACE" root 2>/dev/null
    fi
else
    echo -e "${PLAIN}跳过流量整形分析。${PLAIN}"
fi

echo -e "\n${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}🎉 动态智能调优闭环执行完毕！${PLAIN}"
echo -e "${PLAIN}本脚本真正做到了文章核心：根据实测算 BDP、拒写死参数、按需定 MTU 与 TBF。${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"
