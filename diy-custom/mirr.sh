#!/bin/bash

# 镜像替换脚本 v2.2 (精简版)
# 用途：将 OpenWrt 的 distfeeds 软件源替换为国内镜像

NEW_MIRROR="https://dl-esa-cn-1-immortalwrt.3284123.xyz"

OLD_DOMAINS=(
    "https://downloads.immortalwrt.org"
    "https://mirrors.vsean.net/openwrt"
    "https://downloads.openwrt.org"
    "https://archive.openwrt.org"
)

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "错误：此脚本需要 root 权限，请使用 sudo 运行。"
    exit 1
fi

# 检测包管理器并定位 distfeeds 配置文件
if command -v opkg &>/dev/null && [[ -f /etc/opkg/distfeeds.conf ]]; then
    TARGET_FILE="/etc/opkg/distfeeds.conf"
    PKG_CMD="opkg"
elif command -v apk &>/dev/null && [[ -f /etc/apk/repositories.d/distfeeds.list ]]; then
    TARGET_FILE="/etc/apk/repositories.d/distfeeds.list"
    PKG_CMD="apk"
else
    echo "错误：未找到 opkg 或 apk 的 distfeeds 配置文件。"
    exit 2
fi

echo "检测到 ${PKG_CMD}，目标文件：${TARGET_FILE}"

# 构建 sed 替换表达式
SED_EXPR=""
for old in "${OLD_DOMAINS[@]}"; do
    old_escaped=$(printf '%s\n' "$old" | sed 's/[][\/&$*.^|]/\\&/g')
    new_escaped=$(printf '%s\n' "$NEW_MIRROR" | sed 's/[\/&]/\\&/g')
    SED_EXPR+="s|$old_escaped|$new_escaped|g;"
done
SED_EXPR=${SED_EXPR%;}

# 执行替换并备份
if sed -i.bak "$SED_EXPR" "$TARGET_FILE"; then
    echo "成功：已替换为镜像地址，备份文件：${TARGET_FILE}.bak"
else
    echo "错误：替换失败，请检查权限或磁盘空间。"
    exit 3
fi

echo ""
echo "请运行以下命令更新软件包列表："
echo "  ${PKG_CMD} update"