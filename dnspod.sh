#!/bin/bash

# 默认配置
ID=""
Token=""
domain=""
sub_domain=""
ip_version="4"  # 默认使用IPv4

apt-get update && apt-get install -y jq
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
    echo "  $0 -i 12345 -t abcdef -d example.com -s www -4"
    exit 1
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--id)
            ID="$2"
            shift 2
            ;;
        -t|--token)
            Token="$2"
            shift 2
            ;;
        -d|--domain)
            domain="$2"
            shift 2
            ;;
        -s|--sub)
            sub_domain="$2"
            shift 2
            ;;
        -4)
            ip_version="4"
            shift
            ;;
        -6)
            ip_version="6"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "未知参数: $1"
            show_help
            ;;
    esac
done

# 验证必要参数
if [ -z "$ID" ] || [ -z "$Token" ] || [ -z "$domain" ]; then
    echo "错误: ID, Token 和 domain 是必需的参数"
    show_help
fi

# API接口地址
api="https://dnsapi.cn"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 获取当前IP
get_current_ip() {
    if [ "$ip_version" = "4" ]; then
        curl -s http://ipv4.icanhazip.com
    else
        curl -s http://ipv6.icanhazip.com
    fi
}
# 获取记录列表并直接创建或更新记录
get_and_handle_record() {
    local data="login_token=${ID},${Token}&format=json&domain=${domain}&sub_domain=${sub_domain}"
    local response=$(curl -s -X POST "${api}/Record.List" -d "${data}")
    
    # 输出完整的API响应以便调试
    log "API返回数据: ${response}"
    
    # 使用jq解析记录ID
    local record_id=$(echo "${response}" | jq -r '.records[0].id // empty')
    
    if [ -z "${record_id}" ] || [ "${record_id}" = "null" ]; then
        # 如果没有找到记录，创建新记录
        create_record
    else
        # 如果找到记录，更新现有记录
        update_existing_record "${record_id}"
    fi
}

# 创建新记录
create_record() {
    local record_type="A"
    [ "$ip_version" = "6" ] && record_type="AAAA"
    
    local data="login_token=${ID},${Token}&format=json&domain=${domain}&sub_domain=${sub_domain}&record_type=${record_type}&record_line=默认&value=${current_ip}"
    local create_result=$(curl -s -X POST "${api}/Record.Create" -d "${data}")
    
    log "创建记录结果: ${create_result}"
    
    if echo "${create_result}" | jq -r '.status.code' | grep -q "1"; then
        log "记录创建成功"
    else
        local error_msg=$(echo "${create_result}" | jq -r '.status.message')
        log "记录创建失败: ${error_msg}"
    fi
}

# 更新现有记录
update_existing_record() {
    local record_id="$1"
    local record_type="A"
    [ "$ip_version" = "6" ] && record_type="AAAA"
    
    local data="login_token=${ID},${Token}&format=json&domain=${domain}&sub_domain=${sub_domain}&record_id=${record_id}&record_type=${record_type}&record_line=默认&value=${current_ip}"
    local update_result=$(curl -s -X POST "${api}/Record.Modify" -d "${data}")
    
    if echo "${update_result}" | jq -r '.status.code' | grep -q "1"; then
        log "记录更新成功"
    else
        local error_msg=$(echo "${update_result}" | jq -r '.status.message')
        log "记录更新失败: ${error_msg}"
    fi
}

# 主程序
main() {
    # 获取当前IP
    current_ip=$(get_current_ip)
    log "当前IP: ${current_ip}"
    
    # 处理记录
    get_and_handle_record
}

# 执行主程序
main
