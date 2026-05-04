#!/bin/bash
#=============================================================
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
# Lisence: MIT
# Author: P3TERX
# Blog: https://p3terx.com
#=============================================================

# fw876/helloworld
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.defaultault

#sed -i '$a src-git helloworld https://github.com/fw876/helloworld' feeds.conf.default

sed -i '$a src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2' feeds.conf.default

# lua-daed
git clone https://github.com/sbwml/luci-app-daed-next package/daed-next

# luci-app-vssr
# git clone https://github.com/jerrykuku/luci-app-vssr.git package/lean/luci-app-vssr
