#!/bin/bash

# =========================================================
# Xray-core + v2rayA 管理脚本 (Bug修复版)
# =========================================================

# -------------------------------------------------------------
# 全局配置
# -------------------------------------------------------------
GH_PROXY="https://gh-proxy.com/"

# 兜底版本配置 (当无法连接 GitHub API 时使用)
FALLBACK_XRAY_VER="v25.1.1"
FALLBACK_V2RAYA_VER="v2.2.6"

# 路径定义
XRAY_BIN_PATH="/usr/local/bin/xray"
XRAY_ASSET_PATH="/usr/local/share/xray"
V2RAYA_BIN_PATH="/usr/local/bin/v2raya"
V2RAYA_CONF_PATH="/usr/local/etc/v2raya"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# -------------------------------------------------------------
# 0. 基础环境检测与准备
# -------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

check_arch() {
    ARCH=$(uname -m)
    XRAY_ARCH=""
    V2RAYA_ARCH=""

    if [[ $ARCH == "x86_64" ]]; then
        XRAY_ARCH="64"
        V2RAYA_ARCH="x64"
    elif [[ $ARCH == "aarch64" ]]; then
        XRAY_ARCH="arm64-v8a"
        V2RAYA_ARCH="arm64"
    else
        echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
        exit 1
    fi
}

check_init() {
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif [ -f /sbin/openrc-run ]; then
        INIT_SYSTEM="openrc"
    else
        INIT_SYSTEM="unknown"
    fi
}

install_deps() {
    # 日志输出到 stderr (>&2)，防止污染返回值
    echo -e "${YELLOW}正在检查必要依赖...${PLAIN}" >&2
    if [[ -f /etc/debian_version ]]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl wget unzip ca-certificates >/dev/null 2>&1
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y curl wget unzip ca-certificates >/dev/null 2>&1
    elif [[ -f /etc/alpine-release ]]; then
        apk add curl wget unzip ca-certificates >/dev/null 2>&1
    fi
}

# -------------------------------------------------------------
# 核心逻辑：获取版本 (关键修复: 日志输出到 >&2)
# -------------------------------------------------------------
get_latest_release() {
    local repo=$1
    local fallback=$2
    local name=$3
    
    # 关键修改：所有提示信息输出到 >&2 (标准错误)，不进入变量
    echo -e "正在查询 $name 最新版本..." >&2
    
    # 尝试直连 API (设置 3 秒超时，如果失败立即放弃)
    # 注意：gh-proxy 通常不支持代理 API JSON，所以这里尝试直连或直接失败
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local json=$(curl -s --max-time 3 "$api_url")
    local ver=$(echo "$json" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
    
    if [[ -z "$ver" ]]; then
        echo -e "${RED}API 连接超时或受限，切换使用内置兜底版本: $fallback${PLAIN}" >&2
        echo "$fallback" # 只有这个会进入变量
    else
        echo -e "$name 最新版本: ${GREEN}$ver${PLAIN}" >&2
        echo "$ver" # 只有这个会进入变量
    fi
}

# -------------------------------------------------------------
# 核心逻辑：获取本地已安装版本
# -------------------------------------------------------------
get_local_version() {
    if [[ -f "$XRAY_BIN_PATH" ]]; then
        LOCAL_XRAY_VER=$($XRAY_BIN_PATH version | head -n 1 | awk '{print $2}')
    else
        LOCAL_XRAY_VER="未安装"
    fi

    if [[ -f "$V2RAYA_BIN_PATH" ]]; then
        LOCAL_V2RAYA_VER=$($V2RAYA_BIN_PATH --version | head -n 1 | awk '{print $2}')
    else
        LOCAL_V2RAYA_VER="未安装"
    fi
}

# -------------------------------------------------------------
# 核心逻辑：安装/更新 Xray
# -------------------------------------------------------------
install_xray() {
    local target_ver=$1
    echo -e "${YELLOW}=== 开始部署 Xray-Core ($target_ver) ===${PLAIN}"

    # 停止服务
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then systemctl stop v2raya xray >/dev/null 2>&1; fi
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then rc-service v2raya stop >/dev/null 2>&1; fi

    # 下载
    local dl_url="${GH_PROXY}https://github.com/XTLS/Xray-core/releases/download/${target_ver}/Xray-linux-${XRAY_ARCH}.zip"
    echo -e "下载地址: $dl_url"
    wget -q --show-progress -O /tmp/xray.zip "$dl_url"

    # 检查下载是否成功（检查文件大小是否合理，防止下载了报错页面）
    if [[ $? -ne 0 ]] || [[ ! -s /tmp/xray.zip ]] || [[ $(stat -c%s /tmp/xray.zip) -lt 10000 ]]; then
        echo -e "${RED}下载失败或文件损坏，尝试使用兜底版本...${PLAIN}"
        dl_url="${GH_PROXY}https://github.com/XTLS/Xray-core/releases/download/${FALLBACK_XRAY_VER}/Xray-linux-${XRAY_ARCH}.zip"
        echo -e "兜底下载地址: $dl_url"
        wget -q --show-progress -O /tmp/xray.zip "$dl_url"
        
        if [[ $? -ne 0 ]]; then echo -e "${RED}严重错误：Xray 下载失败。${PLAIN}"; return 1; fi
    fi

    # 解压部署
    mkdir -p /tmp/xray_install
    unzip -o /tmp/xray.zip -d /tmp/xray_install >/dev/null 2>&1
    
    if [[ ! -f /tmp/xray_install/xray ]]; then
        echo -e "${RED}错误：解压失败，压缩包可能已损坏。${PLAIN}"
        rm -rf /tmp/xray.zip
        return 1
    fi

    mv -f /tmp/xray_install/xray "$XRAY_BIN_PATH"
    chmod +x "$XRAY_BIN_PATH"
    
    mkdir -p "$XRAY_ASSET_PATH"
    mv -f /tmp/xray_install/*.dat "$XRAY_ASSET_PATH/"
    
    rm -rf /tmp/xray.zip /tmp/xray_install
    echo -e "${GREEN}Xray-Core 部署完成。${PLAIN}"
}

# -------------------------------------------------------------
# 核心逻辑：安装/更新 v2rayA
# -------------------------------------------------------------
install_v2raya() {
    local target_ver=$1
    echo -e "${YELLOW}=== 开始部署 v2rayA ($target_ver) ===${PLAIN}"

    if [[ "$INIT_SYSTEM" == "systemd" ]]; then systemctl stop v2raya >/dev/null 2>&1; fi
    
    # 构建下载链接
    # 优先尝试标准命名
    local v_num=${target_ver#v} # 去掉v
    local dl_url="${GH_PROXY}https://github.com/v2rayA/v2rayA/releases/download/${target_ver}/v2raya_linux_${V2RAYA_ARCH}_${v_num}"
    
    echo -e "下载地址: $dl_url"
    wget -q --show-progress -O "$V2RAYA_BIN_PATH" "$dl_url"

    # 验证下载 (文件小于 1MB 视为失败，v2raya 通常 20MB+)
    if [[ $? -ne 0 ]] || [[ ! -s "$V2RAYA_BIN_PATH" ]] || [[ $(stat -c%s "$V2RAYA_BIN_PATH") -lt 1000000 ]]; then
        echo -e "${YELLOW}标准命名下载失败，尝试带 v 的文件名...${PLAIN}"
        dl_url="${GH_PROXY}https://github.com/v2rayA/v2rayA/releases/download/${target_ver}/v2raya_linux_${V2RAYA_ARCH}_${target_ver}"
        wget -q --show-progress -O "$V2RAYA_BIN_PATH" "$dl_url"
        
        if [[ $? -ne 0 ]] || [[ $(stat -c%s "$V2RAYA_BIN_PATH") -lt 1000000 ]]; then
            echo -e "${RED}当前版本下载失败，回退到稳定兜底版本 ${FALLBACK_V2RAYA_VER}...${PLAIN}"
            local fallback_num=${FALLBACK_V2RAYA_VER#v}
            dl_url="${GH_PROXY}https://github.com/v2rayA/v2rayA/releases/download/${FALLBACK_V2RAYA_VER}/v2raya_linux_${V2RAYA_ARCH}_${fallback_num}"
            wget -q --show-progress -O "$V2RAYA_BIN_PATH" "$dl_url"
            
            if [[ $? -ne 0 ]]; then echo -e "${RED}严重错误：v2rayA 下载失败。${PLAIN}"; return 1; fi
        fi
    fi

    chmod +x "$V2RAYA_BIN_PATH"
    echo -e "${GREEN}v2rayA 部署完成。${PLAIN}"
}

# -------------------------------------------------------------
# 服务配置
# -------------------------------------------------------------
config_system() {
    echo -e "${YELLOW}配置系统服务...${PLAIN}" >&2
    mkdir -p "$V2RAYA_CONF_PATH"

    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        cat > /etc/systemd/system/v2raya.service <<EOF
[Unit]
Description=v2rayA: A web GUI client of Project V
Documentation=https://v2raya.org
After=network.target nss-lookup.target iptables.service ip6tables.service nftables.service
Wants=network.target

[Service]
Environment="V2RAYA_CONFIG=$V2RAYA_CONF_PATH"
Environment="V2RAYA_LOG_FILE=/var/log/v2raya.log"
Environment="XRAY_LOCATION_ASSET=$XRAY_ASSET_PATH"
Type=simple
User=root
LimitNPROC=500
LimitNOFILE=1000000
ExecStart=$V2RAYA_BIN_PATH
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable v2raya >/dev/null 2>&1
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
         cat > /etc/init.d/v2raya <<EOF
#!/sbin/openrc-run
name="v2rayA"
description="A web GUI client of Project V"
command="$V2RAYA_BIN_PATH"
error_log="/var/log/v2raya.error.log"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background="yes"
rc_ulimit="-n 30000"
rc_cgroup_cleanup="yes"
depend() { need net; after net; }
start_pre() {
    export V2RAYA_CONFIG="$V2RAYA_CONF_PATH"
    export XRAY_LOCATION_ASSET="$XRAY_ASSET_PATH"
}
EOF
        chmod +x /etc/init.d/v2raya
        rc-update add v2raya default >/dev/null 2>&1
    fi
    
    # 防火墙
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then ufw allow 2017/tcp >/dev/null; fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port=2017/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        fi
    fi
}

restart_service() {
    echo -e "${YELLOW}正在重启服务...${PLAIN}"
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl restart v2raya
        echo -e "${GREEN}服务已重启。${PLAIN}"
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        rc-service v2raya restart
        echo -e "${GREEN}服务已重启。${PLAIN}"
    else
        echo -e "${RED}请手动重启 v2raya${PLAIN}"
    fi
}

# -------------------------------------------------------------
# 菜单逻辑
# -------------------------------------------------------------
menu_install() {
    LATEST_XRAY=$(get_latest_release "XTLS/Xray-core" "$FALLBACK_XRAY_VER" "Xray-Core")
    LATEST_V2RAYA=$(get_latest_release "v2rayA/v2rayA" "$FALLBACK_V2RAYA_VER" "v2rayA")
    
    install_xray "$LATEST_XRAY"
    install_v2raya "$LATEST_V2RAYA"
    config_system
    restart_service
    
    # 获取IP
    PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org)
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(hostname -I | awk '{print $1}')
    echo -e "\n${GREEN}安装完成!${PLAIN} 请访问: http://${PUBLIC_IP}:2017"
}

menu_update_xray() {
    get_local_version
    echo -e "当前 Xray 版本: ${SKYBLUE}$LOCAL_XRAY_VER${PLAIN}"
    LATEST_XRAY=$(get_latest_release "XTLS/Xray-core" "$FALLBACK_XRAY_VER" "Xray-Core")
    
    if [[ "$LOCAL_XRAY_VER" == "$LATEST_XRAY" ]] || [[ "v$LOCAL_XRAY_VER" == "$LATEST_XRAY" ]]; then
        echo -e "${GREEN}当前已是最新版本，无需更新。${PLAIN}"
        read -p "是否强制覆盖安装? [y/N]: " force
        if [[ "$force" != "y" ]]; then return; fi
    fi
    
    install_xray "$LATEST_XRAY"
    restart_service
}

menu_update_v2raya() {
    get_local_version
    echo -e "当前 v2rayA 版本: ${SKYBLUE}$LOCAL_V2RAYA_VER${PLAIN}"
    LATEST_V2RAYA=$(get_latest_release "v2rayA/v2rayA" "$FALLBACK_V2RAYA_VER" "v2rayA")
    
    if [[ "$LOCAL_V2RAYA_VER" == "$LATEST_V2RAYA" ]] || [[ "v$LOCAL_V2RAYA_VER" == "$LATEST_V2RAYA" ]]; then
        echo -e "${GREEN}当前已是最新版本，无需更新。${PLAIN}"
        read -p "是否强制覆盖安装? [y/N]: " force
        if [[ "$force" != "y" ]]; then return; fi
    fi
    
    install_v2raya "$LATEST_V2RAYA"
    restart_service
}

menu_update_all() {
    menu_update_xray
    menu_update_v2raya
}

# -------------------------------------------------------------
# 主入口
# -------------------------------------------------------------
check_root
check_arch
check_init
install_deps

clear
echo -e "${SKYBLUE}==============================================${PLAIN}"
echo -e "${SKYBLUE}     Xray-core + v2rayA 管理脚本 (BugFixed)   ${PLAIN}"
echo -e "${SKYBLUE}==============================================${PLAIN}"
get_local_version
echo -e " 系统架构: ${YELLOW}$ARCH ($INIT_SYSTEM)${PLAIN}"
echo -e " Xray 版本: ${YELLOW}$LOCAL_XRAY_VER${PLAIN}"
echo -e " v2rayA版本: ${YELLOW}$LOCAL_V2RAYA_VER${PLAIN}"
echo -e "----------------------------------------------"
echo -e "  1. 安装 / 重置 (所有数据)"
echo -e "  2. 更新 Xray-Core"
echo -e "  3. 更新 v2rayA"
echo -e "  4. 一键更新所有"
echo -e "  0. 退出"
echo -e "----------------------------------------------"
read -p " 请输入选择 [0-4]: " choice

case $choice in
    1) menu_install ;;
    2) menu_update_xray ;;
    3) menu_update_v2raya ;;
    4) menu_update_all ;;
    0) exit 0 ;;
    *) echo -e "${RED}无效选择${PLAIN}" && exit 1 ;;
esac