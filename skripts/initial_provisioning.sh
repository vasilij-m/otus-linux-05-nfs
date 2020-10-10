#!/bin/bash

HOST_NAME=$(hostname)
DOMAIN='nfs.lab'
NFS_SERVER='nfs-srv'
NFS_CLIENT='nfs-cl'
KRB_SERVER='krb-srv'
NFS_SERVER_IP_ADDRESS='192.168.10.10'
NFS_CLIENT_IP_ADDRESS='192.168.10.20'
KRB_SERVER_IP_ADDRESS='192.168.10.30'

hostnamectl set-hostname ${HOST_NAME}.${DOMAIN}

systemctl enable firewalld --now
firewall-cmd --permanent --add-service=ntp
firewall-cmd --reload

if [[ $(hostname) == "${KRB_SERVER}.${DOMAIN}" ]]; then
    firewall-cmd --add-service=kerberos --permanent
    firewall-cmd --add-service=kadmin --permanent
    firewall-cmd --reload
elif [[ $(hostname) == "${NFS_SERVER}.${DOMAIN}" ]]; then
    firewall-cmd --permanent --add-service=mountd
    firewall-cmd --permanent --add-service=rpc-bind
    firewall-cmd --permanent --add-service=nfs
    firewall-cmd --reload
fi

timedatectl set-timezone Europe/Moscow
yum install -y ntp
systemctl enable ntpd --now

cat > /etc/hosts <<EOF
${NFS_SERVER_IP_ADDRESS}   ${NFS_SERVER}.${DOMAIN}   ${NFS_SERVER}
${NFS_CLIENT_IP_ADDRESS}   ${NFS_CLIENT}.${DOMAIN}   ${NFS_CLIENT}
${KRB_SERVER_IP_ADDRESS}   ${KRB_SERVER}.${DOMAIN}   ${KRB_SERVER}
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF
