#!/bin/bash
set -e

# Menambah Repositori Kartolo
cat <<EOF | sudo tee /etc/apt/sources.list
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-updates main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-security main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-backports main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-proposed main restricted universe multiverse
EOF

# Update Repositori
sudo apt update

# Install Isc-Dhcp-Server, IPTables, Dan Iptables-Persistent
sudo apt install -y sshpass isc-dhcp-server iptables iptables-persistent

# Konfigurasi DHCP
echo "Mengonfigurasi DHCP..."
cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet 192.168.13.0 netmask 255.255.255.0 {
    range 192.168.13.10 192.168.13.100;
    option routers 192.168.13.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    option subnet-mask 255.255.255.0;
    option broadcast-address 192.168.13.255;
}
EOF

# Konfigurasi Interfaces DHCP
echo "Mengonfigurasi interface DHCP..."
sudo sed -i 's/^INTERFACESv4=.*/INTERFACESv4="eth1.10"/' /etc/default/isc-dhcp-server

# Konfigurasi IP Statis Untuk Internal Network menggunakan Netplan
echo "Mengonfigurasi IP Statis untuk Internal Network menggunakan Netplan..."
cat <<EOF | sudo tee /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
    eth1:
      dhcp4: no
  vlans:
    eth1.10:
      id: 10
      link: eth1
      addresses: [192.168.13.1/24]
EOF

# Terapkan Konfigurasi Netplan dan Aktifkan Interface
echo "Mengaktifkan interface jaringan..."
sudo ip link set eth1 up
sudo netplan apply

# Restart DHCP Server
echo "Merestart DHCP server..."
sudo systemctl restart isc-dhcp-server

# Mengaktifkan IP Forwarding
echo "Mengaktifkan IP Forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Konfigurasi IPTables untuk NAT
echo "Mengonfigurasi IPTables untuk NAT..."
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth1.10 -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth1.10 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Menyimpan Aturan IPTables
sudo netfilter-persistent save

# Konfigurasi IP Statis untuk MikroTik
echo "Mengatur IP Statis untuk MikroTik..."
sudo ip addr add 192.168.200.2/24 dev eth0  # Ganti dengan interface yang sesuai
sudo ip link set dev eth0 up

# Konfigurasi IP Statis untuk Cisco
echo "Mengatur IP Statis untuk Cisco..."
sudo ip addr add 192.168.13.2/24 dev eth0  # Ganti dengan interface yang sesuai
sudo ip link set dev eth0 up

# Menunggu beberapa detik untuk konfigurasi IP
sleep 5

# Informasi login
username="admin"
password="admin_password"

# Konfigurasi Cisco
echo "Mengonfigurasi Cisco..."
sshpass -p $password ssh -o StrictHostKeyChecking=no $username@192.168.13.1 << EOF
enable
configure terminal
vlan 10
name VLAN10
exit
interface e0/1
switchport mode access
switchport access vlan 10
exit
end
write memory
EOF

# Konfigurasi MikroTik
echo "Mengonfigurasi MikroTik..."
