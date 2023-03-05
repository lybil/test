#!/bin/bash

# 检查系统类型
if [ -f "/etc/centos-release" ]; then
    OS="centos"
elif [ -f "/etc/debian_version" ]; then
    OS="debian"
elif [ -f "/etc/lsb-release" ]; then
    OS="ubuntu"
else
    echo "Unsupported operating system."
    exit 1
fi

# 安装ipset并下载ipset的ipv4
if ! command -v ipset >/dev/null 2>&1; then
    if [ "$OS" = "centos" ]; then
        yum install -y ipset
    elif [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        apt-get update
        apt-get install -y ipset
    else
        echo "Error: Unable to install ipset-china. Please install it manually and try again."
        exit 1
    fi
fi

# Create and populate the "china" ipset
if ! ipset list china &> /dev/null; then
    echo "Creating 'china' ipset..."
    ipset create china hash:net
fi

echo "Populating 'china' ipset..."
# 下载国内IPv4源
#curl -sSL http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest | grep ipv4 | grep CN | awk -F\| '{printf("%s/%d\n", $4, 32-log($5)/log(2))}' > /tmp/china_ip_list_v4.txt
curl -sSL https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt | sed 's/\r$//' | grep -v '^#' | sort -u > /tmp/china_ip_list_v4.txt

# 创建ipset规则
sudo ipset -N china hash:net

# 加载ipset规则
sudo ipset -A china $(cat /tmp/china_ip_list_v4.txt)

# 删除临时文件
rm /tmp/china_ip_list_v4.txt

echo "china_v4 ipset rules have been created and loaded successfully."


# 检查iptables-persistent是否已安装，如果未安装则安装它
if [ "$OS" = "centos" ]; then
    if ! rpm -q iptables-persistent >/dev/null 2>&1; then
        yum install -y iptables-persistent
    fi
elif [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
    if [ ! -f "/usr/sbin/netfilter-persistent" ]; then
        apt-get update
        apt-get install -y iptables-persistent
    fi
fi

# 清除所有规则
iptables -F

# 允许已建立的连接和本地流量
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# 允许所有端口的中国IP地址流量
iptables -A INPUT -m set --match-set china src -j ACCEPT

# 允许40000-50000端口的中国IP地址流量
iptables -A INPUT -m set --match-set china src -p tcp --dport 40000:50000 -j ACCEPT

# 阻止40000-50000端口的海外流量
iptables -A INPUT -p tcp --dport 40000:50000 -m set --match-set china dst -j DROP

# 允许所有其他端口的海外流量
iptables -A INPUT -p tcp -m state --state NEW -j ACCEPT

# 阻止所有其他流量
iptables -A INPUT -j DROP

# 保存iptables规则
if [ "$OS" = "centos" ]; then
    service iptables save
elif [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
fi

# 如果iptables-persistent未在此之前安装，则配置它
if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ] && [ ! -f "/etc/init.d/netfilter-persistent" ]; then
    systemctl enable netfilter-persistent
fi
