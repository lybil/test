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
    echo "  $0 -i 12345 -t abcdef -d example.com -s www -4

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
