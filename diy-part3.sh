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

# daed: MIPS BPF trace target
sed -i 's/BPF_TRACE_TARGET="$(GO_ARCH)"/BPF_TRACE_TARGET="mips"/' \
    feeds/packages/net/daed/Makefile

# daed: MIPS/Linux 6.18 暂不编译 trace BPF
sed -i 's/GO_PKG_TAGS:=embedallowed,trace/GO_PKG_TAGS:=embedallowed/' \
    feeds/packages/net/daed/Makefile

sed -i '/go generate trace\/trace.go/d' \
    feeds/packages/net/daed/Makefile

# daed: 修复 32-bit MIPS 下 cilium/ebpf BTF DECL_TAG
# ComponentIdx = 0xffffffff 在 32-bit Go int 下被错误判断为越界
python3 - <<'PY'
from pathlib import Path

p = Path("feeds/packages/net/daed/Makefile")
s = p.read_text()

old = '''                go generate ./... ; \\
                cd dae-core ; \\
'''

new = '''                go generate ./... ; \\
                cd dae-core ; \\
                EBPF_DIR="$$(go list -m -f '{{.Dir}}' github.com/cilium/ebpf)" ; \\
                echo "==> cilium/ebpf: $$EBPF_DIR" ; \\
                sed -i 's/if uint64(btfIndex) > math.MaxInt {/if btfIndex != ^uint32(0) \\\\&\\\\& uint64(btfIndex) > math.MaxInt {/' \\
                        "$$EBPF_DIR/btf/unmarshal.go" ; \\
'''

if old not in s:
    raise SystemExit("ERROR: daed Build/Compile patch target not found")

p.write_text(s.replace(old, new, 1))
print("==> daed: injected cilium/ebpf MIPS BTF patch")
PY
