#!/bin/bash
#============================================================
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
# Lisence: MIT
# Author: P3TERX
# Blog: https://p3terx.com
#============================================================

#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-material/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]\+\.[0-9]\+/192.168.12.1/g" "$CFG_FILE"

# 隐藏顶部左侧的品牌文字
cat >> package/feeds/luci/luci-theme-material/htdocs/luci-static/material/custom.css <<'EOF'

a.brand {
    display: none !important;
}
EOF

# grpc
#sed -i 's/^  GO_PKG_TAGS:=with_acme.*/  GO_PKG_TAGS:=with_acme,with_clash_api,with_dhcp,with_gvisor,with_quic,with_tailscale,with_utls,with_wireguard,with_grpc/g' feeds/packages/net/sing-box/Makefile

# ============================================================
# daed 1.27.0 - MIPS32 compatibility
# ============================================================

DAED_MAKEFILE="./feeds/packages/net/daed/Makefile"

python3 - "$DAED_MAKEFILE" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

# ------------------------------------------------------------
# 1. MIPS32 不编译 trace
# ------------------------------------------------------------

s = s.replace(
    "GO_PKG_TAGS:=embedallowed,trace",
    "GO_PKG_TAGS:=embedallowed",
)

# ------------------------------------------------------------
# 2. 替换 Build/Compile
#    daed 1.27.0 锁定的 cilium/ebpf 版本是 v0.15.0。
#    该库官方 v0.17.3 发布说明中明确提到修复了
#    "a buffer overflow when running 32-bit user space
#    on a 64-bit kernel"，这正是 MT7621 (mipsel 32位)
#    上出现 "type id XXXXX: index exceeds int" 崩溃的
#    根因。这里在构建前用 `go get` 把依赖升级到该修复
#    版本，而不是手工改源码文件（此前尝试的
#    "unmarshal.go"/"btfIndex" 补丁经核实并不存在，
#    已放弃该方向）。
# ------------------------------------------------------------

start = s.index("define Build/Compile")
end = s.index("endef", start) + len("endef")

new = r'''define Build/Compile
	( \
		pushd $(PKG_BUILD_DIR) ; \
		export \
		$(GO_GENERAL_BUILD_CONFIG_VARS) \
		$(GO_PKG_BUILD_CONFIG_VARS) \
		$(GO_PKG_BUILD_VARS) ; \
		go generate ./... ; \
		cd dae-core ; \
		echo "==> bumping cilium/ebpf to fix 32-bit userspace overflow (see cilium/ebpf v0.17.3 release notes)" ; \
		go get github.com/cilium/ebpf@v0.17.3 ; \
		go mod tidy ; \
		export \
		BPF_CLANG="$(CLANG)" \
		BPF_STRIP_FLAG="-strip=$(LLVM_STRIP)" \
		BPF_CFLAGS="$(DAE_CFLAGS)" \
		BPF_TARGET="bpfel,bpfeb" ; \
		go generate control/control.go ; \
		popd ; \
		( cd $(PKG_BUILD_DIR) && if [ -f go.work ]; then go work sync ; fi ; go mod tidy ) ; \
		$(call GoPackage/Build/Compile) ; \
	)
endef'''

s = s[:start] + new + s[end:]

p.write_text(s)
print("==> daed 1.27.0 Makefile patched successfully")
PY
