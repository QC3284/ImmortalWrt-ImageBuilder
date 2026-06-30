#!/bin/sh

SOURCE_DIR="/mnt/sda2/clashoo"
TARGET_DIR="/etc/clashoo"

# 1. 确保外部存储目录存在
if [ ! -d "$SOURCE_DIR" ]; then
    mkdir -p "$SOURCE_DIR"
    chmod 755 "$SOURCE_DIR"
fi

# 2. 处理目标目录：如果不是指向 SOURCE_DIR 的符号链接，则进行迁移/替换
# 如果 TARGET_DIR 已经是指向 SOURCE_DIR 的符号链接，则跳过
if [ -L "$TARGET_DIR" ]; then
    CURRENT_LINK="$(readlink "$TARGET_DIR")"
    if [ "$CURRENT_LINK" = "$SOURCE_DIR" ]; then
        echo "符号链接已存在且正确，无需操作"
        exit 0
    else
        # 错误的符号链接，删除
        rm -f "$TARGET_DIR"
    fi
fi

# 如果目标存在且不是符号链接（可能是目录或文件）
if [ -e "$TARGET_DIR" ]; then
    if [ -d "$TARGET_DIR" ]; then
        # 目录非空则迁移内容到源目录
        if [ -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
            echo "迁移现有配置到 $SOURCE_DIR ..."
            cp -a "$TARGET_DIR"/. "$SOURCE_DIR/"
        fi
        rm -rf "$TARGET_DIR"
    else
        # 普通文件，直接删除
        rm -f "$TARGET_DIR"
    fi
fi

# 3. 创建符号链接
ln -sf "$SOURCE_DIR" "$TARGET_DIR"

echo "符号链接已创建：$TARGET_DIR -> $SOURCE_DIR"
