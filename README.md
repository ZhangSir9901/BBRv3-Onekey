# ⚡ Debian / Ubuntu 一键安装 XanMod BBRv3 & 全栈网络动态极致调优 (双轨极客版)

一款专为 **Debian 12/13** 以及 **Ubuntu 20.04/22.04/24.04/26.04 (LTS)** 深度定制的 BBRv3 一键安装与全栈网络性能生命周期管理工具。

本脚本彻底打破传统脚本“静态死参数”与“片面调优”的局限，全面进化为**硬件容量感知、链路 BDP 极客计算、UDP/QUIC 极限扩容、Xray 零拷贝加速与双栈 IP 守护**的一体化完整体系。

---

## 🌟 核心突破与全栈亮点

* 🧠 **AI 动态内存感知与 Swap 保命气囊**：自动读取物理内存按千分之十五安全推算 TCP 窗口（防 OOM）；检测到小内存主机（≤1.5GB）且无 Swap 时，**自动挂载 1GB 虚拟内存保命气囊**，并锁定 `swappiness=10` 确保物理内存绝对优先。
* 🚀 **全栈 UDP / QUIC 协议极限吞吐**：突破 Linux 默认 200KB 的 UDP 缓冲区瓶颈，将网卡与 UDP 接收/发送缓冲强力扩容至 **64MB**，为 **Hysteria 2、TUIC、WireGuard、游戏及 HTTP/3** 释放满血传输能力。
* ⚡ **Xray / 代理底层零拷贝与高并发扩容**：将 Linux 管道缓冲提升至 1MB，大幅榨干 Xray/Sing-box 的 `splice()` 零拷贝吞吐；扩充连接跟踪表（`conntrack` 100万）与出站端口池（6.4万），彻底根除晚高峰连接卡死与断流。
* 🥇 **BBRv3 + FQ 黄金搭档与防排队**：全局启用纯正 `fq` 队列调度配合 BBRv3 Pacing 平滑发包；注入 `tcp_notsent_lowat=16384` 从源头消除缓冲膨胀（Bufferbloat），搭配 `tcp_fastopen=3` 与 `slow_start_after_idle=0` 实现首包秒开、常态满速。
* 🌐 **三维 IP 架构自适应与断网守护**：自动识别 **双栈网络、纯 IPv4、纯 IPv6** 拓扑；针对双栈开启内核级转发并注入 `accept_ra=2`，彻底修复 Linux 开启转发后 IPv6 路由丢失的陈年断网 Bug。
* ⛔ **封闭虚拟化与国内云大厂安全熔断**：全自动识别中国大陆 IP 及阿里/腾讯/华为的国内与海外全系实例，**自动触发安全拦截**，坚决防止因缺少 AVX2 指令集或网卡驱动不兼容导致服务器变砖（Kernel Panic）。
* 🔍 **清单级 360° 深度状态体检 (选项 3)**：全面罗列内核、TCP、UDP/QUIC、高并发状态机、IP 栈及虚拟内存调度全量参数，清晰透明评估当前生效状态。
* 🥷 **4 重静默防 WAF 伪装与热重载**：高拟真 Chrome UA 伪装静默绕过 Cloudflare 403 阻断；若内核已是最新版，自动跳过安装并**即时热重载所有网络参数，免重启即改即用**！

---

## 🚀 极速一键运行

使用 `root` 用户登录您的 Debian 或 Ubuntu 服务器，复制并运行以下命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ZhangSir9901/BBRv3-Onekey/main/bbr_tune.sh)
```

---

## 📊 双轨制调优模式 (化繁为简)

脚本具备**防呆智能默认逻辑**（未调优默认回车选 `1` 一键优化；已调优默认回车选 `0` 安全退出）：

| 选项 | 模式名称 | 运行逻辑与适用场景 |
| :---: | :--- | :--- |
| **1** | **[小白/一键] AI 智能自适应全栈调优**<br>*(🏆 默认极简推荐)* | 自动识别物理内存/Swap、自适应 BDP 缓冲、UDP/QUIC 扩容、动态抗堵塞并发全开。<br>**适用：不想折腾的用户，99.9% 的 VPS 一键直达商业级全栈极致性能。** |
| **2** | **[高手/极客] 目标节点精准手工调优**<br>*(🔧 专线测速定制)* | 基于底层物理定律 `Bandwidth * Latency / 8` 计算极限 BDP 窗口。<br>**适用：中转机/机场主/专线链路，输入实测最高带宽与平均延迟，榨干单条线路极限。** |
| **3** | **🔍 详细体检内核与网络加速状态**<br>*(Status Check)* | 全量清单级展示内核架构、TCP、UDP/QUIC、并发状态机、IP 栈及内存调度生效参数。 |

---

## 🛡️ 系统安全保障 (逃生舱设计 & 云厂商熔断)

1. **多内核逃生舱**：包管理器在安装新内核时会**默认保留系统原本的老内核**。万一遇到硬件不兼容导致开机异常，只需在商家 VNC/Console 重启并在 GRUB 菜单选择 `Advanced options` 即可一键选回老内核恢复。
2. **云厂商安全熔断**：为避免国内云厂商（阿里/腾讯/华为）裁剪指令集造成的引导崩溃，脚本会在执行前强制阻断此类机型，保护数据与连接安全。

---

## 💬 作者与技术支持

如果您在部署中遇到难题，或者探讨底层网络与系统调优技术，欢迎与我交流！

* ![WeChat](https://img.shields.io/badge/微信-07C160?style=flat-square&logo=wechat&logoColor=white) `jiujiujiayi666`
* [![Telegram](https://img.shields.io/badge/Telegram-2CA5E0?style=flat-square&logo=telegram&logoColor=white)](https://t.me/YuC2027) [@YuC2027](https://t.me/YuC2027)
* [![Website](https://img.shields.io/badge/官网-乾旭网络-1081C1?style=flat-square&logo=googlechrome&logoColor=white)](https://www.qianxu.vip) [www.qianxu.vip](https://www.qianxu.vip)

💡 如果您对软件有其它建议，欢迎在仓库提交 **Issues**；如果有其它定制需求，请通过上方联系方式与我联系。

---

## ☕ 赞助与打赏

如果这个项目为你节省了宝贵的时间，或者你惊叹于它极度丝滑且硬核的代码艺术，欢迎打赏支持！您的支持是我持续开源与输出硬核代码的最大动力！

### ![Alipay](https://img.shields.io/badge/支付宝-Alipay-1677FF?style=flat-square&logo=alipay&logoColor=white)

👇 鼠标悬停在下方代码框内，点击右上角即可一键复制：

```text
pdlr@qq.com
```

### ![Tether USDT](https://img.shields.io/badge/USDT-TRC20-26A17B?style=flat-square&logo=tether&logoColor=white)

👇 鼠标悬停在下方代码框内，点击右上角即可一键复制：

```text
TXS6K4jaomQn26QsouSkdUZPDRo8Rd63zj
```

---

> *"Talk is cheap. Show me the code."* —— 保持热爱，奔赴山海。
