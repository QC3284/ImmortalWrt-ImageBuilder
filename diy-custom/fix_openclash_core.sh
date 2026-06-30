#!/bin/bash

# 一键替换 OpenClash 内核更新脚本 (openclash_core.sh)
# 解决 Smart 内核更新失败问题

TARGET="/usr/share/openclash/openclash_core.sh"

# 备份原文件
if [ -f "$TARGET" ]; then
    BACKUP="${TARGET}.bak.$(date +%s)"
    cp "$TARGET" "$BACKUP"
    echo "原脚本已备份至: $BACKUP"
else
    echo "警告: 目标文件 $TARGET 不存在，将创建新文件"
fi

# 写入优化后的脚本内容
cat > "$TARGET" << 'EOF'
#!/bin/bash
. /lib/functions.sh
. /usr/share/openclash/log.sh
. /usr/share/openclash/uci.sh
. /usr/share/openclash/openclash_curl.sh
. /usr/share/openclash/openclash_ps.sh

set_lock() {
   exec 872>"/tmp/lock/openclash_core.lock" 2>/dev/null
   flock -x 872 2>/dev/null
}

del_lock() {
   flock -u 872 2>/dev/null
   rm -rf "/tmp/lock/openclash_core.lock" 2>/dev/null
}

set_lock
inc_job_counter

restart=0
github_address_mod=$(uci_get_config "github_address_mod" || echo 0)
if [ "$github_address_mod" = "0" ] && [ -z "$(echo $2 2>/dev/null |grep -E 'http|one_key_update')" ] && [ -z "$(echo $3 2>/dev/null |grep 'http')" ]; then
   LOG_TIP "If the download fails, try setting the CDN in Overwrite Settings - General Settings - Github Address Modify Options"
fi
if [ -n "$3" ] && [ "$2" = "one_key_update" ]; then
   github_address_mod="$3"
fi
if [ -n "$2" ] && [ "$2" = "one_key_update" ] && [ -z "$3" ]; then
   github_address_mod=0
fi
if [ -n "$2" ] && [ "$2" != "one_key_update" ]; then
   github_address_mod="$2"
fi
CORE_TYPE="$1"
C_CORE_TYPE=$(uci_get_config "core_type")
SMART_ENABLE=$(uci_get_config "smart_enable" || echo 0)
[ "$SMART_ENABLE" -eq 1 ] && CORE_TYPE="Smart"
[ -z "$CORE_TYPE" ] && CORE_TYPE="Meta"
small_flash_memory=$(uci_get_config "small_flash_memory")
CPU_MODEL=$(uci_get_config "core_version")
RELEASE_BRANCH=$(uci_get_config "release_branch" || echo "master")

if [ "$github_address_mod" != "0" ]; then
   /usr/share/openclash/clash_version.sh "$github_address_mod" 2>/dev/null
else
   /usr/share/openclash/clash_version.sh 2>/dev/null
fi
if [ ! -f "/tmp/clash_last_version" ]; then
   LOG_ERROR "【"$CORE_TYPE"】Core Version Check Error, Please Try Again Later..."
   SLOG_CLEAN
   del_lock
   exit 0
fi

if [ "$small_flash_memory" != "1" ]; then
   meta_core_path="/etc/openclash/core/clash_meta"
   mkdir -p /etc/openclash/core
else
   meta_core_path="/tmp/etc/openclash/core/clash_meta"
   mkdir -p /tmp/etc/openclash/core
fi

CORE_CV=$($meta_core_path -v 2>/dev/null |awk -F ' ' '{print $3}' |head -1)
DOWNLOAD_FILE="/tmp/clash_meta.tar.gz"
TMP_FILE="/tmp/clash_meta"
TARGET_CORE_PATH="$meta_core_path"

if [ "$CORE_TYPE" = "Smart" ]; then
   CORE_URL_PATH="$RELEASE_BRANCH/smart"
   CORE_LV=$(sed -n 2p /tmp/clash_last_version 2>/dev/null)
else
   CORE_URL_PATH="$RELEASE_BRANCH/meta"
   CORE_LV=$(sed -n 1p /tmp/clash_last_version 2>/dev/null)
fi

[ "$C_CORE_TYPE" = "$CORE_TYPE" ] || [ -z "$C_CORE_TYPE" ] && restart=1

if [ "$CORE_CV" != "$CORE_LV" ] || [ -z "$CORE_CV" ]; then
   if [ "$CPU_MODEL" != 0 ]; then
      LOG_TIP "【$CORE_TYPE】Core Downloading, Please Try to Download and Upload Manually If Fails"
      if [ "$github_address_mod" != "0" ]; then
         if [ "$github_address_mod" == "https://cdn.jsdelivr.net/" ] || [ "$github_address_mod" == "https://fastly.jsdelivr.net/" ] || [ "$github_address_mod" == "https://testingcf.jsdelivr.net/" ]; then
            DOWNLOAD_URL="${github_address_mod}gh/vernesong/OpenClash@core/${CORE_URL_PATH}/clash-${CPU_MODEL}.tar.gz"
         else
            DOWNLOAD_URL="${github_address_mod}https://raw.githubusercontent.com/vernesong/OpenClash/core/${CORE_URL_PATH}/clash-${CPU_MODEL}.tar.gz"
         fi
      else
         DOWNLOAD_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/${CORE_URL_PATH}/clash-${CPU_MODEL}.tar.gz"
      fi

      retry_count=0
      max_retries=3
      update_success=false

      while [ "$retry_count" -lt "$max_retries" ] && [ "$update_success" != "true" ]; do
         retry_count=$((retry_count + 1))

         rm -rf "$DOWNLOAD_FILE" "/tmp/clash" "$TMP_FILE" >/dev/null 2>&1

         SHOW_DOWNLOAD_PROGRESS=1 DOWNLOAD_FILE_CURL "$DOWNLOAD_URL" "$DOWNLOAD_FILE" "$TARGET_CORE_PATH"
         DOWNLOAD_RESULT=$?

         if [ "$DOWNLOAD_RESULT" -eq 0 ]; then
            gzip -t "$DOWNLOAD_FILE" >/dev/null 2>&1
            if [ "$?" -eq 0 ]; then
               LOG_TIP "【"$CORE_TYPE"】Core Download Successful, Start Update..."
               
               tar -xzf "$DOWNLOAD_FILE" -C /tmp 2>/dev/null
               if [ "$?" -ne 0 ] || [ ! -f "/tmp/clash" ]; then
                  LOG_ERROR "【$retry_count/$max_retries】【"$CORE_TYPE"】Extraction Failed or clash not found"
                  rm -rf "$DOWNLOAD_FILE"
                  sleep 2
                  continue
               fi
               
               chmod 755 "/tmp/clash"
               
               if [ ! -x "/tmp/clash" ]; then
                  LOG_ERROR "【$retry_count/$max_retries】【"$CORE_TYPE"】File is not executable"
                  rm -f "/tmp/clash" "$DOWNLOAD_FILE"
                  sleep 2
                  continue
               fi
               
               size=$(stat -c%s "/tmp/clash" 2>/dev/null)
               if [ -n "$size" ] && [ "$size" -lt 1048576 ]; then
                  LOG_ERROR "【$retry_count/$max_retries】【"$CORE_TYPE"】Core file too small (${size} bytes)"
                  rm -f "/tmp/clash" "$DOWNLOAD_FILE"
                  sleep 2
                  continue
               fi
               
               mv "/tmp/clash" "$TMP_FILE" 2>/dev/null
               if [ "$?" -ne 0 ]; then
                  LOG_ERROR "【$retry_count/$max_retries】【"$CORE_TYPE"】Failed to Move Core to $TMP_FILE"
                  rm -rf "$DOWNLOAD_FILE"
                  sleep 2
                  continue
               fi
               
               chmod 755 "$TMP_FILE"
               if [ ! -x "$TMP_FILE" ]; then
                  LOG_ERROR "【$retry_count/$max_retries】【"$CORE_TYPE"】After move, file not executable"
                  rm -f "$TMP_FILE" "$DOWNLOAD_FILE"
                  sleep 2
                  continue
               fi
               
               mv "$TMP_FILE" "$TARGET_CORE_PATH" 2>/dev/null
               if [ "$?" -eq 0 ]; then
                  LOG_TIP "【"$CORE_TYPE"】Core Update Successful!"
                  SLOG_CLEAN
                  update_success=true
                  restart=1
               else
                  LOG_ERROR "【$retry_count/$max_retries】【"$CORE_TYPE"】Failed to Move Core to $TARGET_CORE_PATH"
                  sleep 2
               fi
               
               rm -rf "$DOWNLOAD_FILE"
            else
               LOG_ERROR "【$retry_count/$max_retries】【"$CORE_TYPE"】Core Download Corrupted (gzip test failed)"
               sleep 2
            fi
         elif [ "$DOWNLOAD_RESULT" -eq 2 ]; then
            LOG_TIP "【"$CORE_TYPE"】Core Has Not Been Updated, Stop Continuing Operation!"
            SLOG_CLEAN
            update_success=true
         else
            LOG_ERROR "【$retry_count/$max_retries】【"$CORE_TYPE"】Core Download Failed (curl result $DOWNLOAD_RESULT)"
            sleep 2
         fi
      done
      
      if [ "$update_success" != "true" ]; then
         LOG_ERROR "【"$CORE_TYPE"】Core Update Failed After $max_retries Attempts!"
         SLOG_CLEAN
      fi
   else
      LOG_WARN "No Compiled Version Selected, Please Select In Update Page And Try Again!"
      SLOG_CLEAN
   fi
else
   LOG_TIP "【"$CORE_TYPE"】Core Has Not Been Updated, Stop Continuing Operation!"
   SLOG_CLEAN
fi

rm -rf "/tmp/clash" "$TMP_FILE" "$DOWNLOAD_FILE" >/dev/null 2>&1
dec_job_counter_and_restart "$restart"
del_lock
EOF

# 设置可执行权限
chmod 755 "$TARGET"
echo "脚本已替换并赋予可执行权限"
echo "请重新运行 OpenClash 内核更新，Smart 内核应该能正常更新"
