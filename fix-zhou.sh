#!/bin/bash

################################################################################
# 周周定制 VPS Proxy 落地时失败问题修复小脚本
# Author: 周周定制
# Email: shangkouyou@gmail.com
# WeChat: shangkouyou
# Description: 一键修复VPS Proxy落地连接性问题
# Usage: sudo bash fix_dns_connectivity.sh
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test domain
TEST_DOMAIN="na.proxys5.net"

# DNS servers to add
DNS_SERVERS=("8.8.8.8" "1.1.1.1" "8.8.4.4" "1.0.0.1")

# Log file
LOG_FILE="/tmp/dns_fix_$(date +%Y%m%d_%H%M%S).log"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}╔═════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ $1${NC}"
    echo -e "${BLUE}╚═════════════════════════════════════════════════════════╝${NC}"
}

print_success() {
    echo -e "${GREEN}  ✅ $1${NC}"
    echo "[SUCCESS] $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}  ❌ $1${NC}"
    echo "[ERROR] $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}  ⚠️  $1${NC}"
    echo "[WARNING] $1" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}  ℹ️  $1${NC}"
    echo "[INFO] $1" >> "$LOG_FILE"
}

print_step() {
    echo -e "${YELLOW}  🔧 $1${NC}"
    echo "[STEP] $1" >> "$LOG_FILE"
}

################################################################################
# Check if running as root
################################################################################

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo ""
        print_error "需要 root 权限运行此脚本"
        echo -e "${YELLOW}  💡 请使用: ${NC}sudo bash $0"
        echo ""
        exit 1
    fi
}

################################################################################
# Backup original resolv.conf
################################################################################

backup_resolv_conf() {
    print_header "📦 备份配置文件"
    
    if [ -f /etc/resolv.conf ]; then
        BACKUP_FILE="/etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)"
        cp /etc/resolv.conf "$BACKUP_FILE"
        print_success "备份已创建: $BACKUP_FILE"
    else
        print_warning "/etc/resolv.conf 不存在，将创建新文件"
    fi
}

################################################################################
# Configure DNS servers
################################################################################

configure_dns() {
    print_header "🔧 修复落地连接性"
    
    print_step "正在修复落地连接性测试..."
    
    # Create temporary file
    TEMP_FILE=$(mktemp)
    
    # Add DNS servers (silently)
    for dns in "${DNS_SERVERS[@]}"; do
        echo "nameserver $dns" >> "$TEMP_FILE"
    done
    
    # If original resolv.conf exists, preserve other settings
    if [ -f /etc/resolv.conf ]; then
        # Preserve search domains and options
        grep -E "^(search|domain|options)" /etc/resolv.conf >> "$TEMP_FILE" 2>/dev/null
    fi
    
    # Replace resolv.conf
    cat "$TEMP_FILE" > /etc/resolv.conf
    rm "$TEMP_FILE"
    
    # Prevent some systems from overwriting resolv.conf
    chattr +i /etc/resolv.conf 2>/dev/null || true
    
    print_success "落地连接性修复完成 🎉"
}

################################################################################
# Enable IPv4 if disabled
################################################################################

enable_ipv4() {
    print_header "🌐 检查 IPv4 配置"
    
    # Check if IPv4 is disabled
    if [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
        if [ "$ipv6_status" -eq 1 ]; then
            print_info "IPv6 已禁用，IPv4 应该处于活动状态"
        fi
    fi
    
    # Ensure IPv4 forwarding is enabled (helpful for connectivity)
    if [ -f /proc/sys/net/ipv4/ip_forward ]; then
        current_forward=$(cat /proc/sys/net/ipv4/ip_forward)
        if [ "$current_forward" -eq 0 ]; then
            echo 1 > /proc/sys/net/ipv4/ip_forward
            print_success "IPv4 转发已启用"
        else
            print_success "IPv4 转发已启用"
        fi
    fi
    
    # Check if we have IPv4 address
    ipv4_addr=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    if [ -n "$ipv4_addr" ]; then
        print_success "检测到 IPv4 地址: $ipv4_addr"
    else
        print_warning "未检测到 IPv4 地址"
    fi
}

################################################################################
# Test DNS resolution
################################################################################

test_dns_resolution() {
    print_header "🔍 测试 DNS 解析"
    
    # Test with nslookup
    print_step "正在测试 nslookup 解析 $TEST_DOMAIN..."
    if command -v nslookup &> /dev/null; then
        nslookup_output=$(nslookup "$TEST_DOMAIN" 2>&1)
        if [ $? -eq 0 ]; then
            print_success "DNS 解析成功: $TEST_DOMAIN"
            echo "$nslookup_output" | grep -A2 "Name:" | while read line; do
                echo "  $line"
            done
            
            # Extract IP address
            resolved_ip=$(echo "$nslookup_output" | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -n1)
            if [ -n "$resolved_ip" ]; then
                print_success "解析到的 IP 地址: $resolved_ip 🎯"
                echo "$resolved_ip" > /tmp/resolved_ip.txt
            fi
        else
            print_error "nslookup 解析失败: $TEST_DOMAIN"
            echo "$nslookup_output"
        fi
    else
        print_warning "nslookup 未安装，尝试使用 dig..."
        
        if command -v dig &> /dev/null; then
            dig_output=$(dig +short "$TEST_DOMAIN" 2>&1)
            if [ $? -eq 0 ] && [ -n "$dig_output" ]; then
                print_success "dig 解析成功: $TEST_DOMAIN"
                echo "  解析到的 IP: $dig_output"
            else
                print_error "dig 解析失败: $TEST_DOMAIN"
            fi
        else
            print_warning "nslookup 和 dig 都不可用，跳过 DNS 解析测试"
        fi
    fi
}

################################################################################
# Test connectivity with ping
################################################################################

test_ping() {
    print_header "📡 测试网络连通性"
    
    print_step "正在 Ping $TEST_DOMAIN (发送 5 个数据包)..."
    
    ping_output=$(ping -c 5 -W 3 "$TEST_DOMAIN" 2>&1)
    ping_result=$?
    
    if [ $ping_result -eq 0 ]; then
        print_success "网络连接正常 ✨"
        
        # Extract statistics
        packet_loss=$(echo "$ping_output" | grep "packet loss" | awk '{print $6}')
        avg_time=$(echo "$ping_output" | grep "rtt min/avg/max" | awk -F'/' '{print $5}')
        
        if [ -n "$packet_loss" ]; then
            echo -e "${GREEN}     📊 丢包率: $packet_loss${NC}"
        fi
        if [ -n "$avg_time" ]; then
            echo -e "${GREEN}     ⚡ 平均延迟: ${avg_time}ms${NC}"
        fi
    else
        print_error "Ping $TEST_DOMAIN 失败"
        echo "$ping_output"
    fi
}

################################################################################
# Traceroute (Optional)
################################################################################

test_traceroute() {
    print_header "🗺️  路由追踪"
    
    # Check if traceroute is installed, if not, try to install it
    if ! command -v traceroute &> /dev/null && ! command -v tracepath &> /dev/null; then
        print_warning "未检测到 traceroute 工具"
        
        # Detect OS and install traceroute
        if [ -f /etc/debian_version ]; then
            # Debian/Ubuntu
            print_step "检测到 Debian/Ubuntu 系统，正在安装 traceroute..."
            apt-get update -qq &> /dev/null
            if apt-get install -y traceroute &> /dev/null 2>&1; then
                print_success "traceroute 安装成功"
            else
                print_error "traceroute 安装失败"
                return 1
            fi
        elif [ -f /etc/redhat-release ]; then
            # CentOS/RHEL
            print_step "检测到 CentOS/RHEL 系统，正在安装 traceroute..."
            if yum install -y traceroute &> /dev/null; then
                print_success "traceroute 安装成功"
            else
                print_error "traceroute 安装失败"
                return 1
            fi
        else
            print_warning "无法识别系统类型，跳过路由追踪"
            return 1
        fi
    fi
    
    # Run traceroute
    if command -v traceroute &> /dev/null; then
        print_step "正在运行 traceroute 到 $TEST_DOMAIN (最多15跳)..."
        echo ""
        traceroute -m 15 -w 2 "$TEST_DOMAIN" 2>&1 | tee -a "$LOG_FILE"
    elif command -v tracepath &> /dev/null; then
        print_step "正在运行 tracepath 到 $TEST_DOMAIN..."
        echo ""
        tracepath -m 15 "$TEST_DOMAIN" 2>&1 | tee -a "$LOG_FILE"
    else
        print_warning "无法执行路由追踪"
        return 1
    fi
}

################################################################################
# Generate final report
################################################################################

generate_report() {
    echo ""
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}║          🎉 na.proxys5.net 域名修复报告 🎉             ║${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # DNS Configuration Status
    echo -e "${BLUE}📌 [1] DNS 配置状态:${NC}"
    if grep -q "nameserver 8.8.8.8" /etc/resolv.conf; then
        echo -e "    ${GREEN}✅  服务器修复配置成功${NC}"
        echo -e "    ${BLUE}🌐 域名服务器:${NC} ${DNS_SERVERS[*]}"
    else
        echo -e "    ${RED}❌ DNS 配置可能存在问题${NC}"
    fi
    echo ""
    
    # IPv4 Status
    echo -e "${BLUE}📌 [2] IPv4 网络状态:${NC}"
    ipv4_addr=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    if [ -n "$ipv4_addr" ]; then
        echo -e "    ${GREEN}✅ IPv4 已激活:${NC} $ipv4_addr"
    else
        echo -e "    ${YELLOW}⚠️  未检测到 IPv4 地址${NC}"
    fi
    echo ""
    
    # DNS Resolution Status
    echo -e "${BLUE}📌 [3] DNS 解析测试 ($TEST_DOMAIN):${NC}"
    if [ -f /tmp/resolved_ip.txt ]; then
        resolved_ip=$(cat /tmp/resolved_ip.txt)
        echo -e "    ${GREEN}✅ 成功解析到:${NC} $resolved_ip 🎯"
        rm -f /tmp/resolved_ip.txt
    else
        echo -e "    ${YELLOW}⚠️  解析状态不明确${NC}"
    fi
    echo ""
    
    # Connectivity Status
    echo -e "${BLUE}📌 [4] 网络连通性测试:${NC}"
    if ping -c 1 -W 2 "$TEST_DOMAIN" &> /dev/null; then
        echo -e "    ${GREEN}✅ 成功连接到 $TEST_DOMAIN ✨${NC}"
    else
        echo -e "    ${RED}❌ 无法连接到 $TEST_DOMAIN${NC}"
    fi
    echo ""
    
    # Log file location
    echo -e "${BLUE}📌 [5] 详细日志:${NC}"
    echo -e "    ${BLUE}📄 完整日志保存在:${NC} $LOG_FILE"
    echo ""
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}        ✨ 修复完成！请查看上方报告了解状态 ✨        ${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  💡 温馨提示                                           │${NC}"
    echo -e "${YELLOW}│  下次出问题记得联系我编写脚本修复哦！                 │${NC}"
    echo -e "${YELLOW}│                                                        │${NC}"
    echo -e "${YELLOW}│  📧 邮箱: shangkouyou@gmail.com                        │${NC}"
    echo -e "${YELLOW}│  💬 微信: shangkouyou                                  │${NC}"
    echo -e "${YELLOW}└────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

################################################################################
# Main execution
################################################################################

main() {
    clear
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}║     🚀 周周定制 VPS Proxy 落地修复小脚本 🚀            ║${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}  📧 Email: shangkouyou@gmail.com  💬 WeChat: shangkouyou${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}  🕐 开始时间:${NC} $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${GREEN}  📝 日志文件:${NC} $LOG_FILE${NC}"
    echo ""
    
    # Check root privileges
    check_root
    
    # Step 1: Backup
    backup_resolv_conf
    echo ""
    
    # Step 2: Configure DNS
    configure_dns
    echo ""
    
    # Step 3: Enable IPv4
    enable_ipv4
    echo ""
    
    # Step 4: Test DNS resolution
    test_dns_resolution
    echo ""
    
    # Step 5: Test connectivity
    test_ping
    echo ""
    
    # Step 6: Traceroute (automatic)
    test_traceroute
    echo ""
    
    # Step 7: Generate report
    generate_report
    
    echo ""
    echo -e "${GREEN}  ✅ 脚本完成时间:${NC} $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${GREEN}  ⏱️  总耗时:${NC} $SECONDS 秒${NC}"
    echo ""
}

# Run main function
main
