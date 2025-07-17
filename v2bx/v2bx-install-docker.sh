#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

# =============== 新增函数 开始 ===============
# 检查 Docker 是否安装
check_docker() {
    if command -v docker &> /dev/null; then
        echo -e "${green}Docker 已安装。${plain}"
        return 0
    else
        echo -e "${yellow}正在安装 Docker...${plain}"
        install_docker
    fi
}

# 安装 Docker（基于不同系统）
    install_docker() {
    echo -e "${yellow}正在使用兼容方式安装 Docker...${plain}"

    # 安装依赖
    if [[ "$release" == "ubuntu" || "$release" == "debian" ]]; then
        apt-get update -y
        apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
    elif [[ "$release" == "centos" ]]; then
        yum install -y -q yum-utils
    fi

    # 添加 Docker GPG 密钥
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/docker-archive-keyring.gpg >/dev/null

    # 判断系统是 ubuntu 还是 debian 并设置对应仓库
    OS_ID=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
    OS_VERSION_CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d '"')

    echo "Detected OS: $OS_ID, Version CodeName: $OS_VERSION_CODENAME"

    if [[ "$OS_ID" == "ubuntu" ]]; then
        REPO="https://download.docker.com/linux/ubuntu"
    elif [[ "$OS_ID" == "debian" ]]; then
        REPO="https://download.docker.com/linux/debian"
    else
        echo -e "${red}不支持的操作系统：$OS_ID${plain}"
        exit 1
    fi

    echo "Using Docker repo: $REPO"

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $REPO $OS_VERSION_CODENAME stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 更新 APT 缓存
    apt-get update -y

    # 安装 Docker 引擎
    apt-get install -y docker-ce docker-ce-cli containerd.io
    #安装dc
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.29.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # 启动并启用服务
    systemctl enable docker --now
    systemctl start docker

    echo -e "${green}✅ Docker 已成功安装！${plain}"
}



# 构建并启动 Docker 容器
build_run_v2bx_docker() {
    mkdir -p /root/V2bX/
    cd /root/V2bX/

    last_version=$(curl -Ls "https://api.github.com/repos/wyx2685/V2bX/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$last_version" ]]; then
        echo -e "${red}检测 V2bX 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 V2bX 版本安装${plain}"
        exit 1
    fi

    echo -e "正在下载 V2bX Linux-${arch} 最新版本: ${last_version}"
    wget -q -N --no-check-certificate -O V2bX-linux.zip https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 V2bX 失败，请确保你的服务器能够下载 Github 的文件${plain}"
        exit 1
    fi

    unzip V2bX-linux.zip
    rm V2bX-linux.zip -f
    chmod +x V2bX
    #下载singbox、hy2配置文件
    wget https://raw.githubusercontent.com/lybil/test/refs/heads/main/v2bx/hy2config.yaml
    wget https://raw.githubusercontent.com/lybil/test/refs/heads/main/v2bx/sing_origin.json
    wget https://raw.githubusercontent.com/lybil/test/refs/heads/main/v2bx/docker-compose.yml
    #回到root目录
    cd /root
    # 创建 Dockerfile
    cat <<EOF > Dockerfile
FROM alpine
WORKDIR /app
RUN  apk --update --no-cache add tzdata ca-certificates \
&& cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
COPY V2bX /etc/V2bX
  
  ENTRYPOINT [ "/etc/V2bX/V2bX", "server", "--config", "/etc/V2bX/config.json"]  
EOF

    echo -e "${green}开始构建 Docker 镜像 v2bx:latest ...${plain}"
    docker build -t v2bx:latest .

    echo -e "${green}启动容器 v2bx_container ...${plain}"
    docker run -d \
      --name v2bx \
      --network host \
      -v /root/V2bX:/etc/V2bX \
      --restart unless-stopped \
      v2bx:latest


    echo -e "${green}✅ V2bX Docker 容器已运行。你可以用以下命令管理：${plain}"
    echo "docker logs v2bx   # 查看日志"
    echo "docker stop v2bx && docker start v2bx  # 停止/重启容器"
}

# 传统方式安装
install_V2bX() {
    if [[ -e /usr/local/V2bX/ ]]; then
        rm -rf /usr/local/V2bX/
    fi

    mkdir /usr/local/V2bX/ -p
    cd /usr/local/V2bX/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/wyx2685/V2bX/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 V2bX 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 V2bX 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 V2bX 最新版本：${last_version}，开始安装"
        wget -q -N --no-check-certificate -O /usr/local/V2bX/V2bX-linux.zip https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 V2bX 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
        echo -e "开始安装 V2bX $1"
        wget -q -N --no-check-certificate -O /usr/local/V2bX/V2bX-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 V2bX $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip V2bX-linux.zip
    rm V2bX-linux.zip -f
    chmod +x V2bX
    mkdir /etc/V2bX/ -p
    cp geoip.dat /etc/V2bX/
    cp geosite.dat /etc/V2bX/

    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/V2bX -f
        cat <<EOF > /etc/init.d/V2bX
#!/sbin/openrc-run

name="V2bX"
description="V2bX"

command="/usr/local/V2bX/V2bX"
command_args="server"
command_user="root"

pidfile="/run/V2bX.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
        echo -e "${green}V2bX ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/V2bX.service -f
        file="https://github.com/wyx2685/V2bX-script/raw/master/V2bX.service"
        wget -q -N --no-check-certificate -O /etc/systemd/system/V2bX.service ${file}
        systemctl daemon-reload
        systemctl stop V2bX
        systemctl enable V2bX
        echo -e "${green}V2bX ${last_version}${plain} 安装完成，已设置开机自启"
    fi

    if [[ ! -f /etc/V2bX/config.json ]]; then
        cp config.json /etc/V2bX/
        echo -e ""
        echo -e "全新安装，请先参看教程：https://v2bx.v-50.me/，配置必要的内容"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service V2bX start
        else
            systemctl start V2bX
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}V2bX 重启成功${plain}"
        else
            echo -e "${red}V2bX 可能启动失败，请稍后使用 V2bX log 查看日志信息，若无法启动，则可能更改了配置格式，请前往 wiki 查看：https://github.com/V2bX-project/V2bX/wiki${plain}"
        fi
    fi

    curl -o /usr/bin/V2bX -Ls https://raw.githubusercontent.com/wyx2685/V2bX-script/master/V2bX.sh
    chmod +x /usr/bin/V2bX
    if [ ! -L /usr/bin/v2bx ]; then
        ln -s /usr/bin/V2bX /usr/bin/v2bx
        chmod +x /usr/bin/v2bx
    fi

    echo -e "${green}安装完成！你可以使用命令 'V2bX' 管理工具。${plain}"
}

# ========== 主流程开始 ==========
read -rp "请选择安装方式 (d: Docker, n: 普通安装): " install_mode
case "${install_mode}" in
    d|D)
        check_docker
        build_run_v2bx_docker
        ;;
    n|N)
        install_base
        install_V2bX $1
        ;;
    *)
        echo -e "${red}无效选项，请输入 d 或 n${plain}"
        exit 1
        ;;
esac
