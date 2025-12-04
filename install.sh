#!/bin/bash

# =========================================================
# Xray-core + v2rayA 管理脚本
# =========================================================

# -------------------------------------------------------------
# 全局配置
# -------------------------------------------------------------
GH_PROXY="https://gh-proxy.com/"

# 兜底版本
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
BOLD='\033[1m'

# -------------------------------------------------------------
# 0. 基础环境检测
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
    if [[ -f /etc/debian_version ]]; then
        if ! command -v curl >/dev/null 2>&1; then apt-get update -y && apt-get install -y curl wget unzip; fi
    elif [[ -f /etc/redhat-release ]]; then
        if ! command -v curl >/dev/null 2>&1; then yum install -y curl wget unzip; fi
    elif [[ -f /etc/alpine-release ]]; then
        if ! command -v curl >/dev/null 2>&1; then apk add curl wget unzip ca-certificates; fi
    fi
}

# -------------------------------------------------------------
# 辅助逻辑：端口获取与验证
# -------------------------------------------------------------
get_current_port() {
    # 尝试从 systemd 文件中读取端口
    if [[ -f /etc/systemd/system/v2raya.service ]]; then
        CURRENT_PORT=$(grep "V2RAYA_ADDRESS" /etc/systemd/system/v2raya.service | awk -F: '{print $2}' | tr -d '"')
    elif [[ -f /etc/init.d/v2raya ]]; then
        CURRENT_PORT=$(grep "V2RAYA_ADDRESS" /etc/init.d/v2raya | awk -F: '{print $2}' | tr -d '"')
    fi
    
    # 如果没找到，默认是 2017
    if [[ -z "$CURRENT_PORT" ]]; then
        CURRENT_PORT="2017 (默认)"
    fi
}

validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    else
        return 0
    fi
}

# -------------------------------------------------------------
# 核心逻辑：获取版本
# -------------------------------------------------------------
get_latest_release_silent() {
    local repo=$1
    local fallback=$2
    local ver=""
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local json=$(curl -s --max-time 2 "$api_url")
    ver=$(echo "$json" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
    if [[ -z "$ver" ]]; then
        local redirect_url=$(curl -sL -I -o /dev/null -w %{url_effective} --max-time 3 "https://github.com/$repo/releases/latest")
        ver=$(basename "$redirect_url")
        if [[ "$ver" == "latest" ]] || [[ "$ver" == "releases" ]]; then ver=""; fi
    fi
    if [[ -z "$ver" ]]; then echo "$fallback"; else echo "$ver"; fi
}

get_local_version() {
    if [[ -f "$XRAY_BIN_PATH" ]]; then
        LOCAL_XRAY_VER=$($XRAY_BIN_PATH version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
        if [[ -z "$LOCAL_XRAY_VER" ]]; then LOCAL_XRAY_VER="未知"; fi
    else
        LOCAL_XRAY_VER="未安装"
    fi

    if [[ -f "$V2RAYA_BIN_PATH" ]]; then
        LOCAL_V2RAYA_VER=$($V2RAYA_BIN_PATH --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
        if [[ -z "$LOCAL_V2RAYA_VER" ]]; then LOCAL_V2RAYA_VER="未知"; fi
    else
        LOCAL_V2RAYA_VER="未安装"
    fi
}

# -------------------------------------------------------------
# 安装与更新逻辑
# -------------------------------------------------------------
install_xray() {
    local target_ver=$1
    echo -e "${YELLOW}>>> 开始部署 Xray-Core ($target_ver) ...${PLAIN}"
    
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then systemctl stop v2raya xray >/dev/null 2>&1; fi
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then rc-service v2raya stop >/dev/null 2>&1; fi

    local dl_url="${GH_PROXY}https://github.com/XTLS/Xray-core/releases/download/${target_ver}/Xray-linux-${XRAY_ARCH}.zip"
    echo -e "正在下载: $dl_url"
    wget -q --show-progress -O /tmp/xray.zip "$dl_url"

    if [[ $? -ne 0 ]] || [[ ! -s /tmp/xray.zip ]]; then
        echo -e "${RED}下载失败，尝试兜底版本...${PLAIN}"
        dl_url="${GH_PROXY}https://github.com/XTLS/Xray-core/releases/download/${FALLBACK_XRAY_VER}/Xray-linux-${XRAY_ARCH}.zip"
        wget -q --show-progress -O /tmp/xray.zip "$dl_url"
        if [[ $? -ne 0 ]]; then echo -e "${RED}错误: Xray 下载失败${PLAIN}"; return 1; fi
    fi

    mkdir -p /tmp/xray_install
    unzip -o /tmp/xray.zip -d /tmp/xray_install >/dev/null 2>&1
    mv -f /tmp/xray_install/xray "$XRAY_BIN_PATH"
    chmod +x "$XRAY_BIN_PATH"
    mkdir -p "$XRAY_ASSET_PATH"
    mv -f /tmp/xray_install/*.dat "$XRAY_ASSET_PATH/"
    rm -rf /tmp/xray.zip /tmp/xray_install
    echo -e "${GREEN}Xray 部署完成。${PLAIN}"
}

install_v2raya() {
    local target_ver=$1
    echo -e "${YELLOW}>>> 开始部署 v2rayA ($target_ver) ...${PLAIN}"
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then systemctl stop v2raya >/dev/null 2>&1; fi

    local v_num=${target_ver#v}
    local dl_url="${GH_PROXY}https://github.com/v2rayA/v2rayA/releases/download/${target_ver}/v2raya_linux_${V2RAYA_ARCH}_${target_ver}"
    echo -e "正在下载: $dl_url"
    wget -q --show-progress -O "$V2RAYA_BIN_PATH" "$dl_url"

    if [[ $? -ne 0 ]] || [[ ! -s "$V2RAYA_BIN_PATH" ]]; then
        dl_url="${GH_PROXY}https://github.com/v2rayA/v2rayA/releases/download/${target_ver}/v2raya_linux_${V2RAYA_ARCH}_${v_num}"
        wget -q --show-progress -O "$V2RAYA_BIN_PATH" "$dl_url"
        if [[ $? -ne 0 ]]; then
             dl_url="${GH_PROXY}https://github.com/v2rayA/v2rayA/releases/download/${FALLBACK_V2RAYA_VER}/v2raya_linux_${V2RAYA_ARCH}_${FALLBACK_V2RAYA_VER#v}"
             wget -q --show-progress -O "$V2RAYA_BIN_PATH" "$dl_url"
             if [[ $? -ne 0 ]]; then echo -e "${RED}错误: v2rayA 下载失败${PLAIN}"; return 1; fi
        fi
    fi
    chmod +x "$V2RAYA_BIN_PATH"
    echo -e "${GREEN}v2rayA 部署完成。${PLAIN}"
}

config_system() {
    local custom_port=$1
    echo -e "${YELLOW}>>> 配置系统服务 (端口: $custom_port) ...${PLAIN}"
    mkdir -p "$V2RAYA_CONF_PATH"

    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        cat > /etc/systemd/system/v2raya.service <<EOF
[Unit]
Description=v2rayA
Documentation=https://v2raya.org
After=network.target nss-lookup.target iptables.service ip6tables.service nftables.service
Wants=network.target

[Service]
Environment="V2RAYA_CONFIG=$V2RAYA_CONF_PATH"
Environment="V2RAYA_LOG_FILE=/var/log/v2raya.log"
Environment="V2RAYA_ADDRESS=0.0.0.0:$custom_port"
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
    export V2RAYA_ADDRESS="0.0.0.0:$custom_port"
}
EOF
        chmod +x /etc/init.d/v2raya
        rc-update add v2raya default >/dev/null 2>&1
    fi
    
    # 自动放行端口
    echo -e "${YELLOW}正在尝试放行端口 $custom_port ...${PLAIN}"
    if command -v ufw >/dev/null 2>&1; then ufw allow $custom_port/tcp >/dev/null; fi
    if command -v firewall-cmd >/dev/null 2>&1; then 
        firewall-cmd --permanent --add-port=$custom_port/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport $custom_port -j ACCEPT >/dev/null 2>&1
    fi
}

restart_service() {
    echo -e "${YELLOW}正在重启服务...${PLAIN}"
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then systemctl restart v2raya; fi
    if [[ "$INIT_SYSTEM" == "openrc" ]]; then rc-service v2raya restart; fi
    echo -e "${GREEN}服务已重启。${PLAIN}"
}

# -------------------------------------------------------------
# 卸载功能
# -------------------------------------------------------------
uninstall_app() {
    echo -e "${RED}⚠️  警告: 此操作将删除 Xray-core 和 v2rayA 以及相关配置文件。${PLAIN}"
    read -p "确定要继续吗? [y/N]: " confirm
    if [[ "$confirm" != "y" ]]; then echo "操作已取消"; return; fi

    echo -e "${YELLOW}正在停止并移除服务...${PLAIN}"
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl stop v2raya >/dev/null 2>&1
        systemctl disable v2raya >/dev/null 2>&1
        rm -f /etc/systemd/system/v2raya.service
        systemctl daemon-reload
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        rc-service v2raya stop >/dev/null 2>&1
        rc-update del v2raya >/dev/null 2>&1
        rm -f /etc/init.d/v2raya
    fi
    
    # 杀进程
    pkill -9 v2raya >/dev/null 2>&1
    pkill -9 xray >/dev/null 2>&1

    echo -e "${YELLOW}正在删除文件...${PLAIN}"
    rm -rf "$XRAY_BIN_PATH"
    rm -rf "$XRAY_ASSET_PATH"
    rm -rf "$V2RAYA_BIN_PATH"
    rm -rf "$V2RAYA_CONF_PATH"
    rm -f /var/log/v2raya.log /var/log/v2raya.error.log

    echo -e "${GREEN}卸载完成！系统已清理干净。${PLAIN}"
    echo -e "注意: 防火墙端口可能需要您手动关闭。"
    exit 0
}

# -------------------------------------------------------------
# 状态显示与菜单
# -------------------------------------------------------------
show_status_and_menu() {
    clear
    echo -e "${SKYBLUE}正在联网检查最新版本，请稍候...${PLAIN}"
    
    get_local_version
    get_current_port
    REMOTE_XRAY=$(get_latest_release_silent "XTLS/Xray-core" "$FALLBACK_XRAY_VER")
    REMOTE_V2RAYA=$(get_latest_release_silent "v2rayA/v2rayA" "$FALLBACK_V2RAYA_VER")

    clear
    echo -e "${SKYBLUE}====================================================${PLAIN}"
    echo -e "${BOLD}      Xray-core + v2rayA 管理脚本        ${PLAIN}"
    echo -e "${SKYBLUE}====================================================${PLAIN}"
    
    echo -e " 系统架构: ${YELLOW}$ARCH${PLAIN}  |  Init: ${YELLOW}$INIT_SYSTEM${PLAIN}  |  端口: ${YELLOW}$CURRENT_PORT${PLAIN}"
    echo -e "----------------------------------------------------"
    printf "${BOLD}%-10s %-16s %-16s %-10s${PLAIN}\n" "组件" "本地版本" "最新版本" "状态"
    echo -e "----------------------------------------------------"

    # Xray 状态
    if [[ "$LOCAL_XRAY_VER" == "未安装" ]]; then
        X_STATUS="${RED}[未安装]${PLAIN}"
    elif [[ "$REMOTE_XRAY" == *"$LOCAL_XRAY_VER"* ]]; then
        X_STATUS="${GREEN}[最新]${PLAIN}"
    else
        X_STATUS="${YELLOW}[可更新]${PLAIN}"
    fi
    printf "%-10s %-16s %-16s %-10b\n" "Xray" "$LOCAL_XRAY_VER" "$REMOTE_XRAY" "$X_STATUS"

    # v2rayA 状态
    if [[ "$LOCAL_V2RAYA_VER" == "未安装" ]]; then
        V_STATUS="${RED}[未安装]${PLAIN}"
    elif [[ "$REMOTE_V2RAYA" == *"$LOCAL_V2RAYA_VER"* ]]; then
        V_STATUS="${GREEN}[最新]${PLAIN}"
    else
        V_STATUS="${YELLOW}[可更新]${PLAIN}"
    fi
    printf "%-10s %-16s %-16s %-10b\n" "v2rayA" "$LOCAL_V2RAYA_VER" "$REMOTE_V2RAYA" "$V_STATUS"
    
    echo -e "----------------------------------------------------"
    echo -e "  1. 安装 / 重置 (支持自定义端口)"
    echo -e "  2. 更新 Xray-Core"
    echo -e "  3. 更新 v2rayA"
    echo -e "  4. 一键更新所有 (保持现有端口配置)"
    echo -e "  5. 修改监听端口 (不重装)"
    echo -e "  6. 卸载 Xray 和 v2rayA"
    echo -e "  0. 退出"
    echo -e "----------------------------------------------------"
    
    read -p " 请输入选择 [0-6]: " choice
    case $choice in
        1) 
            read -p "请输入 v2rayA 监听端口 [默认2017]: " input_port
            if [[ -z "$input_port" ]]; then input_port="2017"; fi
            if ! validate_port "$input_port"; then echo -e "${RED}无效端口，请输入 1-65535${PLAIN}"; exit 1; fi
            
            install_xray "$REMOTE_XRAY"
            install_v2raya "$REMOTE_V2RAYA"
            config_system "$input_port"
            restart_service
            
            # 获取IP提示
            PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org)
            [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(hostname -I | awk '{print $1}')
            echo -e "\n${GREEN}安装完成!${PLAIN} 面板地址: http://${PUBLIC_IP}:${input_port}"
            ;;
        2) 
            install_xray "$REMOTE_XRAY"
            restart_service
            ;;
        3) 
            install_v2raya "$REMOTE_V2RAYA"
            restart_service
            ;;
        4)
            install_xray "$REMOTE_XRAY"
            install_v2raya "$REMOTE_V2RAYA"
            restart_service
            ;;
        5)
            read -p "请输入新的 v2rayA 端口: " new_port
            if ! validate_port "$new_port"; then echo -e "${RED}无效端口${PLAIN}"; exit 1; fi
            config_system "$new_port"
            restart_service
            echo -e "${GREEN}端口已修改为 $new_port${PLAIN}"
            ;;
        6)
            uninstall_app
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择${PLAIN}" && exit 1 ;;
    esac
}

# -------------------------------------------------------------
# 主程序入口
# -------------------------------------------------------------
check_root
check_arch
check_init
install_deps
show_status_and_menu