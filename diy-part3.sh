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
#    动态解析 cilium/ebpf 版本号，而不是写死版本，
#    避免依赖升级后补丁路径失效导致构建中断。
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
		echo "========================================" ; \
		echo "==> downloading full cilium/ebpf module source..." ; \
		go mod download github.com/cilium/ebpf ; \
		echo "==> resolving cilium/ebpf version..." ; \
		EBPF_VER="$$$$(go list -m -f '{{.Version}}' github.com/cilium/ebpf)" ; \
		echo "==> resolved version: $$$$EBPF_VER" ; \
		EBPF_DIR="$$$$(go env GOMODCACHE)/github.com/cilium/ebpf@$$$${EBPF_VER}" ; \
		EBPF_FILE="$$$${EBPF_DIR}/btf/unmarshal.go" ; \
		echo "==> target file: $$$${EBPF_FILE}" ; \
		if [ ! -f "$$$${EBPF_FILE}" ] ; then \
			echo "==> WARN: not found at $$$${EBPF_FILE}, falling back to find" ; \
			EBPF_FILE="$$$$(find "$$$$(go env GOMODCACHE)/github.com" -path '*/cilium/ebpf@*/btf/unmarshal.go' 2>/dev/null | head -n1)" ; \
			echo "==> fallback found: $$$${EBPF_FILE}" ; \
		fi ; \
		test -n "$$$${EBPF_FILE}" -a -f "$$$${EBPF_FILE}" || { \
			echo "==> ERROR: cilium/ebpf unmarshal.go not found anywhere" ; \
			find "$$$$(go env GOMODCACHE)/github.com/cilium" -maxdepth 1 -type d 2>/dev/null ; \
			exit 1 ; \
		} ; \
		EBPF_DIR="$$$$(dirname "$$$$(dirname "$$$${EBPF_FILE}")")" ; \
		chmod -R u+w "$$$${EBPF_DIR}" ; \
		echo "==> BEFORE PATCH:" ; \
		grep -n 'btfIndex.*math.MaxInt' "$$$${EBPF_FILE}" || true ; \
		sed -i 's/if uint64(btfIndex) > math.MaxInt {/if btfIndex != ^uint32(0) \&\& uint64(btfIndex) > math.MaxInt {/' "$$$${EBPF_FILE}" ; \
		echo "==> AFTER PATCH:" ; \
		grep -n 'btfIndex.*math.MaxInt' "$$$${EBPF_FILE}" ; \
		if ! grep -q 'btfIndex != \^uint32(0)' "$$$${EBPF_FILE}"; then \
			echo "==> ERROR: cilium/ebpf BTF patch NOT applied" ; \
			exit 1 ; \
		fi ; \
		echo "==> cilium/ebpf BTF patch applied successfully" ; \
		echo "========================================" ; \
		export \
		BPF_CLANG="$(CLANG)" \
		BPF_STRIP_FLAG="-strip=$(LLVM_STRIP)" \
		BPF_CFLAGS="$(DAE_CFLAGS)" \
		BPF_TARGET="bpfel,bpfeb" ; \
		go generate control/control.go ; \
		popd ; \
		$(call GoPackage/Build/Compile) ; \
	)
endef'''

s = s[:start] + new + s[end:]

p.write_text(s)
print("==> daed 1.27.0 Makefile patched successfully")
PY
