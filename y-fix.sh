#!/bin/bash
echo "开始修复 Argosbx..."

pkill -f sing-box 2>/dev/null
sleep 1

# 检查必要文件
if [ ! -f $HOME/agsbx/sing-box ]; then
    echo "❌ 未安装 sing-box 内核"
    exit 1
fi

if [ ! -f $HOME/agsbx/sb.json ]; then
    echo "❌ 未找到配置文件"
    exit 1
fi

# 读取原有UUID和端口
UUID=$(cat $HOME/agsbx/uuid 2>/dev/null)
PORT_HY2=$(cat $HOME/agsbx/port_hy2 2>/dev/null)
PORT_SO=$(cat $HOME/agsbx/port_so 2>/dev/null)

# 如果文件不存在，生成新的
[ -z "$UUID" ] && UUID=$($HOME/agsbx/sing-box generate uuid) && echo $UUID > $HOME/agsbx/uuid
[ -z "$PORT_HY2" ] && PORT_HY2=$(shuf -i 10000-65535 -n 1) && echo $PORT_HY2 > $HOME/agsbx/port_hy2
[ -z "$PORT_SO" ] && PORT_SO=$(shuf -i 10000-65535 -n 1) && echo $PORT_SO > $HOME/agsbx/port_so

echo "UUID: $UUID"
echo "Hysteria2端口: $PORT_HY2"
echo "SOCKS5端口: $PORT_SO"

# 备份原配置
cp $HOME/agsbx/sb.json $HOME/agsbx/sb.json.bak.$(date +%Y%m%d%H%M%S)

# 生成正确配置（保留原有UUID和端口）
cat > $HOME/agsbx/sb.json << JSONEOF
{
"log": {"disabled": false,"level": "info","timestamp": true},
"inbounds": [
{"type": "hysteria2","tag": "hy2-sb","listen": "::","listen_port": $PORT_HY2,"users": [{"password": "$UUID"}],"ignore_client_bandwidth":false,"tls": {"enabled": true,"alpn": ["h3"],"certificate_path": "$HOME/agsbx/cert.pem","key_path": "$HOME/agsbx/private.key"}},
{"tag": "socks5-sb","type": "socks","listen": "::","listen_port": $PORT_SO,"users": [{"username": "$UUID","password": "$UUID"}]}
],
"outbounds": [{"type": "direct","tag": "direct"}],
"route": {"rules": [{"action": "sniff"},{"ip_cidr": ["::/0","0.0.0.0/0"],"outbound": "direct"}],"final": "direct"}
}
JSONEOF

nohup $HOME/agsbx/sing-box run -c $HOME/agsbx/sb.json > $HOME/agsbx/singbox.log 2>&1 &
sleep 3

if pgrep -f 'agsbx/sing-box' > /dev/null; then
    echo "✅ Sing-box 启动成功!"
else
    echo "❌ 启动失败"
    $HOME/agsbx/sing-box run -c $HOME/agsbx/sb.json
fi
