# ⚡ Debian 12/13 一键安装 XanMod BBRv3 智能网络调优脚本

这是一个专为 **Debian 12 (bookworm)** 和 **Debian 13 (trixie)** 深度定制的 BBRv3 一键安装及网络调度调优脚本。

## 🌟 项目亮点
- **高精度战区识别**：集成 Cloudflare 边缘路由链路分析，100% 精准识别 VPS 物理出网路由。
- **双轨制智能高亮**：根据 VPS 物理地理位置，自动在菜单中高亮推荐最适合当前机器的调优方案（区分“建站+翻墙”和“纯翻墙”场景）。
- **避坑 Debian 12 404**：自动识别旧稳定版（oldstable）环境，强制适配 LTS 分支，告别“Unable to locate package”报错。
- **高可用重试机制**：针对境外 VPS 路由抖动，网络命令配备 5 次自动重试，极大提高一键安装成功率。
- **安全干净**：每次写入配置前自动清理历史冲突参数，拒绝 sysctl 配置文件冗余。

## 🚀 一键运行命令
请使用 `root` 用户登录您的 Debian 12/13 服务器，复制并运行以下命令：

```bash
bash <(curl -fsSL https://github.com/ZhangSir9901/BBRv3-Onekey/blob/main/bbr3.sh)
