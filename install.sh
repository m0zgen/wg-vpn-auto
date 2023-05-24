#!/bin/bash
# Description

# Sys env / paths / etc
# -------------------------------------------------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)

WG_CATALOG=/usr/local/bin/wgui
WG_ADDERSS=10.0.1.0
WG_PORT=51823

# Functions
# -------------------------------------------------------------------------------------------\

# Selleep function
function timeout_sleep() {
    echo "Sleeping for $1 seconds"
    for (( i=$1; i>0; i--)); do
        echo -ne "$i\r"
        sleep 1
    done
}

# Update Debian system
function update_debian() {
    apt-get update
    apt-get upgrade -y
    apt-get dist-upgrade -y
    apt-get autoremove -y
    apt-get autoclean -y
}

# Install wireguard on Debian
function install_wireguard() {
    apt -y install wireguard wget net-tools iptables iftop htop zip
}

# Syscrl frowarder
function sysctl_forwarder() {
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
}

# Web GUI for Wireguard
function install_wg_gui() {
    mkdir -p $WG_CATALOG
    cd $WG_CATALOG
    wget https://github.com/ngoduykhanh/wireguard-ui/releases/download/v0.4.0/wireguard-ui-v0.4.0-linux-amd64.tar.gz
    tar zxvf wireguard-ui-v0.4.0-linux-amd64.tar.gz
}

# Create systemd unit for wireguard
function create_wg_unit() {
    cat > /etc/systemd/system/wgui.service <<EOF
[Unit]
Description=Restart WireGuard
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart wg-quick@wg0.service

[Install]
RequiredBy=wgui.path
EOF

    cat > /etc/systemd/system/wgui.path <<EOF
[Unit]
Description=Watch /etc/wireguard/wg0.conf for changes

[Path]
PathModified=/etc/wireguard/wg0.conf

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/wgweb.service <<EOF
[Unit]
Description=wgweb
After=syslog.target network.target

[Service]
Type=simple
PIDFile=/run/wgweb.pid
ExecStart=$WG_CATALOG/wireguard-ui # -bind-address $WG_ADDERSS:$WG_PORT
WorkingDirectory=/usr/local/bin/wgui/
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
User=root
Group=root
Restart=always
TimeoutSec=300
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

}

# Add public ssh key to root user
function add_ssh_key() {
    mkdir -p /root/.ssh
    cat > /root/.ssh/authorized_keys <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCF28f8CJnJnzFSAnfubISxZFEVKg+RQD3kbncG7gnq+vXC9nXpro/Pj6PeuVaXNoHIhdJQXV3Hd+oCMZWk4GJ4tz09Jho7QV23qT5xaHOOANRMQqmNZwqtjEZ6QkfdYytxX20a+N+7u07gwsusQsWf7//WavqTCXEZ9GT95ncwM87AxM0M3X59m6G+i3z9R/ZeCDbwGBban31SbIPHs3pSpj/UGydT+v9EU0KaWsJErz3d/jvdOFAA256xVFC6YN75RRlreWfTo2A9Ee/2iupi9Bon28vi9QHuzHJqbErrjbm08ytamMeEpC7HwBvtZxJyXEX8uimoQQpkYY9bMDyx rsa-key-20220320
EOF
    chmod 600 /root/.ssh/authorized_keys
}

# Determine network interface name
function get_net_interface() {
    NET_INTERFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}')

    sed -i "s/^PostUp.*/PostUp = iptables -A FORWARD -i $NET_INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o $NET_INTERFACE -j MASQUERADE;/" /etc/wireguard/wg0.conf
    sed -i "s/^PostDown.*/PostDown = iptables -D FORWARD -i $NET_INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o $NET_INTERFACE -j MASQUERADE;/" /etc/wireguard/wg0.conf

}

# Systemd reload
function systemd_reload() {
    systemctl daemon-reload
    systemctl enable wgweb
    systemctl enable wgui.path
    systemctl enable wgui.service
    systemctl enable wg-quick@wg0.service
    systemctl restart wgweb
    timeout_sleep 3
    systemctl start wg-quick@wg0.service
    timeout_sleep 3
    systemctl start wgui.{path,service}   
    timeout_sleep 3
    get_net_interface
    systemctl restart wg-quick@wg0.service
}

# Reboot computer
function reboot_computer() {
    reboot
}

# Show info
function show_info() {
    echo "Wireguard web GUI: http://$WG_ADDERSS:$WG_PORT"
    echo "Wireguard config: /etc/wireguard/wg0.conf"

    echo -e "Wireguard config detail:\n"
    cat /etc/wireguard/wg0.conf
    
}

# Actions
# -------------------------------------------------------------------------------------------\
update_debian
install_wireguard
sysctl_forwarder
install_wg_gui
create_wg_unit
add_ssh_key
systemd_reload
show_info

# systemctl status wg-quick@wg0.service