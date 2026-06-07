#!/bin/sh
# 该脚本为immortalwrt首次启动时 运行的脚本 即 /etc/uci-defaults/99-custom.sh 也就是说该文件在路由器内 重启后消失 只运行一次
# 设置默认防火墙规则，方便虚拟机首次访问 WebUI
LOGFILE="/etc/config/uci-defaults-log.txt"
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件是否存在
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
else
   # 读取pppoe信息(由build.sh写入)
   . "$SETTINGS_FILE"
fi
# 设置子网掩码 
uci set network.lan.netmask='255.255.255.0'
# 设置路由器管理后台地址
IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
if [ -f "$IP_VALUE_FILE" ]; then
    CUSTOM_IP=$(cat "$IP_VALUE_FILE")
    # 设置路由器的管理后台地址
    uci set network.lan.ipaddr=$CUSTOM_IP
    echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
fi


# 判断是否启用 PPPoE
echo "print enable_pppoe value=== $enable_pppoe" >> $LOGFILE
if [ "$enable_pppoe" = "yes" ]; then
    echo "PPPoE is enabled at $(date)" >> $LOGFILE
    # 设置拨号信息
    uci set network.wan.proto='pppoe'                
    uci set network.wan.username=$pppoe_account     
    uci set network.wan.password=$pppoe_password     
    uci set network.wan.peerdns='1'                  
    uci set network.wan.auto='1' 
    echo "PPPoE configuration completed successfully." >> $LOGFILE
else
    echo "PPPoE is not enabled. Skipping configuration." >> $LOGFILE
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall
    # 追加新的 zone + forwarding 配置
    cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by wukongdaily"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

#!/bin/sh

#!/bin/sh

# Openssh
# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOGFILE"
}

# 检查软件包是否已安装（支持 apk 和 opkg）
is_pkg_installed() {
    pkg="$1"
    if command -v apk >/dev/null 2>&1; then
        apk list --installed 2>/dev/null | grep -q "^${pkg}-" || apk list --installed 2>/dev/null | grep -q "^${pkg}$"
        return $?
    elif command -v opkg >/dev/null 2>&1; then
        opkg list-installed 2>/dev/null | grep -q "^${pkg} -"
        return $?
    else
        return 1
    fi
}

log "开始检测 OpenSSH 环境"

# 条件：安装了 openssh-server 或存在 /etc/ssh 目录
if is_pkg_installed "openssh-server" || [ -d "/etc/ssh" ]; then
    log "检测到 openssh-server 或 /etc/ssh 目录，开始切换至 OpenSSH"

    # 0. 禁用并停止 dropbear
    if [ -x "/etc/init.d/dropbear" ]; then
        log "禁用 dropbear"
        /etc/init.d/dropbear disable >> "$LOGFILE" 2>&1
        /etc/init.d/dropbear stop >> "$LOGFILE" 2>&1
    else
        log "dropbear 服务脚本不存在，跳过"
    fi

    # 1. 修改 sshd_config 允许 root 登录
    SSH_CONFIG="/etc/ssh/sshd_config"
    if [ -f "$SSH_CONFIG" ]; then
        log "配置 sshd 允许 root 登录"
        sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' "$SSH_CONFIG"
        sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
    else
        log "错误：$SSH_CONFIG 不存在"
        exit 1
    fi

    # 2. 创建 /root/.ssh/ 目录
    mkdir -p /root/.ssh/ >> "$LOGFILE" 2>&1

    # 3. 复制 dropbear 密钥到 /root/.ssh/
    if [ -d "/etc/dropbear" ]; then
        log "复制 /etc/dropbear/* 到 /root/.ssh/"
        cp -f /etc/dropbear/* /root/.ssh/ >> "$LOGFILE" 2>&1
    else
        log "警告：/etc/dropbear 目录不存在，无密钥可复制"
    fi

    # 4. 启用 sshd
    if [ -x "/etc/init.d/sshd" ]; then
        log "启用 sshd"
        /etc/init.d/sshd enable >> "$LOGFILE" 2>&1
    else
        log "错误：/etc/init.d/sshd 不存在"
        exit 1
    fi

    # 5. 重启 sshd
    log "重启 sshd"
    /etc/init.d/sshd restart >> "$LOGFILE" 2>&1

    log "切换完成，请确保防火墙放行 22 端口"
else
    log "未检测到 openssh-server 或 /etc/ssh 目录，脚本退出"
    exit 0
fi

exit 0
