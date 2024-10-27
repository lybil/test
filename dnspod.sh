#!/bin/bash

# 设置错误处理
set -e

# 默认配置
ID=""
Token=""
domain=""
sub_domain=""
ip_version="4"  # 默认使用IPv4

# 安装必要的工具
install_requirements() {
    if ! command -v jq &> /dev/null; then
        echo "正在安装必要的工具..."
        apt-get update &> /dev/null
        apt-get install -y jq curl &> /dev/null || {
            echo "安装工具失败，请手动安装 jq 和 curl"
            exit 1
        }
    fi
}

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -i, --id        DNSPod ID"
    echo "  -t, --token     DNSPod Token"
    echo "  -d, --domain    主域名"
    echo "  -s, --sub       子域名"
    echo "  -4              使用IPv4 (默认)"
    echo "  -6              使用IPv6"
    echo "  -h, --help      显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 -i 12345 -t abcdef -d example.com -s www -
