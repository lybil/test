#!/bin/bash

IMG_URL="https://down.idc.wiki/Image/Mikrotik/chr-7.4.img"
IMG_FILE=$(mktemp)
ROOT_DISK=$(df -h / | tail -n 1 | awk '{print $1}' | sed 's/\([0-9]\+\)//g')

INTERFACE=$(ip r | grep default | awk -F'dev' '{print $2}' | awk '{print $1}')
GATEWAY=$(ip r | grep default | awk -F'via' '{print $2}' | awk '{print $1}' | head -n 1)
ADDRESS=$(ip a | grep scope | grep $INTERFACE | awk '{print $2}' | head -n 1)
MACADDRESS=$(ip link | grep -A 1 $INTERFACE | grep link | awk '{print $2}' | head -n 1)

# 安全退出处理
cleanup() {
    echo "Cleaning up..."
    [ -n "$LOOP_DEVICE" ] && losetup -d "$LOOP_DEVICE" 2>/dev/null
    umount /tmp/chr 2>/dev/null
    rm -rf /tmp/chr 2>/dev/null
    rm -f "$IMG_FILE" 2>/dev/null
    exit
}
trap cleanup EXIT INT TERM

# 检查必要工具
check_dependencies() {
    local deps=("wget" "losetup" "partprobe" "dd" "awk" "grep" "sed")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Error: $dep is required but not installed"
            exit 1
        fi
    done
}

# 检查磁盘空间
check_disk_space() {
    local img_size=$(stat -c %s "$IMG_FILE" 2>/dev/null || wget --spider -S "$IMG_URL" 2>&1 | grep -i 'content-length' | awk '{print $2}')
    local disk_space=$(df -B1 "$ROOT_DISK" | awk 'NR==2 {print $4}')
    
    if [ "$img_size" -gt "$disk_space" ]; then
        echo "Error: Not enough disk space. Need: $img_size, Available: $disk_space"
        exit 1
    fi
}

setup_loop(){
    modprobe loop >/dev/null 2>&1
    losetup -D >/dev/null 2>&1
}

# 主执行函数
main() {
    echo "Starting Mikrotik CHR installation..."
    
    check_dependencies
    
    if [ ! -b "$ROOT_DISK" ]; then
        echo "Error: $ROOT_DISK must be a block device"
        exit 1
    fi

    if [ -n "$1" ]; then
        echo "Using $1 as image"
        IMG_URL="$1"
    fi

    # 下载镜像
    echo "Downloading image from $IMG_URL..."
    if ! wget -O "$IMG_FILE" "$IMG_URL"; then
        echo "Failed to download image file"
        exit 1
    fi

    # 检查文件完整性
    if [ ! -s "$IMG_FILE" ]; then
        echo "Downloaded file is empty or corrupted"
        exit 1
    fi

    check_disk_space
    setup_loop

    # 清理临时目录
    rm -rf /tmp/chr
    mkdir -p /tmp/chr

    # 设置loop设备
    LOOP_DEVICE=$(losetup -f --show "$IMG_FILE")
    if [ $? -ne 0 ]; then
        echo "Failed to setup loop device"
        exit 1
    fi

    # 尝试不同的分区命名方案
    partprobe "$LOOP_DEVICE"
    sleep 2

    # 尝试挂载分区
    local mounted=false
    for part in "${LOOP_DEVICE}p1" "${LOOP_DEVICE}1"; do
        if mount "$part" /tmp/chr 2>/dev/null; then
            mounted=true
            break
        fi
    done

    if [ "$mounted" = false ]; then
        echo "Failed to mount image partition"
        losetup -d "$LOOP_DEVICE"
        exit 1
    fi

    # 创建autorun脚本
    cat > /tmp/chr/autorun.scr << EOF
/ip address add address=$ADDRESS interface=[/interface ethernet find where mac-address=$MACADDRESS]
/ip route add gateway=$GATEWAY
EOF

    # 清理
    umount /tmp/chr
    losetup -d "$LOOP_DEVICE"

    echo "Writing image to disk $ROOT_DISK..."
    # 刷新磁盘缓存
    sync
    
    # 使用更可靠的dd方式
    if ! dd if="$IMG_FILE" of="$ROOT_DISK" bs=4M status=progress; then
        echo "Error: Failed to write image to disk"
        exit 1
    fi

    sync
    echo "Image written successfully."

    # 重启系统（使用不同的重启方法）
    echo "Rebooting system..."
    if command -v reboot >/dev/null 2>&1; then
        reboot
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl reboot
    elif command -v shutdown >/dev/null 2>&1; then
        shutdown -r now
    else
        echo "Please reboot the system manually to complete installation"
        echo "echo 1 > /proc/sys/kernel/sysrq && echo b > /proc/sysrq-trigger"
    fi
}

# 执行主函数
main "$@"
