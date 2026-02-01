# 修改默认IP & 固件名称 & 编译署名和时间
sed -i 's/192.168.1.1/10.0.0.252/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='Roc'/g" package/base-files/files/bin/config_generate
sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),# \
            _('Firmware Version'),\n \
            E('span', {}, [\n \
                (L.isObject(boardinfo.release)\n \
                ? boardinfo.release.description + ' / '\n \
                : '') + (luciversion || '') + ' / ',\n \
            E('a', {\n \
                href: 'https://github.com/laipeng668/openwrt-ci-roc/releases',\n \
                target: '_blank',\n \
                rel: 'noopener noreferrer'\n \
                }, [ 'Built by Roc $(date "+%Y-%m-%d %H:%M:%S")' ])\n \
            ]),#" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# 移除luci-app-attendedsysupgrade软件包
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")


# 移除要替换的包
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-wechatpush
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# ariang & frp & WolPlus & Argon & Aurora & Go & OpenList & Lucky & wechatpush & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang
git_sparse_clone frp https://github.com/laipeng668/packages net/frp
mv -f package/frp feeds/packages/net/frp
git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps
git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon feeds/luci/themes/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config feeds/luci/applications/luci-app-argon-config
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 25.x feeds/packages/lang/golang
git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac package/openwrt-gecoosac
# chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

### PassWall & OpenClash ###

# 移除 OpenWrt Feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

# 移除 OpenWrt Feeds 过时的LuCI版本
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-openclash
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
git clone --depth=1 https://github.com/vernesong/OpenClash package/luci-app-openclash

# 清理 PassWall 的 chnlist 规则文件
echo "baidu.com"  > package/luci-app-passwall/luci-app-passwall/root/usr/share/passwall/rules/chnlist

./scripts/feeds update -a
./scripts/feeds install -a
