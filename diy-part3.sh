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
#    daed 1.27.0 锁定的 cilium/ebpf 版本是 v0.15.0，
#    官方 daeuniverse/dae 目前 main 分支已经把这个依赖
#    升级到 v0.20.0，并且配套修改了 control/kern/tproxy.c
#    里 PARAM 的声明（去掉了 static，改成
#    `const volatile struct dae_param PARAM = {};`），
#    因为新版 cilium/ebpf 的 RewriteConstants 现在按
#    libbpf 规则要求全局常量必须是非 static（可见）的，
#    否则运行时会报 "rewrite constants: some constants
#    are missing from .rodata: PARAM"。
#    这里把依赖版本和这处代码都对齐到官方现在的写法。
#    （此前尝试的 "unmarshal.go"/"btfIndex" 补丁经核实
#    并不存在，已放弃该方向。）
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
		echo "==> bumping cilium/ebpf to v0.20.0 (matches upstream daeuniverse/dae main branch)" ; \
		go get github.com/cilium/ebpf@v0.20.0 ; \
		go mod tidy ; \
		echo "==> patching control_plane.go for removed ebpf.ProgramOptions.LogSize field" ; \
		echo "==> context BEFORE patch:" ; \
		grep -n -B2 -A2 'LogSize' control/control_plane.go || echo "(no LogSize reference found)" ; \
		sed -i '/LogSize:[[:space:]]*ebpf\.DefaultVerifierLogSize/d' control/control_plane.go ; \
		echo "==> context AFTER patch:" ; \
		grep -n 'LogSize' control/control_plane.go || echo "(LogSize reference removed OK)" ; \
		echo "==> searching for PARAM eBPF global constant declaration..." ; \
		PARAM_FILES="$$$$(grep -rl 'PARAM' --include='*.c' . 2>/dev/null)" ; \
		echo "==> files mentioning PARAM: $$$${PARAM_FILES}" ; \
		for f in $$$${PARAM_FILES} ; do \
			echo "==> $$$${f} BEFORE:" ; \
			grep -n 'PARAM' "$$$${f}" ; \
			sed -i -E 's/^(\s*)static(\s+.*\bPARAM\b.*=.*)/\1\2/' "$$$${f}" ; \
			echo "==> $$$${f} AFTER:" ; \
			grep -n 'PARAM' "$$$${f}" ; \
		done ; \
		echo "==> LogSize patch applied successfully" ; \
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
