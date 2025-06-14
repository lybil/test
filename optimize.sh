#!/usr/bin/env bash

echo=echo
for cmd in echo /bin/echo; do
    $cmd >/dev/null 2>&1 || continue

    if ! $cmd -e "" | grep -qE '^-e'; then
        echo=$cmd
        break
    fi
done
TARGET="39.174.244.231" #ping的地址
BANDWIDTH_Mbps=300 # Mbps，可以根据你网络的瓶颈带宽修改
#BANDWIDTH_Mbps=600

CSI=$($echo -e "\033[")
CEND="${CSI}0m"
CDGREEN="${CSI}32m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"
CMAGENTA="${CSI}1;35m"
CCYAN="${CSI}1;36m"

OUT_ALERT() {
    echo -e "${CYELLOW}$1${CEND}"
}

OUT_ERROR() {
    echo -e "${CRED}$1${CEND}"
}

OUT_INFO() {
    echo -e "${CCYAN}$1${CEND}"
}

if ! command -v bc &>/dev/null; then
    OUT_ALERT "[信息] 正在安装 bc 工具用于计算..."
    if [[ ${release} == "centos" ]]; then
        yum install -y bc
    else
        apt install -y bc
    fi
fi

# 检测操作系统类型
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -q -E -i "debian|raspbian"; then
    release="debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -q -E -i "raspbian|debian"; then
    release="debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
else
    OUT_ERROR "[错误] 不支持的操作系统！"
    exit 1
fi

OUT_ALERT "[信息] 正在更新系统中！"
if [[ ${release} == "centos" ]]; then
    yum makecache
    yum install epel-release -y
    yum update -y
else
    apt update
    apt dist-upgrade -y
    apt autoremove --purge -y
fi

OUT_ALERT "[信息] 正在安装 haveged 增强性能中！"
if [[ ${release} == "centos" ]]; then
    yum install haveged -y
else
    apt install haveged -y
fi

OUT_ALERT "[信息] 正在配置 haveged 增强性能中！"
systemctl disable --now haveged &>/dev/null || true
systemctl enable --now haveged &>/dev/null || true

OUT_ALERT "[信息] 正在优化系统参数中！"
modprobe ip_conntrack 2>/dev/null

# 获取 RTT 并计算 BDP
PING_OUTPUT=$(ping -c 5 "$TARGET" 2>/dev/null)

if echo "$PING_OUTPUT" | grep -q "avg"; then
    RTT_MS=$(echo "$PING_OUTPUT" | awk -F'/' '/^rtt/ {print $5}')
    RTT_SEC=$(bc <<< "scale=6; $RTT_MS / 1000")
    OUT_INFO "[信息] 成功获取 RTT 往返时延：${RTT_MS}ms（即 ${RTT_SEC}s）"
    
    BDP_bits=$(bc <<< "$BANDWIDTH_Mbps * 1000000 * $RTT_SEC")
    BDP_bytes=$(bc <<< "$BDP_bits / 8")

    OUT_INFO "[信息] 计算出 BDP（带宽时延积）：$BDP_bytes 字节"
    OUT_INFO "[提示] 推荐 tcp_rmem 和 tcp_wmem 最大值 >= $BDP_bytes 字节"
else
    OUT_ERROR "[警告] 无法 ping 通目标 IP 地址：$TARGET"
    read -p "[输入] 请手动输入 RTT（单位 ms，例如 170）: " RTT_MS_INPUT
    RTT_SEC_INPUT=$(bc <<< "scale=6; $RTT_MS_INPUT / 1000")
    OUT_INFO "[信息] 您输入的 RTT 为：${RTT_MS_INPUT}ms（即 ${RTT_SEC_INPUT}s）"

    BDP_bits_input=$(bc <<< "$BANDWIDTH_Mbps * 1000000 * $RTT_SEC_INPUT")
    BDP_bytes_input=$(bc <<< "$BDP_bits_input / 8")

    OUT_INFO "[信息] 根据输入计算出 BDP（带宽时延积）：$BDP_bytes_input 字节"
    OUT_INFO "[提示] 推荐 tcp_rmem 和 tcp_wmem 最大值 >= $BDP_bytes_input 字节"
    BDP_bytes=${BDP_bytes_input%.*}
fi

chattr -i /etc/sysctl.conf &>/dev/null || true
cat > /etc/sysctl.conf << EOF
vm.swappiness = 0
fs.file-max = 1024000
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 1024000
net.core.default_qdisc = fq
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2
net.ipv4.ip_forward = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_keepalive_time = 10
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rmem = 4096 87380 $BDP_bytes
net.ipv4.tcp_wmem = 4096 16384 $BDP_bytes
net.ipv4.tcp_congestion_control = bbr
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.nf_conntrack_max = 25000000
net.netfilter.nf_conntrack_max = 25000000
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_established = 180
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
EOF

cat > /etc/security/limits.conf << EOF
* soft nofile 512000
* hard nofile 512000
* soft nproc 512000
* hard nproc 512000
root soft nofile 512000
root hard nofile 512000
root soft nproc 512000
root hard nproc 512000
EOF

cat > /etc/systemd/journald.conf <<EOF
[Journal]
SystemMaxUse=384M
SystemMaxFileSize=128M
ForwardToSyslog=no
EOF

sysctl -p

OUT_INFO "[信息] 优化完毕！"
exit 0
