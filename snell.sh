#!/bin/bash

# 更新APT包列表并安装必要的软件包
sudo apt update && sudo apt install -y wget unzip vim openssl

# 下载Snell Server，根据系统架构选择下载
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    wget https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-amd64.zip
elif [ "$ARCH" == "aarch64" ]; then
    wget https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-aarch64.zip
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# 创建 /etc/snell 目录（如果存在则不报错），并清空目录内容
sudo mkdir -p /etc/snell
echo "/etc/snell 目录已被创建或已存在，清空目录内容..."
sudo rm -rf /etc/snell/*

# 解压Snell Server到指定目录
if [ "$ARCH" == "x86_64" ]; then
    sudo unzip snell-server-v4.0.1-linux-amd64.zip -d /usr/local/bin
elif [ "$ARCH" == "aarch64" ]; then
    sudo unzip snell-server-v4.0.1-linux-aarch64.zip -d /usr/local/bin
fi

# 赋予服务器可执行权限
sudo chmod +x /usr/local/bin/snell-server

# 生成随机PSK
PSK=$(openssl rand -base64 32)

# 创建并输出Snell Server配置文件
sudo bash -c "cat << EOF > /etc/snell/snell-server.conf
[snell-server]
listen = 0.0.0.0:11807
psk = $PSK
ipv6 = false
EOF"

echo "Snell Server配置文件内容："
cat /etc/snell/snell-server.conf

# 创建Systemd服务文件
sudo bash -c 'cat << EOF > /lib/systemd/system/snell.service
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl enable snell
sudo systemctl start snell

# 输出提示信息，而不是执行命令
echo "请执行以下命令以完成Snell服务的配置："
echo "sudo systemctl daemon-reload"
echo "sudo systemctl enable snell"
echo "sudo systemctl start snell"
echo "sudo systemctl status snell"
