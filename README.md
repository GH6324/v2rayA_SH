
# 🚀 Xray-core + v2rayA 全能管理脚本

> **一键部署、智能版本探测、平滑升级、多架构支持**

这是一个专为 **Debian / Ubuntu / CentOS / Alpine** 等 Linux 系统设计的 Shell 脚本。它能够自动化部署和管理最新版本的 [Xray-core](https://github.com/XTLS/Xray-core) 和 [v2rayA](https://github.com/v2rayA/v2rayA)。

脚本解决了常见的 API 限制问题、文件名版本号不匹配问题，并内置了智能的兜底机制，确保在各种网络环境下都能 100% 安装成功。

如遇问题，请在 [Issues](https://github.com/GH6324/v2rayA_SH/issues/new) 反馈。

# ⭐ 如果觉得有帮助，点个 Star 吧！

💖 **你的支持是我们更新的动力！**  
动动发财的小手，给项目点个 [🌟 Star](https://github.com/GH6324/v2rayA_SH) 吧！谢谢！ 🎈🎈🎈  
-----

## ✨ 核心特性

| 功能 | 说明 |
| :--- | :--- |
| 🛠️ **一键部署** | 自动安装 Curl, Wget, Unzip 等依赖，无需手动干预。 |
| 🌍 **智能代理** | 内置 `gh-proxy` 加速，解决国内服务器下载 GitHub 资源慢/失败的问题。 |
| 🔍 **版本探测** | 自动通过 API 获取最新版本，若 API 超时自动切换至内置稳定兜底版本。 |
| 🖥️ **架构自检** | 自动识别 `x86_64` (AMD64) 和 `aarch64` (ARM64) 架构。 |
| 🔄 **平滑升级** | 提供交互式菜单，可单独更新 Xray 内核或 v2rayA 面板，配置不丢失。 |
| 🛡️ **防火墙配置** | 自动检测 UFW / Firewalld 并放行 `2017` 端口。 |
| ⚙️ **服务守护** | 完美支持 `Systemd` 和 `OpenRC` (Alpine Linux) 两种服务管理器。 |

-----

## 📥 快速开始

### 方式一：直接运行 (推荐)

直接运行一键脚本即可：

```bash
bash <(curl -Ls https://gh-proxy.com/raw.githubusercontent.com/GH6324/v2rayA_SH/main/install.sh)
```

-----

## 🎮 使用菜单

运行脚本后，您将看到如下交互式管理面板：

```text
==============================================
     Xray-core + v2rayA 管理脚本 (BugFixed)   
==============================================
 系统架构: x86_64 (systemd)
 Xray 版本: 1.8.4
 v2rayA版本: 2.2.4
----------------------------------------------
  1. 安装 / 重置 (所有数据)  <-- 全新安装或重装
  2. 更新 Xray-Core         <-- 仅升级内核 (保留配置)
  3. 更新 v2rayA            <-- 仅升级面板 (保留配置)
  4. 一键更新所有            <-- 升级全部组件
  0. 退出
----------------------------------------------
```

-----

## 📂 文件路径说明

为了方便高级用户维护，以下是关键文件的安装位置：

| 组件 | 文件类型 | 路径 |
| :--- | :--- | :--- |
| **Xray** | 二进制文件 | `/usr/local/bin/xray` |
| **Xray** | 资源文件 (GeoIP/GeoSite) | `/usr/local/share/xray/` |
| **v2rayA** | 二进制文件 | `/usr/local/bin/v2raya` |
| **v2rayA** | **配置文件目录** | `/usr/local/etc/v2raya/` |
| **Log** | 日志文件 | `/var/log/v2raya.log` |

-----

## ❓ 常见问题 (FAQ)

#### Q1: 安装完成后无法访问 2017 端口？

  * **检查云服务商安全组**：如果你使用的是阿里云、腾讯云、AWS 等，请务必在网页控制台的“安全组”或“防火墙”设置中放行 **TCP 2017** 端口。
  * **检查服务状态**：
    ```bash
    systemctl status v2raya
    # 或者
    journalctl -u v2raya -f
    ```

#### Q2: 为什么下载速度有时很慢？

脚本默认使用了 `gh-proxy.com` 进行加速。如果此时该代理服务繁忙，可能会导致速度波动。脚本内置了超时检测，如果长时间卡住，建议 `Ctrl+C` 中止后重新运行。

#### Q3: 如何卸载？

运行以下命令即可彻底清理：

```bash
systemctl stop v2raya
systemctl disable v2raya
rm -rf /usr/local/bin/xray /usr/local/bin/v2raya /usr/local/share/xray /usr/local/etc/v2raya /etc/systemd/system/v2raya.service
systemctl daemon-reload
echo "卸载完成"
```

-----

## 📜 免责声明

  * 本脚本仅用于技术研究和服务器管理，请勿用于非法用途。
  * 使用本脚本造成的任何数据丢失或系统问题，作者不承担责任。建议在生产环境使用前备份数据。

-----