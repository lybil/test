#!/bin/bash

# Check if redhat-lsb-core is installed, if not, install it
if ! rpm -q iredhat-lsb-core &> /dev/null
then
    echo "redhat-lsb-core not found, installing..."
    sudo yum install redhat-lsb-core -y
fi
# Check if ipset is installed, if not, install it
if ! command -v ipset &> /dev/null
then
    echo "ipset not found, installing..."
    if [[ $(lsb_release -si) == "Ubuntu" ]]; then
        sudo apt-get update
        sudo apt-get install ipset -y
    elif [[ $(lsb_release -si) == "CentOS" ]]; then
        sudo yum install ipset -y
    elif [[ $(lsb_release -si) == "Debian" ]]; then
        sudo apt-get update
        sudo apt-get install ipset -y
    else
        echo "Unsupported distribution."
        exit 1
    fi
fi

# Check if iptables-services is installed, if not, install it
if ! rpm -q iptables-services &> /dev/null
then
    echo "iptables-services not found, installing..."
    sudo yum install iptables-services -y
fi

# Create an ipset called "china"
sudo iptables -F
sudo ipset destroy 

sudo ipset create china hash:net

# Download the latest APNIC delegated file
wget https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest -O /root/delegated-apnic-latest.txt

# Add China's IP ranges to the "china" ipset
cat /root/delegated-apnic-latest.txt | grep '|CN|ipv4|' | awk -F\| '{ printf("%s/%d\n", $4, 32-log($5)/log(2)) }' | sudo xargs -I{} ipset add china {}



# Allow Chinese IP addresses to access ports 40000-50000, and deny others

sudo iptables -I INPUT -m set ! --match-set china src -p tcp --dport 40000:50000 -j DROP

# Save the iptables rules
if [[ $(lsb_release -si) == "Ubuntu" ]]; then
    sudo iptables-save > /etc/iptables/rules.v4
elif [[ $(lsb_release -si) == "CentOS" ]]; then
    sudo service iptables save
elif [[ $(lsb_release -si) == "Debian" ]]; then
    sudo iptables-save > /etc/iptables/rules.v4
else
    echo "Unsupported distribution."
    exit 1
fi
# 删除临时文件
rm /root/delegated-apnic-latest.txt

echo "Done."
