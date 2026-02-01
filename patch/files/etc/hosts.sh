#!/bin/sh
# -------------------------- 智能更新 Hosts（定时+防重复） --------------------------
set -e  # 遇到错误立即退出，避免继续执行

# ====================== 核心配置区（可根据需求修改）======================
# 基础配置
HOSTS_MARK_START="# ING Hosts Start"
HOSTS_MARK_END="# ING Hosts End"
HOSTS_URL="https://github-hosts.tinsfox.com/hosts"
# HOSTS_URL="https://raw.hellogithub.com/hosts"
HOSTS_FILE="/etc/hosts"
# 备份/对比用文件（用于检测内容是否变动）
LAST_HOSTS_BAK="/tmp/last_ing_hosts.bak"
# 日志文件
LOG_FILE="/tmp/hosts_update.log"
# =========================================================================

# 日志函数（同时输出到终端和日志文件）
log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "${msg}"
    echo "${msg}" >> "${LOG_FILE}"
}

# 第一步：权限检查
log "===== 开始执行 Hosts 更新脚本 ====="
log "[1/5] 检查运行权限..."
if [ "$(id -u)" -ne 0 ]; then
    log "[错误] 请以 root 权限运行此脚本（或加 sudo）"
    exit 1
fi

# 第二步：下载最新 Hosts 到临时文件
log "[2/5] 下载最新公共 Hosts 规则..."
TMP_NEW_HOSTS=$(mktemp)
if ! curl -s -k -L "${HOSTS_URL}" -o "${TMP_NEW_HOSTS}"; then
    log "[错误] 下载 Hosts 失败，请检查网络或 URL 是否有效"
    rm -f "${TMP_NEW_HOSTS}"
    exit 1
fi

# 第三步：对比内容是否变动（无变动则直接退出）
log "[3/5] 检测 Hosts 内容是否变动..."
# 过滤注释和空行后生成MD5（替代diff，兼容OpenWrt）
filter_hosts() {
    grep -vE '^$|^#' "$1" | sort | uniq
}
# 生成过滤后的内容并计算MD5
NEW_HOSTS_MD5=$(filter_hosts "${TMP_NEW_HOSTS}" | md5sum | awk '{print $1}')

# 对比上次备份的MD5（备份不存在则视为首次更新）
if [ -f "${LAST_HOSTS_BAK}" ]; then
    LAST_HOSTS_MD5=$(filter_hosts "${LAST_HOSTS_BAK}" | md5sum | awk '{print $1}')
    if [ "${NEW_HOSTS_MD5}" = "${LAST_HOSTS_MD5}" ]; then
        log "[提示] Hosts 内容无变动，无需更新"
        rm -f "${TMP_NEW_HOSTS}"
        exit 0
    fi
fi

# 第四步：更新系统 Hosts（删除旧块 + 追加新内容）
log "[4/5] 更新系统 Hosts 文件..."
# 删除旧的 ING Hosts 块
sed -i "/${HOSTS_MARK_START}/,/${HOSTS_MARK_END}/d" "${HOSTS_FILE}"
# 追加新的 Hosts 块（直接使用下载的原始内容）
echo -e "\n${HOSTS_MARK_START}" >> "${HOSTS_FILE}"
cat "${TMP_NEW_HOSTS}" >> "${HOSTS_FILE}"
echo -e "\n${HOSTS_MARK_END}" >> "${HOSTS_FILE}"

# 第五步：备份本次内容 + 清理临时文件
log "[5/5] 备份本次 Hosts 内容 + 清理临时文件..."
cp "${TMP_NEW_HOSTS}" "${LAST_HOSTS_BAK}"  # 备份原始内容用于下次对比
rm -f "${TMP_NEW_HOSTS}"

# 刷新 DNS 缓存（兼容不同系统）
log "[完成] 刷新 DNS 缓存..."
if command -v systemd-resolve > /dev/null; then
    systemd-resolve --flush-caches 2>/dev/null
elif command -v service > /dev/null; then
    service dnsmasq restart 2>/dev/null || true
else
    log "[提示] 未检测到 DNS 缓存刷新命令，需手动刷新"
fi

log "[成功] Hosts 智能更新完成！日志文件：${LOG_FILE}"
log "=========================================\n"