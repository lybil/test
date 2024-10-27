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

# 获取记录列表
get_record_list() {
    local data="login_token=${ID},${Token}&format=json&domain=${domain}&sub_domain=${sub_domain}"
    curl -s -X POST "${api}/Record.List" -d "${data}"
}

# 更新记录
update_record() {
    local record_id="$1"
    local ip="$2"
    local record_type="A"
    [ "$ip_version" = "6" ] && record_type="AAAA"
    
    local data="login_token=${ID},${Token}&format=json&domain=${domain}&sub_domain=${sub_domain}&record_id=${record_id}&record_type=${record_type}&record_line=默认&record_line_id=0&value=${ip}"
    curl -s -X POST "${api}/Record.Modify" -d "${data}"
}
# 获取记录列表
get_record_list() {
    local data="login_token=${ID},${Token}&format=json&domain=${domain}&sub_domain=${sub_domain}"
    local response=$(curl -s -X POST "${api}/Record.List" -d "${data}")
    echo "${response}"
}

# 新增：解析JSON的函数
parse_record_id() {
    local response="$1"
    # 使用更精确的方式解析JSON
    if command -v jq >/dev/null 2>&1; then
        # 如果系统安装了jq，使用jq解析
        echo "$response" | jq -r '.records[0].id // empty'
    else
        # 如果没有jq，使用grep但更精确的匹配
        echo "$response" | grep -o '"records":\[{[^}]*"id":"[0-9]*"' | grep -o '"id":"[0-9]*"' | cut -d'"' -f4
    fi
}

# 主程序
main() {
    # 获取当前IP
    current_ip=$(get_current_ip)
    log "当前IP: ${current_ip}"

    # 获取域名记录
    record_info=$(get_record_list)
    log "API返回信息: ${record_info}"  # 添加调试信息
    
    # 使用新的解析函数获取记录ID
    record_id=$(parse_record_id "${record_info}")
    
    if [ -z "${record_id}" ]; then
        log "未找到域名记录，尝试创建新记录"
        # 这里可以添加创建记录的逻辑
        create_record
        exit 1
    fi
    
    log "域名记录ID: ${record_id}"

    # 更新记录
    update_result=$(update_record "${record_id}" "${current_ip}")
    
    # 检查更新结果
    if echo "${update_result}" | grep -q '"code":"1"'; then
        log "域名记录更新成功"
    else
        log "域名记录更新失败: ${update_result}"
        # 输出完整的错误信息
        log "错误详情: $(echo ${update_result} | grep -o '"message":"[^"]*"')"
    fi
}

# 新增：创建记录的函数
create_record() {
    local data="login_token=${ID},${Token}&format=json&domain=${domain}&sub_domain=${sub_domain}&record_type=A&record_line=默认&value=${current_ip}"
    local create_result=$(curl -s -X POST "${api}/Record.Create" -d "${data}")
    log "创建记录结果: ${create_result}"
}

# 执行主程序
main
