#!/bin/sh
# ==============================================================================
# OpenWRT 网络配置一键更新脚本（修复版 v2.6 2026-01-06）
# 功能：更新 Hosts、SmartDNS 规则、dnscrypt-proxy 配置、MosDNS 规则，并重启相关服务
# 更新：增加下载失败时不删除原始文件的功能
# 适用环境：基于 OpenWRT 的路由器（如 R619AC）
# 执行权限：必须 root 用户（无 sudo 提权，非 root 必然权限不足失败）
# ==============================================================================

# -------------------------- 基础配置（可按需调整） --------------------------
SCRIPT_VERSION="v2.6"
TMP_DIR="/tmp/update-config"
GITHUB_PROXY="https://gh-proxy.com/"  # 末尾必须带 /，确保 URL 拼接正确
# GITHUB_PROXY="https://ghfast.top/"  # 末尾必须带 /，确保 URL 拼接正确

# 各组件配置目录
MOSDNS_RULE_DIR="/etc/mosdns/rule"
SMARTDNS_CONF_DIR="/etc/smartdns"
DNSCRYPT_CONF_DIR="/etc/dnscrypt-proxy2"

# curl 通用参数（静默+证书忽略+重定向+超时+重试）
CURL_OPTS="-fsSL -k -L --connect-timeout 15 --max-time 30 --retry 2 --retry-delay 3"

# -------------------------- 工具函数 --------------------------
# 文件下载：修复URL处理，下载失败时不删除原始文件
download_file() {
  local url="$1"
  local dest="$2"
  local desc="$3"
  
  # 打印简短URL（避免过长输出）
  local short_url="${url#https://}"
  short_url="${short_url#http://}"
  short_url="${short_url%%/*}..."
  
  echo "  → 下载：$desc"
  
  # 确保父目录存在
  mkdir -p "$(dirname "$dest")"
  
  # 下载文件
  if curl $CURL_OPTS "$url" -o "$dest"; then
    echo "  ✅ $desc 下载完成"
    return 0
  else
    echo "  ❌ $desc 下载失败"
    return 1
  fi
}

# 安全文件复制：仅当源文件存在且下载成功时才复制
safe_copy_file() {
  local src="$1"
  local dest="$2"
  local desc="$3"
  
  if [ -f "$src" ]; then
    echo "  → 复制：$desc"
    mkdir -p "$(dirname "$dest")"
    cp -f "$src" "$dest"
    return 0
  else
    echo "  ⚠️  跳过复制：$desc（源文件不存在）"
    return 1
  fi
}

# 创建目录
ensure_dir() {
  local dir="$1"
  mkdir -p "$dir"
  echo "  → 创建目录：$dir"
}

# -------------------------- 初始化 --------------------------
echo "  → 请确保当前为 root 用户执行（无 sudo 提权，非 root 会权限不足）"

# 捕获退出信号，清理临时目录
trap 'rm -rf "$TMP_DIR" 2>/dev/null' EXIT INT TERM

# 初始化临时目录
echo "[1/6] 初始化环境..."
rm -rf "$TMP_DIR" 2>/dev/null
mkdir -p "$TMP_DIR"
echo "  ✅ 临时目录：$TMP_DIR"

# 检查 /tmp 空间
TMP_FREE=$(df -m /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
echo "  ✅ /tmp 剩余空间：$TMP_FREE MB"

# 确保目标目录存在
ensure_dir "$SMARTDNS_CONF_DIR/domain-set"
ensure_dir "$SMARTDNS_CONF_DIR/ip-set"
ensure_dir "$SMARTDNS_CONF_DIR/conf.d"
ensure_dir "$DNSCRYPT_CONF_DIR"
ensure_dir "$MOSDNS_RULE_DIR"
echo "  ✅ 所有目标目录准备完成"

# -------------------------- 更新 SmartDNS 规则 --------------------------
echo -e "\n[3/6] 更新 SmartDNS 规则..."

# SmartDNS 规则列表 - 修复：确保每行都有正确的格式
{
echo "${GITHUB_PROXY}raw.githubusercontent.com/leesuncom/update/refs/heads/main/r619ac/etc/smartdns/blacklist-ip.conf|$SMARTDNS_CONF_DIR/blacklist-ip.conf|IP黑名单"
echo "https://www.cloudflare.com/ips-v4/|$SMARTDNS_CONF_DIR/ip-set/cloudflare-ipv4.txt|Cloudflare IPv4列表"
echo "${GITHUB_PROXY}raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt|$SMARTDNS_CONF_DIR/ip-set/china_ip_list.txt|中国IP列表"
echo "${GITHUB_PROXY}raw.githubusercontent.com/leesuncom/update/refs/heads/main/r619ac/etc/smartdns/domain-set/domains.china.smartdns.conf|$SMARTDNS_CONF_DIR/domain-set/domains.china.smartdns.conf|中国域名列表"
echo "${GITHUB_PROXY}raw.githubusercontent.com/leesuncom/update/refs/heads/main/r619ac/etc/smartdns/domain-set/proxy-domain-list.conf|$SMARTDNS_CONF_DIR/domain-set/proxy-domain-list.conf|GFW代理域名列表"
echo "${GITHUB_PROXY}raw.githubusercontent.com/Cats-Team/AdRules/main/smart-dns.conf|$SMARTDNS_CONF_DIR/address.conf|Cats-Team广告过滤规则"
echo "https://anti-ad.net/anti-ad-for-smartdns.conf|$SMARTDNS_CONF_DIR/conf.d/anti-ad-smartdns.conf|anti-ad广告过滤规则"
} | while IFS="|" read -r url dest desc; do
  # 跳过空行
  [ -z "$url" ] && continue
  
  # 下载到临时文件
  tmp_file="$TMP_DIR/$(basename "$dest")"
  if download_file "$url" "$tmp_file" "$desc"; then
    # 只有下载成功时才复制到目标位置
    safe_copy_file "$tmp_file" "$dest" "$desc"
  else
    echo "  ⚠️  保留原始文件：$dest"
  fi
  rm -f "$tmp_file" 2>/dev/null
done

echo "  ✅ SmartDNS 规则更新完成"

# -------------------------- 更新 dnscrypt-proxy 配置 --------------------------
echo -e "\n[4/6] 更新 dnscrypt-proxy 配置..."

{
echo "dnscrypt-blacklist-domains.txt|域名黑名单"
echo "dnscrypt-blacklist-ips.txt|IP黑名单"
echo "dnscrypt-captive-portals.txt|公共网络检测规则"
echo "dnscrypt-cloaking-rules.txt|域名伪装规则"
echo "dnscrypt-forwarding-rules.txt|转发规则"
echo "dnscrypt-whitelist-domains.txt|域名白名单"
echo "dnscrypt-whitelist-ips.txt|IP白名单"
echo "relays.md|中继服务器文档"
echo "public-resolvers.md|公共解析器文档"
echo "parental-control.md|家长控制文档"
echo "odoh-servers.md|ODOH服务器文档"
echo "odoh-relays.md|ODOH中继文档"
} | while IFS="|" read -r filename desc; do
  # 跳过空行
  [ -z "$filename" ] && continue
  
  url="${GITHUB_PROXY}raw.githubusercontent.com/CNMan/dnscrypt-proxy-config/refs/heads/master/$filename"
  dest="$DNSCRYPT_CONF_DIR/$filename"
  tmp_file="$TMP_DIR/$filename"
  
  if download_file "$url" "$tmp_file" "$desc"; then
    # 只有下载成功时才复制到目标位置
    safe_copy_file "$tmp_file" "$dest" "$desc"
  else
    echo "  ⚠️  保留原始文件：$dest"
  fi
  rm -f "$tmp_file" 2>/dev/null
done

echo "  ✅ dnscrypt-proxy 配置更新完成"

# -------------------------- 更新 MosDNS 规则 --------------------------
echo -e "\n[5/6] 更新 MosDNS 规则..."

# 5.1 Journalist-HK 规则集
echo "  → 下载 Journalist-HK 规则集..."

{
echo "akamai_domain_list.txt|akamai_domain_list.txt"
echo "block_list.txt|blocklist.txt"
echo "cachefly_ipv4.txt|cachefly_ipv4.txt"
echo "cdn77_ipv4.txt|cdn77_ipv4.txt"
echo "cdn77_ipv6.txt|cdn77_ipv6.txt"
echo "china_domain_list_mini.txt|china_domain_list_mini.txt"
echo "cloudfront.txt|cloudfront.txt"
echo "cloudfront_ipv6.txt|cloudfront_ipv6.txt"
echo "custom_list.txt|custom_list.txt"
echo "gfw_ip_list.txt|gfw_ip_list.txt"
echo "grey_list_js.txt|grey_list_js.txt"
echo "grey_list.txt|greylist.txt"
echo "hosts_akamai.txt|hosts_akamai.txt"
echo "hosts_fastly.txt|hosts_fastly.txt"
echo "jp_dns_list.txt|jp_dns_list.txt"
echo "original_domain_list.txt|original_domain_list.txt"
echo "ipv6_domain_list.txt|ipv6_domain_list.txt"
echo "private.txt|private.txt"
echo "redirect.txt|redirect.txt"
echo "sucuri_ipv4.txt|sucuri_ipv4.txt"
echo "us_dns_list.txt|us_dns_list.txt"
echo "white_list.txt|whitelist.txt"
} | while IFS="|" read -r src dest; do
  # 跳过空行
  [ -z "$src" ] && continue
  
  url="${GITHUB_PROXY}raw.githubusercontent.com/Journalist-HK/Rules/main/$src"
  tmp_file="$TMP_DIR/$dest"
  
  if download_file "$url" "$tmp_file" "Journalist-HK/$src"; then
    safe_copy_file "$tmp_file" "$MOSDNS_RULE_DIR/$dest" "Journalist-HK/$src"
  else
    echo "  ⚠️  保留原始文件：$MOSDNS_RULE_DIR/$dest"
  fi
  rm -f "$tmp_file" 2>/dev/null
done

# 5.2 Loyalsoldier 规则集
echo "  → 下载 Loyalsoldier 规则集..."

{
echo "geoip/release/text/facebook.txt|facebook.txt|Facebook IP列表"
echo "geoip/release/text/fastly.txt|fastly.txt|Fastly IP列表"
echo "geoip/release/text/telegram.txt|telegram.txt|Telegram IP列表"
echo "geoip/release/text/twitter.txt|twitter.txt|Twitter IP列表"
echo "v2ray-rules-dat/release/gfw.txt|gfw.txt|GFW域名列表"
echo "v2ray-rules-dat/release/greatfire.txt|greatfire.txt|GreatFire域名列表"
} | while IFS="|" read -r path dest desc; do
  # 跳过空行
  [ -z "$path" ] && continue
  
  url="${GITHUB_PROXY}raw.githubusercontent.com/Loyalsoldier/$path"
  tmp_file="$TMP_DIR/$dest"
  
  if download_file "$url" "$tmp_file" "Loyalsoldier/$desc"; then
    safe_copy_file "$tmp_file" "$MOSDNS_RULE_DIR/$dest" "Loyalsoldier/$desc"
  else
    echo "  ⚠️  保留原始文件：$MOSDNS_RULE_DIR/$dest"
  fi
  rm -f "$tmp_file" 2>/dev/null
done

# 5.3 pmkol/easymosdns 规则集
echo "  → 下载 pmkol/easymosdns 规则集..."

{
echo "rules/ad_domain_list.txt|ad_domain_list.txt|广告域名列表"
echo "rules/cdn_domain_list.txt|cdn_domain_list.txt|CDN域名列表"
echo "rules/china_domain_list.txt|china_domain_list.txt|中国域名列表"
echo "rules/china_ip_list.txt|china_ip_list.txt|中国IP列表"
} | while IFS="|" read -r path dest desc; do
  # 跳过空行
  [ -z "$path" ] && continue
  
  url="${GITHUB_PROXY}raw.githubusercontent.com/pmkol/easymosdns/$path"
  tmp_file="$TMP_DIR/$dest"
  
  if download_file "$url" "$tmp_file" "pmkol/$desc"; then
    safe_copy_file "$tmp_file" "$MOSDNS_RULE_DIR/$dest" "pmkol/$desc"
  else
    echo "  ⚠️  保留原始文件：$MOSDNS_RULE_DIR/$dest"
  fi
  rm -f "$tmp_file" 2>/dev/null
done

# 5.4 CloudflareSpeedTest IP列表
echo "  → 下载 CloudflareSpeedTest 规则集..."

tmp_file_ipv4="$TMP_DIR/ip.txt"
tmp_file_ipv6="$TMP_DIR/ipv6.txt"

if download_file "${GITHUB_PROXY}raw.githubusercontent.com/XIU2/CloudflareSpeedTest/master/ip.txt" \
  "$tmp_file_ipv4" "Cloudflare IPv4测试列表"; then
  safe_copy_file "$tmp_file_ipv4" "$MOSDNS_RULE_DIR/ip.txt" "Cloudflare IPv4测试列表"
else
  echo "  ⚠️  保留原始文件：$MOSDNS_RULE_DIR/ip.txt"
fi

if download_file "${GITHUB_PROXY}raw.githubusercontent.com/XIU2/CloudflareSpeedTest/master/ipv6.txt" \
  "$tmp_file_ipv6" "Cloudflare IPv6测试列表"; then
  safe_copy_file "$tmp_file_ipv6" "$MOSDNS_RULE_DIR/ipv6.txt" "Cloudflare IPv6测试列表"
else
  echo "  ⚠️  保留原始文件：$MOSDNS_RULE_DIR/ipv6.txt"
fi

rm -f "$tmp_file_ipv4" "$tmp_file_ipv6" 2>/dev/null

echo "  ✅ MosDNS 规则更新完成"

# -------------------------- 重启服务 + 清理收尾 --------------------------
echo -e "\n[6/6] 重启服务并清理..."

# 重启服务（如果服务存在）
[ -f /etc/init.d/dnscrypt-proxy ] && /etc/init.d/dnscrypt-proxy restart
[ -f /etc/init.d/mosdns ] && /etc/init.d/mosdns restart
[ -f /etc/init.d/smartdns ] && /etc/init.d/smartdns restart

# 最终清理
rm -rf "$TMP_DIR" 2>/dev/null
echo "  ✅ 临时文件已彻底清理"

# -------------------------- 结束提示 --------------------------
echo -e "\n======================================"
echo "✅ 全部配置更新完成！（脚本版本：$SCRIPT_VERSION）"
echo "📌 关键注意事项："
echo "  1. 必须以 root 用户执行"
echo "  2. 服务状态检查："
echo "     /etc/init.d/dnscrypt-proxy status"
echo "     /etc/init.d/mosdns status"
echo "     /etc/init.d/smartdns status"
echo "  3. 网络测试：ping baidu.com 和 ping google.com"
echo "  4. 如果下载失败，会保留原始文件，可尝试更换代理："
echo "     https://ghfast.top/"
echo "  5. 下载失败的文件会显示警告信息"
echo "======================================"