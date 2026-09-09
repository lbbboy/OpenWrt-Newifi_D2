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

# daed 1.27.0 - MIPS/32-bit compatibility
DAED_MAKEFILE="feeds/packages/net/daed/Makefile"

python3 - "$DAED_MAKEFILE" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

# 1. 不启用 trace Go build tag
s = s.replace(
    "GO_PKG_TAGS:=embedallowed,trace",
    "GO_PKG_TAGS:=embedallowed",
)

# 2. 整个替换 Build/Compile
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
		EBPF_DIR="$$(go list -m -f '{{.Dir}}' github.com/cilium/ebpf)" ; \
		echo "==> cilium/ebpf: $$EBPF_DIR" ; \
		sed -i 's/if uint64(btfIndex) > math.MaxInt {/if btfIndex != ^uint32(0) \&\& uint64(btfIndex) > math.MaxInt {/' \
			"$$EBPF_DIR/btf/unmarshal.go" ; \
		export \
		BPF_CLANG="$(CLANG)" \
		BPF_STRIP_FLAG="-strip=$(LLVM_STRIP)" \
		BPF_CFLAGS="$(DAE_CFLAGS)" \
		BPF_TARGET="bpfel,bpfeb" \
		BPF_TRACE_TARGET="mips" ; \
		go generate control/control.go ; \
		popd ; \
		$(call GoPackage/Build/Compile) ; \
	)
endef'''

s = s[:start] + new + s[end:]

p.write_text(s)
print("==> daed Makefile patched successfully")
PY
print("==> daed Build/Compile replaced successfully")
PY
